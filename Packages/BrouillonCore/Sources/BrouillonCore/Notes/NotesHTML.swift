import Foundation

/// Corps HTML d'une note de l'app Notes -> texte brut de Brouillon. Pur, sans WebKit :
/// paragraphes et retours, listes a puces et numerotees, cases a cocher, liens gardes en texte,
/// entites, tableaux en texte tabule, images et pieces jointes en mention. Gras, italique et
/// styles sont simplifies : seul le texte reste.
public enum NotesHTML {
    /// Texte du brouillon importe : le corps converti, qui commence par le nom de la note.
    /// Notes tire le nom de la premiere ligne ; si le corps ne commence pas par lui, il est ajoute
    /// en tete (le titre de Brouillon vient de la premiere ligne).
    public static func draftText(name: String, html: String) -> String {
        let body = text(from: html)
        let title = collapse(name)
        guard !title.isEmpty else { return body }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map { collapse(String($0)) } ?? ""
        if firstLine.hasPrefix(title) { return body }
        return body.isEmpty ? title : title + "\n\n" + body
    }

    public static func text(from html: String) -> String {
        var renderer = Renderer()
        for token in Tokenizer(html) { renderer.handle(token) }
        return renderer.finish()
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Jetons

    enum Token {
        case text(String)
        case open(String, [String: String], selfClosing: Bool)
        case close(String)
    }

    struct Tokenizer: Sequence, IteratorProtocol {
        private let chars: [Character]
        private var i = 0

        init(_ html: String) { chars = Array(html) }

        mutating func next() -> Token? {
            guard i < chars.count else { return nil }
            if chars[i] == "<" {
                // Commentaire, doctype, instruction : ignores.
                if match("<!--") {
                    i = find("-->").map { $0 + 3 } ?? chars.count
                    return next()
                }
                if i + 1 < chars.count, chars[i + 1] == "!" || chars[i + 1] == "?" {
                    i = find(">").map { $0 + 1 } ?? chars.count
                    return next()
                }
                if let tag = parseTag() { return tag }
                // « < » isole : texte.
                i += 1
                return .text("<")
            }
            let start = i
            while i < chars.count, chars[i] != "<" { i += 1 }
            return .text(String(chars[start..<i]))
        }

        private func match(_ s: String) -> Bool {
            let a = Array(s)
            guard i + a.count <= chars.count else { return false }
            return Array(chars[i..<(i + a.count)]) == a
        }

        private func find(_ s: String) -> Int? {
            let a = Array(s)
            var j = i
            while j + a.count <= chars.count {
                if Array(chars[j..<(j + a.count)]) == a { return j }
                j += 1
            }
            return nil
        }

        /// `<nom attr="v" ...>`, `</nom>` ou `<nom/>` ; nil si ce n'est pas une balise.
        private mutating func parseTag() -> Token? {
            var j = i + 1
            let closing = j < chars.count && chars[j] == "/"
            if closing { j += 1 }
            let nameStart = j
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "-" || chars[j] == ":" { j += 1 }
            guard j > nameStart, chars[nameStart].isLetter else { return nil }
            let name = String(chars[nameStart..<j]).lowercased()
            var attributes: [String: String] = [:]
            var selfClosing = false
            while j < chars.count, chars[j] != ">" {
                let c = chars[j]
                if c == "/" { selfClosing = true; j += 1; continue }
                if c.isWhitespace { j += 1; continue }
                let keyStart = j
                while j < chars.count, !chars[j].isWhitespace, chars[j] != "=", chars[j] != ">", chars[j] != "/" { j += 1 }
                let key = String(chars[keyStart..<j]).lowercased()
                var value = ""
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "=" {
                    j += 1
                    while j < chars.count, chars[j].isWhitespace { j += 1 }
                    if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                        let quote = chars[j]
                        j += 1
                        let valueStart = j
                        while j < chars.count, chars[j] != quote { j += 1 }
                        value = String(chars[valueStart..<Swift.min(j, chars.count)])
                        j += 1
                    } else {
                        let valueStart = j
                        while j < chars.count, !chars[j].isWhitespace, chars[j] != ">" { j += 1 }
                        value = String(chars[valueStart..<j])
                    }
                    selfClosing = false
                }
                if !key.isEmpty { attributes[key] = NotesHTML.decodeEntities(value) }
            }
            i = Swift.min(j + 1, chars.count)
            return closing ? .close(name) : .open(name, attributes, selfClosing: selfClosing)
        }
    }

    // MARK: - Rendu

    struct Renderer {
        private struct ListContext { let ordered: Bool; let checklist: Bool; var counter = 0 }
        private struct LinkContext { let href: String; var label = "" }

        private var lines: [String] = []
        private var current = ""
        /// Le texte de la ligne courante au-dela de son prefixe (puce, retrait).
        private var currentHasContent = false
        private var lists: [ListContext] = []
        private var links: [LinkContext] = []
        private var cellDepth = 0
        private var cellIndex = 0
        private var preDepth = 0
        private var hiddenDepth = 0

        private static let blocks: Set<String> = ["div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
                                                  "section", "article", "header", "footer", "dl", "dt", "dd", "hr"]
        private static let hidden: Set<String> = ["head", "style", "script", "title", "template"]
        private static let voids: Set<String> = ["br", "img", "input", "hr", "meta", "link", "embed", "source"]
        private static let attachments: Set<String> = ["object", "embed", "attachment", "iframe", "video", "audio"]

        mutating func handle(_ token: Token) {
            switch token {
            case .text(let raw):
                guard hiddenDepth == 0 else { return }
                appendText(NotesHTML.decodeEntities(raw), raw: raw)
            case .open(let name, let attributes, let selfClosing):
                if Self.hidden.contains(name) {
                    if !selfClosing { hiddenDepth += 1 }
                    return
                }
                guard hiddenDepth == 0 else { return }
                open(name, attributes)
                if selfClosing && !Self.voids.contains(name) { close(name) }
            case .close(let name):
                if Self.hidden.contains(name) {
                    hiddenDepth = max(0, hiddenDepth - 1)
                    return
                }
                guard hiddenDepth == 0 else { return }
                close(name)
            }
        }

        private mutating func open(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "br":
                if cellDepth > 0 { appendSeparator() } else { newline() }
            case "ul", "ol":
                if cellDepth == 0 { breakLine() }
                let checklist = attributes["class"].map { $0.lowercased().contains("checklist") || $0.lowercased().contains("todo") } ?? false
                lists.append(ListContext(ordered: name == "ol", checklist: checklist))
            case "li":
                guard cellDepth == 0 else { appendSeparator(); return }
                breakLine()
                let depth = max(lists.count, 1)
                var marker: String
                if var list = lists.popLast() {
                    list.counter += 1
                    marker = list.ordered ? "\(list.counter). " : "- "
                    if list.checklist || (attributes["class"]?.lowercased().contains("checked") ?? false) {
                        let done = attributes["class"]?.lowercased().contains("checked") ?? false
                        marker += done ? "[x] " : "[ ] "
                    }
                    lists.append(list)
                } else {
                    marker = "- "
                }
                current = String(repeating: "  ", count: depth - 1) + marker
                currentHasContent = false
            case "table":
                breakLine()
            case "tr":
                if cellDepth == 0 { breakLine() }
                cellIndex = 0
            case "td", "th":
                if cellIndex > 0 { current += "\t"; currentHasContent = true }
                cellIndex += 1
                cellDepth += 1
            case "pre":
                breakLine()
                preDepth += 1
            case "img":
                appendMention("[image]")
            case "input":
                if attributes["type"]?.lowercased() == "checkbox" {
                    appendMention(attributes["checked"] != nil ? "[x]" : "[ ]")
                }
            case "a":
                links.append(LinkContext(href: attributes["href"] ?? ""))
            default:
                if Self.attachments.contains(name) {
                    appendMention("[pi\u{00E8}ce jointe]")
                } else if Self.blocks.contains(name) {
                    if cellDepth > 0 { appendSeparator() } else { breakLine() }
                    if name == "hr" { appendText("\u{2014}\u{2014}\u{2014}", raw: ""); breakLine() }
                }
            }
        }

        private mutating func close(_ name: String) {
            switch name {
            case "ul", "ol":
                _ = lists.popLast()
                if cellDepth == 0 { breakLine() }
            case "li":
                if cellDepth == 0 { breakLine() }
            case "td", "th":
                cellDepth = max(0, cellDepth - 1)
                trimTrailingSpaces()
            case "tr", "table":
                if cellDepth == 0 { breakLine() }
            case "pre":
                preDepth = max(0, preDepth - 1)
                breakLine()
            case "a":
                guard let link = links.popLast() else { return }
                let label = NotesHTML.collapse(link.label)
                let href = link.href.trimmingCharacters(in: .whitespaces)
                if !href.isEmpty, !Self.sameLink(label, href) {
                    appendText(label.isEmpty ? href : " (\(href))", raw: "")
                }
            default:
                if Self.blocks.contains(name), cellDepth == 0 { breakLine() }
            }
        }

        static func sameLink(_ label: String, _ href: String) -> Bool {
            func bare(_ s: String) -> String {
                var s = s.lowercased()
                if s.hasPrefix("mailto:") { s.removeFirst(7) }
                return s
            }
            return bare(label) == bare(href)
        }

        /// Texte d'un noeud : espaces replies hors `pre` (les insecables restent).
        private mutating func appendText(_ decoded: String, raw: String) {
            if preDepth > 0 {
                let parts = decoded.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
                for (index, part) in parts.enumerated() {
                    if index > 0 { newline() }
                    current += part.replacingOccurrences(of: "\u{00A0}", with: " ")
                    if !part.isEmpty { currentHasContent = true }
                }
                return
            }
            var out = ""
            var lastWasSpace = current.last.map { $0 == " " || $0 == "\t" } ?? true
            if !currentHasContent { lastWasSpace = true }
            for c in decoded {
                if c == "\u{00A0}" {
                    out.append(" ")
                    lastWasSpace = false
                } else if c.isWhitespace {
                    if !lastWasSpace { out.append(" ") }
                    lastWasSpace = true
                } else {
                    out.append(c)
                    lastWasSpace = false
                }
            }
            guard !out.isEmpty else { return }
            current += out
            if !links.isEmpty { links[links.count - 1].label += out }
            if out.contains(where: { $0 != " " }) || currentHasContent { currentHasContent = true }
        }

        private mutating func appendMention(_ mention: String) {
            if currentHasContent, let last = current.last, last != " ", last != "\t" { current += " " }
            current += mention
            currentHasContent = true
        }

        /// Separateur dans une cellule de tableau : une espace au lieu d'un retour.
        private mutating func appendSeparator() {
            if currentHasContent, let last = current.last, last != " ", last != "\t" { current += " " }
        }

        private mutating func trimTrailingSpaces() {
            while current.last == " " { current.removeLast() }
        }

        /// Termine la ligne courante si elle a du contenu.
        private mutating func breakLine() {
            if currentHasContent { newline() } else if !current.isEmpty, lists.isEmpty { current = "" }
        }

        private mutating func newline() {
            trimTrailingSpaces()
            lines.append(current)
            current = ""
            currentHasContent = false
        }

        mutating func finish() -> String {
            if currentHasContent { newline() }
            var result = lines
            while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeFirst() }
            while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { result.removeLast() }
            return result.joined(separator: "\n")
        }
    }

    // MARK: - Entites

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "eacute": "\u{00E9}", "egrave": "\u{00E8}", "ecirc": "\u{00EA}", "euml": "\u{00EB}",
        "aacute": "\u{00E1}", "agrave": "\u{00E0}", "acirc": "\u{00E2}", "auml": "\u{00E4}",
        "iacute": "\u{00ED}", "igrave": "\u{00EC}", "icirc": "\u{00EE}", "iuml": "\u{00EF}",
        "oacute": "\u{00F3}", "ograve": "\u{00F2}", "ocirc": "\u{00F4}", "ouml": "\u{00F6}",
        "uacute": "\u{00FA}", "ugrave": "\u{00F9}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}",
        "ccedil": "\u{00E7}", "Ccedil": "\u{00C7}", "Eacute": "\u{00C9}", "Egrave": "\u{00C8}",
        "Ecirc": "\u{00CA}", "Agrave": "\u{00C0}", "Acirc": "\u{00C2}", "Ocirc": "\u{00D4}",
        "oelig": "\u{0153}", "OElig": "\u{0152}", "aelig": "\u{00E6}", "yuml": "\u{00FF}", "ntilde": "\u{00F1}",
        "hellip": "\u{2026}", "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "mdash": "\u{2014}", "ndash": "\u{2013}", "bull": "\u{2022}",
        "middot": "\u{00B7}", "euro": "\u{20AC}", "pound": "\u{00A3}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "trade": "\u{2122}", "deg": "\u{00B0}", "times": "\u{00D7}", "divide": "\u{00F7}", "shy": "",
        "zwj": "\u{200D}", "zwnj": "\u{200C}", "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}",
    ]

    /// `&amp;`, `&#233;`, `&#xE9;` et les entites nommees courantes ; une entite inconnue reste telle quelle.
    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            let c = s[index]
            guard c == "&", let semicolon = s[index...].prefix(12).firstIndex(of: ";") else {
                out.append(c)
                index = s.index(after: index)
                continue
            }
            let body = s[s.index(after: index)..<semicolon]
            var decoded: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if body.hasPrefix("#") {
                decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                decoded = named[String(body)]
            }
            if let decoded {
                out += decoded
                index = s.index(after: semicolon)
            } else {
                out.append(c)
                index = s.index(after: index)
            }
        }
        return out
    }
}
