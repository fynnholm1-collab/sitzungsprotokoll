import SwiftUI

@main
struct SitzungsprotokollApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Sitzungsprotokoll") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.aufnahme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            EinstellungenView()
                .environmentObject(model)
                .frame(width: 720, height: 560)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var aufnahme: AufnahmeController
    @State private var neueSitzung = false
    @State private var zuLoeschen: Sitzung?

    var body: some View {
        NavigationSplitView {
            List(selection: $model.auswahl) {
                ForEach(model.sitzungen) { s in
                    SitzungZeile(sitzung: s, reihe: model.reihe(fuer: s)?.name, nimmtAuf: aufnahme.laufendeSitzung == s.id)
                        .tag(s.id)
                        .contextMenu {
                            Button("Sitzung löschen …", role: .destructive) { zuLoeschen = s }
                                .disabled(aufnahme.laufendeSitzung == s.id)
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
            .overlay {
                if model.sitzungen.isEmpty {
                    ContentUnavailableView("Noch keine Sitzungen", systemImage: "waveform",
                                           description: Text("Lege mit + eine neue Sitzung an."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { neueSitzung = true } label: { Label("Neue Sitzung", systemImage: "plus") }
                        .keyboardShortcut("n")
                }
            }
        } detail: {
            if let id = model.auswahl, model.sitzung(id) != nil {
                SitzungView(id: id).id(id)
            } else {
                ContentUnavailableView("Keine Sitzung ausgewählt", systemImage: "doc.text",
                                       description: Text("Wähle links eine Sitzung oder lege eine neue an."))
            }
        }
        .sheet(isPresented: $neueSitzung) {
            NeueSitzungView().environmentObject(model)
        }
        .confirmationDialog("Sitzung löschen?", isPresented: Binding(get: { zuLoeschen != nil }, set: { if !$0 { zuLoeschen = nil } }), presenting: zuLoeschen) { s in
            Button("Löschen", role: .destructive) { model.loesche(s.id) }
        } message: { s in
            Text("„\(s.titel)“ mit Aufnahme, Transkript und Entwurf wird von diesem Mac gelöscht. Bereits in der Nextcloud abgelegte Protokolle bleiben erhalten.")
        }
        .alert("Hinweis", isPresented: Binding(get: { model.fehlermeldung != nil }, set: { if !$0 { model.fehlermeldung = nil } })) {
            Button("OK") { model.fehlermeldung = nil }
        } message: {
            Text(model.fehlermeldung ?? "")
        }
    }
}

struct SitzungZeile: View {
    let sitzung: Sitzung
    let reihe: String?
    let nimmtAuf: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: nimmtAuf ? "record.circle.fill" : sitzung.status.symbol)
                .foregroundStyle(nimmtAuf ? .red : (sitzung.status == .freigegeben ? .green : .secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(sitzung.titel).lineLimit(1)
                Text("\(sitzung.datum.formatted(date: .abbreviated, time: .omitted)) · \(reihe ?? "ohne Reihe")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if sitzung.online {
                Image(systemName: "globe").foregroundStyle(.secondary).help("Online-Sitzung")
            }
        }
        .padding(.vertical, 2)
    }
}

struct NeueSitzungView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var reiheID: UUID?
    @State private var titel = ""
    @State private var datum = Date()
    @State private var online = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Neue Sitzung").font(.title2.bold())
            Form {
                Picker("Sitzungsreihe", selection: $reiheID) {
                    Text("Ohne Reihe").tag(UUID?.none)
                    ForEach(model.reihen) { r in Text(r.name).tag(UUID?.some(r.id)) }
                }
                TextField("Titel", text: $titel)
                DatePicker("Datum", selection: $datum)
                Picker("Ort", selection: $online) {
                    Text("Vor Ort").tag(false)
                    Text("Online (z. B. BigBlueButton)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Anlegen") {
                    let reihe = model.reihen.first { $0.id == reiheID }
                    let t = titel.trimmingCharacters(in: .whitespaces)
                    model.neueSitzung(reihe: reihe, titel: t.isEmpty ? (reihe?.name ?? "Sitzung") : t, datum: datum, online: online)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if reiheID == nil, let erste = model.reihen.first {
                reiheID = erste.id
                titel = erste.name
                online = erste.meistOnline
            }
        }
        .onChange(of: reiheID) { alt, neu in
            let alteReihe = model.reihen.first { $0.id == alt }
            guard let r = model.reihen.first(where: { $0.id == neu }) else { return }
            if titel.isEmpty || titel == alteReihe?.name { titel = r.name }
            online = r.meistOnline
        }
    }
}
