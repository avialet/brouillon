import SwiftUI
import VialetKit

/// Identite de l'app : le seul fichier Swift qui connait son nom.
enum Brand {
    static let name = "Brouillon"
    static let displayName = "Brouillon"
    static let accent = Color(hex: 0x8B78E6)
    /// Teintes de l'affiche (sites, plaques, DMG), calculees par scripts/teintes.py : texte `deep` sur `background`.
    static let background: UInt32 = 0x8B78E6
    static let deep: UInt32 = 0x261455
    static let pale: UInt32 = 0xF1F0FF
    static let night: UInt32 = 0x1A172E
    static let nightInk: UInt32 = 0xD5D2FD
    /// Pictogramme de la plaque : sous-ensemble SVG absolu (M L H V C Q Z), boite 0-100, trait non rempli.
    static let glyph = "M 18 70 C 28 34 40 34 50 54 C 60 74 72 74 82 40"
    static let updater = UpdaterConfiguration(repository: "avialet/brouillon", appName: name,
                                              bundleIdentifier: "fr.vialet.brouillon", displayName: displayName)

    /// Cles UserDefaults, prefixees par le nom de l'app.
    static func key(_ suffix: String) -> String { name + suffix }
}

extension Updater {
    static let shared = Updater(configuration: Brand.updater)
}

extension HotKeyController {
    /// ⌥⇧Espace par defaut : chaque app vialet.app a son propre raccourci (Pico garde ⇧⌘Espace).
    static let shared = HotKeyController(defaultsKey: Brand.key("HotKey"), logName: Brand.displayName,
                                         initial: .space([.option, .shift]))
}
