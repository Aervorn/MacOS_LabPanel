import SwiftUI

/// Clic droit sur un onglet, qu'il soit dans la capsule ou dans le dock.
struct TabContextMenu: View {
    let service: Service
    let isSelected: Bool

    @Environment(Browser.self) private var browser
    @Environment(ServiceStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let session = browser.session(service.id)
        Button("Recharger") { session?.reload() }
            .disabled(session == nil)
        Button("Revenir à l'accueil du service") { session?.loadHome() }
            .disabled(session == nil)
        Button("Remplir l'identifiant") { session?.fillCredentials() }
            .disabled(session == nil)
        Button("Décharger l'onglet") { browser.unload(service.id) }
            .disabled(session == nil || isSelected)
        Divider()
        Button("Ouvrir dans le navigateur") { URLActions.openInBrowser(session?.displayedURL ?? service.url) }
            .disabled(!service.isConfigured)
        Button("Copier l'adresse") { URLActions.copy(session?.displayedURL ?? service.url) }
            .disabled(!service.isConfigured)
        Divider()
        Button("Modifier…") {
            store.editingID = service.id
            openSettings()
        }
        Button("Masquer l'onglet") {
            store.update(service.id) { $0.isVisible = false }
        }
    }
}

/// Infobulle d'un onglet : nom, adresse, disponibilité, et s'il est déchargé.
@MainActor
enum TabTooltip {
    static func text(for service: Service, monitor: AvailabilityMonitor, browser: Browser) -> String {
        var lines = [service.name]
        if let url = service.url { lines.append(url.absoluteString) }
        if service.isConfigured { lines.append(monitor.availability(of: service.id).label) }
        if browser.isUnloaded(service.id) {
            lines.append(String(localized: "Déchargé de la mémoire : la page se rouvrira à ton retour"))
        }
        return lines.joined(separator: "\n")
    }
}
