import AppKit
import SwiftUI

/// Liste des services (glisser pour réordonner les onglets) et fiche du service choisi.
struct ServicesSettings: View {
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(IconLibrary.self) private var icons
    @State private var removing: Service?

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $store.editingID) {
                    ForEach(store.services) { service in
                        ServiceRow(service: service).tag(service.id)
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 2) {
                    Menu {
                        ForEach(ServiceKind.allCases) { kind in
                            Button {
                                store.editingID = store.add(kind).id
                            } label: {
                                if kind == .custom {
                                    Label("Service personnalisé", systemImage: kind.symbolName)
                                } else {
                                    Label {
                                        Text(verbatim: kind.productName)
                                    } icon: {
                                        Image(systemName: kind.symbolName)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuIndicator(.hidden)
                    .help("Ajouter un service")

                    Button {
                        removing = store.service(store.editingID)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(store.editingID == nil)
                    .help("Supprimer le service")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 240)

            Divider()

            Group {
                if let id = store.editingID, store.service(id) != nil {
                    ServiceEditor(id: id).id(id)
                } else {
                    Text("Choisis un service, ou ajoute-en un avec +.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if store.editingID == nil { store.editingID = store.selected?.id ?? store.services.first?.id }
        }
        .confirmationDialog(
            "Supprimer \(removing?.name ?? String()) ?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { service in
            Button("Supprimer", role: .destructive) {
                store.remove(service.id)
                icons.removeImported(service.icon)
                CredentialStore.delete(service.id)
                Task { await browser.forgetData(for: service.id) }
            }
        } message: { _ in
            Text("Son onglet disparaît, et ses cookies, données de connexion et identifiant enregistré sont effacés.")
        }
    }
}

private struct ServiceRow: View {
    let service: Service

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(service: service, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: service.name)
                    .lineLimit(1)
                if let url = service.url {
                    Text(verbatim: url.host(percentEncoded: false) ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Adresse à saisir")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            if !service.isVisible {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.tertiary)
                    .help("Onglet masqué")
            }
        }
        .opacity(service.isVisible ? 1 : 0.55)
        .padding(.vertical, 2)
    }
}

/// Fiche d'un service.
private struct ServiceEditor: View {
    let id: UUID
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @Environment(AvailabilityMonitor.self) private var monitor
    @State private var address = ""
    @State private var confirmingForget = false
    @State private var forgotten = false

    private var service: Service? { store.service(id) }

    /// L'adresse n'est appliquée qu'à la validation : sinon chaque frappe rechargerait la page.
    private var pendingURL: URL? {
        ServiceURL.normalize(address, preferHTTPS: service?.kind.prefersHTTPS ?? false)
    }
    private var addressChanged: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines) != service?.address
    }

    var body: some View {
        if let service {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ServiceIcon(service: service, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: service.name).font(.title3.weight(.semibold))
                            if service.isConfigured {
                                Label {
                                    Text(monitor.availability(of: id).label)
                                } icon: {
                                    StatusDot(availability: monitor.availability(of: id))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("Nom", text: store.binding(id, \.name, fallback: ""))
                    TextField("Adresse", text: $address, prompt: Text(verbatim: service.kind.addressExample))
                        .onSubmit(applyAddress)
                    if addressChanged {
                        HStack {
                            if address.isEmpty || pendingURL != nil {
                                Text(verbatim: pendingURL.map { "→ \($0.absoluteString)" } ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Adresse non valable : http(s)://hôte[:port]")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                            Button("Annuler") { address = service.address }
                            Button("Appliquer", action: applyAddress)
                                .keyboardShortcut(.defaultAction)
                                .disabled(!address.isEmpty && pendingURL == nil)
                        }
                    }
                    Toggle("Afficher l'onglet", isOn: store.binding(id, \.isVisible, fallback: true))
                }

                IconSettingsSection(service: service)

                Section {
                    Toggle("Accepter un certificat auto-signé", isOn: store.binding(id, \.allowsSelfSignedCertificate, fallback: false))
                    Toggle("Ne jamais décharger cet onglet", isOn: store.binding(id, \.keepsAlive, fallback: false))
                    LabeledContent("Zoom de la page") {
                        HStack {
                            Text(service.zoom, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("Zoom", value: store.binding(id, \.zoom, fallback: 1), in: 0.5...2, step: 0.1)
                                .labelsHidden()
                        }
                    }
                    HStack {
                        Button("Effacer les cookies et les données…", role: .destructive) { confirmingForget = true }
                        if forgotten {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Connexion")
                } footer: {
                    Text("Le certificat n'est accepté que pour l'hôte de ce service. Garder l'onglet chargé évite de devoir se reconnecter aux services qui ferment la session quand leur page est fermée, comme Proxmox. Chaque service garde ses propres cookies : effacer ceux-ci te déconnecte de ce service seulement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AutofillSettingsSection(service: service)
            }
            .formStyle(.grouped)
            .onAppear { address = service.address }
            .confirmationDialog("Effacer les données de \(service.name) ?", isPresented: $confirmingForget) {
                Button("Effacer", role: .destructive) {
                    Task {
                        await browser.forgetData(for: id)
                        forgotten = true
                        if let service = store.service(id), service.isVisible { browser.prepare(service) }
                    }
                }
            } message: {
                Text("Tu seras déconnecté de ce service ; la page sera rechargée.")
            }
        }
    }

    private func applyAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || pendingURL != nil else { return }
        address = trimmed
        store.update(id) { $0.address = trimmed }
    }
}
