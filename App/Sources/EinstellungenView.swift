import AppKit
import ProtokollKern
import SwiftUI

struct EinstellungenView: View {
    var body: some View {
        TabView {
            AllgemeinTab().tabItem { Label("Allgemein", systemImage: "gearshape") }
            KITab().tabItem { Label("Transkription & KI", systemImage: "cpu") }
            ReihenTab().tabItem { Label("Sitzungsreihen", systemImage: "list.bullet.rectangle") }
            VorlagenTab().tabItem { Label("Vorlagen", systemImage: "doc.richtext") }
        }
        .padding(16)
    }
}

/// Ordnerauswahl über den Finder-Dialog.
@MainActor
func waehleOrdner(start: URL?, titel: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = titel
    panel.prompt = "Auswählen"
    if let start { panel.directoryURL = start }
    return panel.runModal() == .OK ? panel.url : nil
}

private struct AllgemeinTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Protokolle") {
                TextField("Dein Name (Protokollführung)", text: $model.einstellungen.eigenerName)
                LabeledContent("Nextcloud-Protokollordner") {
                    HStack {
                        Text(model.einstellungen.nextcloudOrdner.isEmpty ? "nicht gewählt" : model.einstellungen.nextcloudOrdner)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(model.einstellungen.nextcloudOrdner.isEmpty ? .secondary : .primary)
                        Button("Wählen …") {
                            if let url = waehleOrdner(start: model.einstellungen.nextcloudURL,
                                                      titel: "Wähle den lokal synchronisierten Nextcloud-Ordner, in dem die Protokolle liegen.") {
                                model.einstellungen.nextcloudOrdner = url.path
                            }
                        }
                    }
                }
                Text("Das ist der Ordner auf deinem Mac, den der Nextcloud-Client synchronisiert. Darin liegen die Unterordner der Sitzungsreihen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Word-Datei (.docx) ablegen", isOn: $model.einstellungen.formatWord)
                Toggle("Markdown-Datei (.md) ablegen (für Obsidian und für „offene Punkte“)", isOn: $model.einstellungen.formatMarkdown)
                Toggle("Aufnahme und Transkript nach der Freigabe löschen", isOn: $model.einstellungen.aufnahmeLoeschen)
            }
            Section("Online-Sitzungen") {
                Picker("Ton aufnehmen von", selection: $model.einstellungen.tonquelle) {
                    ForEach(Einstellungen.tonquellen) { Text($0.name).tag($0.id) }
                }
                Text("„Alle Programme“ ist am zuverlässigsten. Schalte dann Mitteilungstöne aus (Fokus „Nicht stören“).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Doppelte Stellen entfernen, wenn das Mikrofon den Lautsprecher mit aufnimmt", isOn: $model.einstellungen.echoFilter)
                HStack {
                    Button("Mikrofon-Freigabe öffnen") { AufnahmeController.oeffneDatenschutzEinstellungen("Privacy_Microphone") }
                    Button("Bildschirm-/Audioaufnahme öffnen") { AufnahmeController.oeffneDatenschutzEinstellungen("Privacy_ScreenCapture") }
                }
            }
            Section("Hinweis zur Einwilligung") {
                TextEditor(text: $model.einstellungen.einwilligungsText)
                    .frame(height: 80)
                Button("Standardtext wiederherstellen") {
                    model.einstellungen.einwilligungsText = Einstellungen.standardEinwilligung
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KITab: View {
    @EnvironmentObject var model: AppModel
    @State private var whisperModelle: [String] = []
    @State private var ollamaModelle: [String] = []
    @State private var ollamaStatus: String?

    var body: some View {
        Form {
            Section("Spracherkennung (Whisper, lokal)") {
                Picker("Modell", selection: $model.einstellungen.whisperModell) {
                    Text("Empfohlen für diesen Mac").tag("")
                    ForEach(whisperModelle, id: \.self) { Text($0).tag($0) }
                    if !model.einstellungen.whisperModell.isEmpty && !whisperModelle.contains(model.einstellungen.whisperModell) {
                        Text(model.einstellungen.whisperModell).tag(model.einstellungen.whisperModell)
                    }
                }
                Text("Das Modell wird beim ersten Transkribieren einmalig heruntergeladen (nur das Modell, keine Daten von dir). Größere Modelle („large-v3“) sind genauer, kleinere („small“) schneller und brauchen weniger Arbeitsspeicher.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Modellordner im Finder zeigen") { NSWorkspace.shared.open(Ablage.modelle) }
            }
            Section("Lokale Zusammenfassung (Ollama)") {
                TextField("Adresse", text: $model.einstellungen.ollamaAdresse)
                if !model.einstellungen.ollamaIstLokal {
                    Text("Achtung: Diese Adresse zeigt nicht auf diesen Mac. Die App fasst nur lokal zusammen.")
                        .font(.caption).foregroundStyle(.red)
                }
                HStack {
                    TextField("Modell", text: $model.einstellungen.ollamaModell)
                    if !ollamaModelle.isEmpty {
                        Menu("Installierte") {
                            ForEach(ollamaModelle, id: \.self) { m in Button(m) { model.einstellungen.ollamaModell = m } }
                        }
                        .fixedSize()
                    }
                }
                Picker("Kontextlänge", selection: $model.einstellungen.ollamaKontext) {
                    Text("8 000 Tokens (wenig Arbeitsspeicher)").tag(8192)
                    Text("16 000 Tokens (empfohlen bei 16 GB)").tag(16384)
                    Text("32 000 Tokens (ab 32 GB)").tag(32768)
                }
                HStack {
                    Button("Verbindung prüfen") { Task { await pruefeOllama() } }
                    if let ollamaStatus { Text(ollamaStatus).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Ollama installieren: ollama.com → herunterladen, dann im Terminal einmalig „ollama pull \(model.einstellungen.ollamaModell)“.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("AskAlma") {
                TextField("Adresse von AskAlma (optional)", text: $model.einstellungen.askAlmaAdresse, prompt: Text("https://…"))
                Text("Wenn hier eine Adresse steht, öffnet die App AskAlma nach dem Kopieren automatisch im Browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            whisperModelle = await TranskriptionsDienst.verfuegbareModelle()
            await pruefeOllama()
        }
    }

    private func pruefeOllama() async {
        let client = OllamaClient(adresse: model.einstellungen.ollamaAdresse, modell: model.einstellungen.ollamaModell, kontext: model.einstellungen.ollamaKontext)
        do {
            ollamaModelle = try await client.modelle()
            if ollamaModelle.isEmpty {
                ollamaStatus = "Ollama läuft, aber es ist noch kein Modell installiert."
            } else if ollamaModelle.contains(where: { $0 == model.einstellungen.ollamaModell || $0 == model.einstellungen.ollamaModell + ":latest" }) {
                ollamaStatus = "Ollama läuft, Modell ist installiert."
            } else {
                ollamaStatus = "Ollama läuft, das gewählte Modell ist aber nicht installiert."
            }
        } catch {
            ollamaModelle = []
            ollamaStatus = "Ollama ist nicht erreichbar."
        }
    }
}

private struct ReihenTab: View {
    @EnvironmentObject var model: AppModel
    @State private var auswahl: UUID?
    @State private var meldung: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                List(selection: $auswahl) {
                    ForEach(model.reihen) { r in
                        Text(r.name).tag(r.id)
                    }
                    .onMove { model.reihen.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(width: 230)
                HStack {
                    Button {
                        let neu = Sitzungsreihe(name: "Neue Reihe")
                        model.reihen.append(neu)
                        auswahl = neu.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let auswahl { model.reihen.removeAll { $0.id == auswahl } }
                        auswahl = nil
                    } label: { Image(systemName: "minus") }
                    .disabled(auswahl == nil)
                    Spacer()
                }
            }
            VStack(alignment: .leading) {
                if let auswahl, let aktuelle = model.reihen.first(where: { $0.id == auswahl }) {
                    ReiheEditor(reihe: Binding(
                        get: { model.reihen.first(where: { $0.id == auswahl }) ?? aktuelle },
                        set: { neu in
                            if let i = model.reihen.firstIndex(where: { $0.id == auswahl }) { model.reihen[i] = neu }
                        }))
                    .id(auswahl)
                } else {
                    Text("Wähle links eine Sitzungsreihe.").foregroundStyle(.secondary)
                }
                Spacer()
                Divider()
                Text("Gemeinsam nutzen").font(.headline)
                Text("Lege Vorlagen und Reihen im Nextcloud-Ordner „\(Ablage.nextcloudVorlagenOrdner)“ ab, damit Kolleg:innen sie übernehmen können.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("In Nextcloud bereitstellen") {
                        do {
                            let n = try model.vorlagenInNextcloudBereitstellen()
                            meldung = "Bereitgestellt: Reihen und \(n) neue Vorlage(n)."
                        } catch { meldung = error.localizedDescription }
                    }
                    Button("Reihen aus Nextcloud übernehmen") {
                        do {
                            let n = try model.reihenAusNextcloudUebernehmen()
                            meldung = "Übernommen, \(n) neue Reihe(n)."
                        } catch { meldung = "Keine gemeinsame Reihenliste gefunden." }
                    }
                }
                .disabled(model.einstellungen.nextcloudURL == nil)
                if let meldung { Text(meldung).font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReiheEditor: View {
    @EnvironmentObject var model: AppModel
    @Binding var reihe: Sitzungsreihe

    var body: some View {
        Form {
            TextField("Name", text: $reihe.name)
            Picker("Vorlage", selection: $reihe.vorlage) {
                ForEach(model.vorlagenSchluessel(), id: \.self) { Text(Vorlagen.anzeigename($0)).tag($0) }
            }
            LabeledContent("Nextcloud-Unterordner") {
                HStack {
                    TextField("", text: $reihe.ordner, prompt: Text(Dateinamen.bereinigt(reihe.name)))
                    Button("Wählen …") {
                        guard let wurzel = model.einstellungen.nextcloudURL else { return }
                        if let url = waehleOrdner(start: wurzel.appendingPathComponent(reihe.zielordner),
                                                  titel: "Wähle den bestehenden Nextcloud-Ordner für „\(reihe.name)“.") {
                            let w = wurzel.resolvingSymlinksInPath().path
                            let p = url.resolvingSymlinksInPath().path
                            if p.hasPrefix(w + "/") {
                                reihe.ordner = String(p.dropFirst(w.count + 1))
                            } else if p == w {
                                reihe.ordner = ""
                            } else {
                                model.fehlermeldung = "Der Ordner muss innerhalb des Nextcloud-Protokollordners liegen."
                            }
                        }
                    }
                    .disabled(model.einstellungen.nextcloudURL == nil)
                }
            }
            Toggle("Findet meist online statt", isOn: $reihe.meistOnline)
            Picker("Protokollsprache", selection: $reihe.protokollsprache) {
                ForEach(Einstellungen.protokollsprachen, id: \.self) { Text($0).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct VorlagenTab: View {
    @EnvironmentObject var model: AppModel
    @State private var auswahl: String?
    @State private var text = ""
    @State private var quelle: Vorlagenquelle = .eingebaut
    @State private var neuerName = ""
    @State private var meldung: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $auswahl) {
                    ForEach(model.vorlagenSchluessel(), id: \.self) { k in
                        Text(Vorlagen.anzeigename(k)).tag(k)
                    }
                }
                .frame(width: 230)
                HStack {
                    TextField("Neue Vorlage", text: $neuerName)
                    Button("Anlegen") {
                        let name = Dateinamen.bereinigt(neuerName)
                        try? model.speichereVorlage(name, text: Vorlagen.eingebaut[Vorlagen.allgemein]!)
                        neuerName = ""
                        auswahl = name
                    }
                    .disabled(neuerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(width: 230)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let auswahl {
                    Text("Quelle: \(quelle.rawValue)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .border(.quaternary)
                    HStack {
                        Button("Speichern") {
                            do {
                                try model.speichereVorlage(auswahl, text: text)
                                lade(auswahl)
                                meldung = "Gespeichert (\(quelle.rawValue))."
                            } catch { meldung = error.localizedDescription }
                        }
                        Button("Lokalen Vorlagenordner öffnen") { NSWorkspace.shared.open(Ablage.vorlagen) }
                        if let meldung { Text(meldung).font(.caption) }
                    }
                    Text("Platzhalter: {{titel}}, {{reihe}}, {{datum}}, {{teilnehmende}}, {{protokoll}}. Aufgaben als „- [ ] …“ unter „## Aufgaben“ und offene Punkte unter „## Offene Punkte“ werden in die nächste Sitzung übernommen.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Wähle links eine Vorlage.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: auswahl) { _, neu in
            meldung = nil
            if let neu { lade(neu) }
        }
    }

    private func lade(_ schluessel: String) {
        let v = model.vorlage(schluessel)
        text = v.text
        quelle = v.quelle
    }
}
