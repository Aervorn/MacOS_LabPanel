import SwiftUI

/// Barre d'onglets, au centre de la barre de titre, sur une capsule de verre.
///
/// L'onglet choisi est surligné à la couleur de son service ; la surbrillance glisse d'un onglet
/// à l'autre. Quand la fenêtre est étroite, seuls les icônes restent, sauf pour l'onglet choisi.
struct TabStrip: View {
    let services: [Service]
    let selectedID: UUID?
    let compact: Bool
    let onSelect: (UUID) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(services) { service in
                TabButton(
                    service: service,
                    isSelected: service.id == selectedID,
                    compact: compact,
                    selectionNamespace: selection
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        onSelect(service.id)
                    }
                }
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }
}

private struct TabButton: View {
    let service: Service
    let isSelected: Bool
    let compact: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @Environment(AvailabilityMonitor.self) private var monitor
    @Environment(Browser.self) private var browser
    @Environment(ServiceStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false

    private var showsName: Bool { !compact || isSelected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ServiceIcon(service: service, size: 20)
                    .overlay(alignment: .bottomTrailing) {
                        StatusDot(availability: monitor.availability(of: service.id))
                            .offset(x: 2, y: 2)
                    }
                    .scaleEffect(isSelected ? 1.06 : 1)
                if showsName {
                    Text(verbatim: service.name)
                        .font(.callout.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, showsName ? 10 : 5)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule()
                        .fill(service.color.opacity(0.2))
                        .overlay(Capsule().strokeBorder(service.color.opacity(0.45), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                } else if hovering {
                    Capsule().fill(.primary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(tooltip)
        .accessibilityLabel(Text(verbatim: service.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { menu }
    }

    private var tooltip: String {
        var lines = [service.name]
        if let url = service.url { lines.append(url.absoluteString) }
        if service.isConfigured { lines.append(monitor.availability(of: service.id).label) }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private var menu: some View {
        let session = browser.session(service.id)
        Button("Recharger") { session?.reload() }
            .disabled(session == nil)
        Button("Revenir à l'accueil du service") { session?.loadHome() }
            .disabled(session == nil)
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
