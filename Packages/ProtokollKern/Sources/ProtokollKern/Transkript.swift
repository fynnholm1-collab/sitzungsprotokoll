import Foundation

/// Ein Abschnitt des Transkripts mit Zeitangaben in Sekunden ab Aufnahmebeginn.
public struct Segment: Codable, Hashable, Sendable {
    public var start: Double
    public var ende: Double
    public var text: String
    public var sprecher: String?

    public init(start: Double, ende: Double, text: String, sprecher: String? = nil) {
        self.start = start
        self.ende = ende
        self.text = text
        self.sprecher = sprecher
    }
}

/// Eine Tonspur der Aufnahme (z. B. Mikrofon oder Browser-Ton bei Online-Sitzungen).
public struct Spur: Sendable {
    public var sprecher: String?
    /// Sekunden, um die diese Spur nach dem Aufnahmebeginn startet.
    public var versatz: Double
    public var segmente: [Segment]

    public init(sprecher: String?, versatz: Double, segmente: [Segment]) {
        self.sprecher = sprecher
        self.versatz = versatz
        self.segmente = segmente
    }
}

public enum Transkript {
    /// Typische Fehlerkennungen von Whisper bei Stille oder Rauschen.
    static let halluzinationen = [
        "untertitel im auftrag des zdf",
        "untertitelung im auftrag des zdf",
        "untertitel der amara.org-community",
        "untertitel von stephanie geiges",
        "vielen dank fürs zuschauen",
        "danke fürs zuschauen",
        "bis zum nächsten mal",
        "copyright wdr",
        "swr 2020",
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "ご視聴ありがとうございました",
        "チャンネル登録",
    ]

    private static let tokenMuster = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>")

    /// Entfernt Steuerzeichen von Whisper (z. B. `<|0.00|>`) und überflüssige Leerzeichen.
    public static func bereinigt(_ text: String) -> String {
        let bereich = NSRange(text.startIndex..<text.endIndex, in: text)
        let ohneTokens = tokenMuster.stringByReplacingMatches(in: text, options: [], range: bereich, withTemplate: "")
        return ohneTokens
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public static func istHalluzination(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.union(.whitespaces).contains($0) }) { return true }
        guard t.count < 90 else { return false }
        return halluzinationen.contains { t.contains($0) }
    }

    /// Führt mehrere Spuren zeitlich zusammen, bereinigt sie und entfernt bei
    /// Online-Sitzungen das Echo: Wenn das Mikrofon (Spur `echoSpur`) den
    /// Lautsprecherton mit aufnimmt, werden diese doppelten Stellen verworfen.
    public static func zusammenfuehren(_ spuren: [Spur], echoSpur: Int? = nil) -> [Segment] {
        var proSpur: [[Segment]] = spuren.map { spur in
            spur.segmente.compactMap { s in
                let text = bereinigt(s.text)
                guard !istHalluzination(text) else { return nil }
                return Segment(start: s.start + spur.versatz, ende: s.ende + spur.versatz, text: text, sprecher: spur.sprecher ?? s.sprecher)
            }
        }
        if let echo = echoSpur, proSpur.indices.contains(echo), proSpur.count > 1 {
            let andere = proSpur.enumerated().filter { $0.offset != echo }.flatMap { $0.element }
            proSpur[echo] = proSpur[echo].filter { eigenes in
                !andere.contains { fremd in
                    ueberlappt(eigenes, fremd, toleranz: 2.0) && aehnlichkeit(eigenes.text, fremd.text) >= 0.5
                }
            }
        }
        return proSpur.flatMap { $0 }.sorted { ($0.start, $0.ende) < ($1.start, $1.ende) }
    }

    static func ueberlappt(_ a: Segment, _ b: Segment, toleranz: Double) -> Bool {
        a.start <= b.ende + toleranz && b.start <= a.ende + toleranz
    }

    /// Anteil gemeinsamer Wörter (Jaccard), 0 bis 1.
    static func aehnlichkeit(_ a: String, _ b: String) -> Double {
        func woerter(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
        }
        let wa = woerter(a), wb = woerter(b)
        guard !wa.isEmpty || !wb.isEmpty else { return 1 }
        return Double(wa.intersection(wb).count) / Double(wa.union(wb).count)
    }

    /// Lesbarer Text: aufeinanderfolgende Abschnitte derselben Person werden zu
    /// Absätzen von höchstens `absatzSekunden` zusammengefasst.
    public static func text(_ segmente: [Segment], absatzSekunden: Double = 45) -> String {
        var zeilen: [String] = []
        var aktuell: (start: Double, sprecher: String?, texte: [String])? = nil

        func abschliessen() {
            guard let a = aktuell else { return }
            let kopf = a.sprecher.map { "[\(zeitstempel(a.start))] \($0):" } ?? "[\(zeitstempel(a.start))]"
            zeilen.append("\(kopf) \(a.texte.joined(separator: " "))")
            aktuell = nil
        }

        for s in segmente {
            if let a = aktuell, a.sprecher == s.sprecher, s.start - a.start < absatzSekunden {
                aktuell?.texte.append(s.text)
            } else {
                abschliessen()
                aktuell = (s.start, s.sprecher, [s.text])
            }
        }
        abschliessen()
        return zeilen.joined(separator: "\n")
    }

    /// Zeitangabe `H:MM:SS`.
    public static func zeitstempel(_ sekunden: Double) -> String {
        let gesamt = max(0, Int(sekunden.rounded(.down)))
        return String(format: "%d:%02d:%02d", gesamt / 3600, (gesamt % 3600) / 60, gesamt % 60)
    }
}
