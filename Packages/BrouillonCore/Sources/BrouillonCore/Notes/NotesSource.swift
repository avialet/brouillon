import Foundation
import Synchronization

/// Un dossier de l'app Notes (sous-dossiers en chemin « Parent › Enfant »).
public struct NotesFolder: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var account: String
    public var noteCount: Int

    public init(id: String, name: String, account: String, noteCount: Int) {
        self.id = id
        self.name = name
        self.account = account
        self.noteCount = noteCount
    }

    /// Dossier systeme des notes supprimees : jamais propose.
    public var isRecentlyDeleted: Bool {
        ["Recently Deleted", "Suppressions r\u{00E9}centes", "R\u{00E9}cemment supprim\u{00E9}es"].contains(name)
    }
}

/// Une note, sans son corps (lu ensuite, seulement s'il faut l'importer).
public struct NotesNoteInfo: Sendable, Equatable {
    public var id: String
    public var name: String
    public var folderId: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// Protegee par mot de passe dans Notes : ignoree, jamais lue.
    public var isLocked: Bool

    public init(id: String, name: String, folderId: String, createdAt: Date, modifiedAt: Date, isLocked: Bool) {
        self.id = id
        self.name = name
        self.folderId = folderId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isLocked = isLocked
    }
}

public enum NotesSourceError: Error, Equatable, CustomStringConvertible {
    /// Autorisation Automatisation refusee (Reglages Systeme > Confidentialite > Automatisation).
    case notAuthorized
    /// L'app Notes n'a pas pu etre lancee ou n'a pas repondu.
    case notesUnavailable
    case failed(String)

    public var description: String {
        switch self {
        case .notAuthorized:
            "Brouillon n'a pas l'autorisation de lire l'app Notes. Autorisez-le dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Automatisation \u{203A} Brouillon \u{203A} Notes."
        case .notesUnavailable:
            "L'app Notes ne r\u{00E9}pond pas. Ouvrez-la puis r\u{00E9}essayez."
        case .failed(let message):
            "Lecture de Notes impossible : \(message)"
        }
    }
}

/// Lecture seule de l'app Notes.
public protocol NotesSource: Sendable {
    func folders() throws -> [NotesFolder]
    func notes(inFolders ids: [String]) throws -> [NotesNoteInfo]
    /// Corps HTML par identifiant ; une note illisible est absente du resultat.
    func bodies(of ids: [String]) throws -> [String: String]
    /// Arrete la lecture en cours (annulation de l'import).
    func cancel()
}

extension NotesSource {
    public func cancel() {}
}

/// Scripts JavaScript for Automation (osascript) : uniquement des lectures (`get`), jamais d'ecriture.
public enum NotesScript {
    static let folders = """
    function run() {
      var N = Application("Notes"), out = [], seen = {};
      function walk(f, account, prefix) {
        var id = f.id();
        if (seen[id]) return;
        seen[id] = true;
        var name = prefix ? prefix + " \\u203A " + f.name() : f.name();
        out.push({id: id, name: name, account: account, count: f.notes.length});
        f.folders().forEach(function (s) { walk(s, account, name); });
      }
      N.accounts().forEach(function (a) {
        var account = a.name(), all = a.folders();
        all.forEach(function (f) {
          var top = true;
          try { top = f.container().properties().pcls !== "folder"; } catch (e) {}
          if (top) walk(f, account, "");
        });
        all.forEach(function (f) { walk(f, account, ""); });
      });
      return JSON.stringify(out);
    }
    """

    static let notes = """
    function run(argv) {
      var N = Application("Notes"), out = [];
      argv.forEach(function (fid) {
        var notes = N.folders.byId(fid).notes;
        var ids = notes.id(), names = notes.name(), created = notes.creationDate(),
            modified = notes.modificationDate(), locked = notes.passwordProtected();
        for (var i = 0; i < ids.length; i++) {
          out.push({id: ids[i], name: names[i], folderId: fid, created: created[i].toISOString(),
                    modified: modified[i].toISOString(), locked: locked[i]});
        }
      });
      return JSON.stringify(out);
    }
    """

    /// Les images embarquees (data URL) sont retirees avant le transfert : elles deviennent « [image] ».
    static let bodies = """
    function run(argv) {
      var N = Application("Notes"), out = {};
      argv.forEach(function (id) {
        try {
          out[id] = N.notes.byId(id).body().replace(/src="data:[^"]*"/g, 'src=""');
        } catch (e) {}
      });
      return JSON.stringify(out);
    }
    """

    private struct FolderJSON: Decodable { let id: String; let name: String; let account: String; let count: Int }
    private struct NoteJSON: Decodable {
        let id: String; let name: String; let folderId: String; let created: String; let modified: String; let locked: Bool
    }

    public static func decodeFolders(_ data: Data) throws -> [NotesFolder] {
        try JSONDecoder().decode([FolderJSON].self, from: data)
            .map { NotesFolder(id: $0.id, name: $0.name, account: $0.account, noteCount: $0.count) }
            .filter { !$0.isRecentlyDeleted }
    }

    public static func decodeNotes(_ data: Data) throws -> [NotesNoteInfo] {
        try JSONDecoder().decode([NoteJSON].self, from: data).map {
            NotesNoteInfo(id: $0.id, name: $0.name, folderId: $0.folderId,
                          createdAt: try date($0.created), modifiedAt: try date($0.modified), isLocked: $0.locked)
        }
    }

    public static func decodeBodies(_ data: Data) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: data)
    }

    static func date(_ s: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return d }
        throw NotesSourceError.failed("date illisible \(s)")
    }

    /// Erreur d'osascript : -1743 refus d'Automatisation, -600 / -609 / -1712 Notes absente ou muette.
    public static func error(status: Int32, stderr: String) -> NotesSourceError {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.contains("-1743") { return .notAuthorized }
        if message.contains("(-600)") || message.contains("(-609)") || message.contains("(-1712)") { return .notesUnavailable }
        return .failed(message.isEmpty ? "osascript a \u{00E9}chou\u{00E9} (\(status))" : message)
    }
}

/// Source reelle : osascript en JavaScript for Automation, hors du thread principal.
/// L'autorisation Automatisation est demandee par macOS au premier appel. Chaque appel est borne
/// (`timeout`, 120 s par defaut) ; `cancel()` arrete le processus en cours.
public struct OsascriptNotesSource: NotesSource {
    public var timeout: TimeInterval
    private let running = RunningProcess()

    public init(timeout: TimeInterval = 120) {
        self.timeout = timeout
    }

    public func folders() throws -> [NotesFolder] {
        try NotesScript.decodeFolders(run(NotesScript.folders, arguments: []))
    }

    public func notes(inFolders ids: [String]) throws -> [NotesNoteInfo] {
        guard !ids.isEmpty else { return [] }
        return try NotesScript.decodeNotes(run(NotesScript.notes, arguments: ids))
    }

    public func bodies(of ids: [String]) throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        return try NotesScript.decodeBodies(run(NotesScript.bodies, arguments: ids))
    }

    public func cancel() { running.terminate() }

    private func run(_ script: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        running.set(process)
        defer { running.set(nil) }
        // Sortie et erreurs lues en parallele : un tuyau plein bloquerait osascript.
        let collected = Collected()
        let reads = DispatchGroup()
        for (pipe, isError) in [(output, false), (errors, true)] {
            let handle = pipe.fileHandleForReading
            reads.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                collected.store(handle.readDataToEndOfFile(), error: isError)
                reads.leave()
            }
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = reads.wait(timeout: .now() + 5)
            throw NotesSourceError.failed("l'app Notes n'a pas r\u{00E9}pondu en \(Int(timeout)) s")
        }
        _ = reads.wait(timeout: .now() + 5)
        if process.terminationReason == .uncaughtSignal {
            throw NotesSourceError.failed("lecture interrompue")
        }
        guard process.terminationStatus == 0 else {
            throw NotesScript.error(status: process.terminationStatus, stderr: String(decoding: collected.error, as: UTF8.self))
        }
        return collected.output
    }
}

/// Processus osascript en cours, pour l'arreter a l'annulation.
final class RunningProcess: Sendable {
    private let process = Mutex<Process?>(nil)
    func set(_ value: Process?) { process.withLock { $0 = value } }
    func terminate() { process.withLock { if let p = $0, p.isRunning { p.terminate() } } }
}

/// Sortie et erreurs d'osascript, remplies depuis deux files.
final class Collected: Sendable {
    private let data = Mutex<(output: Data, error: Data)>((Data(), Data()))
    func store(_ value: Data, error: Bool) {
        data.withLock { if error { $0.error = value } else { $0.output = value } }
    }
    var output: Data { data.withLock { $0.output } }
    var error: Data { data.withLock { $0.error } }
}
