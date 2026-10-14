import VialetKit

/// Icone de barre des menus : masquee quand l'app Vialet est installee (reglage Automatique, Toujours, Jamais).
extension MenuBarPresence {
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Icone du Dock : seulement pendant qu'une fenetre est ouverte (reglage Toujours).
extension DockPresence {
    static let shared = DockPresence(app: Brand.identity)
}

/// Phrase des Reglages sur les echanges reseau : l'app peut tenir le menu rassembleur des apps vialet.app.
extension HubPresence {
    static let updateNote = "\u{00C9}changes r\u{00E9}seau de \(Brand.displayName) : la derni\u{00E8}re version publi\u{00E9}e sur GitHub et, quand son ic\u{00F4}ne rassemble vos apps vialet.app, celle de ces apps et le catalogue de vialet.app une fois par jour. Aucune donn\u{00E9}e n'est envoy\u{00E9}e."
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
