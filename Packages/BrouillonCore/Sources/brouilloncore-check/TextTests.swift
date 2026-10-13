import Foundation
import BrouillonCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

let transformTests: (String, [Test]) = ("Transform", [
    Test("json") {
        expectEqual(TextTransform.prettyJSON.apply("{\"b\":1,\"a\":2}"), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        expectEqual(TextTransform.minifyJSON.apply("{\n  \"a\" : 2 }"), "{\"a\":2}")
        expect(TextTransform.prettyJSON.apply("pas du json") == nil)
    },
    Test("urlBase64Html") {
        expectEqual(TextTransform.urlDecode.apply("a%20b%C3%A9+c"), "a bé c")
        expectEqual(TextTransform.urlEncode.apply("a bé/c?d=1"), "a%20b%C3%A9%2Fc%3Fd%3D1")
        expectEqual(TextTransform.base64Encode.apply("Été"), "w4l0w6k=")
        expectEqual(TextTransform.base64Decode.apply("w4l0w6k="), "Été")
        expect(TextTransform.base64Decode.apply("pas du base64 !!") == nil)
        expectEqual(TextTransform.htmlDecode.apply("&eacute;t&eacute; &amp; &#233;&lt;b&gt;"), "été & é<b>")
    },
    Test("cases") {
        expectEqual(TextTransform.upper.apply("été à paris"), "ÉTÉ À PARIS")
        expectEqual(TextTransform.lower.apply("ÉTÉ À PARIS"), "été à paris")
        expectEqual(TextTransform.titleCase.apply("bonjour le monde"), "Bonjour Le Monde")
        expectEqual(TextTransform.sentenceCase.apply("BONJOUR. ça VA ? oui"), "Bonjour. Ça va ? Oui")
    },
    Test("whitespaceAndInvisible") {
        expectEqual(TextTransform.cleanWhitespace.apply("a  \t\n\n\n\n b \n\n"), "a\n\n b")
        expectEqual(TextTransform.removeInvisible.apply("a\u{200B}b\u{00A0}c\u{00AD}d\u{FEFF}"), "ab cd")
    },
    Test("lines") {
        expectEqual(TextTransform.sortLines.apply("pomme\nÉpinard\nabricot\nbanane"), "abricot\nbanane\nÉpinard\npomme")
        expectEqual(TextTransform.dedupeLines.apply("a\nb\na\n\nb"), "a\nb\n")
        expectEqual(TextTransform.reverseLines.apply("1\n2\n3"), "3\n2\n1")
        expectEqual(TextTransform.numberLines.apply("a\nb"), "1. a\n2. b")
    },
    Test("slugAndConversions") {
        expectEqual(TextTransform.slugify.apply("  Été à Paris, 2026 ! "), "ete-a-paris-2026")
        expectEqual(TextTransform.timestampToDate.apply("1790000000"), "2026-09-21T14:13:20Z")
        expectEqual(TextTransform.timestampToDate.apply("1790000000000"), "2026-09-21T14:13:20Z")
        expect(TextTransform.timestampToDate.apply("42") == nil, "trop court pour un timestamp")
        expectEqual(TextTransform.dateToTimestamp.apply("2026-09-21T14:13:20Z"), "1790000000")
        expectEqual(TextTransform.colorToRGB.apply("#2F6FEB"), "rgb(47, 111, 235)")
        expectEqual(TextTransform.colorToHex.apply("rgb(47, 111, 235)"), "#2F6FEB")
        expect(TextTransform.colorToHex.apply("bleu") == nil)
    },
    Test("everyTransformHasLabelAndGroup") {
        for t in TextTransform.allCases {
            expect(!t.label.isEmpty && !t.icon.isEmpty, t.rawValue)
        }
        expect(Set(TextTransform.allCases.map(\.group)).count >= 4)
    },
])

let statsTests: (String, [Test]) = ("Stats", [
    Test("countsCharactersWordsLinesParagraphs") {
        let s = TextStats.of("Bonjour le monde.\n\nDeuxième paragraphe ici, c'est tout.")
        expectEqual(s.characters, 55)
        expectEqual(s.charactersWithoutSpaces, 47)
        expectEqual(s.words, 8)
        expectEqual(s.lines, 3)
        expectEqual(s.paragraphs, 2)
        expectEqual(s.readingMinutes, 1)
        expectEqual(TextStats.of("").words, 0)
        expectEqual(TextStats.of("").lines, 0)
    },
])

let suggestionTests: (String, [Test]) = ("Suggestions", [
    Test("followTheDetectedKind") {
        expectEqual(Suggestions.transforms(for: "{\"a\":1}").prefix(2).map { $0 }, [.prettyJSON, .minifyJSON])
        expectEqual(Suggestions.transforms(for: "https://x.y/a%20b").first, .urlDecode)
        expectEqual(Suggestions.transforms(for: "https://x.y/a").first, .urlEncode)
        expectEqual(Suggestions.transforms(for: "1790000000").first, .timestampToDate)
        expectEqual(Suggestions.transforms(for: "#2F6FEB").first, .colorToRGB)
        expectEqual(Suggestions.transforms(for: "rgb(1, 2, 3)").first, .colorToHex)
        expectEqual(Suggestions.transforms(for: "2026-09-21T14:13:20Z").first, .dateToTimestamp)
        expectEqual(Suggestions.transforms(for: "w4l0w6k=").first, .base64Decode)
        expect(Suggestions.transforms(for: "Bonjour  le monde").contains(.cleanWhitespace))
        expect(Suggestions.transforms(for: "func a() {\n}").first == .cleanWhitespace)
        expect(Suggestions.transforms(for: "").isEmpty)
    },
])

let draftTests: (String, [Test]) = ("Drafts", [
    Test("saveUpdatesSameDraftAndListsByRecency") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let a = try store.save(id: nil, text: "Premier brouillon\nsuite", now: t0)!
        expectEqual(a.title, "Premier brouillon")
        let a2 = try store.save(id: a.id, text: "Premier brouillon modifié", now: t0.addingTimeInterval(10))!
        expectEqual(a2.id, a.id)
        let b = try store.save(id: nil, text: "Second", now: t0.addingTimeInterval(5))!
        expectEqual(try store.list().map(\.id), [a.id, b.id], "le plus recemment modifie en tete")
        expect(try store.save(id: nil, text: "   \n", now: t0) == nil, "vide non sauvegarde")
        try store.delete(a.id)
        expectEqual(try store.list().map(\.id), [b.id])
        expectEqual(try store.draft(b.id)?.text, "Second")
    },
    Test("titleSkipsTinyFirstLines") {
        expectEqual(Draft.title(for: "{\n  \"a\" : 1,\n  \"b\" : 2\n}"), "{ \"a\" : 1, \"b\" : 2 }")
        expectEqual(Draft.title(for: "- \nListe de courses\nlait"), "- Liste de courses lait")
        expectEqual(Draft.title(for: "Premier brouillon\nsuite"), "Premier brouillon")
    },
    Test("titleIsShort") {
        let store = DraftStore(database: try AppDatabase.inMemory())
        let d = try store.save(id: nil, text: "\n\n" + String(repeating: "mot ", count: 40), now: t0)!
        expect(d.title.count <= 61 && d.title.hasSuffix("…"), d.title)
    },
])
