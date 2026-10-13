import Foundation
import BrouillonCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

let lockTests: (String, [Test]) = ("Lock", [
    Test("delays") {
        expectEqual(LockPolicy.delays, [1, 5, 15, 60])
        expectEqual(LockPolicy(delayMinutes: nil).delayMinutes, 5)
        expectEqual(LockPolicy(delayMinutes: 15).delayMinutes, 15)
        expectEqual(LockPolicy(delayMinutes: 7).delayMinutes, 5, "valeur hors liste : defaut")
        expectEqual(LockPolicy(delayMinutes: 0).delayMinutes, 5)
    },
    Test("idleExpiry") {
        let policy = LockPolicy(delayMinutes: 5)
        expect(!policy.isIdleExpired(lastActivity: t0, now: t0.addingTimeInterval(299)))
        expect(policy.isIdleExpired(lastActivity: t0, now: t0.addingTimeInterval(300)))
        expect(!policy.isIdleExpired(lastActivity: t0, now: t0.addingTimeInterval(-10)), "horloge reculee : pas de verrou")
        expectEqual(policy.deadline(after: t0), t0.addingTimeInterval(300))
    },
    Test("triggersLockOnlyWhenProtected") {
        for trigger in LockTrigger.allCases {
            expect(ProtectionState.on.locks(on: trigger))
            expect(!ProtectionState.off.locks(on: trigger))
            expect(!ProtectionState.undecided.locks(on: trigger))
        }
    },
    Test("onboarding") {
        expectEqual(ProtectionOnboarding.decide(state: .undecided, draftCount: 0), .enableByDefault, "nouvelle installation")
        expectEqual(ProtectionOnboarding.decide(state: .undecided, draftCount: 3), .offer, "base 0.1 / 0.2 : carte d'accueil")
        expectEqual(ProtectionOnboarding.decide(state: .on, draftCount: 3), .none)
        expectEqual(ProtectionOnboarding.decide(state: .off, draftCount: 0), .none)
        expectEqual(ProtectionOnboarding.decide(state: .undecided, draftCount: 0, canAuthenticate: false), .offer,
                    "session sans mot de passe : jamais verrouillee d'office sans issue")
        expectEqual(ProtectionOnboarding.decide(state: .undecided, draftCount: 0, keyAlreadyStored: true), .offer,
                    "cle deja rangee : elle ne se lit qu'apres authentification")
        expectEqual(ProtectionOnboarding.decide(state: .on, draftCount: 0, canAuthenticate: false), .none)
    },
])

let searchTests: (String, [Test]) = ("Search", [
    Test("matchesTitleAndTextWithoutAccents") {
        let drafts = [
            Draft(id: "a", text: "\u{00C9}l\u{00E8}ve en retard\nvoir le proviseur", title: "\u{00C9}l\u{00E8}ve en retard", createdAt: t0, updatedAt: t0),
            Draft(id: "b", text: "Courses\nlait, \u{0153}ufs", title: "Courses", createdAt: t0, updatedAt: t0),
        ]
        let index = DraftSearchIndex(drafts)
        expectEqual(index.filter(drafts, query: "eleve").map(\.id), ["a"])
        expectEqual(index.filter(drafts, query: "PROVISEUR retard").map(\.id), ["a"], "tous les mots")
        expectEqual(index.filter(drafts, query: "lait proviseur").map(\.id), [])
        expectEqual(index.filter(drafts, query: "  ").map(\.id), ["a", "b"], "vide : tout")
    },
    Test("incrementalUpdate") {
        var drafts = [Draft(id: "a", text: "alpha", title: "alpha", createdAt: t0, updatedAt: t0)]
        var index = DraftSearchIndex(drafts)
        drafts[0].text = "beta"
        drafts[0].title = "beta"
        index.update(drafts[0])
        expectEqual(index.filter(drafts, query: "beta").map(\.id), ["a"])
        expectEqual(index.filter(drafts, query: "alpha").map(\.id), [])
        index.remove("a")
        expectEqual(index.filter(drafts, query: "beta").map(\.id), [])
    },
    Test("fiveThousandEncryptedNotes") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        try store.enableProtection(key: NoteCipher.newKey())
        let words = ["projet", "facture", "r\u{00E9}union", "id\u{00E9}e", "courses", "voyage", "code", "lettre"]
        let paragraph = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 12)
        for i in 0..<5000 {
            _ = try store.save(id: nil, text: "\(words[i % words.count]) \(i)\n\(paragraph)", now: t0.addingTimeInterval(Double(i)))
        }
        let start = Date()
        let drafts = try store.list()
        let decrypted = Date()
        let index = DraftSearchIndex(drafts)
        let indexed = Date()
        var hits = 0
        for query in ["reunion", "idee 42", "facture", "introuvable", "lorem elit"] {
            hits += index.filter(drafts, query: query).count
        }
        let searched = Date()
        expectEqual(drafts.count, 5000)
        expect(hits > 0)
        let ms = { (a: Date, b: Date) in Int(b.timeIntervalSince(a) * 1000) }
        print("     5000 notes chiffrees : dechiffrement \(ms(start, decrypted)) ms, index \(ms(decrypted, indexed)) ms, 5 recherches \(ms(indexed, searched)) ms")
        expect(searched.timeIntervalSince(start) < 5, "trop lent")
        expect(searched.timeIntervalSince(indexed) < 0.5, "recherche trop lente")
    },
])
