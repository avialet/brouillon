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
        didSet { if !suppressSave { scheduleSave() } }
    }
    /// Recherche dans la colonne des brouillons (en memoire, sur les brouillons dechiffres).
    var searchQuery = ""
    private var searchIndex = DraftSearchIndex()
    /// Feuille "Importer depuis Notes" et son etat.
    var showingImport = false
    private(set) var importModel: NotesImportModel?
    /// Source de l'import : l'app Notes (une source factice en mode capture).
    @ObservationIgnored var importSource: any NotesSource = OsascriptNotesSource()
    /// Texte recu par `brouillon://new?text=` pendant le verrouillage : cree au deverrouillage.
    var pendingNewText: String?
    private var suppressSave = false
    /// Erreur de lecture de la base, affichee dans la colonne des brouillons.
    private(set) var loadError: String?
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

    /// Brouillons affiches : filtres par la recherche.
    var visibleDrafts: [Draft] { searchIndex.filter(drafts, query: searchQuery) }

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
        do {
            drafts = try store.list()
            loadError = nil
        } catch DraftStoreError.locked {
            // Verrouille : rien a afficher, l'ecran de verrou le dit.
            drafts = []
            loadError = nil
        } catch {
            drafts = []
            loadError = "Lecture des brouillons impossible : \(error)"
        }
        searchIndex = DraftSearchIndex(drafts)
    }

    /// Brouillons chiffres que la cle n'ouvre pas (affiches, jamais modifies).
    var unreadableCount: Int { drafts.filter(\.isUnreadable).count }

    func newDraft() {
        flushSave()
        currentId = nil
        undoStack = []
        text = ""
        focusRequest += 1
    }

    func open(_ draft: Draft) {
        // Illisible : ne s'ouvre pas, pour ne jamais etre ecrase.
        guard !draft.isUnreadable else { NSSound.beep(); return }
        flushSave()
        currentId = draft.id
        undoStack = []
        text = draft.text
        focusRequest += 1
    }

    func delete(_ draft: Draft) {
        try? store.delete(draft.id)
        if draft.id == currentId {
            saveTask?.cancel()
            currentId = nil
            undoStack = []
            suppressSave = true
            text = ""
            suppressSave = false
        }
        drafts.removeAll { $0.id == draft.id }
        searchIndex.remove(draft.id)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// Sauvegarde immediate (vide : pas de brouillon cree). Renvoie false si l'ecriture a echoue :
    /// le texte reste alors en memoire.
    @discardableResult
    func flushSave() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        do {
            if let saved = try store.save(id: currentId, text: text) {
                currentId = saved.id
                upsert(saved)
            }
            return true
        } catch {
            return false
        }
    }

    /// Met a jour la liste sans tout relire (ni tout dechiffrer).
    private func upsert(_ draft: Draft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            if drafts[index] == draft { return }
            drafts.remove(at: index)
        }
        let position = drafts.firstIndex(where: { $0.updatedAt <= draft.updatedAt }) ?? drafts.endIndex
        drafts.insert(draft, at: position)
        searchIndex.update(draft)
    }

    // MARK: Import

    func beginImport() {
        flushSave()
        importModel = NotesImportModel(source: importSource)
        showingImport = true
        WindowSummoner.show()
    }

    // MARK: Verrou

    /// Au verrouillage : sauvegarde, puis plus rien de dechiffre en memoire (le texte en cours n'est
    /// garde que si sa sauvegarde a echoue, pour ne pas le perdre).
    func lockContent() {
        let saved = flushSave()
        suppressSave = true
        if saved { text = "" }
        drafts = []
        searchIndex = DraftSearchIndex()
        searchQuery = ""
        undoStack = []
        showingImport = false
        suppressSave = false
    }

    /// Au deverrouillage : relit les brouillons et rouvre celui qui etait ouvert.
    func didUnlock() {
        reload()
        if !text.isEmpty {
            flushSave()
        } else if let id = currentId, let draft = drafts.first(where: { $0.id == id }) {
            open(draft)
        } else if let last = drafts.first {
            open(last)
        }
        if let pending = pendingNewText {
            pendingNewText = nil
            newDraft()
            text = pending
        }
    }

    func requestFocus() { focusRequest += 1 }
}
