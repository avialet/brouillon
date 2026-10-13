import AppKit
import Observation
import Synchronization
import SwiftUI
import VialetKit
import BrouillonCore

/// Etat de la feuille d'import : dossiers, progression, resume. Le travail (osascript, ecriture)
/// se fait hors du thread principal ; annulable entre deux lots.
@MainActor
@Observable
final class NotesImportModel {
    enum Phase: Equatable {
        case loading
        case choosing
        case importing
        case done(NotesImportSummary)
        case failed(String, notAuthorized: Bool)
    }

    let source: any NotesSource
    private(set) var phase: Phase = .loading
    private(set) var folders: [NotesFolder] = []
    var selected: Set<String> = []
    var updateModified = false
    private(set) var done = 0
    private(set) var total = 0
    @ObservationIgnored private let cancelFlag = CancelFlag()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(source: any NotesSource) {
        self.source = source
    }

    var selectedCount: Int { folders.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.noteCount } }

    func load() {
        phase = .loading
        let source = source
        task = Task {
            do {
                let folders = try await Task.detached { try source.folders() }.value
                self.folders = folders
                self.selected = Set(folders.filter { $0.noteCount > 0 }.map(\.id))
                self.phase = .choosing
            } catch {
                self.fail(error)
            }
        }
    }

    func start(store: DraftStore, onFinish: @escaping @MainActor () -> Void) {
        let ids = folders.filter { selected.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        phase = .importing
        done = 0
        total = 0
        cancelFlag.reset()
        let importer = NotesImporter(store: store, source: source)
        let update = updateModified
        let flag = cancelFlag
        task = Task {
            do {
                let summary = try await Task.detached {
                    try importer.run(folderIds: ids, updateModified: update,
                                     progress: { done, total in
                                         Task { @MainActor in self.progress(done, total) }
                                     },
                                     isCancelled: { flag.isSet })
                }.value
                self.phase = .done(summary)
            } catch {
                self.fail(error)
            }
            onFinish()
        }
    }

    private func progress(_ done: Int, _ total: Int) {
        guard phase == .importing else { return }
        self.done = done
        self.total = total
    }

    /// Annule entre deux lots et arrete la lecture osascript en cours.
    func cancel() {
        cancelFlag.set()
        source.cancel()
    }

    #if DEBUG
    /// Mode capture : etat fixe, sans osascript.
    func preview(folders: [NotesFolder], selected: Set<String>, phase: Phase, done: Int = 0, total: Int = 0) {
        self.folders = folders
        self.selected = selected
        self.phase = phase
        self.done = done
        self.total = total
    }
    #endif

    private func fail(_ error: Error) {
        if let notes = error as? NotesSourceError {
            phase = .failed(notes.description, notAuthorized: notes == .notAuthorized)
        } else if let store = error as? DraftStoreError {
            phase = .failed(store.description, notAuthorized: false)
        } else {
            phase = .failed(error.localizedDescription, notAuthorized: false)
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Drapeau d'annulation lu par l'import (autre thread).
final class CancelFlag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
    func reset() { value.withLock { $0 = false } }
}

/// Feuille sobre : choix des dossiers (avec leur nombre de notes), mise a jour optionnelle,
/// progression, resume.
struct NotesImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var model: NotesImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Importer depuis Notes").font(Theme.display(20)).foregroundStyle(Theme.ink)
                Text("Lecture seule : vos notes restent intactes dans l'app Notes.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
            }
            content
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.paper)
        .fontDesign(.rounded)
        .onAppear { if model.phase == .loading { model.load() } }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Lecture des dossiers de Notes\u{2026}").font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            footer { Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction) }
        case .choosing:
            choosing
        case .importing:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(model.done), total: Double(max(model.total, 1)))
                Text(model.total == 0 ? "Pr\u{00E9}paration\u{2026}" : "\(model.done) / \(model.total) notes")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft).monospacedDigit()
            }
            .padding(.vertical, 12)
            footer { Button("Annuler") { model.cancel() }.keyboardShortcut(.cancelAction) }
        case .done(let summary):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: summary.cancelled ? "pause.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.accent)
                Text(summary.text).font(Theme.ui(13.5, weight: .medium)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            footer { Button("Terminer") { dismiss() }.keyboardShortcut(.defaultAction) }
        case .failed(let message, let notAuthorized):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(Theme.coral)
                Text(message).font(Theme.ui(12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            footer {
                if notAuthorized {
                    Button("Ouvrir les R\u{00E9}glages Syst\u{00E8}me") { NotesImportModel.openAutomationSettings() }
                }
                Button("R\u{00E9}essayer") { model.load() }
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
    }

    private var choosing: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            if model.folders.isEmpty {
                Text("Aucun dossier dans l'app Notes.").font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.folders) { folder in
                            FolderRow(folder: folder, isOn: Binding(
                                get: { model.selected.contains(folder.id) },
                                set: { on in if on { model.selected.insert(folder.id) } else { model.selected.remove(folder.id) } }))
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 230)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            }
            Toggle(isOn: $model.updateModified) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mettre \u{00E0} jour les notes modifi\u{00E9}es depuis le dernier import").font(Theme.ui(12.5))
                    Text("Un brouillon modifi\u{00E9} dans Brouillon n'est jamais \u{00E9}cras\u{00E9} : la nouvelle version s'ajoute \u{00E0} c\u{00F4}t\u{00E9}.")
                        .font(Theme.ui(11)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Text("Les notes verrouill\u{00E9}es dans Notes sont ignor\u{00E9}es. Les images deviennent une mention [image], les pi\u{00E8}ces jointes [pi\u{00E8}ce jointe].")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            footer {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.selectedCount > 0 ? "Importer \(model.selectedCount) note\(model.selectedCount > 1 ? "s" : "")" : "Importer") {
                    model.start(store: state.store) { state.reload() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selected.isEmpty)
            }
        }
    }

    private func footer<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        HStack(spacing: 8) {
            Spacer()
            buttons()
        }
        .controlSize(.large)
    }
}

private struct FolderRow: View {
    let folder: NotesFolder
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name).font(Theme.ui(12.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(folder.account).font(Theme.ui(11)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(folder.noteCount) note\(folder.noteCount > 1 ? "s" : "")")
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.inkSoft).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .disabled(folder.noteCount == 0)
    }
}
