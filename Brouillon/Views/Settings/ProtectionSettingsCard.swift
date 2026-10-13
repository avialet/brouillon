import AppKit
import SwiftUI
import VialetKit
import BrouillonCore

/// Carte "Protection" des Reglages : activer (verrou et chiffrement), delai d'inactivite,
/// verrouiller maintenant, sauvegarde en clair d'avant le chiffrement.
struct ProtectionSettingsCard: View {
    @Environment(ProtectionController.self) private var protection
    @State private var confirmsEnable = false
    @State private var confirmsDisable = false

    var body: some View {
        @Bindable var protection = protection
        SettingsCard(icon: "lock.fill", color: Theme.accentDeep, title: "Protection") {
            Toggle("Verrouiller et chiffrer les brouillons", isOn: Binding(
                get: { protection.state == .on },
                set: { on in if on { confirmsEnable = true } else { confirmsDisable = true } }))
                .disabled(protection.isBusy)
            if protection.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(protection.busyLabel).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            HStack(spacing: 10) {
                Text("Verrouiller apr\u{00E8}s").font(Theme.ui(12.5))
                Picker("", selection: $protection.delayMinutes) {
                    ForEach(LockPolicy.delays, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .disabled(protection.state != .on)
            Button("Verrouiller maintenant") { protection.lock(.manual) }
                .disabled(protection.state != .on || protection.isLocked)
            Text(verbatim: "Touch ID ou le mot de passe du Mac d\u{00E9}verrouille \(Brand.displayName). Il se verrouille au lancement, apr\u{00E8}s ce d\u{00E9}lai d'inactivit\u{00E9}, \u{00E0} la mise en veille et au verrouillage de l'\u{00E9}cran. Titres et textes sont chiffr\u{00E9}s (AES-GCM) avec une cl\u{00E9} rang\u{00E9}e dans votre trousseau : si elle est perdue, les brouillons chiffr\u{00E9}s sont illisibles.")
                .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let message = protection.message {
                Text(message).font(Theme.ui(12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
            }
            if let backup = protection.backups.last {
                HStack(spacing: 6) {
                    Text(verbatim: "Copie en clair d'avant le chiffrement : \(backup.lastPathComponent). Supprimez-la quand tout va bien.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Afficher") { protection.revealDatabaseFolder() }
                        .buttonStyle(.link).font(Theme.ui(12, weight: .semibold))
                }
            }
        }
        .enableProtectionConfirmation(isPresented: $confirmsEnable)
        .alert("D\u{00E9}sactiver la protection ?", isPresented: $confirmsDisable) {
            Button("Annuler", role: .cancel) {}
            Button("D\u{00E9}sactiver", role: .destructive) { Task { await protection.disable() } }
        } message: {
            Text("Vos brouillons seront d\u{00E9}chiffr\u{00E9}s et enregistr\u{00E9}s en clair sur ce Mac, et \(Brand.displayName) ne se verrouillera plus.")
        }
    }
}
