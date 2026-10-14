import SwiftUI
import VialetKit

/// Reglages : les quatre cartes standard du kit (raccourci, toujours la, mises a jour, apparence),
/// puis la carte Protection de Brouillon.
struct SettingsView: View {
    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: HotKeyController.shared, updater: Updater.shared,
                       menuBar: MenuBarPresence.shared, dock: DockPresence.shared,
                       hotKeyHint: "Depuis n'importe quelle app : ouvre \(Brand.displayName) avec le curseur dans le texte, ou le masque.",
                       updateNote: HubPresence.updateNote) {
            ProtectionSettingsCard()
        }
    }
}
