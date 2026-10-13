import SwiftUI
import VialetKit

/// Identite de l'app : le seul fichier Swift qui connait son nom.
enum Brand {
    static let name = "Brouillon"
    static let displayName = "Brouillon"
    static let accent = Color(hex: 0x8B78E6)
    static let updater = UpdaterConfiguration(repository: "avialet/brouillon", appName: name,
                                              bundleIdentifier: "fr.vialet.brouillon", displayName: displayName)

    /// Cles UserDefaults, prefixees par le nom de l'app.
    static func key(_ suffix: String) -> String { name + suffix }
}

extension Updater {
    static let shared = Updater(configuration: Brand.updater)
}

extension HotKeyController {
    static let shared = HotKeyController(defaultsKey: Brand.key("HotKey"), logName: Brand.displayName)
}
