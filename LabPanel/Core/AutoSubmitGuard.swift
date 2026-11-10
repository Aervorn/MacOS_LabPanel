import Foundation

/// Empêche de valider en boucle un formulaire de connexion : si le mot de passe enregistré est faux,
/// la page de connexion revient, et la renvoyer sans fin pourrait faire bloquer le compte.
/// Une validation automatique au plus par période ; au-delà, les champs sont seulement remplis.
struct AutoSubmitGuard: Sendable {
    var period: TimeInterval = 120
    private(set) var lastSubmit: Date?

    init(period: TimeInterval = 120) {
        self.period = period
    }

    /// Vrai si la validation est permise maintenant (et la note).
    mutating func allow(at now: Date = .now) -> Bool {
        if let lastSubmit, now.timeIntervalSince(lastSubmit) < period { return false }
        lastSubmit = now
        return true
    }
}
