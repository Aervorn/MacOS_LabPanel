import AppKit
import SwiftUI

/// Réglages (⌘,) : services, apparence et mises à jour.
struct SettingsView: View {
    @Environment(ServiceStore.self) private var store
    @State private var tab = SettingsTab.services

    enum SettingsTab: Hashable { case services, general, updates }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Services", systemImage: "square.grid.2x2", value: .services) {
                ServicesSettings()
            }
            Tab("Général", systemImage: "gearshape", value: .general) {
                GeneralSettings()
            }
            Tab("Mises à jour", systemImage: "arrow.down.app", value: .updates) {
                UpdatesSettings()
            }
        }
        .frame(width: 760, height: 520)
        // « Modifier… » depuis un onglet : on arrive sur la page des services.
        .onChange(of: store.editingID, initial: true) { _, id in
            if id != nil { tab = .services }
        }
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                Picker("Apparence", selection: Binding(
                    get: { preferences.appearance },
                    set: { preferences.appearance = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Les pages qui le permettent (Home Assistant, AdGuard, Zigbee2MQTT…) suivent aussi le mode clair ou sombre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Vérifier la disponibilité des services", isOn: Binding(
                    get: { preferences.checksAvailability },
                    set: { preferences.checksAvailability = $0 }
                ))
            } footer: {
                Text("Une requête par minute vers chaque service affiché, pour la pastille de son onglet : verte s'il répond, orange si son certificat n'est pas accepté, rouge s'il ne répond pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Rétablir les services par défaut…", role: .destructive) { confirmingReset = true }
            } footer: {
                Text("Remet les neuf services de départ, sans adresse. Les connexions déjà ouvertes sont oubliées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Rétablir les services par défaut ?", isPresented: $confirmingReset) {
            Button("Rétablir", role: .destructive) {
                let ids = store.services.map(\.id)
                store.resetToDefaults()
                Task { for id in ids { await browser.forgetData(for: id) } }
            }
        } message: {
            Text("Les adresses, l'ordre des onglets et les services ajoutés sont perdus.")
        }
    }
}

// MARK: - Mises à jour

private struct UpdatesSettings: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Version installée") {
                    Text(updater.currentVersion).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if updater.isEnabled {
                    Toggle("Rechercher automatiquement chaque jour", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    LabeledContent("Dernière recherche") {
                        if let date = updater.lastCheck {
                            Text(date, format: .dateTime.day().month().year().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("jamais").foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if updater.isEnabled {
                    Text("Une nouvelle version est proposée avec ses notes ; rien ne s'installe sans ton accord.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Désactivées dans les builds de développement lancés depuis Xcode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if updater.isEnabled {
                Section {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Rechercher maintenant", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }
}
