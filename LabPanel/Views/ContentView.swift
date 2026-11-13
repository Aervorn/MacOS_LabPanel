import AppKit
import SwiftUI

/// Fenêtre principale : les onglets (capsule dans la barre de titre ou dock en bas),
/// la page du service, et le sélecteur rapide par-dessus.
struct ContentView: View {
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(AvailabilityMonitor.self) private var monitor
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openSettings) private var openSettings
    @State private var windowWidth: CGFloat = 1400

    private var current: WebSession? { browser.session(store.selected?.id) }

    private var usesDock: Bool { preferences.navigationStyle == .dock }

    /// Le dock reste affiché : la page lui laisse sa place en bas.
    private var reservesDockSpace: Bool { usesDock && !preferences.dockAutoHides && !store.visibleServices.isEmpty }

    /// Capsule : seul l'onglet ouvert affiche son nom, sauf si l'option « tous les noms » est cochée
    /// et que la fenêtre est assez large (estimation : nom + icône par onglet, plus les boutons autour).
    private var compactTabs: Bool {
        guard preferences.showsAllTabNames else { return true }
        let tabs = store.visibleServices.reduce(CGFloat(0)) { width, service in
            width + CGFloat(service.name.count) * 7.5 + 46
        }
        return tabs + 360 > windowWidth
    }

    var body: some View {
        Group {
            if let service = store.selected {
                ServicePane(service: service)
            } else {
                emptyState
            }
        }
        .padding(.bottom, reservesDockSpace ? FloatingDock.reservedHeight : 0)
        .background(Color(nsColor: .windowBackgroundColor))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .navigationTitle(store.selected?.name ?? "LabPanel")
        .toolbar(removing: .title)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if usesDock {
                FloatingDock(autoHides: preferences.dockAutoHides)
            }
        }
        .overlay(alignment: .bottom) {
            DownloadToast()
                .padding(.bottom, usesDock && !preferences.dockAutoHides ? FloatingDock.reservedHeight : 0)
        }
        .overlay {
            if store.showsSwitcher {
                QuickSwitcher()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.showsSwitcher)
        .animation(.spring(response: 0.35), value: preferences.navigationStyle)
        .onChange(of: store.selected?.id, initial: true) { previous, _ in
            browser.noteShown(previous)
            store.showsSwitcher = false
            if let service = store.selected { browser.prepare(service) }
        }
        .background(MainWindowObserver())
        .onChange(of: store.services) { _, services in
            browser.sync(with: services)
            if let service = store.selected { browser.prepare(service) }
            monitor.refreshSoon()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                current?.goBack()
            } label: {
                Label("Précédent", systemImage: "chevron.backward")
            }
            .disabled(!(current?.canGoBack ?? false))
            .help("Page précédente (⌘[)")

            Button {
                current?.goForward()
            } label: {
                Label("Suivant", systemImage: "chevron.forward")
            }
            .disabled(!(current?.canGoForward ?? false))
            .help("Page suivante (⌘])")

            Button {
                if current?.isLoading == true {
                    current?.webView.stopLoading()
                } else {
                    current?.reload()
                }
            } label: {
                if current?.isLoading == true {
                    Label("Arrêter", systemImage: "xmark")
                } else {
                    Label("Recharger", systemImage: "arrow.clockwise")
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .disabled(current == nil)
            .help("Recharger la page (⌘R)")
        }

        ToolbarItem(placement: .principal) {
            Group {
                if usesDock {
                    PageTitle(service: store.selected, session: current)
                } else {
                    TabStrip(
                        services: store.visibleServices,
                        selectedID: store.selected?.id,
                        compact: compactTabs
                    ) { store.select($0) }
                }
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.showsSwitcher.toggle()
            } label: {
                Label("Aller à…", systemImage: "magnifyingglass")
            }
            .help(preferences.quickSwitcherShortcut.map { Text("Aller à un service (\($0.display))") } ?? Text("Aller à un service"))

            Button {
                URLActions.openInBrowser(current?.displayedURL ?? store.selected?.url)
            } label: {
                Label("Ouvrir dans le navigateur", systemImage: "safari")
            }
            .disabled(store.selected?.isConfigured != true)
            .help("Ouvrir dans le navigateur par défaut (⌥⌘O)")

            SettingsLink {
                Label("Réglages", systemImage: "gearshape")
            }
            .help("Réglages (⌘,)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Aucun onglet affiché")
                .font(.title2.weight(.semibold))
            Text("Tous les services sont masqués. Affiche-les ou ajoute-en un dans les Réglages.")
                .foregroundStyle(.secondary)
            Button("Ouvrir les Réglages") { openSettings() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Fermer la fenêtre principale ferme aussi les Réglages et « À propos » : sinon ces fenêtres
/// restent seules à l'écran alors que LabPanel a l'air fermé.
private struct MainWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Tracker() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Tracker: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated { Self.closeAuxiliaryWindows(except: window) }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        @MainActor
        private static func closeAuxiliaryWindows(except main: NSWindow?) {
            for window in NSApp.windows where window !== main && window.isVisible {
                let id = window.identifier?.rawValue ?? ""
                // Réglages : « com_apple_SwiftUI_Settings_window » ; À propos : « about », « about-AppWindow-1 »…
                if id.localizedCaseInsensitiveContains("settings") || id.hasPrefix(AboutView.windowID) {
                    window.close()
                }
            }
        }
    }
}

/// Mode dock : le service ouvert et son adresse, au centre de la barre de titre.
private struct PageTitle: View {
    let service: Service?
    let session: WebSession?
    @Environment(AvailabilityMonitor.self) private var monitor

    var body: some View {
        if let service {
            HStack(spacing: 8) {
                ServiceIcon(service: service, size: 18)
                Text(verbatim: service.name)
                    .fontWeight(.semibold)
                if let url = session?.displayedURL ?? service.url {
                    Text(verbatim: url.host(percentEncoded: false).map { host in url.port.map { "\(host):\($0)" } ?? host } ?? "")
                        .foregroundStyle(.secondary)
                }
                if service.isConfigured {
                    StatusDot(availability: monitor.availability(of: service.id))
                }
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
        }
    }
}

/// Annonce un téléchargement terminé (ou raté), quelques secondes en bas de la fenêtre.
private struct DownloadToast: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        Group {
            if let url = browser.lastDownload {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("Téléchargé : \(url.lastPathComponent)")
                        .lineLimit(1)
                    Button("Afficher") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.glass)
                }
                .task(id: url) { await dismiss() }
            } else if let error = browser.downloadError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Échec du téléchargement : \(error)")
                        .lineLimit(2)
                }
                .task(id: error) { await dismiss() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 18)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(.spring(response: 0.35), value: browser.lastDownload)
    }

    private var isHidden: Bool { browser.lastDownload == nil && browser.downloadError == nil }

    private func dismiss() async {
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled else { return }
        browser.lastDownload = nil
        browser.downloadError = nil
    }
}
