import AppKit
import SwiftUI
import Observation
import BrouillonCore
import VialetKit

/// Le brouillon courant, la liste, ce qu'on en comprend et ce qu'on peut en faire.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let database: AppDatabase
    let store: DraftStore

    private(set) var drafts: [Draft] = []
    private(set) var currentId: String?
    var text = "" {
        didSet { scheduleSave() }
    }
    /// Incremente pour redonner le focus a l'editeur.
    private(set) var focusRequest = 0
    private var undoStack: [String] = []
    private var saveTask: Task<Void, Never>?

    private init() {
        do {
            database = try AppDatabase.open()
        } catch {
            fatalError("Impossible d'ouvrir la base \(AppDatabase.defaultURL.path) : \(error)")
        }
        store = DraftStore(database: database)
        reload()
        if let last = drafts.first { open(last) }
    }

    // MARK: Analyse

    var kind: ContentKind {
        text.count > 50_000 ? .text : ContentDetector.detect(text)
    }

    var stats: TextStats { TextStats.of(text) }

    var suggestions: [TextTransform] { Array(Suggestions.transforms(for: text).prefix(6)) }

    var isCodeLike: Bool { kind == .json || kind == .code }

    var canUndoTransform: Bool { !undoStack.isEmpty }

    // MARK: Transformations

    /// Applique au texte entier ; renvoie false si la transformation ne s'applique pas.
    @discardableResult
    func apply(_ transform: TextTransform) -> Bool {
        guard let result = transform.apply(text), result != text else { NSSound.beep(); return false }
        undoStack.append(text)
        if undoStack.count > 50 { undoStack.removeFirst() }
        text = result
        return true
    }

    func undoTransform() {
        guard let previous = undoStack.popLast() else { return }
        text = previous
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func pasteReplacing() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { NSSound.beep(); return }
        undoStack.append(text)
        text = pasted
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .json ? .json : .plainText]
        panel.nameFieldStringValue = (Draft.title(for: text).isEmpty ? "brouillon" : Draft.title(for: text).replacingOccurrences(of: "…", with: "")) + (kind == .json ? ".json" : ".txt")
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Brouillons

    func reload() {
        drafts = (try? store.list()) ?? []
    }

    func newDraft() {
        flushSave()
        currentId = nil
        undoStack = []
        text = ""
        focusRequest += 1
    }

    func open(_ draft: Draft) {
        flushSave()
        currentId = draft.id
        undoStack = []
        text = draft.text
        focusRequest += 1
    }

    func delete(_ draft: Draft) {
        try? store.delete(draft.id)
        if draft.id == currentId { currentId = nil; undoStack = []; text = "" }
        reload()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// Sauvegarde immediate (vide : pas de brouillon cree).
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        if let saved = try? store.save(id: currentId, text: text) {
            currentId = saved.id
        }
        reload()
    }

    func requestFocus() { focusRequest += 1 }
}
