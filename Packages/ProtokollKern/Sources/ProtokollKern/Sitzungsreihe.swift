import Foundation

/// Eine Sitzungsreihe, z. B. „Geschäftsführung“ oder „AG Bibliothek“.
/// Jede Reihe hat eine Protokollvorlage und einen Zielordner in der Nextcloud.
public struct Sitzungsreihe: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Schlüssel der Vorlage (Dateiname ohne `.md`).
    public var vorlage: String
    /// Unterordner im Nextcloud-Protokollordner. Leer bedeutet: Name der Reihe.
    public var ordner: String
    /// Ob die Sitzungen dieser Reihe in der Regel online stattfinden.
    public var meistOnline: Bool
    /// Sprache, in der das Protokoll geschrieben wird.
    public var protokollsprache: String

    public init(
        id: UUID = UUID(),
        name: String,
        vorlage: String = Vorlagen.allgemein,
        ordner: String = "",
        meistOnline: Bool = false,
        protokollsprache: String = "Deutsch"
    ) {
        self.id = id
        self.name = name
        self.vorlage = vorlage
        self.ordner = ordner
        self.meistOnline = meistOnline
        self.protokollsprache = protokollsprache
    }

    /// Kennzeichen für „direkt im Nextcloud-Protokollordner, ohne Unterordner“.
    public static let hauptordner = "."

    /// Relativer Pfad des Zielordners im Nextcloud-Protokollordner. Leer bedeutet:
    /// direkt im Protokollordner (Einstellung „.“). Ohne Angabe wird ein Unterordner
    /// mit dem Namen der Reihe verwendet.
    public var zielordner: String {
        let bereinigt = ordner
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if bereinigt == Self.hauptordner { return "" }
        return bereinigt.isEmpty ? Dateinamen.bereinigt(name) : bereinigt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, vorlage, ordner, meistOnline, protokollsprache
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Neue Reihe"
        vorlage = try c.decodeIfPresent(String.self, forKey: .vorlage) ?? Vorlagen.allgemein
        ordner = try c.decodeIfPresent(String.self, forKey: .ordner) ?? ""
        meistOnline = try c.decodeIfPresent(Bool.self, forKey: .meistOnline) ?? false
        protokollsprache = try c.decodeIfPresent(String.self, forKey: .protokollsprache) ?? "Deutsch"
    }

    /// Die Sitzungsreihen der Abteilung Japanologie als Ausgangspunkt.
    public static var standard: [Sitzungsreihe] {
        [
            Sitzungsreihe(name: "Geschäftsführung", vorlage: Vorlagen.geschaeftsfuehrung),
            Sitzungsreihe(name: "AG Bibliothek"),
            Sitzungsreihe(name: "AG Öffentlichkeitsarbeit"),
            Sitzungsreihe(name: "AG Sprachunterricht", meistOnline: true),
            Sitzungsreihe(name: "AG Tübingen-Kyoto", meistOnline: true),
            Sitzungsreihe(name: "AG Unterrichtsplanung"),
            Sitzungsreihe(name: "AG EU Campus"),
            Sitzungsreihe(name: "Dienstbesprechung", vorlage: Vorlagen.dienstbesprechung, meistOnline: true),
            Sitzungsreihe(name: "Finanzplansitzung", vorlage: Vorlagen.finanzplan, meistOnline: true),
            Sitzungsreihe(name: "Mitgliederversammlung Canut", vorlage: Vorlagen.mitgliederversammlung),
        ]
    }
}
