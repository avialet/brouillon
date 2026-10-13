import Foundation
import GRDB
import BrouillonCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

/// Source Notes factice : dossiers, notes et corps fixes ; compte les corps demandes.
final class FakeNotesSource: NotesSource, @unchecked Sendable {
    var folderList: [NotesFolder]
    var notesByFolder: [String: [NotesNoteInfo]]
    var bodiesById: [String: String]
    var failingBodies: Set<String> = []
    /// Simule une annulation pendant la lecture d'un lot : le processus arrete, le lot echoue.
    var cancelDuringBodies: CancelBox?
    private(set) var requestedBodies: [String] = []

    init(folders: [NotesFolder], notes: [String: [NotesNoteInfo]], bodies: [String: String]) {
        folderList = folders
        notesByFolder = notes
        bodiesById = bodies
    }

    func folders() throws -> [NotesFolder] { folderList }

    func notes(inFolders ids: [String]) throws -> [NotesNoteInfo] {
        ids.flatMap { notesByFolder[$0] ?? [] }
    }

    func bodies(of ids: [String]) throws -> [String: String] {
        requestedBodies += ids
        if let cancelDuringBodies {
            cancelDuringBodies.cancelled = true
            throw NotesSourceError.failed("arrete")
        }
        if ids.contains(where: failingBodies.contains) { throw NotesSourceError.failed("corps illisible") }
        return bodiesById.filter { ids.contains($0.key) }
    }
}

private func note(_ id: String, _ name: String, modified: TimeInterval = 0, locked: Bool = false) -> NotesNoteInfo {
    NotesNoteInfo(id: id, name: name, folderId: "f1", createdAt: t0, modifiedAt: t0.addingTimeInterval(modified), isLocked: locked)
}

private func sampleSource() -> FakeNotesSource {
    FakeNotesSource(
        folders: [NotesFolder(id: "f1", name: "Notes", account: "iCloud", noteCount: 4),
                  NotesFolder(id: "f2", name: "Recettes", account: "iCloud", noteCount: 1)],
        notes: ["f1": [note("n1", "Courses"), note("n2", "Idees"), note("n3", "Coffre", locked: true), note("n4", "Vide")],
                "f2": [NotesNoteInfo(id: "n5", name: "Tarte", folderId: "f2", createdAt: t0, modifiedAt: t0, isLocked: false)]],
        bodies: ["n1": "<div><h1>Courses</h1></div><div>lait</div>", "n2": "<div>Idees</div><ul><li>une</li></ul>",
                 "n4": "", "n5": "<div>Tarte</div><div>pommes</div>"])
}

private func runImport(_ store: DraftStore, _ source: FakeNotesSource, folders: [String] = ["f1"], update: Bool = false,
                       cancelAfter: Int? = nil) throws -> NotesImportSummary {
    let importer = NotesImporter(store: store, source: source)
    let progress = ProgressLog()
    return try importer.run(folderIds: folders, updateModified: update, batchSize: 2, now: t0.addingTimeInterval(3600),
                            progress: { done, total in progress.append(done, total) },
                            isCancelled: { cancelAfter.map { progress.lastDone >= $0 } ?? false })
}

final class CancelBox: @unchecked Sendable {
    var cancelled = false
}

final class ProgressLog: @unchecked Sendable {
    private(set) var steps: [(Int, Int)] = []
    var lastDone: Int { steps.last?.0 ?? 0 }
    func append(_ done: Int, _ total: Int) { steps.append((done, total)) }
}

let notesImportTests: (String, [Test]) = ("NotesImport", [
    Test("importsNotesWithTitleAndDates") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let summary = try runImport(store, sampleSource())
        expectEqual(summary.imported, 3)
        expectEqual(summary.locked, 1)
        expectEqual(summary.text, "3 notes import\u{00E9}es, 1 verrouill\u{00E9}e ignor\u{00E9}e")
        let drafts = try store.list()
        let courses = drafts.first { $0.title == "Courses" }
        expectEqual(courses?.text, "Courses\nlait")
        expectEqual(courses?.createdAt, t0)
        expectEqual(drafts.first { $0.title == "Idees" }?.text, "Idees\n- une")
        expectEqual(drafts.first { $0.title == "Vide" }?.text, "Vide")
    },
    Test("lockedNotesAreNeverRead") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        expect(!source.requestedBodies.contains("n3"))
    },
    Test("rerunDoesNotDuplicate") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        let second = try runImport(store, source, folders: ["f1", "f2"])
        expectEqual(second.imported, 1, "seule la note du second dossier est nouvelle")
        expectEqual(second.unchanged, 3)
        expectEqual(second.text, "1 note import\u{00E9}e, 3 d\u{00E9}j\u{00E0} import\u{00E9}es, 1 verrouill\u{00E9}e ignor\u{00E9}e")
        expectEqual(try store.list().count, 4)
    },
    Test("modifiedNotesIgnoredByDefault") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        source.notesByFolder["f1"]![0] = note("n1", "Courses", modified: 120)
        source.bodiesById["n1"] = "<div>Courses</div><div>lait, oeufs</div>"
        let summary = try runImport(store, source)
        expectEqual(summary.modifiedSkipped, 1)
        expectEqual(summary.imported, 0)
        expectEqual(summary.text, "Aucune note import\u{00E9}e, 2 d\u{00E9}j\u{00E0} import\u{00E9}es, 1 modifi\u{00E9}e depuis ignor\u{00E9}e, 1 verrouill\u{00E9}e ignor\u{00E9}e")
        expectEqual(try store.list().first { $0.title == "Courses" }?.text, "Courses\nlait")
    },
    Test("modifiedNotesUpdatedOnRequest") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        source.notesByFolder["f1"]![0] = note("n1", "Courses", modified: 120)
        source.bodiesById["n1"] = "<div>Courses</div><div>lait, oeufs</div>"
        let summary = try runImport(store, source, update: true)
        expectEqual(summary.updated, 1)
        let courses = try store.list().filter { $0.title == "Courses" }
        expectEqual(courses.map(\.text), ["Courses\nlait, oeufs"], "remplace, sans doublon")
        expectEqual(courses.first?.updatedAt, t0.addingTimeInterval(120))
    },
    Test("updateKeepsDraftEditedInBrouillon") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        let imported = try store.list().first { $0.title == "Courses" }!
        _ = try store.save(id: imported.id, text: "Courses\nlait\nmon ajout", now: t0.addingTimeInterval(7200))
        source.notesByFolder["f1"]![0] = note("n1", "Courses", modified: 120)
        source.bodiesById["n1"] = "<div>Courses</div><div>lait, oeufs</div>"
        let summary = try runImport(store, source, update: true)
        expectEqual(summary.updated, 1)
        let texts = Set(try store.list().filter { $0.title == "Courses" }.map(\.text))
        expectEqual(texts, ["Courses\nlait\nmon ajout", "Courses\nlait, oeufs"], "la version modifiee dans Brouillon est gardee")
        // Et la fois suivante, rien ne bouge.
        let third = try runImport(store, source, update: true)
        expectEqual(third.updated, 0)
        expectEqual(try store.list().filter { $0.title == "Courses" }.count, 2)
    },
    Test("deletedDraftCanBeImportedAgain") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        _ = try runImport(store, source)
        let courses = try store.list().first { $0.title == "Courses" }!
        try store.delete(courses.id)
        let summary = try runImport(store, source)
        expectEqual(summary.imported, 1)
    },
    Test("importIsSealedWhenProtected") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        try store.enableProtection(key: NoteCipher.newKey())
        _ = try runImport(store, sampleSource())
        let plain = try store.database.read { try String.fetchAll($0, sql: "SELECT text FROM draft") }
        expect(plain.allSatisfy(\.isEmpty), "rien en clair")
        expectEqual(try store.list().count, 3)
        store.lock()
        expectThrows { _ = try runImport(store, sampleSource()) }
    },
    Test("cancelKeepsWhatWasImported") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        let summary = try runImport(store, source, cancelAfter: 2)
        expect(summary.cancelled)
        expectEqual(summary.imported, 2)
        expect(summary.text.hasPrefix("Import annul\u{00E9} : 2 notes import\u{00E9}es"), summary.text)
        let rest = try runImport(store, source)
        expectEqual(rest.imported, 1)
        expectEqual(rest.unchanged, 2)
    },
    Test("cancelDuringBatchStopsWithoutFailures") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        let box = CancelBox()
        source.cancelDuringBodies = box
        let summary = try NotesImporter(store: store, source: source)
            .run(folderIds: ["f1"], updateModified: false, batchSize: 2, now: t0,
                 progress: { _, _ in }, isCancelled: { box.cancelled })
        expect(summary.cancelled)
        expectEqual(summary.failed, 0, "une annulation n'est pas un echec")
        expectEqual(summary.imported, 0)
        expectEqual(source.requestedBodies.count, 2, "pas de relecture note par note apres l'annulation")
    },
    Test("emptyNoteIsIgnored") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        source.notesByFolder["f2"] = [NotesNoteInfo(id: "n6", name: " ", folderId: "f2", createdAt: t0, modifiedAt: t0, isLocked: false)]
        source.bodiesById["n6"] = "<div><br></div>"
        let summary = try runImport(store, source, folders: ["f2"])
        expectEqual(summary.imported, 0)
        expectEqual(summary.empty, 1)
        expectEqual(summary.text, "Aucune note import\u{00E9}e, 1 vide ignor\u{00E9}e")
        expectEqual(try store.count(), 0)
    },
    Test("failingBodyIsCountedNotFatal") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let source = sampleSource()
        source.failingBodies = ["n2"]
        let summary = try runImport(store, source)
        expectEqual(summary.imported, 2)
        expectEqual(summary.failed, 1)
        expect(summary.text.hasSuffix("1 en \u{00E9}chec"), summary.text)
    },
    Test("progressCountsNotesToFetch") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let importer = NotesImporter(store: store, source: sampleSource())
        let log = ProgressLog()
        _ = try importer.run(folderIds: ["f1"], updateModified: false, batchSize: 2, now: t0,
                             progress: { log.append($0, $1) }, isCancelled: { false })
        expectEqual(log.steps.last.map { [$0.0, $0.1] }, [3, 3])
    },
])

let notesSourceTests: (String, [Test]) = ("NotesSource", [
    Test("decodesFolders") {
        let json = """
        [{"id":"x-coredata://A/ICFolder/p3","name":"Notes","account":"Sur mon Mac","count":94},
         {"id":"x-coredata://A/ICFolder/p2","name":"Recently Deleted","account":"Sur mon Mac","count":1},
         {"id":"x-coredata://A/ICFolder/p9","name":"Projets","account":"iCloud","count":0}]
        """
        let folders = try NotesScript.decodeFolders(Data(json.utf8))
        expectEqual(folders.map(\.name), ["Notes", "Projets"], "suppressions recentes ecartees")
        expectEqual(folders.first?.noteCount, 94)
        expectEqual(folders.first?.account, "Sur mon Mac")
    },
    Test("decodesNotes") {
        let json = """
        [{"id":"n1","name":"Courses","folderId":"f1","created":"2026-10-13T19:52:48.000Z","modified":"2026-10-13T19:52:52.000Z","locked":false},
         {"id":"n2","name":"Coffre","folderId":"f1","created":"2026-10-13T19:52:48Z","modified":"2026-10-13T19:52:48Z","locked":true}]
        """
        let notes = try NotesScript.decodeNotes(Data(json.utf8))
        expectEqual(notes.count, 2)
        expectEqual(notes[0].modifiedAt.timeIntervalSince(notes[0].createdAt), 4)
        expect(notes[1].isLocked)
    },
    Test("decodesBodies") {
        let bodies = try NotesScript.decodeBodies(Data("{\"n1\":\"<div>a</div>\"}".utf8))
        expectEqual(bodies, ["n1": "<div>a</div>"])
    },
    Test("mapsAutomationErrors") {
        expectEqual(NotesScript.error(status: 1, stderr: "execution error: Not authorized to send Apple events to Notes. (-1743)"), .notAuthorized)
        expectEqual(NotesScript.error(status: 1, stderr: "Erreur : L\u{2019}application n\u{2019}est pas ouverte. (-600)"), .notesUnavailable)
        expectEqual(NotesScript.error(status: 1, stderr: "autre chose (-2700)"), .failed("autre chose (-2700)"))
    },
    Test("summaryWording") {
        expectEqual(NotesImportSummary(imported: 42, locked: 3).text, "42 notes import\u{00E9}es, 3 verrouill\u{00E9}es ignor\u{00E9}es")
        expectEqual(NotesImportSummary(imported: 1).text, "1 note import\u{00E9}e")
        expectEqual(NotesImportSummary(imported: 0, updated: 2).text, "Aucune note import\u{00E9}e, 2 mises \u{00E0} jour")
    },
])
