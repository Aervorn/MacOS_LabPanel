import AppKit
import Foundation
import Observation
import SwiftUI

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

/// Raccourci clavier choisi dans les Réglages : une lettre, avec ⌘ ou ⌃ (et éventuellement ⌥ ⇧).
/// Lettres seulement : les chiffres et la ponctuation changent de touche selon la disposition
/// du clavier (AZERTY, QWERTY…), une lettre reste la même pour AppKit comme pour SwiftUI.
struct Shortcut: Codable, Equatable {
    var key: String
    var command = false
    var option = false
    var control = false
    var shift = false

    /// ⌘K par défaut pour le sélecteur rapide.
    static let quickSwitcherDefault = Shortcut(key: "k", command: true)

    /// Raccourci de cette frappe, s'il peut en être un (une lettre, avec ⌘ ou ⌃).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control),
              let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1, let letter = characters.first,
              letter.isASCII, letter.isLetter
        else { return nil }
        self.init(key: String(letter), command: flags.contains(.command), option: flags.contains(.option),
                  control: flags.contains(.control), shift: flags.contains(.shift))
    }

    init(key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    var keyboardShortcut: KeyboardShortcut {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if shift { modifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: modifiers)
    }

    /// Dans l'ordre des menus de macOS : ⌃⌥⇧⌘K.
    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }

    /// Déjà pris par LabPanel (menus Présentation, Édition, Fenêtre…) ou par macOS.
    var isReserved: Bool {
        let taken: [Shortcut] = [
            .init(key: "a", command: true), .init(key: "c", command: true), .init(key: "f", command: true),
            .init(key: "h", command: true), .init(key: "m", command: true), .init(key: "q", command: true),
            .init(key: "r", command: true), .init(key: "v", command: true), .init(key: "w", command: true),
            .init(key: "x", command: true), .init(key: "z", command: true),
            .init(key: "c", command: true, shift: true), .init(key: "h", command: true, shift: true),
            .init(key: "r", command: true, shift: true), .init(key: "z", command: true, shift: true),
            .init(key: "h", command: true, option: true), .init(key: "l", command: true, option: true),
            .init(key: "o", command: true, option: true),
            .init(key: "f", command: true, control: true), .init(key: "q", command: true, control: true),
        ]
        return taken.contains(self)
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

    /// Ouvre le sélecteur rapide ; `nil` : aucun raccourci (la touche reste à la page, à Dockhand par exemple).
    var quickSwitcherShortcut: Shortcut? {
        didSet {
            guard quickSwitcherShortcut != oldValue else { return }
            if let quickSwitcherShortcut, let data = try? JSONEncoder().encode(quickSwitcherShortcut) {
                UserDefaults.standard.set(data, forKey: Self.switcherShortcutKey)
            } else {
                UserDefaults.standard.set(Self.noShortcut, forKey: Self.switcherShortcutKey)
            }
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
    nonisolated static let switcherShortcutKey = "quickSwitcher.shortcut"
    nonisolated static let noShortcut = "none"

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
        let storedShortcut = UserDefaults.standard.object(forKey: Self.switcherShortcutKey)
        if storedShortcut as? String == Self.noShortcut {
            quickSwitcherShortcut = nil
        } else {
            quickSwitcherShortcut = (storedShortcut as? Data)
                .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .quickSwitcherDefault
        }
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
