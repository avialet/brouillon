import SwiftUI
import VialetKit
import BrouillonCore

@main
struct BrouillonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared
    @AppStorage("BrouillonMenuBar") private var menuBarVisible = true

    var body: some Scene {
        Window(Brand.displayName, id: "main") {
            MainWindow()
                .environment(state)
                .fontDesign(.rounded)
                .frame(minWidth: 900, minHeight: 520)
                .onAppear { AppearanceChoice.current(defaultsKey: Brand.key("Appearance")).apply(defaultsKey: Brand.key("Appearance")) }
                .captureOpenWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1080, height: 660)
        .commands { BrouillonCommands(state: state) }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $menuBarVisible) {
            MenuBarContent().environment(state)
        } label: {
            Image(systemName: "note.text")
        }
    }
}

struct BrouillonCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouveau brouillon") { state.newDraft() }.keyboardShortcut("n")
            Button("Coller dans un nouveau brouillon") { state.newDraft(); state.pasteReplacing() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Exporter…") { state.export() }.keyboardShortcut("e").disabled(state.text.isEmpty)
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
