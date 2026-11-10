import Foundation

/// Namen und Fachbegriffe, deren Schreibweise die Spracherkennung und das
/// Protokoll kennen sollen. Ein Eintrag pro Zeile; die Reihenfolge ist die
/// Priorität (bei der Spracherkennung zählen nur die ersten Einträge).
public enum Woerterbuch {
    public static let standard: [String] = [
        // Personen
        "Fynn Holm", "Robert Horres", "Monika Schrimpf", "Klaus Antoni", "Viktoria Eschbach-Szabo",
        "Volker Elis", "Birgit Staemmler", "Eva-Maria Meyer", "Michael Wachutka", "Petra Jeisel",
        "Jana Katzenberg", "Elisa Hasse", "Julia Swoboda", "Sherief Fitz", "Annika Wagner",
        "Tsui Shuen Lau", "Heidi Buck-Albulet", "Annika Böcker", "Mariko Terao", "Akemi Hamada",
        "Melike Durmaz", "Nobuyo Kamegawa", "Eiji Manita", "Kazuyo Nomura", "Kōichi Yamamura",
        "Martina Ebi", "Heike Glantz-Schückle", "Masami Nakajima", "Chikako Toyoshima",
        "Yoko Koyama-Siebert", "Wolfram Schaffar",
        // Einrichtungen und Orte
        "Japanologie", "Abteilung für Japanologie", "Asien-Orient-Institut (AOI)",
        "Fachbereich Asien-Orient-Wissenschaften", "Philosophische Fakultät",
        "Tübinger Zentrum für Japanstudien (TCJS)", "Kyoto-Zentrum", "Dōshisha-Universität",
        "Doshisha EU Campus", "EU Campus", "Doshisha Week", "Rikkyo-Universität", "Kyoto University",
        "University of Manchester", "JSPS", "KAKENHI", "DFG", "CANUT e.V.",
        "Arbeitskreis Japanische Religionen (AJR)", "The Japanese Alpine Empire", "Sacred Narrative",
        "Haikai", "Bunka-Wenhua", "TUDOKU", "DJiK-Kolloquium", "Fachbibliothek Japanologie",
        "Universitätsbibliothek (UB)", "Keplerstraße 2", "Wilhelmstraße 90", "Köstlinstraße 6",
        "Neue Aula",
        // Begriffe aus dem Alltag
        "Studieninformationstag", "Fachschaft", "Fachstudienberatung", "Lektorat", "Geschäftsführung",
        "Dienstbesprechung", "Finanzplansitzung", "Mountainscapes", "Moodle", "ILIAS", "ALMA",
        "BigBlueButton", "Nextcloud",
    ]

    public static var standardText: String { standard.joined(separator: "\n") }

    /// Einträge aus dem Text der Einstellungen (eine Zeile pro Eintrag, leere Zeilen und Dubletten entfallen).
    public static func eintraege(_ text: String) -> [String] {
        var gesehen = Set<String>()
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && gesehen.insert($0.lowercased()).inserted }
    }

    /// Prompt für Whisper: kommagetrennte Einträge mit führendem Leerzeichen und ohne
    /// abschließenden Punkt (ein Punkt am Ende lässt Whisper teils sofort abbrechen).
    /// Es werden so viele Einträge aufgenommen, wie `passt` erlaubt (z. B. Tokenbudget).
    public static func whisperPrompt(_ eintraege: [String], passt: (String) -> Bool) -> String {
        var prompt = ""
        for e in eintraege {
            let kandidat = prompt.isEmpty ? " " + e : prompt + ", " + e
            guard passt(kandidat) else { break }
            prompt = kandidat
        }
        return prompt
    }

    /// Erkennt Segmente, in denen Whisper bei Stille nur den Prompt wiederholt
    /// (alle Wörter stammen aus dem Wörterbuch, z. B. „Holm, Japanologie, AOI“).
    public static func istPromptEcho(_ text: String, eintraege: [String]) -> Bool {
        let woerter = Self.woerter(text)
        guard woerter.count >= 2 else { return false }
        let bekannt = Set(eintraege.flatMap { Self.woerter($0) })
        return woerter.allSatisfy { bekannt.contains($0) }
    }

    static func woerter(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
