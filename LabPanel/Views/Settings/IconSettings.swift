import AppKit
import SwiftUI

/// Section « Apparence » de la fiche d'un service : icône (officielle, symbole ou image) et couleur.
struct IconSettingsSection: View {
    let service: Service
    @Environment(ServiceStore.self) private var store
    @Environment(IconLibrary.self) private var library
    @Environment(\.colorScheme) private var colorScheme

    @State private var slug = ""
    @State private var browsing = false
    @State private var importError: String?

    enum Mode: Hashable { case official, symbol, image }

    private var mode: Mode {
        switch service.icon {
        case .dashboard: .official
        case .symbol: .symbol
        case .file: .image
        }
    }

    private var currentSlug: String {
        if case .dashboard(let slug) = service.icon { return slug }
        return ""
    }

    /// Nom proposé quand on passe à l'icône officielle : celui du type, sinon le nom du service.
    private var suggestedSlug: String {
        service.kind.dashboardIconSlug
            ?? DashboardIcons.clean(service.name).replacingOccurrences(of: " ", with: "-")
    }

    private var isDefault: Bool {
        service.icon == service.kind.defaultIcon
            && service.symbolName == service.kind.symbolName
            && service.colorHex == service.kind.colorHex
    }

    var body: some View {
        Section {
            Picker("Icône", selection: Binding(get: { mode }, set: select)) {
                Text("Officielle").tag(Mode.official)
                Text("Symbole").tag(Mode.symbol)
                Text("Image").tag(Mode.image)
            }
            .pickerStyle(.segmented)

            switch mode {
            case .official: officialRows
            case .symbol: symbolRows
            case .image: imageRows
            }

            ColorPicker("Couleur", selection: Binding(
                get: { service.color },
                set: { color in
                    if let hex = color.hexString { store.update(service.id) { $0.colorHex = hex } }
                }
            ), supportsOpacity: false)

            HStack {
                Spacer()
                Button("Icône et couleur par défaut", action: resetToDefault)
                    .disabled(isDefault)
            }
        } header: {
            Text("Apparence")
        } footer: {
            Text("La couleur sert à la surbrillance de l'onglet et au fil de chargement, ainsi qu'au fond du symbole.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { slug = currentSlug }
        .onChange(of: service.icon) { slug = currentSlug }
    }

    // MARK: - Icône officielle

    @ViewBuilder private var officialRows: some View {
        HStack {
            TextField("Nom de l'icône", text: $slug, prompt: Text(verbatim: suggestedSlug))
                .font(.body.monospaced())
                .onSubmit(applySlug)
            if DashboardIcons.clean(slug) != currentSlug && !DashboardIcons.clean(slug).isEmpty {
                Button("Appliquer", action: applySlug)
            }
            Button("Parcourir…") { browsing = true }
                .popover(isPresented: $browsing, arrowEdge: .trailing) {
                    DashboardIconBrowser(initialQuery: slug.isEmpty ? suggestedSlug : slug) { name in
                        browsing = false
                        slug = name
                        store.update(service.id) { $0.icon = .dashboard(slug: name) }
                    }
                    .environment(library)
                }
        }
        let key = library.key(for: service.icon, dark: colorScheme == .dark)
        if library.hasFailed(key) {
            Label("Icône introuvable : le symbole est affiché à la place.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 4) {
                Text("Icônes de")
                Link(destination: DashboardIcons.projectURL) { Text(verbatim: "Dashboard Icons") }
                Text("· téléchargées une fois, puis gardées sur le Mac. En mode sombre, la variante claire est utilisée quand elle existe.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Symbole

    @ViewBuilder private var symbolRows: some View {
        HStack {
            TextField("Symbole", text: store.binding(service.id, \.symbolName, fallback: ""))
                .font(.body.monospaced())
            SymbolTile(symbol: service.resolvedSymbol, color: service.color, size: 24)
        }
        Link("Parcourir les symboles (app SF Symbols)", destination: URL(string: "https://developer.apple.com/sf-symbols/")!)
            .font(.caption)
    }

    // MARK: - Image

    @ViewBuilder private var imageRows: some View {
        HStack {
            Button("Choisir une autre image…") { chooseImage() }
            Spacer()
        }
        if let importError {
            Text(verbatim: importError)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("PNG, JPEG, HEIC, SVG… L'image est copiée dans LabPanel, réduite à 256 px : tu peux supprimer l'originale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func select(_ newMode: Mode) {
        guard newMode != mode else { return }
        importError = nil
        switch newMode {
        case .official:
            setIcon(.dashboard(slug: suggestedSlug))
        case .symbol:
            setIcon(.symbol)
        case .image:
            chooseImage()
        }
    }

    private func applySlug() {
        let clean = DashboardIcons.clean(slug)
        guard !clean.isEmpty else { return }
        slug = clean
        setIcon(.dashboard(slug: clean))
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconLibrary.importableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choisis l'icône de \(service.name)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            setIcon(try library.importImage(from: url))
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Change l'icône, et supprime l'image importée qu'elle remplace.
    private func setIcon(_ icon: IconSource) {
        let previous = service.icon
        store.update(service.id) { $0.icon = icon }
        if previous != icon { library.removeImported(previous) }
    }

    private func resetToDefault() {
        setIcon(service.kind.defaultIcon)
        store.update(service.id) {
            $0.symbolName = $0.kind.symbolName
            $0.colorHex = $0.kind.colorHex
        }
        importError = nil
    }
}

/// Recherche dans les icônes de Dashboard Icons.
struct DashboardIconBrowser: View {
    let initialQuery: String
    let onPick: (String) -> Void

    @Environment(IconLibrary.self) private var library
    @State private var query = ""

    private var results: [String] { DashboardIcons.search(query, in: library.catalog) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Rechercher une icône", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            Group {
                if library.catalog.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Téléchargement de la liste des icônes…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text("Aucune icône ne correspond.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(results, id: \.self) { name in
                                IconCell(name: name) { onPick(name) }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(height: 340)
            Divider()
            HStack {
                Link(destination: DashboardIcons.projectURL) {
                    Text(verbatim: "dashboardicons.com")
                }
                Spacer()
                Text("\(library.catalog.count) icônes")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(10)
        }
        .frame(width: 440)
        .onAppear {
            query = initialQuery
            library.refreshCatalogIfNeeded()
        }
    }
}

private struct IconCell: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AsyncImage(url: DashboardIcons.pngURL(name)) { image in
                    image.resizable().interpolation(.high).scaledToFit()
                } placeholder: {
                    ProgressView().controlSize(.small)
                }
                .frame(width: 40, height: 40)
                Text(verbatim: name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
    }
}
