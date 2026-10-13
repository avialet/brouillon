import CryptoKit
import Foundation
import LocalAuthentication
import Security
import BrouillonCore

/// Ou vit la cle de chiffrement des brouillons.
protocol ProtectionKeyStore: Sendable {
    /// Une cle est-elle rangee ? Sans lire la cle (aucune demande du trousseau).
    func exists() -> Bool
    /// nil : aucune cle rangee.
    func load() throws -> SymmetricKey?
    /// Range une cle neuve ; ne remplace jamais une cle existante.
    func save(_ key: SymmetricKey) throws
}

enum KeyStoreError: Error, CustomStringConvertible {
    case denied
    case alreadyExists
    case status(OSStatus)

    var description: String {
        switch self {
        case .denied: "Acc\u{00E8}s au trousseau refus\u{00E9}."
        case .alreadyExists: "Une cl\u{00E9} existe d\u{00E9}j\u{00E0} dans le trousseau."
        case .status(let status):
            "Trousseau : \((SecCopyErrorMessageString(status, nil) as String?) ?? "erreur \(status)")"
        }
    }
}

/// Trousseau de session classique (pas le Data Protection Keychain : l'app est signee ad hoc, sans
/// keychain-access-groups). Service `fr.vialet.brouillon`, compte `notes-key`. La cle n'est jamais
/// supprimee par l'app : une autre base (BROUILLON_DB_PATH) peut s'en servir.
struct KeychainKeyStore: ProtectionKeyStore {
    var service = "fr.vialet.brouillon"
    var account = "notes-key"

    func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func load() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeyStoreError.status(status) }
            return try NoteCipher.key(from: data)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeyStoreError.denied
        default:
            throw KeyStoreError.status(status)
        }
    }

    func save(_ key: SymmetricKey) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Brouillon : cl\u{00E9} de chiffrement des brouillons",
            kSecValueData as String: NoteCipher.data(of: key),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw KeyStoreError.alreadyExists
        case errSecUserCanceled, errSecAuthFailed: throw KeyStoreError.denied
        default: throw KeyStoreError.status(status)
        }
    }
}

/// Cle en memoire : mode capture et essais (jamais le vrai trousseau).
final class MemoryKeyStore: ProtectionKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: SymmetricKey?

    func exists() -> Bool { lock.withLock { key != nil } }

    func load() throws -> SymmetricKey? { lock.withLock { key } }

    func save(_ key: SymmetricKey) throws {
        try lock.withLock {
            guard self.key == nil else { throw KeyStoreError.alreadyExists }
            self.key = key
        }
    }
}

/// Verification du proprietaire du Mac : Touch ID, ou mot de passe de la session.
protocol OwnerAuthenticator: Sendable {
    /// Le Mac sait-il verifier son proprietaire (mot de passe de session, Touch ID) ?
    var canAuthenticate: Bool { get }
    func authenticate(reason: String) async throws
}

struct LocalOwnerAuthenticator: OwnerAuthenticator {
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.passcodeNotSet)
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

/// Mode capture : aucune demande a l'ecran.
struct AcceptingAuthenticator: OwnerAuthenticator {
    var canAuthenticate: Bool { true }
    func authenticate(reason: String) async throws {}
}
