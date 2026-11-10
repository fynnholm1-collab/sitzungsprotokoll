import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

enum AufnahmeFehler: LocalizedError {
    case keinMikrofonZugriff
    case keinBildschirm
    case programmNichtGeoeffnet(String)
    case bildschirmaufnahmeVerweigert

    var errorDescription: String? {
        switch self {
        case .keinMikrofonZugriff:
            return "Die App darf das Mikrofon nicht verwenden. Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon erlauben."
        case .keinBildschirm:
            return "Es wurde kein Bildschirm gefunden, über den der Systemton aufgenommen werden kann."
        case .programmNichtGeoeffnet(let name):
            return "\(name) ist nicht geöffnet. Öffne zuerst die Online-Sitzung im Browser oder wähle in den Einstellungen „Alle Programme“."
        case .bildschirmaufnahmeVerweigert:
            return "Für Online-Sitzungen braucht die App die Erlaubnis „Bildschirm- und Systemaudioaufnahme“. Bitte unter Systemeinstellungen → Datenschutz & Sicherheit erlauben und die App neu starten."
        }
    }
}

/// Hilfsfunktionen zum Schreiben von Audiodateien.
enum Audiodatei {
    /// Legt eine komprimierte AAC-Datei (.m4a) an. Klappt das für das Format nicht,
    /// wird stattdessen eine unkomprimierte .caf-Datei geschrieben.
    static func erstelle(basis: URL, format: AVAudioFormat) throws -> AVAudioFile {
        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let m4a = basis.appendingPathExtension("m4a")
        if format.channelCount <= 2,
           let datei = try? AVAudioFile(forWriting: m4a, settings: aac, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved),
           datei.processingFormat.sampleRate == format.sampleRate,
           datei.processingFormat.channelCount == format.channelCount {
            return datei
        }
        try? FileManager.default.removeItem(at: m4a)
        return try AVAudioFile(forWriting: basis.appendingPathExtension("caf"), settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
    }

    static func pegel(_ puffer: AVAudioPCMBuffer) -> Float {
        guard let daten = puffer.floatChannelData, puffer.frameLength > 0 else { return 0 }
        let n = Int(puffer.frameLength)
        var summe: Float = 0
        let kanal = daten[0]
        for i in 0..<n { summe += kanal[i] * kanal[i] }
        let rms = sqrt(summe / Float(n))
        // grob auf 0…1 abbilden (−50 dB … 0 dB)
        let db = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (db + 50) / 50))
    }
}

/// Nimmt das Mikrofon auf.
final class MikrofonRecorder {
    private let engine = AVAudioEngine()
    private var datei: AVAudioFile?
    private let sperre = NSLock()
    private(set) var ersterPuffer: Date?
    private(set) var dateiURL: URL?
    var beiPegel: ((Float) -> Void)?

    func starte(basis: URL) throws {
        let eingang = engine.inputNode
        let format = eingang.outputFormat(forBus: 0)
        let neueDatei = try Audiodatei.erstelle(basis: basis, format: format)
        datei = neueDatei
        dateiURL = neueDatei.url
        eingang.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] puffer, _ in
            guard let self else { return }
            self.sperre.lock()
            if self.ersterPuffer == nil { self.ersterPuffer = Date() }
            try? self.datei?.write(from: puffer)
            self.sperre.unlock()
            self.beiPegel?(Audiodatei.pegel(puffer))
        }
        engine.prepare()
        try engine.start()
    }

    func stoppe() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sperre.lock()
        datei = nil   // schließt die Datei
        sperre.unlock()
    }
}

/// Nimmt den Ton anderer Programme auf (z. B. BigBlueButton im Browser),
/// über ScreenCaptureKit. Bild wird nicht gespeichert.
final class SystemtonRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var datei: AVAudioFile?
    private var basis: URL?
    private let warteschlange = DispatchQueue(label: "sitzungsprotokoll.systemton")
    private(set) var ersterPuffer: Date?
    private(set) var dateiURL: URL?
    var beiPegel: ((Float) -> Void)?
    var beiFehler: ((Error) -> Void)?

    func starte(basis: URL, bundleID: String) async throws {
        self.basis = basis
        let inhalt: SCShareableContent
        do {
            inhalt = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AufnahmeFehler.bildschirmaufnahmeVerweigert
        }
        guard let bildschirm = inhalt.displays.first else { throw AufnahmeFehler.keinBildschirm }

        let filter: SCContentFilter
        if bundleID.isEmpty {
            let eigene = inhalt.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: bildschirm, excludingApplications: eigene, exceptingWindows: [])
        } else {
            let programme = inhalt.applications.filter { $0.bundleIdentifier == bundleID }
            guard !programme.isEmpty else {
                let name = Einstellungen.tonquellen.first { $0.id == bundleID }?.name ?? bundleID
                throw AufnahmeFehler.programmNichtGeoeffnet(name)
            }
            filter = SCContentFilter(display: bildschirm, including: programme, exceptingWindows: [])
        }

        let konfiguration = SCStreamConfiguration()
        konfiguration.capturesAudio = true
        konfiguration.excludesCurrentProcessAudio = true
        konfiguration.sampleRate = 48_000
        konfiguration.channelCount = 2
        // Das Bild wird nicht gebraucht: so klein und selten wie möglich.
        konfiguration.width = 16
        konfiguration.height = 16
        konfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let neuerStream = SCStream(filter: filter, configuration: konfiguration, delegate: self)
        try neuerStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: warteschlange)
        try neuerStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: warteschlange)
        try await neuerStream.startCapture()
        stream = neuerStream
    }

    func stoppe() async {
        try? await stream?.stopCapture()
        stream = nil
        warteschlange.sync { datei = nil }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let puffer = Self.pcmPuffer(sampleBuffer) else { return }
        if datei == nil, let basis {
            datei = try? Audiodatei.erstelle(basis: basis, format: puffer.format)
            dateiURL = datei?.url
            ersterPuffer = Date()
        }
        try? datei?.write(from: puffer)
        beiPegel?(Audiodatei.pegel(puffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        beiFehler?(error)
    }

    static func pcmPuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let beschreibung = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdZeiger = CMAudioFormatDescriptionGetStreamBasicDescription(beschreibung) else { return nil }
        var asbd = asbdZeiger.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let puffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        puffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: puffer.mutableAudioBufferList)
        return status == noErr ? puffer : nil
    }
}

/// Ergebnis einer Aufnahme.
struct AufnahmeErgebnis {
    var mikrofonDatei: String?
    var systemDatei: String?
    var versatzMikrofon: Double
    var versatzSystem: Double
    var dauer: Double
}

/// Steuert die Aufnahme einer Sitzung (Mikrofon, bei Online-Sitzungen zusätzlich Systemton).
@MainActor
final class AufnahmeController: ObservableObject {
    @Published private(set) var laufendeSitzung: UUID?
    @Published private(set) var dauer: TimeInterval = 0
    @Published private(set) var pegelMikrofon: Float = 0
    @Published private(set) var pegelSystem: Float = 0
    @Published var fehler: String?

    private var mikrofon: MikrofonRecorder?
    private var systemton: SystemtonRecorder?
    private var beginn: Date?
    private var timer: Timer?
    private var aktivitaet: NSObjectProtocol?

    var laeuft: Bool { laufendeSitzung != nil }

    func starte(sitzung: UUID, online: Bool, tonquelle: String) async throws {
        guard laufendeSitzung == nil else { return }

        let erlaubt = await AVCaptureDevice.requestAccess(for: .audio)
        guard erlaubt else { throw AufnahmeFehler.keinMikrofonZugriff }

        let ordner = Ablage.ordner(fuer: sitzung)
        for name in ["mikrofon.m4a", "mikrofon.caf", "system.m4a", "system.caf"] {
            try? FileManager.default.removeItem(at: ordner.appendingPathComponent(name))
        }

        beginn = Date()
        if online {
            let s = SystemtonRecorder()
            s.beiPegel = { [weak self] p in Task { @MainActor in self?.pegelSystem = p } }
            s.beiFehler = { [weak self] e in Task { @MainActor in self?.fehler = "Systemton-Aufnahme unterbrochen: \(e.localizedDescription)" } }
            try await s.starte(basis: ordner.appendingPathComponent("system"), bundleID: tonquelle)
            systemton = s
        }

        let m = MikrofonRecorder()
        m.beiPegel = { [weak self] p in Task { @MainActor in self?.pegelMikrofon = p } }
        do {
            try m.starte(basis: ordner.appendingPathComponent("mikrofon"))
        } catch {
            await systemton?.stoppe()
            systemton = nil
            throw error
        }
        mikrofon = m

        laufendeSitzung = sitzung
        dauer = 0
        aktivitaet = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Sitzung wird aufgenommen")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let beginn = self.beginn else { return }
                self.dauer = Date().timeIntervalSince(beginn)
            }
        }
    }

    func stoppe() async -> AufnahmeErgebnis? {
        guard laufendeSitzung != nil, let beginn else { return nil }
        timer?.invalidate()
        timer = nil
        mikrofon?.stoppe()
        await systemton?.stoppe()
        if let aktivitaet { ProcessInfo.processInfo.endActivity(aktivitaet) }
        aktivitaet = nil

        let ergebnis = AufnahmeErgebnis(
            mikrofonDatei: mikrofon?.ersterPuffer != nil ? mikrofon?.dateiURL?.lastPathComponent : nil,
            systemDatei: systemton?.ersterPuffer != nil ? systemton?.dateiURL?.lastPathComponent : nil,
            versatzMikrofon: mikrofon?.ersterPuffer.map { $0.timeIntervalSince(beginn) } ?? 0,
            versatzSystem: systemton?.ersterPuffer.map { $0.timeIntervalSince(beginn) } ?? 0,
            dauer: Date().timeIntervalSince(beginn))
        mikrofon = nil
        systemton = nil
        self.beginn = nil
        laufendeSitzung = nil
        pegelMikrofon = 0
        pegelSystem = 0
        return ergebnis
    }

    static func oeffneDatenschutzEinstellungen(_ bereich: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(bereich)") {
            NSWorkspace.shared.open(url)
        }
    }
}
