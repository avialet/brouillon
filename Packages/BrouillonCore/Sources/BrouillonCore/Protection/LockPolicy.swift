import Foundation

/// Reverrouillage apres inactivite dans l'app : 1, 5 (defaut), 15 ou 60 minutes.
public struct LockPolicy: Equatable, Sendable {
    public static let delays = [1, 5, 15, 60]
    public static let defaultDelay = 5

    public let delayMinutes: Int

    /// Une valeur absente ou hors liste donne le delai par defaut.
    public init(delayMinutes: Int?) {
        if let delayMinutes, Self.delays.contains(delayMinutes) {
            self.delayMinutes = delayMinutes
        } else {
            self.delayMinutes = Self.defaultDelay
        }
    }

    public var interval: TimeInterval { TimeInterval(delayMinutes * 60) }

    public func deadline(after lastActivity: Date) -> Date { lastActivity.addingTimeInterval(interval) }

    public func isIdleExpired(lastActivity: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastActivity) >= interval
    }
}

/// Ce qui verrouille Brouillon.
public enum LockTrigger: CaseIterable, Sendable {
    case launch, idle, sleep, screenLocked, manual
}

extension ProtectionState {
    /// Seule une protection active verrouille, quel que soit le declencheur.
    public func locks(on trigger: LockTrigger) -> Bool { self == .on }
}

/// Premier lancement de 0.3.0 : protection activee d'office pour une base neuve, proposee
/// (carte d'accueil) a une base qui contient deja des brouillons.
public enum ProtectionOnboarding: Equatable, Sendable {
    case none
    case enableByDefault
    case offer

    public static func decide(state: ProtectionState, draftCount: Int) -> ProtectionOnboarding {
        guard state == .undecided else { return .none }
        return draftCount == 0 ? .enableByDefault : .offer
    }
}
