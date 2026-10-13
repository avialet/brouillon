import Foundation
import VialetKit

/// Les transformations a proposer en premier, selon ce qu'on a colle.
public enum Suggestions {
    public static func transforms(for text: String) -> [TextTransform] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let kind = ContentDetector.detect(trimmed)
        let multiline = trimmed.contains(where: \.isNewline)
        var out: [TextTransform] = []

        switch kind {
        case .json:
            out += [.prettyJSON, .minifyJSON]
        case .url:
            out += trimmed.contains("%") ? [.urlDecode, .urlEncode] : [.urlEncode, .urlDecode]
        case .number:
            if TextTransform.timestampToDate.apply(trimmed) != nil { out.append(.timestampToDate) }
        case .color:
            out += trimmed.hasPrefix("#") ? [.colorToRGB, .colorToHex] : [.colorToHex, .colorToRGB]
        case .code:
            out += [.cleanWhitespace, .removeInvisible, .numberLines]
        case .email, .path:
            out += [.lower, .urlEncode]
        default:
            if TextTransform.dateToTimestamp.apply(trimmed) != nil {
                out.append(.dateToTimestamp)
            } else if looksLikeBase64(trimmed) {
                out.append(.base64Decode)
            }
            if trimmed.contains("&"), trimmed.contains(";") { out.append(.htmlDecode) }
            out += [.cleanWhitespace, .sentenceCase, .titleCase, .upper, .lower, .slugify]
        }
        if multiline { out += [.sortLines, .dedupeLines, .reverseLines, .numberLines] }
        if trimmed.contains(where: { $0 == "\u{00A0}" || $0 == "\u{200B}" || $0 == "\u{FEFF}" }) { out.insert(.removeInvisible, at: 0) }

        var seen = Set<TextTransform>()
        return out.filter { seen.insert($0).inserted }
    }

    static func looksLikeBase64(_ s: String) -> Bool {
        guard s.count >= 8, s.count % 4 == 0, !s.contains(where: \.isWhitespace),
              s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }) else { return false }
        return TextTransform.base64Decode.apply(s) != nil
    }
}
