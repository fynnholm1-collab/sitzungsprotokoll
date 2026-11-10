import Foundation

/// Liest offene Punkte und unerledigte Aufgaben aus einem Protokoll in Markdown,
/// damit sie in der nächsten Sitzung derselben Reihe wieder auftauchen.
public enum OffenePunkte {
    /// Überschriften (Ebene 2), deren Listenpunkte übernommen werden.
    static let stichwoerter = ["offene punkte", "offen", "aufgaben", "to-do", "todo"]

    /// Platzhalter, die nicht als Punkt zählen.
    static let leerwerte: Set<String> = ["", "…", "...", "-", "–", "keine", "keine.", "entfällt", "aufgabe – zuständig – frist"]

    public static func auslesen(aus markdown: String) -> [String] {
        var punkte: [String] = []
        var imAbschnitt = false
        for roheZeile in markdown.components(separatedBy: .newlines) {
            let zeile = roheZeile.trimmingCharacters(in: .whitespaces)
            if let ebene = ueberschriftsebene(zeile) {
                if ebene <= 2 {
                    let titel = zeile.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                    imAbschnitt = stichwoerter.contains { titel.hasPrefix($0) }
                }
                continue
            }
            guard imAbschnitt, let inhalt = listeninhalt(zeile) else { continue }
            var text = inhalt
            if text.hasPrefix("[x]") || text.hasPrefix("[X]") { continue }
            if text.hasPrefix("[ ]") { text = String(text.dropFirst(3)) }
            text = text.trimmingCharacters(in: .whitespaces)
            if leerwerte.contains(text.lowercased()) { continue }
            if !punkte.contains(text) { punkte.append(text) }
        }
        return punkte
    }

    /// Ebene einer Markdown-Überschrift oder `nil`.
    static func ueberschriftsebene(_ zeile: String) -> Int? {
        let rauten = zeile.prefix(while: { $0 == "#" }).count
        guard rauten > 0, rauten <= 6 else { return nil }
        let rest = zeile.dropFirst(rauten)
        return rest.first == " " ? rauten : nil
    }

    /// Inhalt eines Listenpunkts (`- `, `* `, `+ `, `1. `, `1) `) oder `nil`.
    static func listeninhalt(_ zeile: String) -> String? {
        if let erstes = zeile.first, "-*+".contains(erstes), zeile.dropFirst().first == " " {
            return String(zeile.dropFirst(2))
        }
        let ziffern = zeile.prefix(while: { $0.isNumber })
        if !ziffern.isEmpty {
            let rest = zeile.dropFirst(ziffern.count)
            if let zeichen = rest.first, ".)".contains(zeichen), rest.dropFirst().first == " " {
                return String(rest.dropFirst(2))
            }
        }
        return nil
    }

    /// Das neueste Protokoll (`.md`) in einem Ordner. Dateinamen beginnen mit dem Datum
    /// (`JJJJ-MM-TT …`), daher genügt eine Sortierung nach Namen.
    public static func letztesProtokoll(in ordner: URL, ausser: [URL] = [], fileManager: FileManager = .default) -> URL? {
        guard let dateien = try? fileManager.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        let ausgeschlossen = Set(ausser.map { $0.resolvingSymlinksInPath().path })
        return dateien
            .filter { $0.pathExtension.lowercased() == "md" }
            .filter { !ausgeschlossen.contains($0.resolvingSymlinksInPath().path) }
            .filter { $0.lastPathComponent.first?.isNumber == true }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }
}
