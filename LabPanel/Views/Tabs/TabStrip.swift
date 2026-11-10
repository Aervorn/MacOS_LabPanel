import SwiftUI

/// Barre d'onglets, au centre de la barre de titre, sur une capsule de verre.
///
/// L'onglet choisi est surligné à la couleur de son service ; la surbrillance glisse d'un onglet
/// à l'autre. En mode compact (le réglage par défaut, ou une fenêtre trop étroite), seul l'onglet
/// choisi affiche son nom.
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
    @State private var hovering = false

    private var showsName: Bool { !compact || isSelected }
    private var isUnloaded: Bool { browser.isUnloaded(service.id) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ServiceIcon(service: service, size: 20)
                    // Onglet déchargé de la mémoire : atténué, comme dans Safari.
                    .opacity(isUnloaded ? 0.45 : 1)
                    .saturation(isUnloaded ? 0.3 : 1)
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
        .contextMenu { TabContextMenu(service: service, isSelected: isSelected) }
    }

    private var tooltip: String {
        TabTooltip.text(for: service, monitor: monitor, browser: browser)
    }
}
