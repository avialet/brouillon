import CryptoKit
import Foundation

/// Chiffrement des champs d'un brouillon : AES-GCM 256 bits (CryptoKit).
/// Format versionne : 1 octet de version, nonce (12 octets), texte chiffre, tag (16 octets).
/// Le contexte (ex. `draft/<id>/text`) est authentifie sans etre stocke : un champ copie
/// d'une ligne ou d'une colonne a une autre ne se dechiffre pas.
public enum NoteCipher {
    public static let version: UInt8 = 1

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case unsupportedVersion(UInt8)
        case truncated
        case authentication
        case invalidKey

        public var description: String {
            switch self {
            case .unsupportedVersion(let v): "format de chiffrement inconnu (\(v))"
            case .truncated: "donn\u{00E9}es chiffr\u{00E9}es tronqu\u{00E9}es"
            case .authentication: "cl\u{00E9} incorrecte ou donn\u{00E9}es alt\u{00E9}r\u{00E9}es"
            case .invalidKey: "cl\u{00E9} invalide"
            }
        }
    }

    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func data(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    public static func key(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw Failure.invalidKey }
        return SymmetricKey(data: data)
    }

    public static func seal(_ text: String, key: SymmetricKey, context: String) throws -> Data {
        let box = try AES.GCM.seal(Data(text.utf8), using: key, authenticating: Data(context.utf8))
        guard let combined = box.combined else { throw Failure.truncated }
        return Data([version]) + combined
    }

    public static func open(_ data: Data, key: SymmetricKey, context: String) throws -> String {
        guard let first = data.first else { throw Failure.truncated }
        guard first == version else { throw Failure.unsupportedVersion(first) }
        guard data.count >= 1 + 12 + 16 else { throw Failure.truncated }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst())
            let plain = try AES.GCM.open(box, using: key, authenticating: Data(context.utf8))
            guard let text = String(data: plain, encoding: .utf8) else { throw Failure.authentication }
            return text
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.authentication
        }
    }
}
