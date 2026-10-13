import SwiftUI
import VialetKit
import BrouillonCore

struct MainWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            DraftsSidebar()
                .frame(width: 220)
                .background(Theme.sidebar)
            EditorPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AmbientBackground())
            InsightPanel()
                .frame(width: 290)
                .background(Theme.sidebar)
        }
    }
}

/// Colonne de gauche : les brouillons, du plus recent au plus ancien.
struct DraftsSidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Wordmark(Brand.displayName)
                Spacer()
                Button { state.newDraft() } label: { Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Nouveau brouillon (⌘N)")
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(state.drafts) { draft in
                        DraftRow(draft: draft, selected: draft.id == state.currentId)
                            .onTapGesture { state.open(draft) }
                            .contextMenu {
                                Button("Ouvrir") { state.open(draft) }
                                Button("Supprimer") { state.delete(draft) }
                            }
                    }
                    if state.drafts.isEmpty {
                        Text("Vos brouillons apparaîtront ici. Tout est sauvegardé en continu.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.inkFaint)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            UpdateBanner(updater: Updater.shared)
            ShortcutFooter(HotKeyController.shared.shortcut)
        }
    }
}

struct DraftRow: View {
    let draft: Draft
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.title.isEmpty ? "Sans titre" : draft.title)
                .font(Theme.ui(12.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text(draft.updatedAt.formatted(.relative(presentation: .named)))
                .font(Theme.ui(11)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Theme.accentSelection : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Le texte, dans une carte.
struct EditorPane: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            TextEditor(text: $state.text)
                .font(.system(size: state.isCodeLike ? 13 : 14.5))
                .fontDesign(state.isCodeLike ? .monospaced : .rounded)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(14)
                .overlay(alignment: .topLeading) {
                    if state.text.isEmpty {
                        Text("Collez ou tapez quelque chose. Brouillon reconnaît ce que c'est et propose quoi en faire.")
                            .font(Theme.ui(14.5)).foregroundStyle(Theme.inkFaint)
                            .padding(.horizontal, 19).padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.editor, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.editor, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(18)
        .onAppear { focused = true }
        .onChange(of: state.focusRequest) { _, _ in focused = true }
    }
}

/// Colonne de droite : ce qu'on a compris, et quoi en faire.
struct InsightPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let stats = state.stats
        VStack(alignment: .leading, spacing: 18) {
            section("Reconnu") {
                HStack(spacing: 8) {
                    Chip(state.text.isEmpty ? "Vide" : state.kind.label, icon: state.text.isEmpty ? "circle.dashed" : state.kind.icon, color: Theme.accent, filled: !state.text.isEmpty)
                    if state.kind == .color, let hex = ContentDetector.hexColor(state.text) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: hex)).frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line))
                    }
                }
                Text(statsLine(stats)).font(Theme.ui(11.5)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }

            section("Suggestions") {
                if state.suggestions.isEmpty {
                    Text("Rien à proposer sur un texte vide.").font(Theme.ui(12)).foregroundStyle(Theme.inkFaint)
                } else {
                    VStack(spacing: 5) {
                        ForEach(state.suggestions) { t in
                            Button { state.apply(t) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: t.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent).frame(width: 16)
                                    Text(t.label).font(Theme.ui(12.5, weight: .medium)).foregroundStyle(Theme.ink)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            section("Toutes les transformations") {
                Menu {
                    ForEach(TextTransform.Group.allCases, id: \.self) { group in
                        Section(group.label) {
                            ForEach(TextTransform.allCases.filter { $0.group == group }) { t in
                                Button(t.label) { state.apply(t) }
                            }
                        }
                    }
                } label: {
                    Label("Choisir…", systemImage: "wand.and.stars")
                }
                .menuStyle(.borderedButton)
                .disabled(state.text.isEmpty)
                Button("Annuler la dernière transformation") { state.undoTransform() }
                    .controlSize(.small).disabled(!state.canUndoTransform)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Copier tout") { state.copyAll() }.disabled(state.text.isEmpty)
                Button("Exporter…") { state.export() }.disabled(state.text.isEmpty)
            }
            .controlSize(.regular)
        }
        .padding(20)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            content()
        }
    }

    private func statsLine(_ s: TextStats) -> String {
        guard s.characters > 0 else { return "0 caractère" }
        var parts = ["\(s.characters) caractère\(s.characters > 1 ? "s" : "") (\(s.charactersWithoutSpaces) sans espaces)",
                     "\(s.words) mot\(s.words > 1 ? "s" : "")",
                     "\(s.lines) ligne\(s.lines > 1 ? "s" : "")"]
        if s.paragraphs > 1 { parts.append("\(s.paragraphs) paragraphes") }
        if s.readingMinutes > 0 { parts.append("\(s.readingMinutes) min de lecture") }
        return parts.joined(separator: " · ")
    }
}
