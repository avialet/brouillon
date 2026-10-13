import AppKit
import VialetKit
import BrouillonCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowSummoner.onFocus = { AppState.shared.requestFocus() }
        HotKeyController.shared.start { WindowSummoner.toggle() }
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { Updater.shared.checkAutomatically() }
        }
        #if DEBUG
        runSnapshotIfRequested()
        #endif
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
/// Mode de verification sans ecran : `Brouillon -BrouillonSnapshot /chemin/base -BrouillonSnapshotSeed 1`
/// (avec BROUILLON_DB_PATH vers une base jetable) cree des brouillons d'exemple, capture la fenetre, quitte.
extension AppDelegate {
    func runSnapshotIfRequested() {
        let defaults = UserDefaults.standard
        guard let base = defaults.string(forKey: "BrouillonSnapshot") else { return }
        Task { @MainActor in
            let state = AppState.shared
            if defaults.bool(forKey: "BrouillonSnapshotSeed") {
                let now = Date()
                _ = try? state.store.save(id: nil, text: "Relancer le fournisseur\n- devis signé ?\n- date de livraison\n- numéro de suivi", now: now.addingTimeInterval(-86400 * 2))
                _ = try? state.store.save(id: nil, text: "https://app.vialet.app/?utm_source=newsletter&utm_campaign=rentr%C3%A9e%202026", now: now.addingTimeInterval(-3600 * 5))
                state.reload()
                state.newDraft()
                state.text = "{\"name\":\"Brouillon\",\"version\":\"0.1.0\",\"tags\":[\"mac\",\"local\"],\"author\":{\"name\":\"Aurélien\",\"city\":\"Marseille\"}}"
                state.flushSave()
            }
            try? await Task.sleep(for: .seconds(2))
            if let window = WindowSummoner.mainWindow { try? WindowSnapshot.write(window, to: URL(fileURLWithPath: base + "-1.png")) }
            state.apply(.prettyJSON)
            try? await Task.sleep(for: .seconds(1))
            if let window = WindowSummoner.mainWindow { try? WindowSnapshot.write(window, to: URL(fileURLWithPath: base + "-2.png")) }
            print("kind: \(state.kind), suggestions: \(state.suggestions.map(\.rawValue)), drafts: \(state.drafts.count)")
            NSApp.terminate(nil)
        }
    }
}
#endif
