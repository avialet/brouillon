import VialetKit

/// Icone de barre des menus : masquee quand l'app Vialet est installee (reglage Automatique, Toujours, Jamais).
extension MenuBarPresence {
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Action rapide (`brouillon://new`), proposee par l'app Vialet dans son menu.
extension AppActions {
    static let shared: AppActions = {
        let actions = AppActions(Brand.identity, open: { WindowSummoner.show(focus: true) },
                                 checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
        actions.register(AppAction("new", title: "Nouveau brouillon", symbol: "square.and.pencil", shortcut: "⌘N")) {
            AppDelegate.newDraft(text: nil)
        }
        return actions
    }()
}
