import AppKit
import ProtokollKern
import SwiftUI
import UniformTypeIdentifiers

struct SitzungView: View {
    let id: UUID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var aufnahme: AufnahmeController

    @State private var offene: (punkte: [String], quelle: String)?
    @State private var offeneUebernehmen = true
    @State private var askAlmaAntwort = ""
    @State private var askAlmaOffen = false
    @State private var kopiertHinweis: String?
    @State private var importieren = false
    @State private var neuAufnehmenFragen = false
    @State private var entwurfErsetzenFragen = false
    @State private var freigabeFragen = false
    @State private var freigabeErgebnis: [URL] = []

    private var s: Sitzung { model.sitzung(id) ?? Sitzung(titel: "", reiheID: nil) }
    private var nimmtAuf: Bool { aufnahme.laufendeSitzung == id }
    private var andereAufnahmeLaeuft: Bool { aufnahme.laeuft && !nimmtAuf }
    private var beschaeftigt: Bool { model.taetigkeit[id] != nil }
    private var offenePunkteFuerAuftrag: [String] { offeneUebernehmen ? (offene?.punkte ?? []) : [] }

    private func binding<T>(_ pfad: WritableKeyPath<Sitzung, T>) -> Binding<T> {
        Binding(
            get: { s[keyPath: pfad] },
            set: { wert in
                var neu = s
                neu[keyPath: pfad] = wert
                model.aktualisiere(neu)
            })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kopf
                if let t = model.taetigkeit[id] {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(t)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                offenePunkteBereich
                aufnahmeBereich
                transkriptBereich
                protokollBereich
                freigabeBereich
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(s.titel)
        .onAppear(perform: ladeOffenePunkte)
        .onChange(of: s.reiheID) { _, _ in ladeOffenePunkte() }
        .fileImporter(isPresented: $importieren, allowedContentTypes: [.audio, .movie]) { ergebnis in
            if case .success(let url) = ergebnis {
                let zugriff = url.startAccessingSecurityScopedResource()
                model.importiereAudio(id, von: url)
                if zugriff { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private func ladeOffenePunkte() {
        offene = model.offenePunkte(fuer: s)
    }

    // MARK: Kopf

    private var kopf: some View {
        GroupBox {
            Form {
                TextField("Titel", text: binding(\.titel))
                Picker("Sitzungsreihe", selection: binding(\.reiheID)) {
                    Text("Ohne Reihe").tag(UUID?.none)
                    ForEach(model.reihen) { r in Text(r.name).tag(UUID?.some(r.id)) }
                }
                DatePicker("Datum", selection: binding(\.datum))
                TextField("Teilnehmende", text: binding(\.teilnehmende), prompt: Text("z. B. Namen oder Gremium"), axis: .vertical)
                    .lineLimit(1...4)
                Picker("Ort", selection: binding(\.online)) {
                    Text("Vor Ort").tag(false)
                    Text("Online").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(nimmtAuf)
                Picker("Gesprochene Sprache", selection: binding(\.sprache)) {
                    ForEach(Einstellungen.sprachen) { Text($0.name).tag($0.id) }
                }
            }
            .padding(6)
        } label: {
            Label(s.status.anzeige, systemImage: s.status.symbol)
        }
    }

    // MARK: Offene Punkte

    @ViewBuilder
    private var offenePunkteBereich: some View {
        if let offene, !offene.punkte.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(offene.punkte, id: \.self) { p in
                        Label(p, systemImage: "circle").labelStyle(.titleAndIcon)
                    }
                    Toggle("Beim Protokoll berücksichtigen", isOn: $offeneUebernehmen)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            } label: {
                Text("Offene Punkte aus der letzten Sitzung (\(offene.quelle))")
            }
        }
    }

    // MARK: Aufnahme

    private var aufnahmeBereich: some View {
        GroupBox("1 · Aufnahme") {
            VStack(alignment: .leading, spacing: 12) {
                if nimmtAuf {
                    HStack(spacing: 16) {
                        Image(systemName: "record.circle.fill").foregroundStyle(.red).font(.title)
                        Text(Transkript.zeitstempel(aufnahme.dauer)).font(.title2.monospacedDigit())
                        VStack(alignment: .leading, spacing: 4) {
                            pegel("Mikrofon", aufnahme.pegelMikrofon)
                            if s.online { pegel("Browser-Ton", aufnahme.pegelSystem) }
                        }
                        Spacer()
                        Button {
                            Task { await model.stoppeAufnahme() }
                        } label: {
                            Label("Aufnahme beenden", systemImage: "stop.fill")
                        }
                        .controlSize(.large)
                        .keyboardShortcut(".", modifiers: .command)
                    }
                    if let f = aufnahme.fehler {
                        Text(f).foregroundStyle(.red).font(.callout)
                    }
                } else {
                    if s.hatAufnahme {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Aufnahme vorhanden: \(Transkript.zeitstempel(s.aufnahmeDauer))"
                                 + (s.systemDatei != nil ? " · zwei Spuren (Mikrofon und Browser-Ton)" : ""))
                            Spacer()
                            Button("Im Finder zeigen") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [s.mikrofonDatei, s.systemDatei].compactMap { model.audioURL(s, $0) })
                            }
                        }
                    } else if s.status == .freigegeben {
                        Text("Die Aufnahme wurde nach der Freigabe gelöscht.").foregroundStyle(.secondary)
                    }

                    Toggle(isOn: binding(\.einwilligung)) {
                        Text("Alle Teilnehmenden wurden informiert und sind mit der Aufnahme einverstanden.")
                    }
                    HStack {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.einstellungen.einwilligungsText, forType: .string)
                            kopiertHinweis = "Hinweistext kopiert. Bei Online-Sitzungen in den Chat einfügen."
                        } label: {
                            Label("Hinweistext kopieren", systemImage: "doc.on.doc")
                        }
                        if let kopiertHinweis { Text(kopiertHinweis).font(.caption).foregroundStyle(.secondary) }
                    }
                    if s.online {
                        Text("Online: Aufgenommen werden dein Mikrofon und der Ton von \(tonquelleName). Mit Kopfhörern wird es am saubersten.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button {
                            if s.hatAufnahme { neuAufnehmenFragen = true } else { Task { await model.starteAufnahme(id) } }
                        } label: {
                            Label(s.hatAufnahme ? "Neu aufnehmen" : "Aufnahme starten", systemImage: "record.circle")
                        }
                        .controlSize(.large)
                        .disabled(!s.einwilligung || andereAufnahmeLaeuft || beschaeftigt)

                        Button("Audiodatei importieren …") { importieren = true }
                            .disabled(beschaeftigt)
                        if andereAufnahmeLaeuft {
                            Text("Es läuft bereits eine andere Aufnahme.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .confirmationDialog("Neu aufnehmen?", isPresented: $neuAufnehmenFragen) {
            Button("Vorhandene Aufnahme ersetzen", role: .destructive) { Task { await model.starteAufnahme(id) } }
        } message: {
            Text("Die bisherige Aufnahme und das Transkript dieser Sitzung werden ersetzt.")
        }
    }

    private var tonquelleName: String {
        let q = model.einstellungen.tonquelle
        return q.isEmpty ? "allen Programmen" : (Einstellungen.tonquellen.first { $0.id == q }?.name ?? q)
    }

    private func pegel(_ name: String, _ wert: Float) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.caption).frame(width: 80, alignment: .leading)
            ProgressView(value: Double(wert)).frame(width: 140)
        }
    }

    // MARK: Transkript

    private var transkriptBereich: some View {
        GroupBox("2 · Transkript") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        Task { await model.transkribiere(id) }
                    } label: {
                        Label(s.transkript == nil ? "Transkribieren" : "Erneut transkribieren", systemImage: "text.bubble")
                    }
                    .disabled(!s.hatAufnahme || nimmtAuf || beschaeftigt)
                    Text("läuft vollständig auf diesem Mac").font(.caption).foregroundStyle(.secondary)
                }
                if s.transkript != nil {
                    TextEditor(text: Binding(get: { s.transkript ?? "" }, set: { neu in
                        var n = s
                        n.transkript = neu
                        model.aktualisiere(n)
                    }))
                    .font(.system(.body, design: .default))
                    .frame(minHeight: 180, maxHeight: 320)
                    .border(.quaternary)
                    Text("Du kannst Hörfehler hier direkt korrigieren, bevor das Protokoll erstellt wird.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    // MARK: Protokoll

    private var protokollBereich: some View {
        GroupBox("3 · Protokoll") {
            VStack(alignment: .leading, spacing: 10) {
                let hatTranskript = !(s.transkript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack {
                    Button {
                        if s.entwurf.isEmpty { Task { await model.zusammenfassenLokal(id, offenePunkte: offenePunkteFuerAuftrag) } }
                        else { entwurfErsetzenFragen = true }
                    } label: {
                        Label("Lokal zusammenfassen", systemImage: "cpu")
                    }
                    .help("Mit dem lokalen Sprachmodell über Ollama (\(model.einstellungen.ollamaModell))")
                    .disabled(!hatTranskript || beschaeftigt)

                    Button {
                        let zeichen = model.kopiereFuerAskAlma(id, offenePunkte: offenePunkteFuerAuftrag)
                        askAlmaOffen = true
                        kopiertHinweis = nil
                        askAlmaHinweis = "In die Zwischenablage kopiert (\(zeichen.formatted()) Zeichen). In AskAlma einfügen und die Antwort unten wieder einfügen."
                    } label: {
                        Label("Für AskAlma kopieren", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!hatTranskript || beschaeftigt)
                }

                if askAlmaOffen {
                    VStack(alignment: .leading, spacing: 6) {
                        if let askAlmaHinweis { Text(askAlmaHinweis).font(.callout).foregroundStyle(.secondary) }
                        TextEditor(text: $askAlmaAntwort)
                            .frame(minHeight: 100, maxHeight: 200)
                            .border(.quaternary)
                        HStack {
                            Button("Antwort als Entwurf übernehmen") {
                                model.uebernehmeEntwurf(id, text: askAlmaAntwort)
                                askAlmaAntwort = ""
                                askAlmaOffen = false
                            }
                            .disabled(askAlmaAntwort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Schließen") { askAlmaOffen = false }
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }

                if !s.entwurf.isEmpty || s.status == .entwurf || s.status == .freigegeben {
                    Text("Entwurf (Markdown, frei bearbeitbar)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: binding(\.entwurf))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320, maxHeight: 600)
                        .border(.quaternary)
                } else {
                    Button("Leeren Entwurf aus Vorlage anlegen") {
                        let a = model.auftrag(fuer: s, offenePunkte: [])
                        model.uebernehmeEntwurf(id, text: a.vorlage)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .confirmationDialog("Entwurf ersetzen?", isPresented: $entwurfErsetzenFragen) {
            Button("Neuen Entwurf erstellen", role: .destructive) {
                Task { await model.zusammenfassenLokal(id, offenePunkte: offenePunkteFuerAuftrag) }
            }
        } message: {
            Text("Der vorhandene Entwurf mit deinen Änderungen wird überschrieben.")
        }
    }

    @State private var askAlmaHinweis: String?

    // MARK: Freigabe

    private var freigabeBereich: some View {
        GroupBox("4 · Freigabe in die Nextcloud") {
            VStack(alignment: .leading, spacing: 10) {
                let ziele = model.zieldateien(fuer: s)
                if model.einstellungen.nextcloudURL == nil {
                    Text("Wähle in den Einstellungen (⌘,) den synchronisierten Nextcloud-Ordner für Protokolle.")
                        .foregroundStyle(.secondary)
                } else if model.reihe(fuer: s) == nil {
                    Text("Ordne die Sitzung einer Sitzungsreihe zu, damit die App den Zielordner kennt.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(s.status == .freigegeben ? "Freigegeben am \(s.freigegebenAm?.formatted(date: .abbreviated, time: .shortened) ?? "–"):" : "Wird abgelegt als:")
                        .font(.callout)
                    ForEach(ziele, id: \.self) { url in
                        Text(url.path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                HStack {
                    Button {
                        freigabeFragen = true
                    } label: {
                        Label(s.status == .freigegeben ? "Erneut freigeben (ersetzen)" : "Geprüft – freigeben", systemImage: "checkmark.seal")
                    }
                    .controlSize(.large)
                    .disabled(s.entwurf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ziele.isEmpty || beschaeftigt || nimmtAuf)
                    if !s.freigegebenePfade.isEmpty {
                        Button("Im Finder zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting(s.freigegebenePfade.map { URL(fileURLWithPath: $0) })
                        }
                    }
                }
                if let ordner = freigabeErgebnis.first?.deletingLastPathComponent() {
                    Label("Abgelegt im Ordner „\(ordner.lastPathComponent)“: \(ordner.path)", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green).textSelection(.enabled)
                }
                Text("Erst mit diesem Klick wird das Protokoll in den Nextcloud-Ordner gelegt (im Unterordner der Sitzungsreihe; einstellbar unter Einstellungen → Sitzungsreihen). Aufnahme und Transkript gehen nie in die Nextcloud.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .confirmationDialog("Protokoll freigeben?", isPresented: $freigabeFragen) {
            Button("Freigeben") {
                do {
                    freigabeErgebnis = try model.freigeben(id)
                    ladeOffenePunkte()
                } catch {
                    model.fehlermeldung = error.localizedDescription
                }
            }
        } message: {
            Text(model.einstellungen.aufnahmeLoeschen
                 ? "Das Protokoll wird in der Nextcloud abgelegt. Aufnahme und Transkript werden anschließend von diesem Mac gelöscht."
                 : "Das Protokoll wird in der Nextcloud abgelegt.")
        }
    }
}
