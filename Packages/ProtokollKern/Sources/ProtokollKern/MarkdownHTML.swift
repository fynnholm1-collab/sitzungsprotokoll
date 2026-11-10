import Foundation

/// Kleiner Markdown-zu-HTML-Wandler für Protokolle. Unterstützt Überschriften,
/// Absätze (Zeilenumbrüche bleiben erhalten), Listen, Checklisten, einfache
/// Tabellen, Zitate, Trennlinien sowie **fett**, *kursiv* und `Code`.
/// Das HTML dient als Zwischenschritt für den Word-Export.
public enum MarkdownHTML {
    public static func html(aus markdown: String, titel: String = "Protokoll") -> String {
        var ausgabe: [String] = []
        var absatz: [String] = []
        var liste: String? = nil   // "ul" oder "ol"
        var tabelle: [[String]] = []
        var zitat: [String] = []

        func absatzSchliessen() {
            if !absatz.isEmpty {
                ausgabe.append("<p>" + absatz.map(inline).joined(separator: "<br>") + "</p>")
                absatz = []
            }
        }
        func listeSchliessen() {
            if let l = liste { ausgabe.append("</\(l)>"); liste = nil }
        }
        func tabelleSchliessen() {
            guard !tabelle.isEmpty else { return }
            var zeilen = ["<table>"]
            for (i, zellen) in tabelle.enumerated() {
                let tag = i == 0 ? "th" : "td"
                zeilen.append("<tr>" + zellen.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>")
            }
            zeilen.append("</table>")
            ausgabe.append(zeilen.joined())
            tabelle = []
        }
        func zitatSchliessen() {
            if !zitat.isEmpty {
                ausgabe.append("<blockquote>" + zitat.map(inline).joined(separator: "<br>") + "</blockquote>")
                zitat = []
            }
        }
        func allesSchliessen() {
            absatzSchliessen(); listeSchliessen(); tabelleSchliessen(); zitatSchliessen()
        }

        for roheZeile in markdown.components(separatedBy: .newlines) {
            let zeile = roheZeile.trimmingCharacters(in: .whitespaces)

            if zeile.isEmpty { allesSchliessen(); continue }

            if zeile.hasPrefix("|") {
                absatzSchliessen(); listeSchliessen(); zitatSchliessen()
                if istTrennzeile(zeile) { continue }
                tabelle.append(tabellenzellen(zeile))
                continue
            } else { tabelleSchliessen() }

            if let ebene = OffenePunkte.ueberschriftsebene(zeile) {
                allesSchliessen()
                let text = zeile.dropFirst(ebene).trimmingCharacters(in: .whitespaces)
                ausgabe.append("<h\(ebene)>\(inline(text))</h\(ebene)>")
                continue
            }

            if zeile == "---" || zeile == "***" || zeile == "___" {
                allesSchliessen(); ausgabe.append("<hr>"); continue
            }

            if zeile.hasPrefix(">") {
                absatzSchliessen(); listeSchliessen()
                zitat.append(zeile.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            } else { zitatSchliessen() }

            if let inhalt = OffenePunkte.listeninhalt(zeile) {
                absatzSchliessen()
                let geordnet = zeile.first?.isNumber == true
                let art = geordnet ? "ol" : "ul"
                if liste != art { listeSchliessen(); ausgabe.append("<\(art)>"); liste = art }
                ausgabe.append("<li>\(inline(checkbox(inhalt)))</li>")
                continue
            }

            listeSchliessen()
            absatz.append(zeile.hasSuffix("\\") ? String(zeile.dropLast()) : zeile)
        }
        allesSchliessen()

        return """
        <!DOCTYPE html>
        <html lang="de"><head><meta charset="utf-8"><title>\(escape(titel))</title>
        <style>
        body { font-family: Calibri, "Helvetica Neue", Arial, sans-serif; font-size: 11pt; line-height: 1.35; }
        h1 { font-size: 16pt; } h2 { font-size: 13pt; margin-top: 14pt; } h3 { font-size: 11pt; }
        table { border-collapse: collapse; } th, td { border: 1px solid #999; padding: 3pt 6pt; text-align: left; vertical-align: top; }
        blockquote { color: #444; margin-left: 12pt; }
        </style></head><body>
        \(ausgabe.joined(separator: "\n"))
        </body></html>
        """
    }

    static func checkbox(_ text: String) -> String {
        if text.hasPrefix("[ ] ") { return "☐ " + text.dropFirst(4) }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { return "☑ " + text.dropFirst(4) }
        return text
    }

    static func istTrennzeile(_ zeile: String) -> Bool {
        let erlaubt = CharacterSet(charactersIn: "|-: ")
        return zeile.contains("-") && zeile.unicodeScalars.allSatisfy { erlaubt.contains($0) }
    }

    static func tabellenzellen(_ zeile: String) -> [String] {
        var t = zeile
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let codeMuster = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let fettMuster = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let kursivMuster = try! NSRegularExpression(pattern: "(?<![\\*\\w])\\*(?![\\s\\*])(.+?)(?<![\\s\\*])\\*(?![\\*\\w])")

    static func inline(_ text: String) -> String {
        var t = escape(text)
        t = ersetze(codeMuster, in: t, mit: "<code>$1</code>")
        t = ersetze(fettMuster, in: t, mit: "<strong>$1</strong>")
        t = ersetze(kursivMuster, in: t, mit: "<em>$1</em>")
        return t
    }

    private static func ersetze(_ muster: NSRegularExpression, in text: String, mit vorlage: String) -> String {
        let bereich = NSRange(text.startIndex..<text.endIndex, in: text)
        return muster.stringByReplacingMatches(in: text, options: [], range: bereich, withTemplate: vorlage)
    }
}
