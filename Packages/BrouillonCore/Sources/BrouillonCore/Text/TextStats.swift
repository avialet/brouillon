import Foundation

/// Compteurs d'un texte.
public struct TextStats: Equatable, Sendable {
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let words: Int
    public let lines: Int
    public let paragraphs: Int
    /// A 200 mots par minute, au moins 1 des qu'il y a un mot.
    public let readingMinutes: Int

    public static func of(_ text: String) -> TextStats {
        let characters = text.count
        let withoutSpaces = text.filter { !$0.isWhitespace && !$0.isNewline }.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let paragraphs = text.components(separatedBy: "\n").split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty }).count
        let minutes = words == 0 ? 0 : max(1, Int((Double(words) / 200).rounded(.up)))
        return TextStats(characters: characters, charactersWithoutSpaces: withoutSpaces, words: words,
                         lines: lines, paragraphs: paragraphs, readingMinutes: minutes)
    }
}
