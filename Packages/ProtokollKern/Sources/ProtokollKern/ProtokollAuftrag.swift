import Foundation

/// Baut die Anweisungen für das Sprachmodell (lokal über Ollama oder per
/// Kopieren für AskAlma) aus Vorlage, offenen Punkten und Transkript.
public struct ProtokollAuftrag: Sendable {
    /// Bereits ausgefüllte Vorlage (Platzhalter ersetzt).
    public var vorlage: String
    public var offenePunkte: [String]
    public var transkript: String
    public var sprache: String
    public var reihe: String

    public init(vorlage: String, offenePunkte: [String], transkript: String, sprache: String = "Deutsch", reihe: String) {
        self.vorlage = vorlage
        self.offenePunkte = offenePunkte
        self.transkript = transkript
        self.sprache = sprache
        self.reihe = reihe
    }

    public var systemText: String {
        """
        Du schreibst das Kurzprotokoll (Ergebnisprotokoll) einer Sitzung an einer Universität: \(reihe).
        Regeln:
        - Fülle die Vorlage aus und behalte ihre Überschriften und ihre Reihenfolge bei. Abschnitte ohne Inhalt erhalten „–“.
        - Schreibe knapp und sachlich in ganzen Sätzen oder kurzen Stichpunkten. Kein Wortprotokoll, keine Füllwörter.
        - Halte Ergebnisse, Beschlüsse (mit Abstimmungsergebnis, falls genannt), Aufgaben und offene Punkte fest.
        - Es ist ein Ergebnisprotokoll: Fasse die Informationen thematisch nach Tagesordnungspunkten zusammen, nicht im Verlauf der Diskussion. Wer was gesagt hat, gehört nur ins Protokoll, wenn es ausdrücklich gewünscht wird (z. B. „bitte zu Protokoll“), bei Berichten und Anträgen oder bei Zuständigkeiten.
        - Aufgaben müssen eindeutig verteilt sein: immer als Checkliste „- [ ] Aufgabe – zuständig – Frist“. Leite Zuständige aus Formulierungen wie „ich kümmere mich darum“ oder „kannst du …“ ab, wenn die Person erkennbar ist. Unbekannte Angaben als „offen“.
        - Erfinde nichts. Namen, Zahlen, Beträge und Termine nur, wenn sie im Transkript vorkommen. Unklares mit [unklar] markieren.
        - Das Transkript ist automatisch erstellt und kann Hörfehler enthalten. Korrigiere offensichtliche Fehler bei Namen und Fachbegriffen nur, wenn der Zusammenhang eindeutig ist.
        - Wenn offene Punkte aus der letzten Sitzung angegeben sind, vermerke, ob sie besprochen oder erledigt wurden. Nicht besprochene Punkte bleiben unter „Offene Punkte“ stehen.
        - Schreibe das Protokoll auf \(sprache).
        - Gib nur das fertige Protokoll in Markdown aus, ohne Vorbemerkung und ohne Codeblock.
        """
    }

    private var offenePunkteText: String {
        offenePunkte.isEmpty
            ? "Keine."
            : offenePunkte.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Nutzertext für einen einzigen Durchlauf mit dem ganzen Transkript.
    public var nutzerText: String {
        """
        ## Vorlage
        \(vorlage)

        ## Offene Punkte aus der letzten Sitzung
        \(offenePunkteText)

        ## Transkript
        \(transkript)
        """
    }

    /// Ein Text zum Einfügen in AskAlma (Anweisungen und Inhalt zusammen).
    public var askAlmaText: String {
        """
        \(systemText)

        \(nutzerText)
        """
    }

    // MARK: Lange Sitzungen in Abschnitten

    /// Zerlegt ein Transkript an Zeilengrenzen in Abschnitte von höchstens `maxZeichen` Zeichen.
    /// Einzelne zu lange Zeilen werden hart getrennt.
    public static func abschnitte(_ text: String, maxZeichen: Int) -> [String] {
        precondition(maxZeichen > 0)
        var ergebnis: [String] = []
        var aktuell = ""
        func abschliessen() {
            let t = aktuell.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { ergebnis.append(t) }
            aktuell = ""
        }
        for zeile in text.components(separatedBy: "\n") {
            var rest = Substring(zeile)
            while rest.count > maxZeichen {
                abschliessen()
                ergebnis.append(String(rest.prefix(maxZeichen)))
                rest = rest.dropFirst(maxZeichen)
            }
            if aktuell.count + rest.count + 1 > maxZeichen { abschliessen() }
            if !aktuell.isEmpty { aktuell.append("\n") }
            aktuell.append(contentsOf: rest)
        }
        abschliessen()
        return ergebnis
    }

    /// Anweisung für das Zusammenfassen eines Abschnitts (erster Schritt bei langen Sitzungen).
    public func teilauftrag(abschnitt: String, nummer: Int, von anzahl: Int) -> (system: String, nutzer: String) {
        let system = """
        Du fasst Abschnitt \(nummer) von \(anzahl) eines Sitzungstranskripts (\(reihe)) in Stichpunkten zusammen.
        Halte alle Themen, Ergebnisse, Beschlüsse mit Abstimmungsergebnis, Aufgaben (wer, was, bis wann), Zahlen, Termine und offenen Fragen fest.
        Erfinde nichts. Schreibe auf \(sprache). Gib nur die Stichpunkte aus.
        """
        let nutzer = """
        ## Transkript, Abschnitt \(nummer) von \(anzahl)
        \(abschnitt)
        """
        return (system, nutzer)
    }

    /// Anweisung zum Zusammenführen der Abschnittsnotizen zum fertigen Protokoll.
    public func zusammenfuehrung(notizen: [String]) -> (system: String, nutzer: String) {
        let notizText = notizen.enumerated()
            .map { "### Abschnitt \($0.offset + 1)\n\($0.element)" }
            .joined(separator: "\n\n")
        let nutzer = """
        ## Vorlage
        \(vorlage)

        ## Offene Punkte aus der letzten Sitzung
        \(offenePunkteText)

        ## Notizen zur Sitzung (in zeitlicher Reihenfolge)
        \(notizText)
        """
        return (systemText.replacingOccurrences(of: "im Transkript", with: "in den Notizen"), nutzer)
    }
}

/// Bereinigt Antworten von Sprachmodellen.
public enum Modellantwort {
    public static func bereinigt(_ text: String) -> String {
        var t = text
        // Denkblöcke mancher Modelle (z. B. Qwen 3) entfernen.
        while let anfang = t.range(of: "<think>"), let ende = t.range(of: "</think>", range: anfang.upperBound..<t.endIndex) {
            t.removeSubrange(anfang.lowerBound..<ende.upperBound)
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Umschließenden Codeblock entfernen.
        if t.hasPrefix("```") {
            if let zeilenende = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: zeilenende)...])
            }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
