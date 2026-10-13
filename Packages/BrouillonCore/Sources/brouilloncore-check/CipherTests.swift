import CryptoKit
import Foundation
import BrouillonCore

let cipherTests: (String, [Test]) = ("Cipher", [
    Test("roundTrip") {
        let key = NoteCipher.newKey()
        for text in ["", "court", "\u{00C9}t\u{00E9} \u{1F600}\nligne 2", String(repeating: "long ", count: 5000)] {
            let sealed = try NoteCipher.seal(text, key: key, context: "draft/a/text")
            expectEqual(sealed.first, NoteCipher.version, "octet de version en tete")
            expectEqual(sealed.count, 1 + 12 + text.utf8.count + 16, "version + nonce + texte + tag")
            expectEqual(try NoteCipher.open(sealed, key: key, context: "draft/a/text"), text)
        }
    },
    Test("nonceIsRandom") {
        let key = NoteCipher.newKey()
        expect(try NoteCipher.seal("x", key: key, context: "c") != (try NoteCipher.seal("x", key: key, context: "c")))
    },
    Test("wrongKeyFails") {
        let sealed = try NoteCipher.seal("secret", key: NoteCipher.newKey(), context: "c")
        expectThrows { _ = try NoteCipher.open(sealed, key: NoteCipher.newKey(), context: "c") }
    },
    Test("wrongContextFails") {
        let key = NoteCipher.newKey()
        let sealed = try NoteCipher.seal("secret", key: key, context: "draft/a/text")
        expectThrows { _ = try NoteCipher.open(sealed, key: key, context: "draft/b/text") }
        expectThrows { _ = try NoteCipher.open(sealed, key: key, context: "draft/a/title") }
    },
    Test("tamperedDataFails") {
        let key = NoteCipher.newKey()
        let sealed = try NoteCipher.seal("secret", key: key, context: "c")
        for index in [1, 13, sealed.count - 1] {
            var altered = sealed
            altered[index] ^= 0x01
            expectThrows { _ = try NoteCipher.open(altered, key: key, context: "c") }
        }
        var badVersion = sealed
        badVersion[0] = 9
        expectThrows { _ = try NoteCipher.open(badVersion, key: key, context: "c") }
        expectThrows { _ = try NoteCipher.open(Data([1, 2, 3]), key: key, context: "c") }
        expectThrows { _ = try NoteCipher.open(Data(), key: key, context: "c") }
    },
    Test("keyDataRoundTrip") {
        let key = NoteCipher.newKey()
        let data = NoteCipher.data(of: key)
        expectEqual(data.count, 32)
        let back = try NoteCipher.key(from: data)
        let sealed = try NoteCipher.seal("x", key: key, context: "c")
        expectEqual(try NoteCipher.open(sealed, key: back, context: "c"), "x")
        expectThrows { _ = try NoteCipher.key(from: Data(count: 16)) }
    },
])
