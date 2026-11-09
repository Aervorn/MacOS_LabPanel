import AppKit
import SwiftUI

@main
struct LabPanelApp: App {
    static let mainWindowID = "main"

    /// Vrai quand l'app sert d'hôte aux tests : pas de mises à jour ni de vérifications réseau.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    @State private var store = ServiceStore()
    @State private var browser = Browser()
    @State private var monitor = AvailabilityMonitor()
    @State private var preferences = AppPreferences()
    @State private var updater = AppUpdater()

    var body: some Scene {
        // Une seule fenêtre. Les pages vivent dans `browser` : fermer la fenêtre puis la rouvrir
        // (clic sur l'icône du Dock) retrouve chaque service où il en était.
        Window("LabPanel", id: Self.mainWindowID) {
            ContentView()
                .frame(minWidth: 820, minHeight: 520)
                .environment(store)
                .environment(browser)
                .environment(monitor)
                .environment(preferences)
                .environment(updater)
                .task { preferences.appearance.apply() }
                .onChange(of: preferences.checksAvailability, initial: true) { _, enabled in
                    if enabled && !Self.isRunningTests {
                        monitor.start { [store] in store.services }
                    } else {
                        monitor.stop()
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
                Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            PageCommands(store: store, browser: browser)
            ServicesCommands(store: store)
        }

        Window("À propos de LabPanel", id: AboutView.windowID) {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(store)
                .environment(browser)
                .environment(monitor)
                .environment(preferences)
                .environment(updater)
        }
    }
}

/// Menu Présentation : actions sur la page affichée.
private struct PageCommands: Commands {
    let store: ServiceStore
    let browser: Browser

    private var session: WebSession? { browser.session(store.selected?.id) }

    private func setZoom(_ change: (Double) -> Double) {
        guard let id = store.selected?.id else { return }
        store.update(id) { $0.zoom = min(max(change($0.zoom), 0.5), 2) }
    }

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Recharger la page") { session?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session == nil)
            Button("Recharger sans le cache") { session?.reload(fromOrigin: true) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Revenir à l'accueil du service") { session?.loadHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(session == nil)
            Divider()
            Button("Page précédente") { session?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(session?.canGoBack ?? false))
            Button("Page suivante") { session?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(session?.canGoForward ?? false))
            Divider()
            Button("Agrandir") { setZoom { $0 + 0.1 } }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(session == nil)
            Button("Réduire") { setZoom { $0 - 0.1 } }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(session == nil)
            Button("Taille réelle") { setZoom { _ in 1 } }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(session == nil)
            Divider()
            Button("Ouvrir dans le navigateur") {
                URLActions.openInBrowser(session?.displayedURL ?? store.selected?.url)
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(store.selected?.isConfigured != true)
            Button("Copier l'adresse de la page") {
                URLActions.copy(session?.displayedURL ?? store.selected?.url)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(store.selected?.isConfigured != true)
            Divider()
        }
    }
}

/// Menu Services : un raccourci par onglet (⌘1 à ⌘9) et le passage d'un onglet à l'autre.
private struct ServicesCommands: Commands {
    let store: ServiceStore

    var body: some Commands {
        CommandMenu("Services") {
            let visible = Array(store.visibleServices.prefix(9).enumerated())
            ForEach(visible, id: \.element.id) { index, service in
                Button {
                    store.select(service.id)
                } label: {
                    Text(verbatim: service.name)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Onglet suivant") { store.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Onglet précédent") { store.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
    }
}
