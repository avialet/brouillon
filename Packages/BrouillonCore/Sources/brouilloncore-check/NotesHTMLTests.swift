import Foundation
import BrouillonCore

let notesHTMLTests: (String, [Test]) = ("NotesHTML", [
    Test("paragraphsAndBreaks") {
        let html = "<div><h1>Courses</h1></div>\n<div>lait<br></div>\n<div><br></div>\n<div>pain</div>"
        expectEqual(NotesHTML.text(from: html), "Courses\nlait\n\npain")
        expectEqual(NotesHTML.text(from: "<div>a<br>b</div><p>c</p>"), "a\nb\nc")
        expectEqual(NotesHTML.text(from: "<div>  plusieurs \n  espaces  </div>"), "plusieurs espaces")
        expectEqual(NotesHTML.text(from: ""), "")
    },
    Test("headAndStyleIgnored") {
        let html = "<html><head><title>x</title><style>div{color:red}</style></head><body><div>texte</div></body></html>"
        expectEqual(NotesHTML.text(from: html), "texte")
    },
    Test("bulletAndNumberedLists") {
        let html = "<div>Liste</div><ul><li>un</li><li>deux</li></ul><ol><li>premier</li><li>second</li></ol>"
        expectEqual(NotesHTML.text(from: html), "Liste\n- un\n- deux\n1. premier\n2. second")
        let nested = "<ul><li>a</li><ul><li>a1</li></ul><li>b</li></ul>"
        expectEqual(NotesHTML.text(from: nested), "- a\n  - a1\n- b")
    },
    Test("checkboxes") {
        let html = "<ul class=\"checklist\"><li class=\"checked\">fait</li><li>a faire</li></ul>"
        expectEqual(NotesHTML.text(from: html), "- [x] fait\n- [ ] a faire")
        let inputs = "<div><input type=\"checkbox\" checked> oui</div><div><input type=\"checkbox\"> non</div>"
        expectEqual(NotesHTML.text(from: inputs), "[x] oui\n[ ] non")
    },
    Test("boldItalicSimplified") {
        expectEqual(NotesHTML.text(from: "<div>un <b>mot</b> en <i>italique</i> et <u>souligne</u></div>"),
                    "un mot en italique et souligne")
        expectEqual(NotesHTML.text(from: "<div><span style=\"font-weight:bold\">titre</span></div>"), "titre")
    },
    Test("linksKeptAsText") {
        expectEqual(NotesHTML.text(from: "<div>voir <a href=\"https://vialet.app\">le site</a>.</div>"),
                    "voir le site (https://vialet.app).")
        expectEqual(NotesHTML.text(from: "<div><a href=\"https://vialet.app\">https://vialet.app</a></div>"),
                    "https://vialet.app")
        expectEqual(NotesHTML.text(from: "<div><a href=\"https://vialet.app/\">vialet.app</a></div>"),
                    "vialet.app (https://vialet.app/)")
    },
    Test("entities") {
        expectEqual(NotesHTML.text(from: "<div>&lt;b&gt; &amp; &quot;x&quot; &#39;y&#39; &eacute;t&#xE9; &#233;</div>"),
                    "<b> & \"x\" 'y' \u{00E9}t\u{00E9} \u{00E9}")
        expectEqual(NotesHTML.text(from: "<div>a&nbsp;&nbsp;b &hellip; &rsquo;</div>"), "a  b \u{2026} \u{2019}")
        expectEqual(NotesHTML.text(from: "<div>&inconnu; &#xZZ;</div>"), "&inconnu; &#xZZ;")
    },
    Test("tablesAsTabbedText") {
        let html = "<div>Tableau</div><table><tbody><tr><td><div>a</div></td><td><div>b</div></td></tr>"
            + "<tr><td>c</td><td><div>d<br></div></td></tr></tbody></table><div>fin</div>"
        expectEqual(NotesHTML.text(from: html), "Tableau\na\tb\nc\td\nfin")
    },
    Test("imagesAndAttachments") {
        let html = "<div>photo</div><div><img src=\"data:image/png;base64,AAAA\"></div><div>texte <img src=\"x\"> suite</div>"
            + "<div><object data=\"a.pdf\"></object></div>"
        expectEqual(NotesHTML.text(from: html), "photo\n[image]\ntexte [image] suite\n[pi\u{00E8}ce jointe]")
    },
    Test("notesTablesInsideObject") {
        let html = "<div>avant</div><object><table cellspacing=\"0\"><tbody><tr><td><div>a</div></td><td><div>b</div></td></tr></tbody></table></object><div>apres</div>"
        expectEqual(NotesHTML.text(from: html), "avant\na\tb\napres")
        expectEqual(NotesHTML.text(from: "<div>x</div><object></object>"), "x\n[pi\u{00E8}ce jointe]")
        expectEqual(NotesHTML.text(from: "<ul class=\"Apple-dash-list\"><li>tiret</li></ul>"), "- tiret")
    },
    Test("preservesPre") {
        expectEqual(NotesHTML.text(from: "<pre>a  b\n  c</pre><div>d</div>"), "a  b\n  c\nd")
    },
    Test("draftTextStartsWithNoteName") {
        expectEqual(NotesHTML.draftText(name: "Courses", html: "<div><h1>Courses</h1></div><div>lait</div>"), "Courses\nlait")
        expectEqual(NotesHTML.draftText(name: "Courses", html: "<div>lait</div>"), "Courses\n\nlait")
        expectEqual(NotesHTML.draftText(name: "Une note longue", html: "<div>Une note longue et sa suite</div>"),
                    "Une note longue et sa suite")
        expectEqual(NotesHTML.draftText(name: "Vide", html: ""), "Vide")
        expectEqual(NotesHTML.draftText(name: "  ", html: "<div>x</div>"), "x")
    },
])
