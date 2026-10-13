import AppKit
import VialetKit
import BrouillonCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowSummoner.onFocus = { AppState.shared.requestFocus() }
        #if DEBUG
        // Mode capture : ni raccourci global, ni reseau.
        if runSnapshotIfRequested() { return }
        #endif
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
                AppState.shared.newDraft()
                if let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value {
                    AppState.shared.text = text
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
/// [-BrouillonSnapshotSize 1000x720]`, avec BROUILLON_DB_PATH vers une base jetable. Ecrit
/// `mainWindow`, `settings`, `about` et `transformation` (le JSON mis en forme ; `-sombre` en sombre)
/// dans le dossier, puis quitte.
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        let state = AppState.shared
        if UserDefaults.standard.bool(forKey: Brand.key("SnapshotSeed")) { seed(state) }
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
        let transformation = SnapshotScenario("transformation") {
            state.apply(.prettyJSON)
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        return SnapshotRunner.runIfRequested(prefix: Brand.name, scenarios: standard + [transformation])
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
        state.text = "{\"name\":\"Brouillon\",\"version\":\"0.2.0\",\"tags\":[\"mac\",\"local\"],\"author\":{\"name\":\"Camille\",\"city\":\"Lyon\"}}"
        state.flushSave()
    }
}
#endif
