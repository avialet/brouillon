import CryptoKit
import Foundation
import GRDB
import Synchronization

/// Un brouillon : le texte, son titre (premiere ligne), ses dates. Toujours en clair en memoire ;
/// sur le disque, titre et texte sont chiffres quand la protection est active.
public struct Draft: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var text: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, text: String, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.text = text
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Premiere ligne non vide, 60 caracteres au plus. Une premiere ligne trop
    /// courte (« { », « - ») est completee par les suivantes, espaces repliees.
    public static func title(for text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        let title = first.count >= 4 ? first : lines.joined(separator: " ")
        return shortened(title)
    }

    /// 60 caracteres au plus, avec une ellipse.
    public static func shortened(_ title: String) -> String {
        title.count <= 60 ? title : String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Ligne de la table `draft` : en clair (`text`, `title`) ou chiffree (`textSealed`, `titleSealed`,
/// `text` et `title` vides).
struct DraftRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "draft"
    var id: String
    var text: String
    var title: String
    var textSealed: Data?
    var titleSealed: Data?
    var createdAt: Date
    var updatedAt: Date

    var isSealed: Bool { textSealed != nil || titleSealed != nil }
}

/// Etat de la protection (verrou et chiffrement), dans `meta.protection`.
public enum ProtectionState: String, Sendable {
    /// Base d'avant 0.3.0 (ou neuve) : rien n'est decide.
    case undecided
    case on
    case off
}

public enum DraftStoreError: Error, Equatable, CustomStringConvertible {
    /// Protection active et cle absente (verrouille).
    case locked
    /// La cle ne correspond pas a celle qui a chiffre la base.
    case wrongKey
    /// La relecture apres chiffrement ou dechiffrement ne redonne pas les memes brouillons.
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .locked: "Brouillon est verrouill\u{00E9}."
        case .wrongKey: "La cl\u{00E9} du trousseau ne correspond pas \u{00E0} celle qui a chiffr\u{00E9} les brouillons."
        case .verificationFailed(let detail): "La relecture a \u{00E9}chou\u{00E9} (\(detail)) : rien n'a \u{00E9}t\u{00E9} modifi\u{00E9}."
        }
    }
}

/// Brouillons en SQLite : sauvegarde continue du brouillon courant, liste par recence.
/// Protection active : titre et texte chiffres (NoteCipher), cle gardee en memoire seulement
/// deverrouille (`unlock` / `lock`).
public final class DraftStore: Sendable {
    public let database: AppDatabase
    let key = Mutex<SymmetricKey?>(nil)

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: Cle

    public var isUnlocked: Bool { key.withLock { $0 != nil } }

    /// Efface la cle de la memoire.
    public func lock() { key.withLock { $0 = nil } }

    /// Garde la cle en memoire apres avoir verifie qu'elle ouvre la base (protection active).
    public func unlock(with candidate: SymmetricKey) throws {
        if try protectionState() == .on {
            let check = try database.read { db in try Meta.value(Self.keyCheckMeta, in: db) }
            guard let check, try Self.isKeyCheck(check, valid: candidate) else { throw DraftStoreError.wrongKey }
        }
        key.withLock { $0 = candidate }
    }

    // MARK: Brouillons

    /// Cree (id nil) ou met a jour. Un texte vide n'est pas sauvegarde (et renvoie nil).
    @discardableResult
    public func save(id: String?, text: String, now: Date = Date()) throws -> Draft? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let currentKey = key.withLock { $0 }
        return try database.write { db in
            let sealing = try Self.sealingKey(currentKey, in: db)
            if let id, let existing = try DraftRecord.fetchOne(db, key: id) {
                let draft = Draft(id: id, text: text, title: Draft.title(for: text), createdAt: existing.createdAt, updatedAt: now)
                try Self.record(draft, sealing: sealing).update(db)
                return draft
            }
            let draft = Draft(id: id ?? UUID().uuidString.lowercased(), text: text, title: Draft.title(for: text), createdAt: now, updatedAt: now)
            try Self.record(draft, sealing: sealing).insert(db)
            return draft
        }
    }

    public func list() throws -> [Draft] {
        let currentKey = key.withLock { $0 }
        return try database.read { db in
            try DraftRecord.order(Column("updatedAt").desc).fetchAll(db).map { try Self.draft($0, key: currentKey) }
        }
    }

    public func draft(_ id: String) throws -> Draft? {
        let currentKey = key.withLock { $0 }
        return try database.read { db in
            try DraftRecord.fetchOne(db, key: id).map { try Self.draft($0, key: currentKey) }
        }
    }

    public func delete(_ id: String) throws {
        _ = try database.write { db in try DraftRecord.deleteOne(db, key: id) }
    }

    // MARK: Conversions

    static let protectionMeta = "protection"
    static let keyCheckMeta = "keyCheck"
    static let keyCheckText = "brouillon"

    static func context(_ id: String, _ field: String) -> String { "draft/\(id)/\(field)" }

    /// Cle a utiliser pour ecrire : nil sans protection ; erreur si protegee et verrouillee.
    static func sealingKey(_ key: SymmetricKey?, in db: Database) throws -> SymmetricKey? {
        guard try state(in: db) == .on else { return nil }
        guard let key else { throw DraftStoreError.locked }
        return key
    }

    static func state(in db: Database) throws -> ProtectionState {
        try Meta.value(protectionMeta, in: db).flatMap(ProtectionState.init(rawValue:)) ?? .undecided
    }

    static func record(_ draft: Draft, sealing key: SymmetricKey?) throws -> DraftRecord {
        guard let key else {
            return DraftRecord(id: draft.id, text: draft.text, title: draft.title, textSealed: nil, titleSealed: nil,
                               createdAt: draft.createdAt, updatedAt: draft.updatedAt)
        }
        return DraftRecord(id: draft.id, text: "", title: "",
                           textSealed: try NoteCipher.seal(draft.text, key: key, context: context(draft.id, "text")),
                           titleSealed: try NoteCipher.seal(draft.title, key: key, context: context(draft.id, "title")),
                           createdAt: draft.createdAt, updatedAt: draft.updatedAt)
    }

    static func draft(_ record: DraftRecord, key: SymmetricKey?) throws -> Draft {
        guard record.isSealed else {
            return Draft(id: record.id, text: record.text, title: record.title, createdAt: record.createdAt, updatedAt: record.updatedAt)
        }
        guard let key else { throw DraftStoreError.locked }
        let text = try record.textSealed.map { try NoteCipher.open($0, key: key, context: context(record.id, "text")) } ?? ""
        let title = try record.titleSealed.map { try NoteCipher.open($0, key: key, context: context(record.id, "title")) } ?? ""
        return Draft(id: record.id, text: text, title: title, createdAt: record.createdAt, updatedAt: record.updatedAt)
    }

    static func keyCheck(_ key: SymmetricKey) throws -> String {
        try NoteCipher.seal(keyCheckText, key: key, context: "meta/keyCheck").base64EncodedString()
    }

    static func isKeyCheck(_ stored: String, valid key: SymmetricKey) throws -> Bool {
        guard let data = Data(base64Encoded: stored) else { return false }
        return (try? NoteCipher.open(data, key: key, context: "meta/keyCheck")) == keyCheckText
    }
}
