import AppKit
import Foundation
import ProtokollKern
import WhisperKit

/// Lokale Spracherkennung mit WhisperKit. Das Modell wird beim ersten Mal
/// heruntergeladen (einmalig, nur das Modell) und danach offline verwendet.
actor TranskriptionsDienst {
    private var whisper: WhisperKit?
    private var geladenesModell: String?

    private func lade(modell: String) async throws -> WhisperKit {
        if let whisper, geladenesModell == modell { return whisper }
        whisper = nil
        let konfiguration = WhisperKitConfig(
            model: modell.isEmpty ? nil : modell,
            downloadBase: Ablage.modelle)
        let neu = try await WhisperKit(konfiguration)
        whisper = neu
        geladenesModell = modell
        return neu
    }

    /// Schreibt eine Audiodatei ab. `sprache` ist ein Sprachcode oder leer für automatische Erkennung.
    func transkribiere(datei: URL, sprache: String, modell: String) async throws -> [ProtokollKern.Segment] {
        let whisper = try await lade(modell: modell)
        var optionen = DecodingOptions()
        optionen.task = .transcribe
        if sprache.isEmpty {
            optionen.language = nil
            optionen.detectLanguage = true
        } else {
            optionen.language = sprache
            optionen.detectLanguage = false
        }
        optionen.temperature = 0
        optionen.skipSpecialTokens = true
        optionen.withoutTimestamps = false
        optionen.chunkingStrategy = .vad

        let ergebnisse = try await whisper.transcribe(audioPath: datei.path, decodeOptions: optionen)
        return ergebnisse
            .flatMap { $0.segments }
            .map { ProtokollKern.Segment(start: Double($0.start), ende: Double($0.end), text: $0.text) }
            .sorted { $0.start < $1.start }
    }

    func entlade() {
        whisper = nil
        geladenesModell = nil
    }

    static func verfuegbareModelle() async -> [String] {
        (try? await WhisperKit.fetchAvailableModels()) ?? []
    }
}

/// Zugriff auf ein lokal laufendes Ollama (https://ollama.com).
struct OllamaClient {
    var adresse: String
    var modell: String
    var kontext: Int

    enum Fehler: LocalizedError {
        case ungueltigeAdresse
        case nichtErreichbar
        case antwort(String)

        var errorDescription: String? {
            switch self {
            case .ungueltigeAdresse:
                return "Die Ollama-Adresse in den Einstellungen ist ungültig."
            case .nichtErreichbar:
                return "Ollama ist nicht erreichbar. Läuft die Ollama-App? Installation: https://ollama.com"
            case .antwort(let text):
                return "Ollama meldet: \(text)"
            }
        }
    }

    private func url(_ pfad: String) throws -> URL {
        guard let basis = URL(string: adresse.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw Fehler.ungueltigeAdresse }
        return basis.appendingPathComponent(pfad)
    }

    func chat(system: String, nutzer: String) async throws -> String {
        var anfrage = URLRequest(url: try url("api/chat"))
        anfrage.httpMethod = "POST"
        anfrage.timeoutInterval = 1800
        anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Qwen 3 denkt sonst ausführlich nach, bevor es antwortet.
        let nutzerText = modell.lowercased().hasPrefix("qwen3") ? nutzer + "\n\n/no_think" : nutzer
        let koerper: [String: Any] = [
            "model": modell,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": nutzerText],
            ],
            "options": ["num_ctx": kontext, "temperature": 0.2],
        ]
        anfrage.httpBody = try JSONSerialization.data(withJSONObject: koerper)

        let daten: Data
        let antwort: URLResponse
        do {
            (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        } catch let fehler as URLError where fehler.code == .cannotConnectToHost || fehler.code == .cannotFindHost {
            throw Fehler.nichtErreichbar
        }
        let json = try JSONSerialization.jsonObject(with: daten) as? [String: Any]
        if let http = antwort as? HTTPURLResponse, http.statusCode != 200 {
            throw Fehler.antwort((json?["error"] as? String) ?? "HTTP \(http.statusCode)")
        }
        guard let nachricht = json?["message"] as? [String: Any], let inhalt = nachricht["content"] as? String else {
            throw Fehler.antwort("Unerwartete Antwort")
        }
        return Modellantwort.bereinigt(inhalt)
    }

    func modelle() async throws -> [String] {
        let (daten, _) = try await URLSession.shared.data(from: try url("api/tags"))
        let json = try JSONSerialization.jsonObject(with: daten) as? [String: Any]
        let liste = json?["models"] as? [[String: Any]] ?? []
        return liste.compactMap { $0["name"] as? String }.sorted()
    }
}

/// Erstellt Word-Dateien (.docx) aus Markdown, ohne zusätzliche Programme.
enum WordExport {
    @MainActor
    static func daten(markdown: String, titel: String) throws -> Data {
        let html = MarkdownHTML.html(aus: markdown, titel: titel)
        let text = try NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil)
        return try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML,
                .title: titel,
            ])
    }
}
