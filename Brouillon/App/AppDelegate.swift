import AppKit
import VialetKit
import BrouillonCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowSummoner.onFocus = { AppState.shared.requestFocus() }
        #if DEBUG
        // Mode capture et essai d'import : ni raccourci global, ni reseau, ni trousseau.
        if runNotesTrialIfRequested() { return }
        if runSnapshotIfRequested() { return }
        #endif
        ProtectionController.shared.start()
        HotKeyController.shared.start { WindowSummoner.toggle() }
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { Updater.shared.checkAutomatically() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.flushSave()
    }

    /// Liens `brouillon://` : ouvre la fenetre, `brouillon://new?text=...` cree un brouillon preremplit.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "brouillon" {
            if url.host == "new" {
                let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value
                if ProtectionController.shared.isLocked {
                    // Cree au deverrouillage.
                    AppState.shared.pendingNewText = text ?? ""
                } else {
                    AppState.shared.newDraft()
                    if let text { AppState.shared.text = text }
                }
            }
        }
        WindowSummoner.show(focus: true)
    }

    /// L'app reste disponible (raccourci global, barre des menus) fenetre fermee.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSummoner.show() }
        return true
    }
}

#if DEBUG
/// Mode capture sans ecran (voir SnapshotRunner) : `Brouillon -BrouillonSnapshot <dossier>
/// [-BrouillonSnapshotSeed 1] [-BrouillonSnapshotAppearance dark] [-BrouillonSnapshotOnly a,b]
/// [-BrouillonSnapshotSize 1000x720]`, avec BROUILLON_DB_PATH vers une base jetable (neuve : la
/// protection s'y active d'office, cle en memoire, jamais le trousseau). Ecrit `mainWindow`, `settings`
/// (avec la carte Protection), `about`, `transformation` (le JSON mis en forme), `importNotes`
/// (choix des dossiers, source factice), `importNotesResume`, `protectionOffer` (carte d'accueil d'une
/// base d'avant 0.3.0) et `lock` (`-sombre` en sombre) dans le
/// dossier, puis quitte.
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        let state = AppState.shared
        let protection = ProtectionController.shared
        protection.useEphemeralKeys()
        protection.start()
        state.importSource = SnapshotNotesSource()
        if UserDefaults.standard.bool(forKey: Brand.key("SnapshotSeed")) { seed(state) }
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
        let transformation = SnapshotScenario("transformation") {
            state.apply(.prettyJSON)
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let importNotes = SnapshotScenario("importNotes") {
            state.beginImport()
            try await Task.sleep(for: .seconds(1.5))
            return WindowSummoner.mainWindow?.attachedSheet
        }
        let importSummary = SnapshotScenario("importNotesResume") {
            if !state.showingImport { state.beginImport() }
            try await Task.sleep(for: .seconds(1))
            state.importModel?.preview(folders: [], selected: [], phase: .done(NotesImportSummary(imported: 42, locked: 3)))
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow?.attachedSheet
        }
        let offer = SnapshotScenario("protectionOffer") {
            state.showingImport = false
            protection.previewOffer(true)
            try await Task.sleep(for: .seconds(1.5))
            return WindowSummoner.mainWindow
        }
        let lock = SnapshotScenario("lock") {
            state.showingImport = false
            protection.previewOffer(false)
            try await Task.sleep(for: .seconds(1))
            protection.lock(.manual)
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        return SnapshotRunner.runIfRequested(prefix: Brand.name,
                                             scenarios: standard + [transformation, importNotes, importSummary, offer, lock])
    }

    /// Essai reel de l'import (lecture seule de l'app Notes) : `Brouillon -BrouillonNotesTrial 1`, avec
    /// BROUILLON_DB_PATH obligatoire (jamais la vraie base). Importe tous les dossiers deux fois (la
    /// seconde ne doit rien dupliquer), base chiffree avec une cle en memoire, imprime les resumes, quitte.
    func runNotesTrialIfRequested() -> Bool {
        guard UserDefaults.standard.bool(forKey: Brand.key("NotesTrial")) else { return false }
        let protection = ProtectionController.shared
        protection.useEphemeralKeys()
        protection.start()
        let store = AppState.shared.store
        print("essai : base \(AppDatabase.defaultURL.path), protection \(protection.state.rawValue)")
        Task.detached {
            do {
                let source = OsascriptNotesSource()
                var start = Date()
                let folders = try source.folders()
                print("essai : \(folders.count) dossiers, \(folders.reduce(0) { $0 + $1.noteCount }) notes (\(Int(Date().timeIntervalSince(start) * 1000)) ms)")
                let importer = NotesImporter(store: store, source: source)
                for pass in 1...2 {
                    start = Date()
                    let summary = try importer.run(folderIds: folders.map(\.id), updateModified: false,
                                                   progress: { _, _ in }, isCancelled: { false })
                    print("essai : passe \(pass) : \(summary.text) (\(Int(Date().timeIntervalSince(start) * 1000)) ms)")
                }
                let drafts = try store.list()
                let sealed = try store.database.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM draft WHERE textSealed IS NOT NULL AND text = ''") ?? 0
                }
                print("essai : \(drafts.count) brouillons, \(sealed) chiffr\u{00E9}s, \(drafts.filter { $0.text.contains("[image]") }.count) avec [image], \(drafts.filter { $0.text.contains("\t") }.count) avec un tableau")
                // Restes de balises ou d'entites dans le texte converti (seulement des nombres, pas de contenu).
                let leftovers = drafts.filter { $0.text.range(of: "<[a-zA-Z/][^>]*>|&[a-zA-Z]+;|&#[0-9a-fA-F]+;", options: .regularExpression) != nil }
                print("essai : \(leftovers.count) brouillons avec un reste de balise ou d'entit\u{00E9}")
                exit(0)
            } catch {
                print("essai : \(error)")
                exit(1)
            }
        }
        return true
    }

    /// Exemples neutres pour les captures, sans donnee personnelle (chaines en echappements ASCII).
    private func seed(_ state: AppState) {
        let now = Date()
        let samples: [(String, TimeInterval)] = [
            ("Relancer le fournisseur\n- devis sign\u{00E9} ?\n- date de livraison\n- num\u{00E9}ro de suivi", -86400 * 2),
            ("https://vialet.app/?utm_source=newsletter&utm_campaign=rentr%C3%A9e%202026", -3600 * 5),
        ]
        for (text, age) in samples { _ = try? state.store.save(id: nil, text: text, now: now.addingTimeInterval(age)) }
        state.reload()
        state.newDraft()
        state.text = "{\"name\":\"Brouillon\",\"version\":\"0.3.0\",\"tags\":[\"mac\",\"local\"],\"author\":{\"name\":\"Camille\",\"city\":\"Lyon\"}}"
        state.flushSave()
    }
}
#endif

#if DEBUG
/// Source Notes factice du mode capture : dossiers et notes neutres, aucun appel a l'app Notes.
struct SnapshotNotesSource: NotesSource {
    private let sample: [NotesFolder] = [
        NotesFolder(id: "s1", name: "Notes", account: "iCloud", noteCount: 38),
        NotesFolder(id: "s2", name: "Recettes", account: "iCloud", noteCount: 12),
        NotesFolder(id: "s3", name: "Voyages \u{203A} Lisbonne", account: "iCloud", noteCount: 7),
        NotesFolder(id: "s4", name: "Notes", account: "Sur mon Mac", noteCount: 3),
    ]

    func folders() throws -> [NotesFolder] { sample }
    func notes(inFolders ids: [String]) throws -> [NotesNoteInfo] { [] }
    func bodies(of ids: [String]) throws -> [String: String] { [:] }
}
#endif
