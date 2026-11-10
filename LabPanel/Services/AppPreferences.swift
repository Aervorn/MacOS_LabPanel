import AppKit
import Foundation
import Observation

/// Apparence de l'app, et donc des pages : WebKit transmet le mode clair ou sombre aux sites
/// (`prefers-color-scheme`), si bien que Home Assistant, AdGuard ou Zigbee2MQTT suivent aussi.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: String(localized: "Automatique")
        case .light: String(localized: "Clair")
        case .dark: String(localized: "Sombre")
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Langue de l'interface. macOS la lit au lancement (clé AppleLanguages de l'app) :
/// en changer demande de relancer LabPanel. C'est aussi ce que fait Réglages Système ›
/// Général › Langue et région › Applications.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, french, english

    var id: Self { self }

    /// Code passé à macOS ; `nil` : la langue du système.
    var code: String? {
        switch self {
        case .system: nil
        case .french: "fr"
        case .english: "en"
        }
    }

    /// Nom de chaque langue dans cette langue même, comme dans les Réglages Système.
    var label: String {
        switch self {
        case .system: String(localized: "Langue du système")
        case .french: "Français"
        case .english: "English"
        }
    }

    static let defaultsKey = "AppleLanguages"

    /// Langue réglée pour l'app seule (pas celle, globale, du système).
    static var stored: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        guard let first = (domain?[defaultsKey] as? [String])?.first else { return .system }
        if first.hasPrefix("fr") { return .french }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    func store() {
        if let code {
            UserDefaults.standard.set([code], forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
}

/// Où sont les onglets : capsule dans la barre de titre, ou dock flottant en bas de la fenêtre.
enum NavigationStyle: String, CaseIterable, Identifiable {
    case capsule, dock

    var id: Self { self }

    var label: String {
        switch self {
        case .capsule: String(localized: "Capsule en haut")
        case .dock: String(localized: "Dock en bas")
        }
    }
}

/// Délai avant de décharger un onglet inactif.
enum UnloadDelay: Int, CaseIterable, Identifiable {
    case never = 0
    case five = 5
    case fifteen = 15
    case thirty = 30
    case hour = 60

    var id: Self { self }

    var duration: Duration? { self == .never ? nil : .seconds(rawValue * 60) }

    var label: String {
        switch self {
        case .never: String(localized: "Jamais")
        case .five: String(localized: "Après 5 minutes")
        case .fifteen: String(localized: "Après 15 minutes")
        case .thirty: String(localized: "Après 30 minutes")
        case .hour: String(localized: "Après 1 heure")
        }
    }
}

/// Préférences générales. On n'écrit dans UserDefaults que si la valeur change vraiment
/// (même précaution que dans Vestora, où une écriture à chaque mise à jour faisait boucler SwiftUI).
@MainActor
@Observable
final class AppPreferences {
    var appearance: AppearanceMode {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            appearance.apply()
        }
    }

    /// Vérifie régulièrement que chaque service répond (pastille de l'onglet).
    var checksAvailability: Bool {
        didSet {
            guard checksAvailability != oldValue else { return }
            UserDefaults.standard.set(checksAvailability, forKey: Self.availabilityKey)
        }
    }

    /// Décharge de la mémoire les onglets restés inactifs ce temps-là.
    var unloadDelay: UnloadDelay {
        didSet {
            guard unloadDelay != oldValue else { return }
            UserDefaults.standard.set(unloadDelay.rawValue, forKey: Self.unloadKey)
        }
    }

    var navigationStyle: NavigationStyle {
        didSet {
            guard navigationStyle != oldValue else { return }
            UserDefaults.standard.set(navigationStyle.rawValue, forKey: Self.navigationKey)
        }
    }

    /// Capsule : le nom de chaque onglet, et pas seulement celui de l'onglet ouvert.
    var showsAllTabNames: Bool {
        didSet {
            guard showsAllTabNames != oldValue else { return }
            UserDefaults.standard.set(showsAllTabNames, forKey: Self.allNamesKey)
        }
    }

    /// Dock : n'apparaît que quand le pointeur touche le bas de la fenêtre.
    var dockAutoHides: Bool {
        didSet {
            guard dockAutoHides != oldValue else { return }
            UserDefaults.standard.set(dockAutoHides, forKey: Self.dockAutoHideKey)
        }
    }

    /// Langue choisie ; appliquée au prochain lancement.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            language.store()
        }
    }

    /// Langue en vigueur depuis le lancement : si elle diffère du choix, il faut relancer.
    let languageAtLaunch: AppLanguage

    var needsRelaunch: Bool { language != languageAtLaunch }

    nonisolated static let appearanceKey = "appearance.mode"
    nonisolated static let availabilityKey = "availability.enabled"
    nonisolated static let unloadKey = "tabs.unloadAfterMinutes"
    nonisolated static let navigationKey = "navigation.style"
    nonisolated static let allNamesKey = "navigation.capsule.allNames"
    nonisolated static let dockAutoHideKey = "navigation.dock.autoHide"

    init() {
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        checksAvailability = UserDefaults.standard.object(forKey: Self.availabilityKey) as? Bool ?? true
        unloadDelay = (UserDefaults.standard.object(forKey: Self.unloadKey) as? Int)
            .flatMap(UnloadDelay.init(rawValue:)) ?? .thirty
        navigationStyle = UserDefaults.standard.string(forKey: Self.navigationKey)
            .flatMap(NavigationStyle.init(rawValue:)) ?? .capsule
        showsAllTabNames = UserDefaults.standard.bool(forKey: Self.allNamesKey)
        dockAutoHides = UserDefaults.standard.object(forKey: Self.dockAutoHideKey) as? Bool ?? true
        let language = AppLanguage.stored
        self.language = language
        languageAtLaunch = language
    }

    /// Relance LabPanel (pour appliquer la langue).
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
