# Sitzungsprotokoll

Eine Mac-App, die Sitzungen aufnimmt, sie **lokal** abschreibt und daraus ein Kurzprotokoll erstellt. Gedacht für Geschäftsführungs-, AG- und Gremiensitzungen der Abteilung Japanologie in Tübingen.

**Datenschutz:** Aufnahme, Transkript und Entwurf bleiben auf dem eigenen Mac. Es gibt keinen Server und keine Cloud. Die Spracherkennung (Whisper) läuft lokal. Das Protokoll entsteht entweder mit einem lokalen Sprachmodell (Ollama) oder, wenn du es so willst, per Kopieren in AskAlma. Erst wenn du das geprüfte Protokoll freigibst, legt die App es in deinen synchronisierten Nextcloud-Ordner. Aufnahme und Transkript gehen nie in die Nextcloud und werden nach der Freigabe standardmäßig gelöscht.

## Ablauf

1. **Neue Sitzung** anlegen (⌘N), Sitzungsreihe wählen, z. B. „Geschäftsführung“ oder „AG Sprachunterricht“.
2. **Einwilligung** einholen und bestätigen. Für Online-Sitzungen gibt es einen Hinweistext zum Einfügen in den Chat.
3. **Aufnehmen.** Vor Ort über das Mikrofon. Online (z. B. BigBlueButton in Moodle) zusätzlich den Ton des Browsers, damit auch die anderen gut zu verstehen sind. Bei Online-Sitzungen weiß das Transkript dadurch, welche Beiträge von dir kommen.
4. **Transkribieren** (lokal, Deutsch, Englisch oder Japanisch). Hörfehler kannst du direkt im Transkript korrigieren.
5. **Protokoll erstellen:**
   - *Lokal zusammenfassen* mit Ollama, oder
   - *Für AskAlma kopieren*: Anweisungen, Vorlage und Transkript landen in der Zwischenablage. In AskAlma einfügen und die Antwort zurück in die App kopieren.
6. **Prüfen und freigeben.** Das Protokoll wird als Word- und/oder Markdown-Datei im Nextcloud-Ordner der Reihe abgelegt, z. B. `AG Bibliothek/2026-11-10 AG Bibliothek.docx`.

Bei der nächsten Sitzung derselben Reihe zeigt die App die **offenen Punkte und unerledigten Aufgaben** aus dem letzten Protokoll an und gibt sie dem Sprachmodell mit.

## Installation

Voraussetzungen: Mac mit Apple-Chip (M1 oder neuer), macOS 14 Sonoma oder neuer. Für die lokale Zusammenfassung 16 GB Arbeitsspeicher. Wer nur den AskAlma-Weg nutzt, kommt mit 8 GB aus.

1. Unter [Releases](../../releases) (oder unter *Actions → letzter Build → Artifacts*) die Datei `Sitzungsprotokoll.dmg` laden.
2. Öffnen und *Sitzungsprotokoll* in den Ordner *Programme* ziehen.
3. Beim ersten Öffnen meldet macOS, dass die App nicht überprüft werden kann, weil sie nicht über ein kostenpflichtiges Apple-Entwicklerkonto signiert ist. So öffnest du sie trotzdem:
   - Die Meldung mit *Fertig* schließen.
   - *Systemeinstellungen → Datenschutz & Sicherheit* öffnen, ganz nach unten scrollen und bei „Sitzungsprotokoll wurde blockiert“ auf **Dennoch öffnen** klicken.
   - Das ist nur einmal nötig.
4. Beim ersten Aufnehmen fragt macOS nach dem Mikrofon. Bei der ersten Online-Aufnahme fragt es nach *Bildschirm- und Systemaudioaufnahme*. Das Bild wird dabei nicht gespeichert, die App braucht die Erlaubnis nur für den Ton.

### Lokale Zusammenfassung mit Ollama (optional)

1. [Ollama](https://ollama.com) installieren und starten.
2. Im Terminal einmalig das Modell laden: `ollama pull qwen3:8b` (ca. 5 GB).
3. In der App unter *Einstellungen → Transkription & KI* auf *Verbindung prüfen* klicken.

### Nextcloud

Unter *Einstellungen → Allgemein* den lokal synchronisierten Nextcloud-Ordner wählen, in dem eure Protokolle liegen. Unter *Sitzungsreihen* jeder Reihe ihren bestehenden Unterordner zuordnen. Mit *In Nextcloud bereitstellen* legt die App die Vorlagen und die Liste der Reihen im Ordner `_Vorlagen Sitzungsprotokoll` ab. Kolleg:innen übernehmen sie dann mit *Reihen aus Nextcloud übernehmen*. Liegen dort Vorlagen, haben sie Vorrang vor den eingebauten.

## Vorlagen

Vorlagen sind Markdown-Dateien mit Platzhaltern: `{{titel}}`, `{{reihe}}`, `{{datum}}`, `{{teilnehmende}}`, `{{protokoll}}`. Aufgaben stehen als Checkliste (`- [ ] …`) unter `## Aufgaben`, offene Punkte unter `## Offene Punkte`. Nur so findet die App sie in der nächsten Sitzung wieder. Eingebaut sind Vorlagen für AG-Sitzungen, Geschäftsführung, Dienstbesprechung, Finanzplansitzung und Mitgliederversammlung (Verein).

## Rechtliches

Vor jeder Aufnahme müssen alle Teilnehmenden einverstanden sein (§ 201 StGB, DSGVO). Für Gremiensitzungen empfiehlt sich eine kurze Abstimmung mit der/dem Datenschutzbeauftragten der Universität. Die App erleichtert das mit einem Hinweistext und verlangt vor jeder Aufnahme eine Bestätigung.

## Entwicklung

- `Packages/ProtokollKern`: Kernlogik ohne Oberfläche (Vorlagen, offene Punkte, Markdown → Word, Transkript-Zusammenführung) mit Tests: `swift test --package-path Packages/ProtokollKern`
- `App/Sources`: SwiftUI-App, Aufnahme (AVAudioEngine, ScreenCaptureKit), Transkription ([WhisperKit](https://github.com/argmaxinc/WhisperKit)), Ollama, Nextcloud-Freigabe.
- Projekt erzeugen: `brew install xcodegen && xcodegen generate`, dann `Sitzungsprotokoll.xcodeproj` in Xcode öffnen.
- Jeder Push baut die App über GitHub Actions (`.github/workflows/build.yml`). Ein Tag `v…` veröffentlicht ein Release mit der `.dmg`.
