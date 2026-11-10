import Foundation
import ProtokollKern

/// Eine aufgezeichnete Sitzung mit Aufnahme, Transkript und Protokollentwurf.
/// Alles liegt nur lokal unter ~/Library/Application Support/Sitzungsprotokoll.
struct Sitzung: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case neu, aufgenommen, transkribiert, entwurf, freigegeben

        var anzeige: String {
            switch self {
            case .neu: return "Neu"
            case .aufgenommen: return "Aufgenommen"
            case .transkribiert: return "Transkribiert"
            case .entwurf: return "Entwurf"
            case .freigegeben: return "Freigegeben"
            }
        }

        var symbol: String {
            switch self {
            case .neu: return "circle"
            case .aufgenommen: return "waveform"
            case .transkribiert: return "text.alignleft"
            case .entwurf: return "doc.text"
            case .freigegeben: return "checkmark.circle.fill"
            }
        }
    }

    var id: UUID = UUID()
    var titel: String
    var reiheID: UUID?
    var datum: Date = Date()
    var teilnehmende: String = ""
    var online: Bool = false
    /// Sprachcode für Whisper ("de", "en", "ja") oder leer für automatische Erkennung.
    var sprache: String = "de"
    var status: Status = .neu
    var einwilligung: Bool = false
    var mikrofonDatei: String?
    var systemDatei: String?
    var versatzMikrofon: Double = 0
    var versatzSystem: Double = 0
    var aufnahmeDauer: Double = 0
    var transkript: String?
    var entwurf: String = ""
    var freigegebenePfade: [String] = []
    var freigegebenAm: Date?

    init(titel: String, reiheID: UUID?, datum: Date = Date(), online: Bool = false) {
        self.titel = titel
        self.reiheID = reiheID
        self.datum = datum
        self.online = online
    }

    enum CodingKeys: String, CodingKey {
        case id, titel, reiheID, datum, teilnehmende, online, sprache, status, einwilligung
        case mikrofonDatei, systemDatei, versatzMikrofon, versatzSystem, aufnahmeDauer
        case transkript, entwurf, freigegebenePfade, freigegebenAm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        titel = try c.decodeIfPresent(String.self, forKey: .titel) ?? "Sitzung"
        reiheID = try c.decodeIfPresent(UUID.self, forKey: .reiheID)
        datum = try c.decodeIfPresent(Date.self, forKey: .datum) ?? Date()
        teilnehmende = try c.decodeIfPresent(String.self, forKey: .teilnehmende) ?? ""
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? false
        sprache = try c.decodeIfPresent(String.self, forKey: .sprache) ?? "de"
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .neu
        einwilligung = try c.decodeIfPresent(Bool.self, forKey: .einwilligung) ?? false
        mikrofonDatei = try c.decodeIfPresent(String.self, forKey: .mikrofonDatei)
        systemDatei = try c.decodeIfPresent(String.self, forKey: .systemDatei)
        versatzMikrofon = try c.decodeIfPresent(Double.self, forKey: .versatzMikrofon) ?? 0
        versatzSystem = try c.decodeIfPresent(Double.self, forKey: .versatzSystem) ?? 0
        aufnahmeDauer = try c.decodeIfPresent(Double.self, forKey: .aufnahmeDauer) ?? 0
        transkript = try c.decodeIfPresent(String.self, forKey: .transkript)
        entwurf = try c.decodeIfPresent(String.self, forKey: .entwurf) ?? ""
        freigegebenePfade = try c.decodeIfPresent([String].self, forKey: .freigegebenePfade) ?? []
        freigegebenAm = try c.decodeIfPresent(Date.self, forKey: .freigegebenAm)
    }

    var hatAufnahme: Bool { mikrofonDatei != nil || systemDatei != nil }
}

/// Einstellungen der App. Werden lokal gespeichert.
struct Einstellungen: Codable, Equatable {
    /// Name im Protokollkopf und für die eigene Spur bei Online-Sitzungen.
    var eigenerName: String = NSFullUserName()
    /// Lokaler, von der Nextcloud synchronisierter Ordner für Protokolle.
    var nextcloudOrdner: String = ""
    var formatWord: Bool = true
    var formatMarkdown: Bool = true
    /// Aufnahme und Transkript nach der Freigabe löschen.
    var aufnahmeLoeschen: Bool = true
    /// WhisperKit-Modell; leer bedeutet: für diesen Mac empfohlenes Modell.
    var whisperModell: String = ""
    var ollamaAdresse: String = "http://127.0.0.1:11434"
    var ollamaModell: String = "qwen3:8b"
    var ollamaKontext: Int = 16384
    var askAlmaAdresse: String = ""
    /// Bundle-ID des Programms, dessen Ton bei Online-Sitzungen aufgenommen wird; leer = alle Programme.
    var tonquelle: String = ""
    var echoFilter: Bool = true
    var einwilligungsText: String = Einstellungen.standardEinwilligung

    static let standardEinwilligung = """
    Hinweis: Diese Sitzung wird zur Erstellung des Protokolls aufgezeichnet. Aufnahme und Transkript werden ausschließlich lokal auf meinem Rechner verarbeitet und nach Fertigstellung des Protokolls gelöscht. Wenn Sie nicht einverstanden sind, sagen Sie es bitte jetzt; dann wird nicht aufgezeichnet.
    """

    init() {}

    enum CodingKeys: String, CodingKey {
        case eigenerName, nextcloudOrdner, formatWord, formatMarkdown, aufnahmeLoeschen, whisperModell
        case ollamaAdresse, ollamaModell, ollamaKontext, askAlmaAdresse, tonquelle, echoFilter, einwilligungsText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = Einstellungen()
        eigenerName = try c.decodeIfPresent(String.self, forKey: .eigenerName) ?? s.eigenerName
        nextcloudOrdner = try c.decodeIfPresent(String.self, forKey: .nextcloudOrdner) ?? s.nextcloudOrdner
        formatWord = try c.decodeIfPresent(Bool.self, forKey: .formatWord) ?? s.formatWord
        formatMarkdown = try c.decodeIfPresent(Bool.self, forKey: .formatMarkdown) ?? s.formatMarkdown
        aufnahmeLoeschen = try c.decodeIfPresent(Bool.self, forKey: .aufnahmeLoeschen) ?? s.aufnahmeLoeschen
        whisperModell = try c.decodeIfPresent(String.self, forKey: .whisperModell) ?? s.whisperModell
        ollamaAdresse = try c.decodeIfPresent(String.self, forKey: .ollamaAdresse) ?? s.ollamaAdresse
        ollamaModell = try c.decodeIfPresent(String.self, forKey: .ollamaModell) ?? s.ollamaModell
        ollamaKontext = try c.decodeIfPresent(Int.self, forKey: .ollamaKontext) ?? s.ollamaKontext
        askAlmaAdresse = try c.decodeIfPresent(String.self, forKey: .askAlmaAdresse) ?? s.askAlmaAdresse
        tonquelle = try c.decodeIfPresent(String.self, forKey: .tonquelle) ?? s.tonquelle
        echoFilter = try c.decodeIfPresent(Bool.self, forKey: .echoFilter) ?? s.echoFilter
        einwilligungsText = try c.decodeIfPresent(String.self, forKey: .einwilligungsText) ?? s.einwilligungsText
    }

    var nextcloudURL: URL? {
        let pfad = nextcloudOrdner.trimmingCharacters(in: .whitespacesAndNewlines)
        return pfad.isEmpty ? nil : URL(fileURLWithPath: (pfad as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Ob die Ollama-Adresse auf diesen Rechner zeigt.
    var ollamaIstLokal: Bool {
        guard let host = URL(string: ollamaAdresse)?.host?.lowercased() else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }

    static let sprachen: [Auswahl] = [
        Auswahl("de", "Deutsch"), Auswahl("en", "Englisch"), Auswahl("ja", "Japanisch"), Auswahl("", "Automatisch erkennen"),
    ]

    static let tonquellen: [Auswahl] = [
        Auswahl("", "Alle Programme"),
        Auswahl("com.apple.Safari", "Safari"),
        Auswahl("com.google.Chrome", "Google Chrome"),
        Auswahl("org.mozilla.firefox", "Firefox"),
        Auswahl("com.microsoft.edgemac", "Microsoft Edge"),
        Auswahl("us.zoom.xos", "Zoom"),
        Auswahl("com.microsoft.teams2", "Microsoft Teams"),
    ]

    static let protokollsprachen = ["Deutsch", "Englisch", "Japanisch"]
}

/// Ein Eintrag für Auswahllisten.
struct Auswahl: Identifiable, Hashable {
    let id: String
    let name: String
    init(_ id: String, _ name: String) {
        self.id = id
        self.name = name
    }
}

/// Ablageorte der App.
enum Ablage {
    static var basis: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sitzungsprotokoll", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sitzungen: URL { unterordner("Sitzungen") }
    static var vorlagen: URL { unterordner("Vorlagen") }
    static var modelle: URL { unterordner("Modelle") }
    static var einstellungen: URL { basis.appendingPathComponent("einstellungen.json") }
    static var reihen: URL { basis.appendingPathComponent("reihen.json") }

    static func ordner(fuer sitzung: UUID) -> URL {
        let url = sitzungen.appendingPathComponent(sitzung.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func unterordner(_ name: String) -> URL {
        let url = basis.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Name des gemeinsamen Vorlagenordners in der Nextcloud.
    static let nextcloudVorlagenOrdner = "_Vorlagen Sitzungsprotokoll"

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
