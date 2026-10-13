import Foundation
import VialetKit

/// Une transformation pure du texte. `apply` renvoie nil quand elle ne
/// s'applique pas (JSON invalide, base64 illisible...).
public enum TextTransform: String, CaseIterable, Identifiable, Sendable {
    case prettyJSON, minifyJSON
    case urlDecode, urlEncode, base64Decode, base64Encode, htmlDecode
    case upper, lower, titleCase, sentenceCase
    case cleanWhitespace, removeInvisible, slugify
    case sortLines, dedupeLines, reverseLines, numberLines
    case timestampToDate, dateToTimestamp, colorToRGB, colorToHex

    public var id: String { rawValue }

    public enum Group: String, CaseIterable, Sendable {
        case json, web, letterCase, lines, cleaning, convert

        public var label: String {
            switch self {
            case .json: "JSON"
            case .web: "Web"
            case .letterCase: "Casse"
            case .lines: "Lignes"
            case .cleaning: "Nettoyage"
            case .convert: "Conversion"
            }
        }
    }

    public var group: Group {
        switch self {
        case .prettyJSON, .minifyJSON: .json
        case .urlDecode, .urlEncode, .base64Decode, .base64Encode, .htmlDecode: .web
        case .upper, .lower, .titleCase, .sentenceCase: .letterCase
        case .sortLines, .dedupeLines, .reverseLines, .numberLines: .lines
        case .cleanWhitespace, .removeInvisible, .slugify: .cleaning
        case .timestampToDate, .dateToTimestamp, .colorToRGB, .colorToHex: .convert
        }
    }

    public var label: String {
        switch self {
        case .prettyJSON: "Formater le JSON"
        case .minifyJSON: "Compacter le JSON"
        case .urlDecode: "Décoder l'URL"
        case .urlEncode: "Encoder pour une URL"
        case .base64Decode: "Décoder le base64"
        case .base64Encode: "Encoder en base64"
        case .htmlDecode: "Décoder les entités HTML"
        case .upper: "MAJUSCULES"
        case .lower: "minuscules"
        case .titleCase: "Majuscule À Chaque Mot"
        case .sentenceCase: "Majuscule en début de phrase"
        case .cleanWhitespace: "Nettoyer les espaces"
        case .removeInvisible: "Retirer les caractères invisibles"
        case .slugify: "Transformer en slug"
        case .sortLines: "Trier les lignes"
        case .dedupeLines: "Dédoublonner les lignes"
        case .reverseLines: "Inverser les lignes"
        case .numberLines: "Numéroter les lignes"
        case .timestampToDate: "Timestamp → date"
        case .dateToTimestamp: "Date → timestamp"
        case .colorToRGB: "Couleur → rgb()"
        case .colorToHex: "Couleur → #hex"
        }
    }

    public var icon: String {
        switch self {
        case .prettyJSON, .minifyJSON: "curlybraces"
        case .urlDecode, .urlEncode: "link"
        case .base64Decode, .base64Encode: "lock.square"
        case .htmlDecode: "chevron.left.forwardslash.chevron.right"
        case .upper, .lower, .titleCase, .sentenceCase: "textformat"
        case .cleanWhitespace, .removeInvisible: "sparkles"
        case .slugify: "minus"
        case .sortLines, .dedupeLines, .reverseLines, .numberLines: "list.number"
        case .timestampToDate, .dateToTimestamp: "calendar"
        case .colorToRGB, .colorToHex: "paintpalette"
        }
    }

    public func apply(_ text: String) -> String? {
        switch self {
        case .prettyJSON: return JSONTools.pretty(text)
        case .minifyJSON: return JSONTools.minified(text)
        case .urlDecode: return text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        case .urlEncode:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return text.addingPercentEncoding(withAllowedCharacters: allowed)
        case .base64Decode:
            guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .htmlDecode: return HTMLEntities.decode(text)
        case .upper: return text.uppercased(with: Self.french)
        case .lower: return text.lowercased(with: Self.french)
        case .titleCase: return text.capitalized(with: Self.french)
        case .sentenceCase: return Self.sentenceCase(text)
        case .cleanWhitespace: return Self.cleanWhitespace(text)
        case .removeInvisible: return Self.removeInvisible(text)
        case .slugify: return Self.slugify(text)
        case .sortLines: return Self.lines(text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .dedupeLines:
            var seen = Set<String>()
            return Self.lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseLines: return Self.lines(text).reversed().joined(separator: "\n")
        case .numberLines: return Self.lines(text).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .timestampToDate:
            let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard digits.allSatisfy(\.isNumber), digits.count == 10 || digits.count == 13, let value = Double(digits) else { return nil }
            let seconds = digits.count == 13 ? value / 1000 : value
            return Self.iso().string(from: Date(timeIntervalSince1970: seconds))
        case .dateToTimestamp:
            let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = Self.iso().date(from: s) ?? Self.iso(fractional: true).date(from: s) else { return nil }
            return String(Int(date.timeIntervalSince1970))
        case .colorToRGB:
            guard let hex = ContentDetector.hexColor(text) else { return nil }
            return "rgb(\((hex >> 16) & 0xFF), \((hex >> 8) & 0xFF), \(hex & 0xFF))"
        case .colorToHex:
            guard let hex = ContentDetector.hexColor(text) else { return nil }
            return String(format: "#%06X", hex)
        }
    }

    // MARK: Outils

    static let french = Locale(identifier: "fr_FR")

    /// Un formateur par appel : ISO8601DateFormatter n'est pas Sendable.
    static func iso(fractional: Bool = false) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func sentenceCase(_ text: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in text.lowercased(with: french) {
            if capitalizeNext, ch.isLetter {
                out += String(ch).uppercased(with: french)
                capitalizeNext = false
            } else {
                out.append(ch)
            }
            if ch == "." || ch == "!" || ch == "?" || ch.isNewline { capitalizeNext = true }
        }
        return out
    }

    /// Espaces de fin de ligne retires, au plus une ligne vide d'affilee, pas de lignes vides finales.
    static func cleanWhitespace(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { line -> String in
            var l = Substring(line)
            while let last = l.last, last == " " || last == "\t" { l.removeLast() }
            return String(l)
        }
        var out: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty { blank += 1; if blank > 1 { continue } } else { blank = 0 }
            out.append(line)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        lines = out
        return lines.joined(separator: "\n")
    }

    static func removeInvisible(_ text: String) -> String {
        let removed: Set<Character> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}"]
        let spaces: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2007}"]
        return String(text.compactMap { ch -> Character? in
            if removed.contains(ch) { return nil }
            if spaces.contains(ch) { return " " }
            return ch
        })
    }

    static func slugify(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: french).lowercased()
        var out = ""
        var dash = false
        for ch in folded {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                out.append(ch); dash = false
            } else if !dash, !out.isEmpty {
                out.append("-"); dash = true
            }
        }
        while out.last == "-" { out.removeLast() }
        return out
    }
}

/// Entites HTML courantes et numeriques, sans WebKit.
enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â", "auml": "ä",
        "ccedil": "ç", "ugrave": "ù", "ucirc": "û", "uuml": "ü", "ocirc": "ô", "ouml": "ö", "icirc": "î", "iuml": "ï",
        "Eacute": "É", "Egrave": "È", "Agrave": "À", "Ccedil": "Ç", "oelig": "œ", "OElig": "Œ",
        "laquo": "«", "raquo": "»", "hellip": "…", "ndash": "–", "mdash": "—", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "euro": "€", "copy": "©", "reg": "®", "deg": "°", "times": "×",
    ]

    static func decode(_ text: String) -> String? {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            guard let semi = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semi) <= 10 else {
                out.append("&"); rest = rest.dropFirst(); continue
            }
            let body = rest[rest.index(after: rest.startIndex)..<semi]
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[String(body)]
            }
            if let replacement {
                out += replacement
                rest = rest[rest.index(after: semi)...]
            } else {
                out.append("&"); rest = rest.dropFirst()
            }
        }
        out += rest
        return out
    }
}
