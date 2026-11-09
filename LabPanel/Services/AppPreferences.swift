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

    nonisolated static let appearanceKey = "appearance.mode"
    nonisolated static let availabilityKey = "availability.enabled"

    init() {
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        checksAvailability = UserDefaults.standard.object(forKey: Self.availabilityKey) as? Bool ?? true
    }
}
