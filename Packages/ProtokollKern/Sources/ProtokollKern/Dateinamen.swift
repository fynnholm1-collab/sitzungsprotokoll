import Foundation

public enum Dateinamen {
    /// Entfernt Zeichen, die in Datei- und Ordnernamen Probleme machen.
    public static func bereinigt(_ name: String) -> String {
        let verboten = CharacterSet(charactersIn: "/\\:?*\"<>|\n\r\t")
        let teile = name.components(separatedBy: verboten)
        let zusammen = teile.joined(separator: "-")
        let einfach = zusammen
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return einfach.isEmpty ? "Protokoll" : einfach
    }

    /// Datum im Format `JJJJ-MM-TT`, damit Protokolle im Ordner zeitlich sortiert sind.
    public static func isoDatum(_ datum: Date, zeitzone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zeitzone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: datum)
    }

    /// Datum für den Protokollkopf, z. B. „10. November 2026“.
    public static func deutschesDatum(_ datum: Date, zeitzone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = zeitzone
        f.dateFormat = "d. MMMM yyyy"
        return f.string(from: datum)
    }

    /// Basisname eines Protokolls ohne Endung, z. B. „2026-11-10 Geschäftsführung“.
    public static func protokoll(datum: Date, reihe: String, zeitzone: TimeZone = .current) -> String {
        "\(isoDatum(datum, zeitzone: zeitzone)) \(bereinigt(reihe))"
    }

    /// Ein freier Dateiname im Ordner: hängt bei Bedarf „ (2)“, „ (3)“ … an.
    public static func freieDatei(basis: String, endung: String, in ordner: URL, fileManager: FileManager = .default) -> URL {
        var kandidat = ordner.appendingPathComponent("\(basis).\(endung)")
        var nummer = 2
        while fileManager.fileExists(atPath: kandidat.path) {
            kandidat = ordner.appendingPathComponent("\(basis) (\(nummer)).\(endung)")
            nummer += 1
        }
        return kandidat
    }
}
