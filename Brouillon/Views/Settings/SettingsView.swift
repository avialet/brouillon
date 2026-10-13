import SwiftUI
import VialetKit

struct SettingsView: View {
    private let hotKey = HotKeyController.shared
    @AppStorage("BrouillonMenuBar") private var menuBarVisible = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var appearance = AppearanceChoice.current(defaultsKey: Brand.key("Appearance"))

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Réglages").font(Theme.display(26)).foregroundStyle(Theme.ink)
                Text(".").font(Theme.display(26)).foregroundStyle(Brand.accent)
            }

            SettingsCard(icon: "keyboard", color: Theme.sea, title: "Raccourci global") {
                HStack(spacing: 12) {
                    ShortcutRecorder(controller: hotKey)
                    Button("Rétablir") { hotKey.shortcut = .default }
                        .buttonStyle(.plain)
                        .font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .opacity(hotKey.shortcut == .default ? 0 : 1)
                }
                Text(hotKey.isTaken
                     ? "Cette combinaison est déjà utilisée par une autre app. Choisissez-en une autre."
                     : "Depuis n'importe quelle app : ouvre \(Brand.displayName) avec le curseur dans le texte, ou le masque.")
                    .font(Theme.ui(12))
                    .foregroundStyle(hotKey.isTaken ? Theme.danger : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(icon: "power", color: Theme.pine, title: "Toujours là") {
                Toggle("Ouvrir \(Brand.displayName) à la connexion", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        launchAtLogin = LaunchAtLogin.set(on)
                        loginNeedsApproval = LaunchAtLogin.needsApproval
                    }
                if loginNeedsApproval {
                    HStack(spacing: 6) {
                        Text("À autoriser dans Réglages Système › Ouverture.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.coral)
                        Button("Ouvrir") { LaunchAtLogin.openSystemSettings() }
                            .buttonStyle(.link).font(Theme.ui(12, weight: .semibold))
                    }
                }
                Toggle("Icône dans la barre des menus", isOn: $menuBarVisible)
                Text("Fermer la fenêtre ne quitte pas \(Brand.displayName) : le raccourci reste actif. ⌘Q pour quitter.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(icon: "arrow.down.circle", color: Theme.coral, title: "Mises à jour") {
                UpdateCard(updater: Updater.shared)
            }

            SettingsCard(icon: "circle.lefthalf.filled", color: Theme.lavender, title: "Apparence") {
                Picker("", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appearance) { _, choice in choice.apply(defaultsKey: Brand.key("Appearance")) }
            }
        }
        .toggleStyle(.switch)
        .font(Theme.ui(13))
        .padding(26)
        .frame(width: 460)
        .background(Theme.paper)
        .fontDesign(.rounded)
    }
}
