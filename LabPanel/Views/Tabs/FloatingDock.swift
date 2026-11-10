import SwiftUI

/// Dock flottant en bas de la fenêtre : une icône par service, qui grossit au survol avec ses voisines,
/// un point sous l'onglet ouvert, et le nom et l'état du service au-dessus de l'icône survolée.
///
/// Masqué automatiquement (réglage par défaut), il apparaît quand le pointeur touche le bas de la
/// fenêtre, et un instant quand on change d'onglet au clavier. Sinon, il reste affiché et la page
/// lui laisse sa place.
struct FloatingDock: View {
    let autoHides: Bool

    @Environment(ServiceStore.self) private var store
    @State private var hoveredID: UUID?
    @State private var revealed = false
    @State private var hideTask: Task<Void, Never>?

    static let iconSize: CGFloat = 40
    /// Place laissée sous la page quand le dock reste affiché.
    static let reservedHeight: CGFloat = 76

    private var isShown: Bool { !autoHides || revealed }

    var body: some View {
        let services = store.visibleServices
        ZStack(alignment: .bottom) {
            if autoHides {
                // Bord bas de la fenêtre : y amener le pointeur fait apparaître le dock.
                Color.clear
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { reveal() } else { scheduleHide(after: .seconds(1)) }
                    }
            }

            if !services.isEmpty {
                dock(services)
                    .offset(y: isShown ? 0 : 110)
                    .opacity(isShown ? 1 : 0)
                    .allowsHitTesting(isShown)
                    .onHover { inside in
                        if inside {
                            reveal()
                        } else {
                            hoveredID = nil
                            scheduleHide(after: .milliseconds(600))
                        }
                    }
                    .padding(.bottom, 14)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isShown)
        .onChange(of: store.selected?.id) {
            guard autoHides else { return }
            reveal()
            scheduleHide(after: .seconds(1.5))
        }
        .onChange(of: autoHides) { revealed = false }
    }

    private func dock(_ services: [Service]) -> some View {
        let hoveredIndex = services.firstIndex { $0.id == hoveredID }
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                DockItem(
                    service: service,
                    isSelected: service.id == store.selected?.id,
                    size: Self.iconSize * magnification(index: index, hovered: hoveredIndex),
                    showsLabel: service.id == hoveredID
                ) {
                    store.select(service.id)
                }
                .onHover { inside in
                    if inside {
                        hoveredID = service.id
                    } else if hoveredID == service.id {
                        hoveredID = nil
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hoveredID)
    }

    /// Grossissement façon Dock de macOS : l'icône survolée et, un peu moins, ses voisines.
    private func magnification(index: Int, hovered: Int?) -> CGFloat {
        guard let hovered else { return 1 }
        switch abs(index - hovered) {
        case 0: return 1.45
        case 1: return 1.2
        case 2: return 1.06
        default: return 1
        }
    }

    private func reveal() {
        hideTask?.cancel()
        hideTask = nil
        revealed = true
    }

    private func scheduleHide(after delay: Duration) {
        guard autoHides else { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, hoveredID == nil else { return }
            revealed = false
        }
    }
}

private struct DockItem: View {
    let service: Service
    let isSelected: Bool
    let size: CGFloat
    let showsLabel: Bool
    let action: () -> Void

    @Environment(AvailabilityMonitor.self) private var monitor
    @Environment(Browser.self) private var browser

    private var isUnloaded: Bool { browser.isUnloaded(service.id) }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                ServiceIcon(service: service, size: size * 0.78)
                    .opacity(isUnloaded ? 0.45 : 1)
                    .saturation(isUnloaded ? 0.3 : 1)
                    .frame(width: size, height: size)
                    .background {
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .fill(isSelected ? service.color.opacity(0.18) : .clear)
                    }
                    .overlay(alignment: .topTrailing) {
                        StatusDot(availability: monitor.availability(of: service.id), size: 9)
                            .offset(x: 1, y: -1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { TabContextMenu(service: service, isSelected: isSelected) }
            .accessibilityLabel(Text(verbatim: service.name))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .help(TabTooltip.text(for: service, monitor: monitor, browser: browser))

            Circle()
                .fill(isSelected ? Color.primary : .clear)
                .frame(width: 4, height: 4)
        }
        .overlay(alignment: .top) {
            if showsLabel {
                label
                    .fixedSize()
                    .offset(y: -34)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    .allowsHitTesting(false)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(verbatim: service.name)
                .fontWeight(.semibold)
            if service.isConfigured {
                Text(verbatim: "·")
                Text(monitor.availability(of: service.id).label)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}
