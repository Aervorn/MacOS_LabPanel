import AppKit
import SwiftUI

/// Fenêtre principale : la barre d'onglets dans la barre de titre, la page du service en dessous.
struct ContentView: View {
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(AvailabilityMonitor.self) private var monitor
    @Environment(\.openSettings) private var openSettings
    @State private var windowWidth: CGFloat = 1400

    private var current: WebSession? { browser.session(store.selected?.id) }

    /// Largeur nécessaire aux onglets avec leurs noms (estimation), plus les boutons de part et d'autre.
    private var compactTabs: Bool {
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .navigationTitle(store.selected?.name ?? "LabPanel")
        .toolbar(removing: .title)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { DownloadToast() }
        .onChange(of: store.selected?.id, initial: true) {
            if let service = store.selected { browser.prepare(service) }
        }
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
            TabStrip(
                services: store.visibleServices,
                selectedID: store.selected?.id,
                compact: compactTabs
            ) { store.select($0) }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
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
