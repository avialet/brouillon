import AppKit
import CryptoKit
import LocalAuthentication
import Observation
import BrouillonCore

/// Verrou et chiffrement : etat, deverrouillage (Touch ID ou mot de passe du Mac), reverrouillage
/// (lancement, inactivite, veille, ecran verrouille, commande), activation et desactivation.
/// La cle n'est lue dans le trousseau qu'apres une verification LocalAuthentication reussie ;
/// elle ne vit en memoire (DraftStore) que deverrouille.
@MainActor
@Observable
final class ProtectionController {
    static let shared = ProtectionController(app: .shared)

    enum Failure: Error, CustomStringConvertible {
        case keyMissing

        var description: String {
            "La cl\u{00E9} de chiffrement est introuvable dans le trousseau : les brouillons chiffr\u{00E9}s ne peuvent pas \u{00EA}tre relus."
        }
    }

    private let app: AppState
    private var store: DraftStore { app.store }
    private(set) var keyStore: any ProtectionKeyStore = KeychainKeyStore()
    private(set) var authenticator: any OwnerAuthenticator = LocalOwnerAuthenticator()
    /// Faux en mode capture et en essai : rien n'est ecrit dans les preferences.
    private var persistsPreferences = true

    private(set) var state: ProtectionState
    private(set) var isLocked: Bool
    private(set) var isBusy = false
    private(set) var busyLabel = ""
    /// Derniere erreur a montrer (verrou, reglages, carte d'accueil).
    var message: String?
    /// Carte d'accueil des bases d'avant 0.3.0 : proposer la protection.
    private(set) var offersProtection = false
    /// Carte d'information apres l'activation d'office (nouvelle installation).
    private(set) var showsWelcome = false
    /// Derniere sauvegarde en clair ecrite a l'activation.
    private(set) var lastBackup: URL?

    var delayMinutes: Int {
        didSet {
            delayMinutes = LockPolicy(delayMinutes: delayMinutes).delayMinutes
            if persistsPreferences { UserDefaults.standard.set(delayMinutes, forKey: Brand.key("LockDelay")) }
        }
    }

    private var lastActivity = Date()
    private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var timer: Timer?

    private init(app: AppState) {
        self.app = app
        let state = (try? app.store.protectionState()) ?? .undecided
        self.state = state
        // Verrouille des le lancement : rien n'est affiche avant le deverrouillage.
        self.isLocked = state.locks(on: .launch)
        let stored = UserDefaults.standard.object(forKey: Brand.key("LockDelay")) as? Int
        self.delayMinutes = LockPolicy(delayMinutes: stored).delayMinutes
    }

    var policy: LockPolicy { LockPolicy(delayMinutes: delayMinutes) }

    var backups: [URL] { store.existingBackups() }

    #if DEBUG
    /// Mode capture et essai : cle en memoire, aucune demande d'authentification, ni trousseau ni preferences.
    func useEphemeralKeys() {
        keyStore = MemoryKeyStore()
        authenticator = AcceptingAuthenticator()
        persistsPreferences = false
    }

    /// Mode capture : affiche ou retire la carte d'accueil (base d'avant 0.3.0).
    func previewOffer(_ visible: Bool) { offersProtection = visible }
    #endif

    /// Au lancement : activation d'office d'une base neuve, carte d'accueil d'une ancienne, surveillance.
    func start() {
        guard !started else { return }
        started = true
        let count = (try? store.count()) ?? 0
        // Session sans mot de passe ni Touch ID, ou cle deja rangee : on propose au lieu d'activer.
        switch ProtectionOnboarding.decide(state: state, draftCount: count,
                                           canAuthenticate: authenticator.canAuthenticate,
                                           keyAlreadyStored: keyStore.exists()) {
        case .enableByDefault:
            enableByDefault()
        case .offer:
            offersProtection = true
        case .none:
            break
        }
        installMonitors()
    }

    private func enableByDefault() {
        do {
            let key = NoteCipher.newKey()
            try keyStore.save(key)
            try store.enableProtection(key: key)
            state = .on
            showsWelcome = persistsPreferences && !UserDefaults.standard.bool(forKey: Brand.key("ProtectionWelcomeSeen"))
        } catch {
            offersProtection = true
        }
    }

    // MARK: Verrou

    func lock(_ trigger: LockTrigger) {
        guard state.locks(on: trigger), !isLocked, !isBusy else { return }
        app.lockContent()
        store.lock()
        isLocked = true
        message = nil
    }

    func unlock() async {
        guard isLocked, !isBusy else { return }
        do {
            try await authenticator.authenticate(reason: "d\u{00E9}verrouiller vos brouillons")
            try await openStore()
            isLocked = false
            message = nil
            lastActivity = Date()
            app.didUnlock()
        } catch {
            message = Self.describe(error)
        }
    }

    /// Lit la cle (hors du thread principal : le trousseau peut afficher sa propre fenetre) et la
    /// verifie contre la base.
    private func openStore() async throws {
        let keyStore = keyStore
        let store = store
        try await Task.detached {
            guard let key = try keyStore.load() else { throw Failure.keyMissing }
            try store.unlock(with: key)
        }.value
    }

    func noteActivity() { lastActivity = Date() }

    private func checkIdle() {
        if state == .on, !isLocked, policy.isIdleExpired(lastActivity: lastActivity, now: Date()) {
            lock(.idle)
        }
    }

    private func installMonitors() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved, .leftMouseDragged]
        ) { event in
            MainActor.assumeIsolated { ProtectionController.shared.noteActivity() }
            return event
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ProtectionController.shared.lock(.sleep) }
        })
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ProtectionController.shared.lock(.screenLocked) }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { ProtectionController.shared.checkIdle() }
        }
    }

    // MARK: Activation

    /// Activer (apres confirmation) : authentification, cle (celle du trousseau ou une neuve),
    /// sauvegarde en clair, chiffrement verifie. En cas d'echec, rien n'est perdu.
    func enable() async {
        guard state != .on, !isBusy else { return }
        app.flushSave()
        isBusy = true
        busyLabel = "Chiffrement des brouillons\u{2026}"
        defer { isBusy = false }
        do {
            try await authenticator.authenticate(reason: "activer la protection de vos brouillons")
            let keyStore = keyStore
            let store = store
            let backup = try await Task.detached { () -> URL? in
                var key = try keyStore.load()
                if key == nil {
                    let fresh = NoteCipher.newKey()
                    try keyStore.save(fresh)
                    key = fresh
                }
                return try store.enableProtection(key: key!)
            }.value
            state = .on
            offersProtection = false
            lastBackup = backup
            lastActivity = Date()
            message = nil
        } catch {
            message = Self.describe(error)
        }
    }

    /// Desactiver (apres confirmation) : authentification, dechiffrement verifie. La cle reste dans
    /// le trousseau (une autre base peut s'en servir).
    func disable() async {
        guard state == .on, !isBusy else { return }
        let wasLocked = isLocked
        if !wasLocked { app.flushSave() }
        isBusy = true
        busyLabel = "D\u{00E9}chiffrement des brouillons\u{2026}"
        defer { isBusy = false }
        do {
            try await authenticator.authenticate(reason: "d\u{00E9}sactiver la protection de vos brouillons")
            if !store.isUnlocked { try await openStore() }
            let store = store
            try await Task.detached { try store.disableProtection() }.value
            state = .off
            isLocked = false
            message = nil
            if wasLocked { app.didUnlock() }
        } catch {
            message = Self.describe(error)
        }
    }

    /// « Pas maintenant » sur la carte d'accueil.
    func decline() {
        try? store.declineProtection()
        state = (try? store.protectionState()) ?? state
        offersProtection = false
    }

    func dismissWelcome() {
        showsWelcome = false
        if persistsPreferences { UserDefaults.standard.set(true, forKey: Brand.key("ProtectionWelcomeSeen")) }
    }

    func revealDatabaseFolder() {
        if let url = backups.last ?? store.database.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Message lisible ; nil pour une annulation (Touch ID refuse par l'utilisateur).
    static func describe(_ error: Error) -> String? {
        if let la = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(la.code) { return nil }
        switch error {
        case let e as DraftStoreError: return e.description
        case let e as KeyStoreError: return e.description
        case let e as Failure: return e.description
        case let e as NoteCipher.Failure: return e.description
        default: return error.localizedDescription
        }
    }
}
