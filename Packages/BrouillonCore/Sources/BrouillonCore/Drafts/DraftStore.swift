import Foundation
import GRDB

/// Un brouillon : le texte, son titre (premiere ligne), ses dates.
public struct Draft: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "draft"

    public var id: String
    public var text: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    /// Premiere ligne non vide, 60 caracteres au plus. Une premiere ligne trop
    /// courte (« { », « - ») est completee par les suivantes, espaces repliees.
    public static func title(for text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        let title = first.count >= 4 ? first : lines.joined(separator: " ")
        return title.count <= 60 ? title : String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Brouillons en SQLite : sauvegarde continue du brouillon courant, liste par recence.
public final class DraftStore: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Cree (id nil) ou met a jour. Un texte vide n'est pas sauvegarde (et renvoie nil).
    @discardableResult
    public func save(id: String?, text: String, now: Date = Date()) throws -> Draft? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try database.write { db in
            if let id, var existing = try Draft.fetchOne(db, key: id) {
                existing.text = text
                existing.title = Draft.title(for: text)
                existing.updatedAt = now
                try existing.update(db)
                return existing
            }
            let draft = Draft(id: id ?? UUID().uuidString.lowercased(), text: text, title: Draft.title(for: text), createdAt: now, updatedAt: now)
            try draft.insert(db)
            return draft
        }
    }

    public func list() throws -> [Draft] {
        try database.read { db in try Draft.order(Column("updatedAt").desc).fetchAll(db) }
    }

    public func draft(_ id: String) throws -> Draft? {
        try database.read { db in try Draft.fetchOne(db, key: id) }
    }

    public func delete(_ id: String) throws {
        _ = try database.write { db in try Draft.deleteOne(db, key: id) }
    }
}
