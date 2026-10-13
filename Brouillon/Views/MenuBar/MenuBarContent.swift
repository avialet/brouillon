import SwiftUI
import VialetKit
import BrouillonCore

struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button("Nouveau brouillon") { state.newDraft(); WindowSummoner.show(focus: true) }
        Button("Coller dans un nouveau brouillon") { state.newDraft(); state.pasteReplacing(); WindowSummoner.show(focus: true) }
        if !state.drafts.isEmpty {
            Divider()
            ForEach(state.drafts.prefix(6)) { draft in
                Button(draft.title.isEmpty ? "Sans titre" : draft.title) { state.open(draft); WindowSummoner.show(focus: true) }
            }
        }
        Divider()
        Button("Ouvrir \(Brand.displayName)") { WindowSummoner.show(focus: true) }
        SettingsLink { Text("Réglages…") }
        Button("Quitter") { NSApp.terminate(nil) }
    }
}
