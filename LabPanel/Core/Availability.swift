import Foundation

/// Disponibilité d'un service, vérifiée en arrière-plan (pastille de l'onglet).
enum Availability: Equatable, Sendable {
    /// Pas encore vérifié, ou adresse absente.
    case unknown
    /// Le serveur a répondu (quel que soit le code HTTP : une page de connexion compte).
    case online(milliseconds: Int)
    /// Le serveur répond, mais son certificat n'est pas reconnu et n'a pas été accepté.
    case untrustedCertificate
    /// Rien n'a répondu.
    case offline(code: Int)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    /// Classe le résultat d'une requête.
    static func from(error: Error?, elapsed: TimeInterval) -> Availability {
        guard let error else { return .online(milliseconds: Int((elapsed * 1000).rounded())) }
        let code = (error as NSError).code
        return NetworkError.isCertificateError(code: code) ? .untrustedCertificate : .offline(code: code)
    }
}

enum NetworkError {
    /// Erreurs `NSURLError…` dues au certificat du serveur.
    static func isCertificateError(code: Int) -> Bool {
        [
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed,
        ].contains(code)
    }

    /// Erreur que l'on peut ignorer : navigation remplacée par une autre, ou page confiée à un téléchargement.
    static func isBenign(domain: String, code: Int) -> Bool {
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled { return true }
        // WebKitErrorFrameLoadInterruptedByPolicyChange
        if domain == "WebKitErrorDomain" && code == 102 { return true }
        return false
    }
}
