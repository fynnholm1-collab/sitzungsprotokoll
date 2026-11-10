import AppKit
import Foundation
import ProtokollKern

/// Woher eine Vorlage stammt.
enum Vorlagenquelle: String {
    case nextcloud = "Nextcloud (gemeinsam)"
    case lokal = "Nur auf diesem Mac"
    case eingebaut = "Eingebaut"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var einstellungen: Einstellungen { didSet { speichereEinstellungen() } }
    @Published var reihen: [Sitzungsreihe] { didSet { speichereReihen() } }
    @Published private(set) var sitzungen: [Sitzung] = []
    @Published var auswahl: Sitzung.ID?
    /// Laufende Arbeitsschritte je Sitzung (z. B. „Transkription läuft …“).
    @Published private(set) var taetigkeit: [UUID: String] = [:]
    @Published var fehlermeldung: String?

    let aufnahme = AufnahmeController()
    let transkription = TranskriptionsDienst()

    init() {
        einstellungen = (try? Ablage.decoder.decode(Einstellungen.self, from: Data(contentsOf: Ablage.einstellungen))) ?? Einstellungen()
        reihen = (try? Ablage.decoder.decode([Sitzungsreihe].self, from: Data(contentsOf: Ablage.reihen))) ?? Sitzungsreihe.standard
        ladeSitzungen()
    }

    // MARK: Speichern und Laden

    private func speichereEinstellungen() {
        try? Ablage.encoder.encode(einstellungen).write(to: Ablage.einstellungen, options: .atomic)
    }

    private func speichereReihen() {
        try? Ablage.encoder.encode(reihen).write(to: Ablage.reihen, options: .atomic)
    }

    private func ladeSitzungen() {
        let fm = FileManager.default
        let ordner = (try? fm.contentsOfDirectory(at: Ablage.sitzungen, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        sitzungen = ordner.compactMap { url in
            try? Ablage.decoder.decode(Sitzung.self, from: Data(contentsOf: url.appendingPathComponent("sitzung.json")))
        }
        sortiere()
    }

    private func sortiere() {
        sitzungen.sort { $0.datum > $1.datum }
    }

    private func schreibe(_ sitzung: Sitzung) {
        let url = Ablage.ordner(fuer: sitzung.id).appendingPathComponent("sitzung.json")
        do {
            try Ablage.encoder.encode(sitzung).write(to: url, options: .atomic)
        } catch {
            fehlermeldung = "Sitzung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func sitzung(_ id: UUID) -> Sitzung? {
        sitzungen.first { $0.id == id }
    }

    func aktualisiere(_ sitzung: Sitzung) {
        guard let index = sitzungen.firstIndex(where: { $0.id == sitzung.id }) else { return }
        guard sitzungen[index] != sitzung else { return }
        let datumGeaendert = sitzungen[index].datum != sitzung.datum
        sitzungen[index] = sitzung
        schreibe(sitzung)
        if datumGeaendert { sortiere() }
    }

    private func aendere(_ id: UUID, _ aenderung: (inout Sitzung) -> Void) {
        guard var s = sitzung(id) else { return }
        aenderung(&s)
        aktualisiere(s)
    }

    func reihe(fuer sitzung: Sitzung) -> Sitzungsreihe? {
        reihen.first { $0.id == sitzung.reiheID }
    }

    @discardableResult
    func neueSitzung(reihe: Sitzungsreihe?, titel: String, datum: Date, online: Bool) -> Sitzung {
        var s = Sitzung(titel: titel, reiheID: reihe?.id, datum: datum, online: online)
        if let reihe, reihe.protokollsprache == "Englisch" { s.sprache = "en" }
        if let reihe, reihe.protokollsprache == "Japanisch" { s.sprache = "ja" }
        sitzungen.append(s)
        sortiere()
        schreibe(s)
        auswahl = s.id
        return s
    }

    func loesche(_ id: UUID) {
        guard aufnahme.laufendeSitzung != id else { return }
        try? FileManager.default.removeItem(at: Ablage.sitzungen.appendingPathComponent(id.uuidString))
        sitzungen.removeAll { $0.id == id }
        if auswahl == id { auswahl = nil }
    }

    // MARK: Aufnahme

    func starteAufnahme(_ id: UUID) async {
        guard let s = sitzung(id) else { return }
        do {
            try await aufnahme.starte(sitzung: id, online: s.online, tonquelle: einstellungen.tonquelle)
            aendere(id) {
                $0.mikrofonDatei = nil
                $0.systemDatei = nil
                $0.transkript = nil
            }
        } catch {
            fehlermeldung = error.localizedDescription
        }
    }

    func stoppeAufnahme() async {
        guard let id = aufnahme.laufendeSitzung, let ergebnis = await aufnahme.stoppe() else { return }
        aendere(id) {
            $0.mikrofonDatei = ergebnis.mikrofonDatei
            $0.systemDatei = ergebnis.systemDatei
            $0.versatzMikrofon = ergebnis.versatzMikrofon
            $0.versatzSystem = ergebnis.versatzSystem
            $0.aufnahmeDauer = ergebnis.dauer
            $0.status = .aufgenommen
        }
        if ergebnis.mikrofonDatei == nil && ergebnis.systemDatei == nil {
            fehlermeldung = "Es wurde kein Ton aufgenommen. Bitte Mikrofon und Berechtigungen prüfen."
        }
    }

    /// Übernimmt eine vorhandene Aufnahme (z. B. vom Handy) in die Sitzung.
    func importiereAudio(_ id: UUID, von quelle: URL) {
        let ordner = Ablage.ordner(fuer: id)
        let endung = quelle.pathExtension.isEmpty ? "m4a" : quelle.pathExtension.lowercased()
        let ziel = ordner.appendingPathComponent("import.\(endung)")
        do {
            try? FileManager.default.removeItem(at: ziel)
            try FileManager.default.copyItem(at: quelle, to: ziel)
            aendere(id) {
                $0.mikrofonDatei = ziel.lastPathComponent
                $0.systemDatei = nil
                $0.versatzMikrofon = 0
                $0.versatzSystem = 0
                $0.transkript = nil
                $0.status = .aufgenommen
            }
        } catch {
            fehlermeldung = "Die Datei konnte nicht übernommen werden: \(error.localizedDescription)"
        }
    }

    func audioURL(_ sitzung: Sitzung, _ datei: String?) -> URL? {
        datei.map { Ablage.ordner(fuer: sitzung.id).appendingPathComponent($0) }
    }

    // MARK: Transkription

    func transkribiere(_ id: UUID) async {
        guard let s = sitzung(id), taetigkeit[id] == nil else { return }
        let modell = einstellungen.whisperModell
        let zweiSpuren = s.mikrofonDatei != nil && s.systemDatei != nil
        taetigkeit[id] = "Spracherkennung wird geladen … (beim ersten Mal wird das Modell heruntergeladen, ca. 1–2 GB)"
        defer { taetigkeit[id] = nil }
        do {
            var spuren: [Spur] = []
            if let url = audioURL(s, s.mikrofonDatei) {
                taetigkeit[id] = zweiSpuren ? "Eigene Spur (Mikrofon) wird abgeschrieben …" : "Aufnahme wird abgeschrieben …"
                let segmente = try await transkription.transkribiere(datei: url, sprache: s.sprache, modell: modell)
                let name = einstellungen.eigenerName.isEmpty ? "Ich" : einstellungen.eigenerName
                spuren.append(Spur(sprecher: zweiSpuren ? name : nil, versatz: s.versatzMikrofon, segmente: segmente))
            }
            if let url = audioURL(s, s.systemDatei) {
                taetigkeit[id] = "Online-Teilnehmende (Browser-Ton) werden abgeschrieben …"
                let segmente = try await transkription.transkribiere(datei: url, sprache: s.sprache, modell: modell)
                spuren.append(Spur(sprecher: zweiSpuren ? "Online-Teilnehmende" : nil, versatz: s.versatzSystem, segmente: segmente))
            }
            let echo: Int? = (zweiSpuren && einstellungen.echoFilter) ? 0 : nil
            let text = Transkript.text(Transkript.zusammenfuehren(spuren, echoSpur: echo))
            aendere(id) {
                $0.transkript = text
                if $0.status == .aufgenommen || $0.status == .neu { $0.status = .transkribiert }
            }
            if text.isEmpty { fehlermeldung = "In der Aufnahme wurde keine Sprache erkannt." }
        } catch {
            fehlermeldung = "Transkription fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Vorlagen

    var nextcloudVorlagenOrdner: URL? {
        einstellungen.nextcloudURL?.appendingPathComponent(Ablage.nextcloudVorlagenOrdner, isDirectory: true)
    }

    /// Sucht eine Vorlage: zuerst gemeinsam in der Nextcloud, dann lokal, dann eingebaut.
    func vorlage(_ schluessel: String) -> (text: String, quelle: Vorlagenquelle) {
        let datei = "\(schluessel).md"
        if let ordner = nextcloudVorlagenOrdner,
           let text = try? String(contentsOf: ordner.appendingPathComponent(datei), encoding: .utf8) {
            return (text, .nextcloud)
        }
        if let text = try? String(contentsOf: Ablage.vorlagen.appendingPathComponent(datei), encoding: .utf8) {
            return (text, .lokal)
        }
        return (Vorlagen.eingebaut[schluessel] ?? Vorlagen.eingebaut[Vorlagen.allgemein]!, .eingebaut)
    }

    /// Alle bekannten Vorlagen (eingebaut, lokal und in der Nextcloud).
    func vorlagenSchluessel() -> [String] {
        var schluessel = Set(Vorlagen.eingebaut.keys)
        for ordner in [Ablage.vorlagen, nextcloudVorlagenOrdner].compactMap({ $0 }) {
            let dateien = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for d in dateien where d.pathExtension.lowercased() == "md" {
                schluessel.insert(d.deletingPathExtension().lastPathComponent)
            }
        }
        return schluessel.sorted { Vorlagen.anzeigename($0).localizedCompare(Vorlagen.anzeigename($1)) == .orderedAscending }
    }

    /// Speichert eine Vorlage dort, woher sie stammt (eingebaute Vorlagen werden lokal gespeichert).
    func speichereVorlage(_ schluessel: String, text: String) throws {
        let ziel: URL
        if vorlage(schluessel).quelle == .nextcloud, let ordner = nextcloudVorlagenOrdner {
            ziel = ordner
        } else {
            ziel = Ablage.vorlagen
        }
        try text.write(to: ziel.appendingPathComponent("\(Dateinamen.bereinigt(schluessel)).md"), atomically: true, encoding: .utf8)
        objectWillChange.send()
    }

    /// Legt alle Vorlagen und die Liste der Sitzungsreihen im gemeinsamen Nextcloud-Ordner ab,
    /// damit Kolleg:innen dieselben Vorlagen nutzen. Vorhandene Dateien bleiben unverändert.
    func vorlagenInNextcloudBereitstellen() throws -> Int {
        guard let ordner = nextcloudVorlagenOrdner else { throw NextcloudFehler.keinOrdner }
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        var anzahl = 0
        for schluessel in vorlagenSchluessel() {
            let ziel = ordner.appendingPathComponent("\(schluessel).md")
            guard !FileManager.default.fileExists(atPath: ziel.path) else { continue }
            try vorlage(schluessel).text.write(to: ziel, atomically: true, encoding: .utf8)
            anzahl += 1
        }
        try Ablage.encoder.encode(reihen).write(to: ordner.appendingPathComponent("reihen.json"), options: .atomic)
        objectWillChange.send()
        return anzahl
    }

    /// Übernimmt die Sitzungsreihen aus dem gemeinsamen Nextcloud-Ordner.
    func reihenAusNextcloudUebernehmen() throws -> Int {
        guard let ordner = nextcloudVorlagenOrdner else { throw NextcloudFehler.keinOrdner }
        let daten = try Data(contentsOf: ordner.appendingPathComponent("reihen.json"))
        let neue = try Ablage.decoder.decode([Sitzungsreihe].self, from: daten)
        var hinzugefuegt = 0
        for reihe in neue {
            if let i = reihen.firstIndex(where: { $0.id == reihe.id || $0.name == reihe.name }) {
                let alteID = reihen[i].id
                reihen[i] = reihe
                reihen[i].id = alteID
            } else {
                reihen.append(reihe)
                hinzugefuegt += 1
            }
        }
        return hinzugefuegt
    }

    // MARK: Offene Punkte

    /// Offene Punkte aus dem letzten Protokoll derselben Reihe.
    func offenePunkte(fuer sitzung: Sitzung) -> (punkte: [String], quelle: String)? {
        guard let reihe = self.reihe(fuer: sitzung) else { return nil }
        let eigene = sitzung.freigegebenePfade.map { URL(fileURLWithPath: $0) }
        if let ordner = zielordner(fuer: reihe),
           let datei = OffenePunkte.letztesProtokoll(in: ordner, ausser: eigene),
           let text = try? String(contentsOf: datei, encoding: .utf8) {
            return (OffenePunkte.auslesen(aus: text), datei.lastPathComponent)
        }
        // Sonst: letzte freigegebene Sitzung dieser Reihe auf diesem Mac.
        let frueher = sitzungen
            .filter { $0.reiheID == reihe.id && $0.id != sitzung.id && $0.status == .freigegeben && $0.datum < sitzung.datum }
            .max { $0.datum < $1.datum }
        if let frueher {
            return (OffenePunkte.auslesen(aus: frueher.entwurf), "\(frueher.titel), \(Dateinamen.deutschesDatum(frueher.datum))")
        }
        return nil
    }

    // MARK: Protokoll

    func auftrag(fuer s: Sitzung, offenePunkte: [String]) -> ProtokollAuftrag {
        let reihe = self.reihe(fuer: s)
        let vorlagenText = vorlage(reihe?.vorlage ?? Vorlagen.allgemein).text
        let ausgefuellt = Vorlagen.ausfuellen(vorlagenText, werte: [
            "reihe": reihe?.name ?? "Sitzung",
            "titel": s.titel,
            "datum": Dateinamen.deutschesDatum(s.datum),
            "teilnehmende": s.teilnehmende,
            "protokoll": einstellungen.eigenerName,
        ])
        return ProtokollAuftrag(
            vorlage: ausgefuellt,
            offenePunkte: offenePunkte,
            transkript: s.transkript ?? "",
            sprache: reihe?.protokollsprache ?? "Deutsch",
            reihe: reihe?.name ?? s.titel)
    }

    /// Erstellt den Protokollentwurf mit dem lokalen Sprachmodell (Ollama).
    func zusammenfassenLokal(_ id: UUID, offenePunkte: [String]) async {
        guard let s = sitzung(id), taetigkeit[id] == nil else { return }
        guard einstellungen.ollamaIstLokal else {
            fehlermeldung = "Die Ollama-Adresse zeigt nicht auf diesen Mac. Aus Datenschutzgründen fasst die App nur lokal zusammen."
            return
        }
        let client = OllamaClient(adresse: einstellungen.ollamaAdresse, modell: einstellungen.ollamaModell, kontext: einstellungen.ollamaKontext)
        let auftrag = self.auftrag(fuer: s, offenePunkte: offenePunkte)
        // Etwa 3,5 Zeichen pro Token; Platz für Vorlage und Antwort lassen.
        let maxZeichen = max(8_000, Int(Double(einstellungen.ollamaKontext) * 3.5 * 0.55))
        taetigkeit[id] = "Protokoll wird vorbereitet …"
        defer { taetigkeit[id] = nil }

        // Spracherkennung freigeben, damit genug Arbeitsspeicher für das Sprachmodell bleibt.
        await transkription.entlade()
        do {
            let ergebnis: String
            if auftrag.transkript.count <= maxZeichen {
                taetigkeit[id] = "Protokoll wird lokal erstellt (\(einstellungen.ollamaModell)) …"
                ergebnis = try await client.chat(system: auftrag.systemText, nutzer: auftrag.nutzerText)
            } else {
                let teile = ProtokollAuftrag.abschnitte(auftrag.transkript, maxZeichen: maxZeichen)
                var notizen: [String] = []
                for (i, teil) in teile.enumerated() {
                    taetigkeit[id] = "Abschnitt \(i + 1) von \(teile.count) wird zusammengefasst …"
                    let a = auftrag.teilauftrag(abschnitt: teil, nummer: i + 1, von: teile.count)
                    notizen.append(try await client.chat(system: a.system, nutzer: a.nutzer))
                }
                taetigkeit[id] = "Protokoll wird zusammengeführt …"
                let z = auftrag.zusammenfuehrung(notizen: notizen)
                ergebnis = try await client.chat(system: z.system, nutzer: z.nutzer)
            }
            aendere(id) {
                $0.entwurf = ergebnis
                if $0.status != .freigegeben { $0.status = .entwurf }
            }
        } catch {
            fehlermeldung = "Zusammenfassung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Kopiert Anweisungen, Vorlage und Transkript für AskAlma in die Zwischenablage.
    func kopiereFuerAskAlma(_ id: UUID, offenePunkte: [String]) -> Int {
        guard let s = sitzung(id) else { return 0 }
        let text = auftrag(fuer: s, offenePunkte: offenePunkte).askAlmaText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if let url = URL(string: einstellungen.askAlmaAdresse.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
        }
        return text.count
    }

    func uebernehmeEntwurf(_ id: UUID, text: String) {
        aendere(id) {
            $0.entwurf = Modellantwort.bereinigt(text)
            if $0.status != .freigegeben { $0.status = .entwurf }
        }
    }

    // MARK: Nextcloud-Freigabe

    enum NextcloudFehler: LocalizedError {
        case keinOrdner, ordnerFehlt(String), keinFormat, keineReihe

        var errorDescription: String? {
            switch self {
            case .keinOrdner: return "Bitte zuerst in den Einstellungen den Nextcloud-Protokollordner wählen."
            case .ordnerFehlt(let pfad): return "Der Nextcloud-Ordner ist nicht erreichbar: \(pfad). Läuft der Nextcloud-Client?"
            case .keinFormat: return "Bitte in den Einstellungen mindestens ein Dateiformat (Word oder Markdown) wählen."
            case .keineReihe: return "Bitte der Sitzung eine Sitzungsreihe zuordnen."
            }
        }
    }

    func zielordner(fuer reihe: Sitzungsreihe) -> URL? {
        einstellungen.nextcloudURL?.appendingPathComponent(reihe.zielordner, isDirectory: true)
    }

    /// Geplante Zieldateien der Freigabe.
    func zieldateien(fuer s: Sitzung) -> [URL] {
        if !s.freigegebenePfade.isEmpty { return s.freigegebenePfade.map { URL(fileURLWithPath: $0) } }
        guard let reihe = self.reihe(fuer: s), let ordner = zielordner(fuer: reihe) else { return [] }
        let basis = Dateinamen.protokoll(datum: s.datum, reihe: reihe.name)
        var dateien: [URL] = []
        if einstellungen.formatWord { dateien.append(Dateinamen.freieDatei(basis: basis, endung: "docx", in: ordner)) }
        if einstellungen.formatMarkdown { dateien.append(Dateinamen.freieDatei(basis: basis, endung: "md", in: ordner)) }
        return dateien
    }

    /// Legt das geprüfte Protokoll im Nextcloud-Ordner der Reihe ab. Nur auf ausdrücklichen Klick.
    func freigeben(_ id: UUID) throws -> [URL] {
        guard let s = sitzung(id) else { return [] }
        guard let wurzel = einstellungen.nextcloudURL else { throw NextcloudFehler.keinOrdner }
        guard FileManager.default.fileExists(atPath: wurzel.path) else { throw NextcloudFehler.ordnerFehlt(wurzel.path) }
        guard reihe(fuer: s) != nil else { throw NextcloudFehler.keineReihe }
        let dateien = zieldateien(fuer: s)
        guard !dateien.isEmpty else { throw NextcloudFehler.keinFormat }

        for datei in dateien {
            try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch datei.pathExtension.lowercased() {
            case "docx":
                try WordExport.daten(markdown: s.entwurf, titel: s.titel).write(to: datei, options: .atomic)
            default:
                try s.entwurf.write(to: datei, atomically: true, encoding: .utf8)
            }
        }

        let loeschen = einstellungen.aufnahmeLoeschen
        if loeschen {
            for datei in [s.mikrofonDatei, s.systemDatei].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: Ablage.ordner(fuer: id).appendingPathComponent(datei))
            }
        }
        aendere(id) {
            $0.freigegebenePfade = dateien.map(\.path)
            $0.freigegebenAm = Date()
            $0.status = .freigegeben
            if loeschen {
                $0.mikrofonDatei = nil
                $0.systemDatei = nil
                $0.transkript = nil
            }
        }
        return dateien
    }
}
