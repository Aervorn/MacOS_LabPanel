import AppKit
import Foundation

/// Dialogues demandés par les pages : alert(), confirm(), prompt() et mot de passe HTTP.
/// Affichés en feuille sur la fenêtre de la page quand elle existe.
@MainActor
enum Dialogs {
    private static func makeAlert(_ message: String, host: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = host.isEmpty ? "LabPanel" : host
        alert.informativeText = message
        return alert
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }

    static func alert(_ message: String, host: String, in window: NSWindow?) async {
        let alert = makeAlert(message, host: host)
        alert.addButton(withTitle: String(localized: "OK"))
        _ = await present(alert, in: window)
    }

    static func confirm(_ message: String, host: String, in window: NSWindow?) async -> Bool {
        let alert = makeAlert(message, host: host)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        return await present(alert, in: window) == .alertFirstButtonReturn
    }

    static func prompt(_ message: String, defaultText: String?, host: String, in window: NSWindow?) async -> String? {
        let alert = makeAlert(message, host: host)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        alert.window.initialFirstResponder = field
        return await present(alert, in: window) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Identifiant et mot de passe pour une page protégée par une authentification HTTP.
    static func askCredential(for space: URLProtectionSpace, in window: NSWindow?) async -> URLCredential? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Connexion à \(space.host)")
        if let realm = space.realm, !realm.isEmpty {
            alert.informativeText = String(localized: "Le site demande un identifiant et un mot de passe (« \(realm) »).")
        } else {
            alert.informativeText = String(localized: "Le site demande un identifiant et un mot de passe.")
        }

        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        user.placeholderString = String(localized: "Identifiant")
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        password.placeholderString = String(localized: "Mot de passe")
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        stack.addSubview(user)
        stack.addSubview(password)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = user

        alert.addButton(withTitle: String(localized: "Se connecter"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        guard await present(alert, in: window) == .alertFirstButtonReturn else { return nil }
        // Gardé pour la session seulement : rien n'est écrit dans le trousseau.
        return URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession)
    }
}
