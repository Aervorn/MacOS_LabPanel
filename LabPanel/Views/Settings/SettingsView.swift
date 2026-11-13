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
        .frame(width: 780, height: 600)
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
    @Environment(IconLibrary.self) private var icons
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
                Picker("Onglets", selection: Binding(
                    get: { preferences.navigationStyle },
                    set: { preferences.navigationStyle = $0 }
                )) {
                    ForEach(NavigationStyle.allCases) { style in
                        Text(verbatim: style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                switch preferences.navigationStyle {
                case .capsule:
                    Toggle("Afficher le nom de tous les onglets", isOn: Binding(
                        get: { preferences.showsAllTabNames },
                        set: { preferences.showsAllTabNames = $0 }
                    ))
                case .dock:
                    Toggle("Masquer le dock automatiquement", isOn: Binding(
                        get: { preferences.dockAutoHides },
                        set: { preferences.dockAutoHides = $0 }
                    ))
                }
            } header: {
                Text("Navigation")
            } footer: {
                Group {
                    switch preferences.navigationStyle {
                    case .capsule:
                        Text("Par défaut, seul l'onglet ouvert affiche son nom ; les noms de tous les onglets s'affichent si la fenêtre est assez large.")
                    case .dock:
                        Text("Masqué, le dock apparaît quand le pointeur touche le bas de la fenêtre, et un instant quand tu changes d'onglet. Toujours affiché, la page lui laisse sa place.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                ShortcutRecorder(
                    "Sélecteur rapide",
                    shortcut: Binding(
                        get: { preferences.quickSwitcherShortcut },
                        set: { preferences.quickSwitcherShortcut = $0 }
                    ),
                    defaultShortcut: .quickSwitcherDefault
                )
            } header: {
                Text("Raccourci clavier")
            } footer: {
                Text("Ouvre le sélecteur rapide, pour aller à un service ou lancer une action. Si une page utilise déjà ce raccourci (⌘K dans Dockhand, par exemple), choisis-en un autre ou aucun : la touche reviendra à la page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Langue", selection: Binding(
                    get: { preferences.language },
                    set: { preferences.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.label).tag(language)
                    }
                }
                if preferences.needsRelaunch {
                    HStack {
                        Label("La nouvelle langue s'appliquera au prochain lancement.", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relancer LabPanel") { AppPreferences.relaunch() }
                    }
                }
            } footer: {
                Text("Pour l'interface de LabPanel. Les pages des services gardent leur propre réglage de langue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Décharger les onglets inactifs", selection: Binding(
                    get: { preferences.unloadDelay },
                    set: { preferences.unloadDelay = $0 }
                )) {
                    ForEach(UnloadDelay.allCases) { delay in
                        Text(verbatim: delay.label).tag(delay)
                    }
                }
            } header: {
                Text("Mémoire")
            } footer: {
                Text("Un onglet déchargé libère sa mémoire et apparaît atténué ; il se rouvre à la même page quand tu y reviens. Tu restes connecté tant que le service n'a pas expiré ta session. Si le Mac manque de mémoire, les onglets en arrière-plan sont déchargés aussitôt. Chaque service peut en être exempté dans ses réglages.")
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
                store.services.forEach {
                    icons.removeImported($0.icon)
                    CredentialStore.delete($0.id)
                }
                store.resetToDefaults()
                Task { for id in ids { await browser.forgetData(for: id) } }
            }
        } message: {
            Text("Les adresses, l'ordre des onglets, les services ajoutés et les identifiants enregistrés sont perdus.")
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
