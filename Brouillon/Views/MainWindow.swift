import SwiftUI
import VialetKit

struct MainWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            AmbientBackground(accent: Brand.accent)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Brand.displayName).font(Theme.display(34)).foregroundStyle(Theme.ink)
                    Text(".").font(Theme.display(34)).foregroundStyle(Brand.accent)
                }
                Text("Tout commence ici. Remplacez cette vue par l'ecran principal de l'app.")
                    .font(Theme.ui(14)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 8) {
                    Chip("Local", icon: "lock", color: Theme.pine)
                    Chip("Sans compte", icon: "person.slash", color: Theme.sea)
                    Chip(HotKeyController.shared.shortcut.display, icon: "keyboard", color: Brand.accent)
                }
                Spacer()
                UpdateBanner(updater: Updater.shared)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
