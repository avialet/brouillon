import CryptoKit
import Foundation
import GRDB
import BrouillonCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

/// Dossier jetable pour une base sur disque (WAL, sauvegarde, VACUUM).
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("brouillon-check-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct RawRow: Equatable {
    let text: String
    let title: String
    let textSealed: Data?
    let titleSealed: Data?
}

private func rawRows(_ db: AppDatabase) throws -> [String: RawRow] {
    try db.read { db in
        var rows: [String: RawRow] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, text, title, textSealed, titleSealed FROM draft") {
            rows[row["id"]] = RawRow(text: row["text"], title: row["title"], textSealed: row["textSealed"], titleSealed: row["titleSealed"])
        }
        return rows
    }
}

/// Octets de tous les fichiers de la base (principal, WAL, SHM).
private func fileBytes(_ url: URL) -> Data {
    var data = Data()
    for suffix in ["", "-wal", "-shm"] {
        if let d = try? Data(contentsOf: URL(fileURLWithPath: url.path + suffix)) { data += d }
    }
    return data
}

private func seededStore(_ dir: URL) throws -> (DraftStore, URL) {
    let url = dir.appendingPathComponent("brouillon.sqlite")
    let store = DraftStore(database: try AppDatabase.open(at: url))
    _ = try store.save(id: nil, text: "Lettre au bailleur\nSECRET-UN", now: t0)
    _ = try store.save(id: nil, text: "Codes du portail\nSECRET-DEUX", now: t0.addingTimeInterval(10))
    _ = try store.save(id: nil, text: "Liste\nSECRET-TROIS", now: t0.addingTimeInterval(20))
    return (store, url)
}

let protectionTests: (String, [Test]) = ("Protection", [
    Test("newDatabaseIsUndecided") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        expectEqual(try store.protectionState(), .undecided)
        try store.declineProtection()
        expectEqual(try store.protectionState(), .off)
    },
    Test("enableEncryptsEverythingAndKeepsBackup") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, url) = try seededStore(dir)
        let before = try store.list()
        let key = NoteCipher.newKey()
        let backup = try store.enableProtection(key: key)
        expectEqual(backup?.lastPathComponent, "brouillon.sqlite.avant-chiffrement")
        expectEqual(try store.protectionState(), .on)
        for (_, row) in try rawRows(store.database) {
            expectEqual(row.text, "")
            expectEqual(row.title, "")
            expect(row.textSealed != nil && row.titleSealed != nil)
        }
        expectEqual(try store.list(), before, "relecture identique")
        let bytes = fileBytes(url)
        for secret in ["SECRET-UN", "SECRET-DEUX", "SECRET-TROIS", "bailleur"] {
            expect(bytes.range(of: Data(secret.utf8)) == nil, "\(secret) encore en clair sur le disque")
        }
        // La sauvegarde est la base d'avant, lisible telle quelle.
        let copy = try DatabaseQueue(path: backup!.path)
        let texts = try copy.read { try String.fetchAll($0, sql: "SELECT text FROM draft ORDER BY updatedAt") }
        expectEqual(texts, ["Lettre au bailleur\nSECRET-UN", "Codes du portail\nSECRET-DEUX", "Liste\nSECRET-TROIS"])
    },
    Test("enableIsIdempotent") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = try seededStore(dir)
        let key = NoteCipher.newKey()
        try store.enableProtection(key: key)
        let sealed = try rawRows(store.database)
        let second = try store.enableProtection(key: key)
        expect(second == nil, "rien a sauvegarder la seconde fois")
        expectEqual(try rawRows(store.database), sealed, "rien de rechiffre")
        expectThrows { try store.enableProtection(key: NoteCipher.newKey()) }
    },
    Test("failureBeforeCommitLosesNothing") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = try seededStore(dir)
        let before = try rawRows(store.database)
        struct Boom: Error {}
        expectThrows { try store.enableProtection(key: NoteCipher.newKey(), beforeCommit: { _ in throw Boom() }) }
        expectEqual(try rawRows(store.database), before, "transaction annulee")
        expectEqual(try store.protectionState(), .undecided)
        expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("brouillon.sqlite.avant-chiffrement").path), "sauvegarde gardee")
    },
    Test("verificationCatchesCorruption") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = try seededStore(dir)
        let before = try rawRows(store.database)
        expectThrows {
            try store.enableProtection(key: NoteCipher.newKey(), beforeCommit: { db in
                try db.execute(sql: "UPDATE draft SET textSealed = x'0100' WHERE rowid = (SELECT min(rowid) FROM draft)")
            })
        }
        expectEqual(try rawRows(store.database), before, "relecture fausse : rien d'ecrit")
        expectEqual(try store.protectionState(), .undecided)
    },
    Test("backupIsNeverOverwritten") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = try seededStore(dir)
        let existing = dir.appendingPathComponent("brouillon.sqlite.avant-chiffrement")
        try Data("ancienne".utf8).write(to: existing)
        let backup = try store.enableProtection(key: NoteCipher.newKey())
        expectEqual(backup?.lastPathComponent, "brouillon.sqlite.avant-chiffrement-2")
        expectEqual(try Data(contentsOf: existing), Data("ancienne".utf8))
    },
    Test("lockedStoreRefusesReadAndWrite") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let draft = try store.save(id: nil, text: "avant", now: t0)!
        let key = NoteCipher.newKey()
        try store.enableProtection(key: key)
        store.lock()
        expect(!store.isUnlocked)
        expectThrows { _ = try store.list() }
        expectThrows { _ = try store.save(id: nil, text: "pendant", now: t0) }
        expectThrows { _ = try store.draft(draft.id) }
        expectThrows { try store.unlock(with: NoteCipher.newKey()) }
        expect(!store.isUnlocked)
        try store.unlock(with: key)
        expectEqual(try store.list().map(\.text), ["avant"])
    },
    Test("savesAreSealedWhenProtected") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        try store.enableProtection(key: NoteCipher.newKey())
        let d = try store.save(id: nil, text: "Nouveau\nsecret", now: t0)!
        _ = try store.save(id: d.id, text: "Nouveau\nsecret modifie", now: t0.addingTimeInterval(1))
        let row = try rawRows(store.database)[d.id]!
        expectEqual(row.text, "")
        expect(row.textSealed != nil)
        expectEqual(try store.draft(d.id)?.text, "Nouveau\nsecret modifie")
        expectEqual(try store.draft(d.id)?.title, "Nouveau")
    },
    Test("disableDecryptsEverything") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = try seededStore(dir)
        let before = try store.list()
        let key = NoteCipher.newKey()
        try store.enableProtection(key: key)
        try store.disableProtection()
        expectEqual(try store.protectionState(), .off)
        expectEqual(try store.list(), before)
        for (_, row) in try rawRows(store.database) {
            expect(row.textSealed == nil && row.titleSealed == nil && !row.text.isEmpty)
        }
        store.lock()
        expectEqual(try store.list(), before, "sans protection, plus besoin de cle")
    },
    Test("migratesDatabaseFromVersion020") {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("brouillon.sqlite")
        // Base telle que l'ecrit Brouillon 0.2.0 : schema v1 seulement.
        let old = try DatabasePool(path: url.path)
        try Migrations.migrate(old, upTo: "v1")
        try old.write { db in
            try db.execute(sql: "INSERT INTO draft (id, text, title, createdAt, updatedAt) VALUES ('a', 'Ancien\ntexte', 'Ancien', ?, ?)",
                           arguments: [t0, t0])
        }
        try old.close()
        let store = DraftStore(database: try AppDatabase.open(at: url))
        expectEqual(try store.protectionState(), .undecided)
        expectEqual(try store.list().map(\.text), ["Ancien\ntexte"])
        try store.enableProtection(key: NoteCipher.newKey())
        expectEqual(try store.list().map(\.text), ["Ancien\ntexte"])
    },
])
