import CryptoKit
import Foundation
import GRDB

/// Activation et desactivation de la protection : aucune note ne doit se perdre.
/// Activer : sauvegarde de la base en clair a cote (`brouillon.sqlite.avant-chiffrement`, jamais
/// ecrasee), chiffrement de tous les brouillons dans une transaction, relecture dans la meme
/// transaction (toute difference annule tout), puis purge des pages liberees.
extension DraftStore {
    public static let backupSuffix = ".avant-chiffrement"

    public func protectionState() throws -> ProtectionState {
        try database.read { db in try Self.state(in: db) }
    }

    /// « Pas maintenant » sur une base d'avant 0.3.0 : la protection reste desactivee.
    public func declineProtection() throws {
        try database.write { db in
            if try Self.state(in: db) == .undecided { try Meta.set(Self.protectionMeta, ProtectionState.off.rawValue, in: db) }
        }
    }

    /// Chiffre tous les brouillons avec `newKey` et garde la cle en memoire (deverrouille).
    /// Renvoie la sauvegarde ecrite avant le chiffrement (nil : rien en clair a sauvegarder, ou base
    /// en memoire). Idempotente : deja active avec la meme cle, ne rechiffre rien ; avec une autre
    /// cle, `DraftStoreError.wrongKey`. `beforeCommit` sert aux tests (panne simulee).
    @discardableResult
    public func enableProtection(key newKey: SymmetricKey,
                                 beforeCommit: (@Sendable (Database) throws -> Void)? = nil) throws -> URL? {
        let (state, check, plainCount) = try database.read { db in
            (try Self.state(in: db), try Meta.value(Self.keyCheckMeta, in: db),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM draft WHERE textSealed IS NULL AND titleSealed IS NULL") ?? 0)
        }
        if state == .on {
            guard let check, try Self.isKeyCheck(check, valid: newKey) else { throw DraftStoreError.wrongKey }
        }

        var backup: URL?
        if plainCount > 0, let file = database.fileURL {
            backup = try writeBackup(of: file)
        }

        try database.write { db in
            var expected: [String: Draft] = [:]
            for record in try DraftRecord.fetchAll(db) {
                // Deja chiffre : le dechiffrer verifie que c'est la meme cle.
                let draft = try Self.draft(record, key: newKey)
                expected[record.id] = draft
                if !record.isSealed { try Self.record(draft, sealing: newKey).update(db) }
            }
            if state != .on { try Meta.set(Self.keyCheckMeta, try Self.keyCheck(newKey), in: db) }
            try Meta.set(Self.protectionMeta, ProtectionState.on.rawValue, in: db)
            try beforeCommit?(db)
            try Self.verify(db, expected: expected, sealedWith: newKey)
        }
        key.withLock { $0 = newKey }
        purgeFreedPages()
        return backup
    }

    /// Dechiffre tous les brouillons (protection desactivee). Demande d'etre deverrouille.
    public func disableProtection(beforeCommit: (@Sendable (Database) throws -> Void)? = nil) throws {
        guard try protectionState() == .on else { return }
        guard let currentKey = key.withLock({ $0 }) else { throw DraftStoreError.locked }
        try database.write { db in
            var expected: [String: Draft] = [:]
            for record in try DraftRecord.fetchAll(db) {
                let draft = try Self.draft(record, key: currentKey)
                expected[record.id] = draft
                if record.isSealed { try Self.record(draft, sealing: nil).update(db) }
            }
            try Meta.set(Self.protectionMeta, ProtectionState.off.rawValue, in: db)
            try db.execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [Self.keyCheckMeta])
            try beforeCommit?(db)
            try Self.verify(db, expected: expected, sealedWith: nil)
        }
        lock()
    }

    /// Sauvegarde coherente (VACUUM INTO, WAL compris) a cote de la base, sans jamais ecraser une
    /// sauvegarde existante ; relue avant de continuer.
    func writeBackup(of file: URL) throws -> URL {
        let url = Self.availableBackupURL(for: file)
        try database.writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [url.path])
        }
        let expectedCount = try database.read { db in try DraftRecord.fetchCount(db) }
        var config = Configuration()
        config.readonly = true
        let copy = try DatabaseQueue(path: url.path, configuration: config)
        let copied = try copy.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM draft") ?? -1 }
        try copy.close()
        guard copied == expectedCount else {
            throw DraftStoreError.verificationFailed("sauvegarde incompl\u{00E8}te : \(copied) sur \(expectedCount)")
        }
        return url
    }

    /// `brouillon.sqlite.avant-chiffrement`, puis `-2`, `-3`... si elle existe deja.
    public static func availableBackupURL(for file: URL) -> URL {
        let base = file.path + backupSuffix
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return URL(fileURLWithPath: candidate)
    }

    /// Sauvegardes d'avant chiffrement presentes a cote de la base.
    public func existingBackups() -> [URL] {
        guard let file = database.fileURL else { return [] }
        let dir = file.deletingLastPathComponent()
        let prefix = file.lastPathComponent + Self.backupSuffix
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { dir.appendingPathComponent($0) }
    }

    /// Relecture dans la transaction : memes brouillons, tous chiffres (ou tous en clair).
    static func verify(_ db: Database, expected: [String: Draft], sealedWith key: SymmetricKey?) throws {
        let records = try DraftRecord.fetchAll(db)
        guard records.count == expected.count else {
            throw DraftStoreError.verificationFailed("\(records.count) brouillons relus sur \(expected.count)")
        }
        for record in records {
            let sealedAsExpected = key == nil ? !record.isSealed
                : (record.textSealed != nil && record.titleSealed != nil && record.text.isEmpty && record.title.isEmpty)
            guard sealedAsExpected, let draft = try? Self.draft(record, key: key), draft == expected[record.id] else {
                throw DraftStoreError.verificationFailed("brouillon \(record.id)")
            }
        }
    }

    /// Le texte en clair remplace ne doit pas rester dans le journal WAL ni dans les pages libres.
    func purgeFreedPages() {
        try? database.writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute(sql: "VACUUM")
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
