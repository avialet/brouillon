import SwiftUI
import VialetKit

/// Reglages : les quatre cartes standard du kit (raccourci, toujours la, mises a jour, apparence).
struct SettingsView: View {
    @AppStorage(Brand.key("MenuBar")) private var menuBarVisible = true

    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: HotKeyController.shared, updater: Updater.shared,
                       menuBarVisible: $menuBarVisible,
                       hotKeyHint: "Depuis n'importe quelle app : ouvre \(Brand.displayName) avec le curseur dans le texte, ou le masque.")
    }
}
