import SwiftUI
import VialetKit
import BrouillonCore

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(ProtectionController.self) private var protection

    var body: some View {
        // Verrouille : aucun titre, aucune action sur le contenu.
        if protection.isLocked {
            Button("D\u{00E9}verrouiller \(Brand.displayName)\u{2026}") {
                WindowSummoner.show(focus: true)
                Task { await protection.unlock() }
            }
        } else {
            content
        }
        Divider()
        Button("Ouvrir \(Brand.displayName)") { WindowSummoner.show(focus: true) }
        SettingsLink { Text("Réglages…") }
        Button("Quitter") { NSApp.terminate(nil) }
    }

    @ViewBuilder private var content: some View {
        Button("Nouveau brouillon") { state.newDraft(); WindowSummoner.show(focus: true) }
        Button("Coller dans un nouveau brouillon") { state.newDraft(); state.pasteReplacing(); WindowSummoner.show(focus: true) }
        if protection.state == .on {
            Button("Verrouiller \(Brand.displayName)") { protection.lock(.manual) }
        }
        if !state.drafts.isEmpty {
            Divider()
            ForEach(state.drafts.prefix(6)) { draft in
                Button(draft.title.isEmpty ? "Sans titre" : draft.title) { state.open(draft); WindowSummoner.show(focus: true) }
            }
        }
    }
}
