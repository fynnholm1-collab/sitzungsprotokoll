import AppKit
import Foundation
import ProtokollKern
import WhisperKit

/// Lokale Spracherkennung mit WhisperKit. Das Modell wird beim ersten Mal
/// heruntergeladen (einmalig, nur das Modell) und danach offline verwendet.
actor TranskriptionsDienst {
    private var whisper: WhisperKit?
    private var geladenesModell: String?

    /// Fortschritt: (erledigte Abschnitte, Abschnitte gesamt).
    typealias Fortschritt = @Sendable (Int, Int) -> Void

    /// Lädt das Modell vollständig (Download, Optimierung für diesen Mac, Tokenizer)
    /// und wärmt es vor. Wichtig: Ohne vollständiges Laden lädt WhisperKit das Modell
    /// erst beim Transkribieren – parallel für jeden Abschnitt –, und dabei gehen
    /// Abschnitte stillschweigend verloren.
    private func lade(modell: String) async throws -> WhisperKit {
        if let whisper, geladenesModell == modell, whisper.modelState == .loaded, whisper.tokenizer != nil {
            return whisper
        }
        // Läuft schon ein Ladevorgang (z. B. die Vorbereitung beim Start), auf ihn warten statt doppelt zu laden.
        if let laden = ladevorgang, ladeModell == modell {
            return try await laden.value
        }
        whisper = nil
        let laden = Task { () throws -> WhisperKit in
            let konfiguration = WhisperKitConfig(
                model: modell.isEmpty ? nil : modell,
                downloadBase: Ablage.modelle,
                prewarm: true,
                load: true)
            let neu = try await WhisperKit(konfiguration)
            if neu.modelState != .loaded || neu.tokenizer == nil {
                try await neu.loadModels()
            }
            return neu
        }
        ladevorgang = laden
        ladeModell = modell
        let stand = generation
        let neu: WhisperKit
        do {
            neu = try await laden.value
        } catch {
            if ladeModell == modell { ladevorgang = nil; ladeModell = nil }
            throw error
        }
        if ladeModell == modell { ladevorgang = nil; ladeModell = nil }
        // Wurde zwischendurch entladen (Arbeitsspeicher für das Sprachmodell), das Modell nicht behalten.
        guard stand == generation else { return neu }
        whisper = neu
        geladenesModell = modell
        return neu
    }

    private var ladevorgang: Task<WhisperKit, Error>?
    private var ladeModell: String?
    private var generation = 0

    /// Lädt das Modell im Voraus (z. B. beim Start der App), damit die erste Transkription schneller beginnt.
    func vorbereiten(modell: String) async {
        _ = try? await lade(modell: modell)
    }

    var istBereit: Bool { whisper?.modelState == .loaded }

    /// Schreibt eine Audiodatei ab. `sprache` ist ein Sprachcode oder leer für automatische Erkennung.
    ///
    /// Die Aufnahme wird an Sprechpausen in Abschnitte von höchstens 30 s geteilt, von denen
    /// mehrere gleichzeitig abgeschrieben werden. Anders als WhisperKits eigene Aufteilung
    /// verliert das keine Abschnitte: Scheitert einer, wird er wiederholt, und scheitert er
    /// erneut, bricht die Transkription mit einer Fehlermeldung ab. Hört Whisper innerhalb eines
    /// Abschnitts zu früh auf (z. B. nach einer Sprechpause), wird der Rest erneut abgeschrieben.
    func transkribiere(datei: URL, sprache: String, modell: String, woerterbuch: [String] = [],
                       fortschritt: Fortschritt? = nil) async throws -> [ProtokollKern.Segment] {
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
        optionen.chunkingStrategy = ChunkingStrategy.none
        if Self.unterstuetztPrompt(whisper) {
            optionen.promptTokens = Self.promptTokens(woerterbuch, tokenizer: whisper.tokenizer)
        }

        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: datei.path)
        let fenster = WhisperKit.sampleRate * 30
        var abschnitte: [AudioChunk]
        if audio.count > fenster {
            abschnitte = try await VADAudioChunker().chunkAll(audioArray: audio, maxChunkLength: fenster, decodeOptions: optionen)
        } else {
            abschnitte = [AudioChunk(seekOffsetIndex: 0, audioSamples: audio)]
        }
        abschnitte.sort { $0.seekOffsetIndex < $1.seekOffsetIndex }

        let gesamt = abschnitte.count
        let parallel = 4
        let o = optionen
        fortschritt?(0, gesamt)
        return try await withThrowingTaskGroup(of: [ProtokollKern.Segment].self) { gruppe in
            var naechster = 0
            func starte() {
                guard naechster < gesamt else { return }
                let abschnitt = abschnitte[naechster]
                naechster += 1
                gruppe.addTask {
                    let versatz = Double(abschnitt.seekOffsetIndex) / Double(WhisperKit.sampleRate)
                    do {
                        return try await Self.abschnitt(abschnitt.audioSamples, versatz: versatz, whisper: whisper, optionen: o)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return try await Self.abschnitt(abschnitt.audioSamples, versatz: versatz, whisper: whisper, optionen: o)
                    }
                }
            }
            for _ in 0..<parallel { starte() }
            var segmente: [ProtokollKern.Segment] = []
            var fertig = 0
            for try await teil in gruppe {
                segmente += teil
                fertig += 1
                fortschritt?(fertig, gesamt)
                starte()
            }
            return segmente.sorted { $0.start < $1.start }
        }
    }

    /// Schreibt einen Abschnitt ab. Endet Whisper mehr als 2 s vor dem Ende des Abschnitts und
    /// folgt danach noch Sprache, wird ab dem letzten erkannten Zeitpunkt weiter abgeschrieben.
    private static func abschnitt(_ samples: [Float], versatz: Double, whisper: WhisperKit,
                                  optionen: DecodingOptions) async throws -> [ProtokollKern.Segment] {
        let rate = WhisperKit.sampleRate
        var ergebnis: [ProtokollKern.Segment] = []
        var start = 0
        var ohnePrompt = optionen
        ohnePrompt.promptTokens = nil
        for _ in 0..<6 {
            try Task.checkCancellation()
            let rest = Array(samples[start...])
            guard rest.count > rate else { break }
            var segmente = try await whisper.transcribe(audioArray: rest, decodeOptions: optionen).flatMap { $0.segments }
            // Mit Prompt beendet Whisper (WhisperKit 0.18) manche Abschnitte sofort ohne Text.
            // Dann denselben Abschnitt ohne Prompt abschreiben, damit nichts verloren geht.
            let ohneText = segmente.allSatisfy { Transkript.bereinigt($0.text).isEmpty }
            if ohneText, optionen.promptTokens != nil {
                segmente = try await whisper.transcribe(audioArray: rest, decodeOptions: ohnePrompt).flatMap { $0.segments }
            }
            let basis = versatz + Double(start) / Double(rate)
            ergebnis += segmente.map {
                ProtokollKern.Segment(start: Double($0.start) + basis, ende: Double($0.end) + basis, text: $0.text)
            }
            let ende = min(rest.count, Int((segmente.map(\.end).max() ?? 0) * Float(rate)))
            guard ende > 0, rest.count - ende > 2 * rate else { break }
            guard !EnergyVAD().calculateActiveChunks(in: Array(rest[ende...])).isEmpty else { break }
            start += ende
        }
        return ergebnis
    }

    /// Wörterbuch als Prompt für Whisper. Gemessen auf einem M2 Pro: Ein Prompt verbessert
    /// Schreibweisen und unterdrückt Fehlerkennungen in Pausen, kostet aber Zeit (95 s Audio:
    /// ohne 29 s, 34 Tokens 40 s, 115 Tokens 68 s). Daher höchstens 60 Tokens; die Reihenfolge
    /// der Einträge ist die Priorität, die vollständige Liste geht ins Protokoll.
    static let promptBudget = 60

    /// Die „Turbo“-Modelle (z. B. large-v3-v20240930, das für Apple-Silicon-Macs empfohlene Modell)
    /// beenden mit Prompt jeden Abschnitt sofort ohne Text (getestet mit WhisperKit 0.18). Bei
    /// ihnen wird das Wörterbuch nur im Protokoll-Auftrag verwendet.
    private static func unterstuetztPrompt(_ whisper: WhisperKit) -> Bool {
        let name = whisper.modelFolder?.lastPathComponent.lowercased() ?? ""
        return !(name.contains("turbo") || name.contains("v20240930"))
    }

    private static func promptTokens(_ woerterbuch: [String], tokenizer: (any WhisperTokenizer)?) -> [Int]? {
        guard !woerterbuch.isEmpty, let tokenizer else { return nil }
        let grenze = tokenizer.specialTokens.specialTokenBegin
        func tokens(_ text: String) -> [Int] { tokenizer.encode(text: text).filter { $0 < grenze } }
        let prompt = Woerterbuch.whisperPrompt(woerterbuch) { tokens($0).count <= promptBudget }
        return prompt.isEmpty ? nil : tokens(prompt)
    }

    func entlade() {
        generation += 1
        ladevorgang?.cancel()
        ladevorgang = nil
        ladeModell = nil
        whisper = nil
        geladenesModell = nil
    }

    /// Ob das Modell schon heruntergeladen wurde (dann kann es beim Start vorbereitet werden).
    static var modellVorhanden: Bool {
        let ordner = Ablage.modelle.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let inhalt = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
        return inhalt.contains { !$0.hasPrefix(".") }
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
