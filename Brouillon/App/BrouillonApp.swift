import SwiftUI
import VialetKit
import BrouillonCore

@main
struct BrouillonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared
    @State private var protection = ProtectionController.shared
    @AppStorage(Brand.key("MenuBar")) private var menuBarVisible = true

    /// Teintes de l'app avant le premier rendu (et police Bricolage Grotesque des titres).
    init() { Theme.configure(Brand.palette) }

    var body: some Scene {
        Window(Brand.displayName, id: "main") {
            MainWindow()
                .environment(state)
                .environment(protection)
                .fontDesign(.rounded)
                .frame(minWidth: 900, minHeight: 520)
                .onAppear { AppearanceChoice.current(defaultsKey: Brand.key("Appearance")).apply(defaultsKey: Brand.key("Appearance")) }
                .captureOpenWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1080, height: 660)
        .commands {
            AboutCommands(identity: Brand.identity)
            UpdateCommands(updater: .shared)
            BrouillonCommands(state: state, protection: protection)
        }

        Settings {
            SettingsView().environment(protection)
        }

        MenuBarExtra(isInserted: $menuBarVisible) {
            MenuBarContent().environment(state).environment(protection)
        } label: {
            MenuBarIcon(glyph: Brand.glyph)
        }
    }
}

struct BrouillonCommands: Commands {
    let state: AppState
    let protection: ProtectionController

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Verrouiller \(Brand.displayName)") { protection.lock(.manual) }
                .keyboardShortcut("l", modifiers: [.control, .command])
                .disabled(protection.state != .on || protection.isLocked)
        }
        CommandGroup(replacing: .newItem) {
            Group {
                Button("Nouveau brouillon") { state.newDraft() }.keyboardShortcut("n")
                Button("Coller dans un nouveau brouillon") { state.newDraft(); state.pasteReplacing() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Importer depuis Notes\u{2026}") { state.beginImport() }
                Button("Exporter…") { state.export() }.keyboardShortcut("e").disabled(state.text.isEmpty)
            }
            .disabled(protection.isLocked)
        }
        CommandMenu("Transformer") {
            ForEach(state.suggestions) { t in
                Button(t.label) { state.apply(t) }
            }
            if !state.suggestions.isEmpty { Divider() }
            ForEach(TextTransform.Group.allCases, id: \.self) { group in
                Menu(group.label) {
                    ForEach(TextTransform.allCases.filter { $0.group == group }) { t in
                        Button(t.label) { state.apply(t) }
                    }
                }
            }
            Divider()
            Button("Annuler la dernière transformation") { state.undoTransform() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!state.canUndoTransform)
            Button("Copier tout") { state.copyAll() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(state.text.isEmpty)
        }
    }
}
