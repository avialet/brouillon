import Foundation
import GRDB

/// Correspondance note de Notes -> brouillon, pour relancer l'import sans doublon.
/// Supprimer le brouillon supprime la correspondance (la note pourra etre reimportee).
struct NotesImportRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "notesImport"
    var notesId: String
    var draftId: String
    /// Date de modification de la note lors de l'import.
    var notesModifiedAt: Date
    /// Date du brouillon ecrit par l'import : differente ensuite, il a ete modifie dans Brouillon.
    var draftUpdatedAt: Date
    var importedAt: Date
}

/// Ce que l'import fait d'une note.
public enum NotesImportAction: Equatable, Sendable {
    case create
    /// Note modifiee depuis l'import ; `keepEdited` : le brouillon a ete modifie dans Brouillon,
    /// la nouvelle version devient un nouveau brouillon (rien n'est ecrase).
    case update(draftId: String, keepEdited: Bool)
    case skipUnchanged
    case skipModified
    case skipLocked

    /// Pur : decision pour une note, d'apres son import precedent.
    static func decide(_ note: NotesNoteInfo, previous: NotesImportRecord?, draftUpdatedAt: Date?,
                       updateModified: Bool) -> NotesImportAction {
        if note.isLocked { return .skipLocked }
        guard let previous, let draftUpdatedAt else { return .create }
        guard note.modifiedAt.timeIntervalSince(previous.notesModifiedAt) > 1 else { return .skipUnchanged }
        guard updateModified else { return .skipModified }
        let edited = abs(draftUpdatedAt.timeIntervalSince(previous.draftUpdatedAt)) > 0.01
        return .update(draftId: previous.draftId, keepEdited: edited)
    }
}

public struct NotesImportSummary: Equatable, Sendable {
    public var imported = 0
    public var updated = 0
    public var unchanged = 0
    public var modifiedSkipped = 0
    public var locked = 0
    public var failed = 0
    public var cancelled = false

    public init(imported: Int = 0, updated: Int = 0, unchanged: Int = 0, modifiedSkipped: Int = 0,
                locked: Int = 0, failed: Int = 0, cancelled: Bool = false) {
        self.imported = imported
        self.updated = updated
        self.unchanged = unchanged
        self.modifiedSkipped = modifiedSkipped
        self.locked = locked
        self.failed = failed
        self.cancelled = cancelled
    }

    /// « 42 notes importées, 3 verrouillées ignorées ».
    public var text: String {
        func n(_ count: Int, _ singular: String, _ plural: String) -> String {
            "\(count) \(count > 1 ? plural : singular)"
        }
        var parts = [imported == 0 ? "Aucune note import\u{00E9}e" : n(imported, "note import\u{00E9}e", "notes import\u{00E9}es")]
        if updated > 0 { parts.append(n(updated, "mise \u{00E0} jour", "mises \u{00E0} jour")) }
        if unchanged > 0 { parts.append(n(unchanged, "d\u{00E9}j\u{00E0} import\u{00E9}e", "d\u{00E9}j\u{00E0} import\u{00E9}es")) }
        if modifiedSkipped > 0 {
            parts.append(n(modifiedSkipped, "modifi\u{00E9}e depuis ignor\u{00E9}e", "modifi\u{00E9}es depuis ignor\u{00E9}es"))
        }
        if locked > 0 { parts.append(n(locked, "verrouill\u{00E9}e ignor\u{00E9}e", "verrouill\u{00E9}es ignor\u{00E9}es")) }
        if failed > 0 { parts.append("\(failed) en \u{00E9}chec") }
        return (cancelled ? "Import annul\u{00E9} : " : "") + parts.joined(separator: ", ")
    }
}

/// Import ponctuel depuis l'app Notes, relancable sans doublon. Chaque note est ecrite dans sa
/// propre transaction (brouillon + correspondance) : une annulation garde ce qui est importe.
/// Protection active : il faut etre deverrouille, les brouillons sont chiffres comme les autres.
public final class NotesImporter: Sendable {
    public let store: DraftStore
    public let source: any NotesSource

    public init(store: DraftStore, source: any NotesSource) {
        self.store = store
        self.source = source
    }

    public func run(folderIds: [String], updateModified: Bool, batchSize: Int = 10, now: Date = Date(),
                    progress: @Sendable (_ done: Int, _ total: Int) -> Void,
                    isCancelled: @Sendable () -> Bool) throws -> NotesImportSummary {
        // Protection active et verrouille : on s'arrete avant de lire quoi que ce soit.
        if try store.protectionState() == .on, !store.isUnlocked { throw DraftStoreError.locked }

        var seen = Set<String>()
        let notes = try source.notes(inFolders: folderIds).filter { seen.insert($0.id).inserted }
        let previous: [String: (NotesImportRecord, Date)] = try store.database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT notesImport.*, draft.updatedAt AS currentDraftUpdatedAt
                FROM notesImport JOIN draft ON draft.id = notesImport.draftId
                """)
            var map: [String: (NotesImportRecord, Date)] = [:]
            for row in rows {
                let record = try NotesImportRecord(row: row)
                map[record.notesId] = (record, row["currentDraftUpdatedAt"])
            }
            return map
        }

        var summary = NotesImportSummary()
        var work: [(NotesNoteInfo, NotesImportAction)] = []
        for note in notes {
            let action = NotesImportAction.decide(note, previous: previous[note.id]?.0, draftUpdatedAt: previous[note.id]?.1,
                                                  updateModified: updateModified)
            switch action {
            case .skipLocked: summary.locked += 1
            case .skipUnchanged: summary.unchanged += 1
            case .skipModified: summary.modifiedSkipped += 1
            case .create, .update: work.append((note, action))
            }
        }

        let total = work.count
        var done = 0
        progress(0, total)
        for start in stride(from: 0, to: work.count, by: max(1, batchSize)) {
            if isCancelled() { summary.cancelled = true; break }
            let batch = Array(work[start..<min(start + max(1, batchSize), work.count)])
            let bodies = try fetchBodies(batch.map(\.0.id))
            for (note, action) in batch {
                if let html = bodies[note.id] {
                    try write(note, html: html, action: action, now: now)
                    if case .create = action { summary.imported += 1 } else { summary.updated += 1 }
                } else {
                    summary.failed += 1
                }
                done += 1
                progress(done, total)
            }
        }
        return summary
    }

    /// Corps d'un lot ; en cas d'erreur du lot, note par note (une note illisible n'arrete pas l'import).
    private func fetchBodies(_ ids: [String]) throws -> [String: String] {
        do {
            return try source.bodies(of: ids)
        } catch NotesSourceError.notAuthorized {
            throw NotesSourceError.notAuthorized
        } catch {
            var bodies: [String: String] = [:]
            for id in ids {
                if let one = try? source.bodies(of: [id]) { bodies.merge(one) { a, _ in a } }
            }
            return bodies
        }
    }

    private func write(_ note: NotesNoteInfo, html: String, action: NotesImportAction, now: Date) throws {
        let text = NotesHTML.draftText(name: note.name, html: html)
        let name = NotesHTML.collapse(note.name)
        let title = name.isEmpty ? Draft.title(for: text) : Draft.shortened(name)
        let currentKey = store.key.withLock { $0 }
        try store.database.write { db in
            let sealing = try DraftStore.sealingKey(currentKey, in: db)
            var draft = Draft(id: UUID().uuidString.lowercased(), text: text, title: title,
                              createdAt: note.createdAt, updatedAt: note.modifiedAt)
            switch action {
            case .update(let draftId, keepEdited: false):
                // Brouillon illisible : jamais ecrase, la note arrive dans un nouveau brouillon.
                if let existing = try DraftRecord.fetchOne(db, key: draftId),
                   (try? DraftStore.strictDraft(existing, key: currentKey)) != nil {
                    draft.id = draftId
                    draft.createdAt = existing.createdAt
                    try DraftStore.record(draft, sealing: sealing).update(db)
                } else {
                    try DraftStore.record(draft, sealing: sealing).insert(db)
                }
            default:
                try DraftStore.record(draft, sealing: sealing).insert(db)
            }
            try NotesImportRecord(notesId: note.id, draftId: draft.id, notesModifiedAt: note.modifiedAt,
                                  draftUpdatedAt: draft.updatedAt, importedAt: now).save(db)
        }
    }
}
