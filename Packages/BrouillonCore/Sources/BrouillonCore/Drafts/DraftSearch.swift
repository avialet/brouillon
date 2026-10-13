import Darwin
import Foundation

/// Recherche en memoire sur les brouillons dechiffres (titre et texte), sans accents ni casse
/// (SearchNormalizer du kit) : tous les mots de la requete doivent y figurer. Rien n'est ecrit
/// sur le disque. Mise a jour brouillon par brouillon apres une sauvegarde.
public struct DraftSearchIndex: Sendable {
    /// Texte normalise en UTF-8 : recherche d'octets (memmem), bien plus rapide que String.contains ;
    /// sans risque sur un texte deja replie (minuscules, sans accents).
    private var normalized: [String: [UInt8]] = [:]

    public init(_ drafts: [Draft] = []) {
        normalized.reserveCapacity(drafts.count)
        for draft in drafts { update(draft) }
    }

    public mutating func update(_ draft: Draft) {
        normalized[draft.id] = Array(SearchNormalizer.normalize(draft.title + "\n" + draft.text).utf8)
    }

    public mutating func remove(_ id: String) {
        normalized[id] = nil
    }

    /// `drafts` filtres, dans leur ordre ; requete vide : tous.
    public func filter(_ drafts: [Draft], query: String) -> [Draft] {
        let terms = SearchNormalizer.normalize(query).split(whereSeparator: \.isWhitespace).map { Array($0.utf8) }
        guard !terms.isEmpty else { return drafts }
        return drafts.filter { draft in
            guard let haystack = normalized[draft.id] else { return false }
            return terms.allSatisfy { Self.contains(haystack, $0) }
        }
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}
