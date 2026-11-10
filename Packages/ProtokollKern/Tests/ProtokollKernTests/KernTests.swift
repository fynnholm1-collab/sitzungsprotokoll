import XCTest
@testable import ProtokollKern

final class OffenePunkteTests: XCTestCase {
    func testLiestOffenePunkteUndUnerledigteAufgaben() {
        let md = """
        # Protokoll: AG Bibliothek

        ## Ergebnisse
        - Neue Signaturen beschlossen

        ## Aufgaben
        - [ ] Liste der Zeitschriften prüfen – Frau A. – 30.11.
        - [x] Raumbuchung – Herr B. – erledigt
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - Umzug der Handapparate
        - …
        1. Budget 2027

        ## Nächste Sitzung
        - Termin: 12.1.2027
        """
        XCTAssertEqual(OffenePunkte.auslesen(aus: md), [
            "Liste der Zeitschriften prüfen – Frau A. – 30.11.",
            "Umzug der Handapparate",
            "Budget 2027",
        ])
    }

    func testUnterueberschriftenBleibenImAbschnitt() {
        let md = """
        ## Aufgaben
        ### Lehre
        - [ ] Modulhandbuch
        ## Ergebnisse
        - nicht übernehmen
        """
        XCTAssertEqual(OffenePunkte.auslesen(aus: md), ["Modulhandbuch"])
    }

    func testLetztesProtokollNachDatum() throws {
        let fm = FileManager.default
        let ordner = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: ordner) }
        for name in ["2026-10-01 AG.md", "2026-11-05 AG.md", "2026-11-05 AG.docx", "Notizen.md"] {
            try "x".write(to: ordner.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(OffenePunkte.letztesProtokoll(in: ordner)?.lastPathComponent, "2026-11-05 AG.md")
        let ohne = OffenePunkte.letztesProtokoll(in: ordner, ausser: [ordner.appendingPathComponent("2026-11-05 AG.md")])
        XCTAssertEqual(ohne?.lastPathComponent, "2026-10-01 AG.md")
    }
}

final class DateinamenTests: XCTestCase {
    func testBereinigt() {
        XCTAssertEqual(Dateinamen.bereinigt("AG  Tübingen/Kyoto: Sitzung?"), "AG Tübingen-Kyoto- Sitzung")
        XCTAssertEqual(Dateinamen.bereinigt("  "), "Protokoll")
    }

    func testProtokollname() {
        var k = DateComponents()
        k.year = 2026; k.month = 11; k.day = 10; k.hour = 14
        let zone = TimeZone(identifier: "Europe/Berlin")!
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zone
        let datum = kalender.date(from: k)!
        XCTAssertEqual(Dateinamen.protokoll(datum: datum, reihe: "Geschäftsführung", zeitzone: zone), "2026-11-10 Geschäftsführung")
        XCTAssertEqual(Dateinamen.deutschesDatum(datum, zeitzone: zone), "10. November 2026")
    }

    func testFreieDatei() throws {
        let fm = FileManager.default
        let ordner = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: ordner) }
        XCTAssertEqual(Dateinamen.freieDatei(basis: "P", endung: "md", in: ordner).lastPathComponent, "P.md")
        try "x".write(to: ordner.appendingPathComponent("P.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Dateinamen.freieDatei(basis: "P", endung: "md", in: ordner).lastPathComponent, "P (2).md")
    }

    func testZielordner() {
        XCTAssertEqual(Sitzungsreihe(name: "AG EU Campus").zielordner, "AG EU Campus")
        XCTAssertEqual(Sitzungsreihe(name: "X", ordner: "/Gremien/GF/").zielordner, "Gremien/GF")
        XCTAssertEqual(Sitzungsreihe(name: "AG Öffentlichkeit", ordner: " . ").zielordner, "")
    }
}

final class VorlagenTests: XCTestCase {
    func testAlleReihenHabenEineEingebauteVorlage() {
        for reihe in Sitzungsreihe.standard {
            XCTAssertNotNil(Vorlagen.eingebaut[reihe.vorlage], reihe.name)
        }
        XCTAssertEqual(Sitzungsreihe.standard.count, 10)
    }

    func testAusfuellen() {
        let text = Vorlagen.ausfuellen("{{reihe}} am {{datum}}, {{teilnehmende}}", werte: ["reihe": "AG", "datum": "1. Mai 2027", "teilnehmende": " "])
        XCTAssertEqual(text, "AG am 1. Mai 2027, –")
    }

    func testEingebauteVorlagenLiefernKeineOffenenPunkte() {
        // Die leeren Vorlagen selbst dürfen keine „offenen Punkte“ erzeugen.
        for (name, vorlage) in Vorlagen.eingebaut {
            XCTAssertEqual(OffenePunkte.auslesen(aus: vorlage), [], name)
        }
    }

    func testReiheDekodiertMitFehlendenFeldern() throws {
        let json = #"{"name": "AG Test"}"#.data(using: .utf8)!
        let reihe = try JSONDecoder().decode(Sitzungsreihe.self, from: json)
        XCTAssertEqual(reihe.name, "AG Test")
        XCTAssertEqual(reihe.vorlage, Vorlagen.allgemein)
        XCTAssertFalse(reihe.meistOnline)
    }
}

final class AuftragTests: XCTestCase {
    func testAbschnitteRespektierenGrenze() {
        let zeilen = (1...100).map { "[0:00:\($0)] Zeile Nummer \($0) mit etwas Text" }
        let teile = ProtokollAuftrag.abschnitte(zeilen.joined(separator: "\n"), maxZeichen: 400)
        XCTAssertGreaterThan(teile.count, 1)
        XCTAssertTrue(teile.allSatisfy { $0.count <= 400 })
        XCTAssertEqual(teile.joined(separator: "\n"), zeilen.joined(separator: "\n"))
    }

    func testAbschnitteTrennenUeberlangeZeilen() {
        let teile = ProtokollAuftrag.abschnitte(String(repeating: "a", count: 25), maxZeichen: 10)
        XCTAssertEqual(teile.map(\.count), [10, 10, 5])
    }

    func testAuftragEnthaeltOffenePunkte() {
        let a = ProtokollAuftrag(vorlage: "# V", offenePunkte: ["Budget"], transkript: "Hallo", reihe: "AG")
        XCTAssertTrue(a.askAlmaText.contains("- Budget"))
        XCTAssertTrue(a.askAlmaText.contains("## Transkript\nHallo"))
        let leer = ProtokollAuftrag(vorlage: "# V", offenePunkte: [], transkript: "Hallo", reihe: "AG")
        XCTAssertTrue(leer.nutzerText.contains("Keine."))
    }

    func testModellantwortBereinigt() {
        XCTAssertEqual(Modellantwort.bereinigt("<think>überlege</think>\n# Protokoll"), "# Protokoll")
        XCTAssertEqual(Modellantwort.bereinigt("```markdown\n# Protokoll\n- a\n```"), "# Protokoll\n- a")
    }
}

final class MarkdownHTMLTests: XCTestCase {
    func testGrundelemente() {
        let html = MarkdownHTML.html(aus: """
        # Titel
        **Datum:** 1. Mai
        **Ort:** Kyoto

        ## Aufgaben
        - [ ] Erste & zweite
        - [x] Erledigt
        1. Eins

        | A | B |
        |---|---|
        | 1 | 2 |
        """)
        XCTAssertTrue(html.contains("<h1>Titel</h1>"))
        XCTAssertTrue(html.contains("<p><strong>Datum:</strong> 1. Mai<br><strong>Ort:</strong> Kyoto</p>"))
        XCTAssertTrue(html.contains("<ul>\n<li>☐ Erste &amp; zweite</li>\n<li>☑ Erledigt</li>\n</ul>\n<ol>\n<li>Eins</li>\n</ol>"))
        XCTAssertTrue(html.contains("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"))
    }

    func testKursivUndKeinFalscherTreffer() {
        XCTAssertEqual(MarkdownHTML.inline("*Vertraulich* und 3 * 4"), "<em>Vertraulich</em> und 3 * 4")
        XCTAssertEqual(MarkdownHTML.inline("`<b>`"), "<code>&lt;b&gt;</code>")
    }
}

final class TranskriptTests: XCTestCase {
    func testBereinigtTokensUndHalluzinationen() {
        XCTAssertEqual(Transkript.bereinigt("<|0.00|> Guten   Morgen <|2.00|>"), "Guten Morgen")
        XCTAssertTrue(Transkript.istHalluzination("Untertitel im Auftrag des ZDF, 2021"))
        XCTAssertTrue(Transkript.istHalluzination(" ... "))
        XCTAssertFalse(Transkript.istHalluzination("Wir beschließen den Haushalt."))
    }

    func testZusammenfuehrenMitVersatzUndEcho() {
        let mikro = Spur(sprecher: "Fynn", versatz: 0, segmente: [
            Segment(start: 0, ende: 3, text: "Guten Morgen zusammen"),
            Segment(start: 10.5, ende: 14, text: "der Antrag ist bewilligt worden"), // Echo
        ])
        let browser = Spur(sprecher: "Online-Teilnehmende", versatz: 0.5, segmente: [
            Segment(start: 4, ende: 8, text: "Hallo, hört ihr mich?"),
            Segment(start: 10, ende: 13, text: "Der Antrag ist bewilligt worden."),
        ])
        let alle = Transkript.zusammenfuehren([mikro, browser], echoSpur: 0)
        XCTAssertEqual(alle.map(\.text), ["Guten Morgen zusammen", "Hallo, hört ihr mich?", "Der Antrag ist bewilligt worden."])
        XCTAssertEqual(alle[1].start, 4.5)
        XCTAssertEqual(alle.map(\.sprecher), ["Fynn", "Online-Teilnehmende", "Online-Teilnehmende"])

        let ohneFilter = Transkript.zusammenfuehren([mikro, browser])
        XCTAssertEqual(ohneFilter.count, 4)
    }

    func testTextMitAbsaetzen() {
        let segmente = [
            Segment(start: 0, ende: 2, text: "Eins.", sprecher: "A"),
            Segment(start: 2, ende: 4, text: "Zwei.", sprecher: "A"),
            Segment(start: 5, ende: 6, text: "Drei.", sprecher: "B"),
            Segment(start: 3700, ende: 3702, text: "Vier."),
        ]
        XCTAssertEqual(Transkript.text(segmente), "[0:00:00] A: Eins. Zwei.\n[0:00:05] B: Drei.\n[1:01:40] Vier.")
    }
}

final class WoerterbuchTests: XCTestCase {
    func testEintraegeAusText() {
        let e = Woerterbuch.eintraege("Fynn Holm\n\n  Japanologie \nfynn holm\nAOI\n")
        XCTAssertEqual(e, ["Fynn Holm", "Japanologie", "AOI"])
        XCTAssertTrue(Woerterbuch.standard.contains("Fynn Holm"))
        XCTAssertEqual(Woerterbuch.eintraege(Woerterbuch.standardText), Woerterbuch.standard)
    }

    func testWhisperPromptHaeltBudgetUndEndetOhnePunkt() {
        let p = Woerterbuch.whisperPrompt(["Fynn Holm", "Japanologie", "AOI"]) { $0.count <= 25 }
        XCTAssertEqual(p, " Fynn Holm, Japanologie")
        XCTAssertFalse(p.hasSuffix("."))
        XCTAssertEqual(Woerterbuch.whisperPrompt(["Sehr langer Eintrag"]) { _ in false }, "")
    }

    func testPromptEchoWirdErkannt() {
        let w = ["Fynn Holm", "Japanologie", "Asien-Orient-Institut (AOI)"]
        XCTAssertTrue(Woerterbuch.istPromptEcho(" Holm, Japanologie, AOI", eintraege: w))
        XCTAssertTrue(Transkript.istHalluzination("Untertitelung des ZDF, 2020"))
        XCTAssertFalse(Woerterbuch.istPromptEcho("Fynn Holm leitet die Sitzung.", eintraege: w))
        XCTAssertFalse(Woerterbuch.istPromptEcho("Japanologie", eintraege: w))
        let spur = Spur(sprecher: nil, versatz: 0, segmente: [
            Segment(start: 0, ende: 2, text: "Das wäre um 15 Uhr."),
            Segment(start: 2, ende: 3, text: " Holm, Japanologie, AOI"),
        ])
        XCTAssertEqual(Transkript.zusammenfuehren([spur], woerterbuch: w).map(\.text), ["Das wäre um 15 Uhr."])
    }

    func testAuftragEnthaeltSchreibweisen() {
        let a = ProtokollAuftrag(vorlage: "# Protokoll", offenePunkte: [], transkript: "Finn sagt …", reihe: "Dienstbesprechung", woerterbuch: ["Fynn Holm", "Japanologie"])
        XCTAssertTrue(a.systemText.contains("Schreibweisen von Namen und Begriffen"))
        XCTAssertTrue(a.systemText.contains("- Fynn Holm"))
        XCTAssertTrue(a.teilauftrag(abschnitt: "x", nummer: 1, von: 2).system.contains("- Japanologie"))
        XCTAssertTrue(a.zusammenfuehrung(notizen: ["n"]).system.contains("- Fynn Holm"))
        let ohne = ProtokollAuftrag(vorlage: "# Protokoll", offenePunkte: [], transkript: "", reihe: "X")
        XCTAssertFalse(ohne.systemText.contains("Schreibweisen"))
    }
}
