import Foundation
import Security

/// Identifiants des services, rangés dans le trousseau de session de macOS
/// (visibles dans l'app Trousseaux d'accès sous « LabPanel – <service> »).
///
/// Le nom d'utilisateur est gardé dans un attribut de l'élément : on peut l'afficher dans les Réglages
/// sans débloquer le mot de passe. Le mot de passe n'est lu qu'au moment de remplir une page.
enum CredentialStore {
    struct Credential: Equatable, Sendable {
        var username: String
        var password: String
    }

    static let service = "io.github.aervorn.labpanel.login"

    enum StoreError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                return String(localized: "Trousseau : \(message)")
            }
        }
    }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    /// Nom d'utilisateur enregistré, sans lire le mot de passe (pas de demande d'autorisation).
    /// `nil` si rien n'est enregistré pour ce service.
    static func username(for id: UUID) -> String? {
        var query = baseQuery(id)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any]
        else { return nil }
        let data = attributes[kSecAttrGeneric as String] as? Data
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Identifiant complet. macOS peut demander l'autorisation la première fois
    /// (et après chaque compilation d'un build de développement, dont la signature change).
    static func read(_ id: UUID) -> Credential? {
        var query = baseQuery(id)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let passwordData = item[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8)
        else { return nil }
        let username = (item[kSecAttrGeneric as String] as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return Credential(username: username, password: password)
    }

    /// Enregistre ou remplace l'identifiant d'un service. Un mot de passe `nil` garde celui déjà enregistré.
    static func save(username: String, password: String?, for id: UUID, label: String) throws {
        let usernameData = Data(username.utf8)
        var attributes: [String: Any] = [
            kSecAttrGeneric as String: usernameData,
            kSecAttrLabel as String: "LabPanel – \(label)",
            kSecAttrDescription as String: String(localized: "Identifiant LabPanel"),
        ]
        if let password { attributes[kSecValueData as String] = Data(password.utf8) }

        let status = SecItemUpdate(baseQuery(id) as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            guard let password else { throw StoreError.status(errSecItemNotFound) }
            var item = baseQuery(id)
            item.merge(attributes) { _, new in new }
            item[kSecValueData as String] = Data(password.utf8)
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError.status(added) }
        default:
            throw StoreError.status(status)
        }
    }

    static func delete(_ id: UUID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }
}
