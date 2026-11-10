import Foundation

/// Eingebaute Protokollvorlagen. Vorlagen sind Markdown-Gerüste mit Platzhaltern
/// in doppelten geschweiften Klammern, z. B. `{{datum}}`.
///
/// Wichtig für die Übernahme offener Punkte in die nächste Sitzung:
/// Aufgaben stehen unter einer Überschrift „## Aufgaben“ als Checkliste
/// (`- [ ] …`), offene Punkte unter „## Offene Punkte“ als Liste.
public enum Vorlagen {
    public static let allgemein = "allgemein"
    public static let geschaeftsfuehrung = "geschaeftsfuehrung"
    public static let dienstbesprechung = "dienstbesprechung"
    public static let finanzplan = "finanzplan"
    public static let mitgliederversammlung = "mitgliederversammlung"

    /// Platzhalter, die beim Ausfüllen ersetzt werden.
    public static let platzhalter = ["reihe", "titel", "datum", "teilnehmende", "protokoll"]

    /// Anzeigenamen der eingebauten Vorlagen.
    public static let anzeigenamen: [String: String] = [
        allgemein: "Allgemein (AG-Sitzung)",
        geschaeftsfuehrung: "Geschäftsführung",
        dienstbesprechung: "Dienstbesprechung",
        finanzplan: "Finanzplansitzung",
        mitgliederversammlung: "Mitgliederversammlung (Verein)",
    ]

    public static func anzeigename(_ schluessel: String) -> String {
        anzeigenamen[schluessel] ?? schluessel
    }

    /// Ersetzt die Platzhalter. Leere Werte werden durch „–“ ersetzt.
    public static func ausfuellen(_ vorlage: String, werte: [String: String]) -> String {
        var text = vorlage
        for (schluessel, wert) in werte {
            let ersatz = wert.trimmingCharacters(in: .whitespacesAndNewlines)
            text = text.replacingOccurrences(of: "{{\(schluessel)}}", with: ersatz.isEmpty ? "–" : ersatz)
        }
        return text
    }

    public static let eingebaut: [String: String] = [
        allgemein: """
        # Protokoll: {{titel}}

        **Sitzung:** {{reihe}}
        **Datum:** {{datum}}
        **Teilnehmende:** {{teilnehmende}}
        **Protokoll:** {{protokoll}}

        ## Tagesordnung
        1. …

        ## Ergebnisse
        ### TOP 1: …
        - …

        ## Beschlüsse
        - …

        ## Aufgaben
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - …

        ## Nächste Sitzung
        - Termin: …
        """,

        geschaeftsfuehrung: """
        # Protokoll: {{titel}}

        *Vertraulich – nur für den Kreis der Geschäftsführung.*

        **Sitzung:** {{reihe}}
        **Datum:** {{datum}}
        **Teilnehmende:** {{teilnehmende}}
        **Protokoll:** {{protokoll}}

        ## Tagesordnung
        1. …

        ## Ergebnisse
        ### TOP 1: …
        - …

        ## Beschlüsse
        - B1: … (Abstimmung, falls genannt)

        ## Personal und Stellen
        - …

        ## Lehre und Studium
        - …

        ## Aufgaben
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - …

        ## Nächste Sitzung
        - Termin: …
        """,

        dienstbesprechung: """
        # Protokoll: {{titel}}

        **Sitzung:** {{reihe}}
        **Datum:** {{datum}}
        **Teilnehmende:** {{teilnehmende}}
        **Protokoll:** {{protokoll}}

        ## Mitteilungen
        - …

        ## Lehre und Prüfungen
        - …

        ## Termine
        - …

        ## Ergebnisse
        ### TOP 1: …
        - …

        ## Aufgaben
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - …
        """,

        finanzplan: """
        # Protokoll: {{titel}}

        **Sitzung:** {{reihe}}
        **Datum:** {{datum}}
        **Teilnehmende:** {{teilnehmende}}
        **Protokoll:** {{protokoll}}

        ## Stand der Mittel
        - …

        ## Anträge und Entscheidungen
        | Posten | Betrag | Entscheidung |
        |---|---|---|
        | … | … | … |

        ## Beschlüsse
        - …

        ## Aufgaben
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - …
        """,

        mitgliederversammlung: """
        # Protokoll: {{titel}}

        **Versammlung:** {{reihe}}
        **Datum:** {{datum}}
        **Anwesende Mitglieder:** {{teilnehmende}}
        **Versammlungsleitung:** …
        **Protokoll:** {{protokoll}}

        ## Formalia
        - Ordnungsgemäße Einladung festgestellt: …
        - Beschlussfähigkeit festgestellt: … (Anzahl anwesender Mitglieder: …)
        - Tagesordnung genehmigt: …

        ## Berichte
        ### Bericht des Vorstands
        - …
        ### Kassenbericht und Kassenprüfung
        - …

        ## Entlastung des Vorstands
        - … (Ja / Nein / Enthaltungen)

        ## Wahlen
        - … (Ergebnis)

        ## Beschlüsse
        - … (Ja / Nein / Enthaltungen)

        ## Verschiedenes
        - …

        ## Aufgaben
        - [ ] Aufgabe – zuständig – Frist

        ## Offene Punkte
        - …

        Ort, Datum, Unterschriften: Versammlungsleitung ……… Protokoll ………
        """,
    ]
}
