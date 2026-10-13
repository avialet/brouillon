import SwiftUI
import VialetKit
import BrouillonCore

/// Plein ecran dans la fenetre quand Brouillon est verrouille : la plaque, une phrase, un bouton.
/// Aucun contenu (titres, texte) n'est affiche.
struct LockView: View {
    @Environment(ProtectionController.self) private var protection

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: GlyphImage.plate(Brand.palette, glyph: Brand.glyph, pixels: 192, strokeDeep: Brand.strokeDeep))
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: Theme.Shadow.panel.color, radius: Theme.Shadow.panel.radius, y: Theme.Shadow.panel.y)
            VStack(spacing: 6) {
                Text("\(Brand.displayName) est verrouill\u{00E9}")
                    .font(Theme.display(26)).foregroundStyle(Theme.ink)
                Text("Touch ID ou le mot de passe de votre Mac pour retrouver vos brouillons.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSoft)
            }
            Button {
                Task { await protection.unlock() }
            } label: {
                Label("D\u{00E9}verrouiller", systemImage: "touchid")
                    .font(Theme.ui(14, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .foregroundStyle(Theme.accentPrimaryButtonForeground)
                    .background(Capsule().fill(Theme.accentPrimaryButtonBackground))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            if let message = protection.message {
                Text(message)
                    .font(Theme.ui(12)).foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Afficher le dossier de la base") { protection.revealDatabaseFolder() }
                    .buttonStyle(.link).font(Theme.ui(12))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmbientBackground())
    }
}

/// Pendant le chiffrement ou le dechiffrement.
struct BusyOverlay: View {
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(label).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
    }
}

/// Carte d'accueil au-dessus de l'editeur : proposer la protection (base d'avant 0.3.0) ou
/// expliquer qu'elle est active (nouvelle installation).
struct ProtectionBanner: View {
    @Environment(ProtectionController.self) private var protection
    @State private var confirmsEnable = false

    var body: some View {
        if protection.offersProtection {
            card(icon: "lock.shield", title: "Prot\u{00E9}ger vos brouillons ?",
                 text: "Verrou par Touch ID ou mot de passe du Mac, et brouillons chiffr\u{00E9}s sur le disque.") {
                Button("Pas maintenant") { protection.decline() }
                Button("Activer\u{2026}") { confirmsEnable = true }.buttonStyle(.borderedProminent)
            }
            .enableProtectionConfirmation(isPresented: $confirmsEnable)
        } else if protection.showsWelcome {
            card(icon: "lock.shield.fill", title: "Vos brouillons sont chiffr\u{00E9}s",
                 text: "Brouillon se verrouille apr\u{00E8}s \(protection.delayMinutes) min d'inactivit\u{00E9}, \u{00E0} la mise en veille et au verrouillage de l'\u{00E9}cran. La cl\u{00E9} est dans votre trousseau : sans elle, les brouillons chiffr\u{00E9}s sont illisibles.") {
                Button("Compris") { protection.dismissWelcome() }
            }
        }
    }

    private func card<Buttons: View>(icon: String, title: String, text: String,
                                     @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.ui(13.5, weight: .bold)).foregroundStyle(Theme.ink)
                Text(text).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let message = protection.message {
                    Text(message).font(Theme.ui(12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { buttons() }.controlSize(.small)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 18).padding(.top, 18)
    }
}

extension View {
    /// Confirmation avant d'activer : ce que fait la protection, et qu'une cle perdue rend les
    /// brouillons chiffres illisibles.
    func enableProtectionConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(EnableProtectionConfirmation(isPresented: isPresented))
    }
}

private struct EnableProtectionConfirmation: ViewModifier {
    @Environment(ProtectionController.self) private var protection
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("Activer la protection ?", isPresented: $isPresented) {
            Button("Annuler", role: .cancel) {}
            Button("Activer") { Task { await protection.enable() } }
        } message: {
            Text("Brouillon chiffre vos brouillons sur le disque et se verrouille (Touch ID ou mot de passe du Mac). La cl\u{00E9} est rang\u{00E9}e dans votre trousseau de session : si elle est perdue, les brouillons chiffr\u{00E9}s sont illisibles, sans r\u{00E9}cup\u{00E9}ration possible. Une copie en clair de la base actuelle est gard\u{00E9}e \u{00E0} c\u{00F4}t\u{00E9} (brouillon.sqlite.avant-chiffrement).")
        }
    }
}
