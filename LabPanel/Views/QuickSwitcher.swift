import AppKit
import SwiftUI

/// Sélecteur rapide (⌘K) : taper quelques lettres, Entrée, et on est sur le service.
/// Propose aussi les actions courantes sur le service en surbrillance.
struct QuickSwitcher: View {
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(AvailabilityMonitor.self) private var monitor
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var highlighted = 0
    /// Service visé par les actions : le dernier service en surbrillance.
    @State private var targetID: UUID?
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    private enum Entry: Identifiable {
        case service(Service, position: Int)
        case action(SwitcherAction)

        var id: String {
            switch self {
            case .service(let service, _): "service-\(service.id)"
            case .action(let action): "action-\(action.kind.rawValue)"
            }
        }
    }

    private var serviceResults: [Service] {
        QuickSearch.rank(store.visibleServices, query: query, name: \.name) {
            $0.url?.host(percentEncoded: false) ?? $0.address
        }
    }

    private var target: Service? {
        let results = serviceResults
        return results.first { $0.id == targetID } ?? results.first
    }

    private var entries: [Entry] {
        let results = serviceResults
        let visible = store.visibleServices
        var list: [Entry] = results.map { service in
            .service(service, position: (visible.firstIndex { $0.id == service.id } ?? 99) + 1)
        }
        if let target {
            list += SwitcherAction.Kind.allCases
                .map { SwitcherAction(kind: $0, service: target) }
                .filter { $0.isAvailable(browser: browser, selectedID: store.selected?.id) }
                .map(Entry.action)
        }
        return list
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    TextField("Aller à un service ou une action", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                    Text(verbatim: "esc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                }
                .padding(.horizontal, 18)
                .frame(height: 56)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            list
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: highlighted) { _, index in
                        let all = entries
                        if all.indices.contains(index) { proxy.scrollTo(all[index].id) }
                    }
                }
            }
            .frame(width: 560)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 16)
            .padding(.top, 70)
        }
        .onAppear {
            focused = true
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: query) {
            highlighted = 0
            targetID = nil
        }
    }

    @ViewBuilder private var list: some View {
        let all = entries
        let firstAction = all.firstIndex { if case .action = $0 { true } else { false } }
        if all.isEmpty {
            Text("Aucun service ne correspond.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        ForEach(Array(all.enumerated()), id: \.element.id) { index, entry in
            if index == 0, case .service = entry {
                sectionHeader("Services")
            }
            if index == firstAction, let target {
                sectionHeader("Actions · \(target.name)")
            }
            row(entry, isHighlighted: index == highlighted)
                .id(entry.id)
                .onHover { if $0 { highlight(index) } }
                .onTapGesture { run(entry) }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            switch entry {
            case .service(let service, let position):
                ServiceIcon(service: service, size: 26)
                    .opacity(browser.isUnloaded(service.id) ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: service.name)
                        .font(.body.weight(.semibold))
                    Text(verbatim: detail(for: service))
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if service.isConfigured {
                    StatusDot(availability: monitor.availability(of: service.id), size: 8)
                }
                if position <= 9 {
                    Text(verbatim: "⌘\(position)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .frame(minWidth: 26, alignment: .trailing)
                }
            case .action(let action):
                Image(systemName: action.kind.symbol)
                    .frame(width: 26)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(verbatim: action.title)
                Spacer(minLength: 8)
                if let shortcut = action.kind.shortcut {
                    Text(verbatim: shortcut)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
    }

    private func detail(for service: Service) -> String {
        var parts: [String] = []
        if let host = service.url?.host(percentEncoded: false) {
            parts.append(service.url?.port.map { "\(host):\($0)" } ?? host)
        } else {
            parts.append(String(localized: "Adresse à saisir"))
        }
        if service.isConfigured {
            parts.append(monitor.availability(of: service.id).label)
        }
        if browser.isUnloaded(service.id) {
            parts.append(String(localized: "déchargé"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func highlight(_ index: Int) {
        let all = entries
        guard all.indices.contains(index) else { return }
        highlighted = index
        if case .service(let service, _) = all[index] { targetID = service.id }
    }

    private func move(_ offset: Int) {
        let count = entries.count
        guard count > 0 else { return }
        highlight((highlighted + offset + count) % count)
    }

    private func runHighlighted() {
        let all = entries
        guard all.indices.contains(highlighted) else { return }
        run(all[highlighted])
    }

    private func run(_ entry: Entry) {
        close()
        switch entry {
        case .service(let service, _):
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { store.select(service.id) }
        case .action(let action):
            if action.kind != .unload { store.select(action.service.id) }
            action.perform(store: store, browser: browser, openSettings: openSettings)
        }
    }

    private func close() {
        store.showsSwitcher = false
    }

    /// ↑ ↓ Entrée et Échap, même quand le champ de recherche a le clavier.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control])
            switch event.keyCode {
            case 125: move(+1); return nil               // ↓
            case 126: move(-1); return nil               // ↑
            case 36, 76: runHighlighted(); return nil    // Entrée
            case 53: close(); return nil                 // Échap
            case 40 where modifiers == .command: close(); return nil  // ⌘K referme
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Action proposée par le sélecteur sur un service.
struct SwitcherAction {
    enum Kind: String, CaseIterable {
        case reload, fillLogin, openInBrowser, home, unload, edit

        var symbol: String {
            switch self {
            case .reload: "arrow.clockwise"
            case .fillLogin: "key"
            case .openInBrowser: "safari"
            case .home: "house"
            case .unload: "moon.zzz"
            case .edit: "slider.horizontal.3"
            }
        }

        var shortcut: String? {
            switch self {
            case .reload: "⌘R"
            case .fillLogin: "⌥⌘L"
            case .openInBrowser: "⌥⌘O"
            case .home: "⇧⌘H"
            case .unload, .edit: nil
            }
        }
    }

    let kind: Kind
    let service: Service

    var title: String {
        let name = service.name
        return switch kind {
        case .reload: String(localized: "Recharger \(name)")
        case .fillLogin: String(localized: "Remplir l'identifiant de \(name)")
        case .openInBrowser: String(localized: "Ouvrir \(name) dans le navigateur")
        case .home: String(localized: "Revenir à l'accueil de \(name)")
        case .unload: String(localized: "Décharger \(name)")
        case .edit: String(localized: "Modifier \(name)…")
        }
    }

    @MainActor
    func isAvailable(browser: Browser, selectedID: UUID?) -> Bool {
        let hasSession = browser.session(service.id) != nil
        switch kind {
        case .reload, .fillLogin, .home: return hasSession
        case .openInBrowser: return service.isConfigured
        // L'onglet affiché ne se décharge pas : il se rechargerait aussitôt.
        case .unload: return hasSession && service.id != selectedID
        case .edit: return true
        }
    }

    @MainActor
    func perform(store: ServiceStore, browser: Browser, openSettings: OpenSettingsAction) {
        let session = browser.session(service.id)
        switch kind {
        case .reload: session?.reload()
        case .fillLogin: session?.fillCredentials()
        case .openInBrowser: URLActions.openInBrowser(session?.displayedURL ?? service.url)
        case .home: session?.loadHome()
        case .unload: browser.unload(service.id)
        case .edit:
            store.editingID = service.id
            openSettings()
        }
    }
}
