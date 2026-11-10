import SwiftUI

/// Section « Connexion automatique » de la fiche d'un service : identifiant rangé dans le trousseau.
struct AutofillSettingsSection: View {
    let service: Service
    @Environment(ServiceStore.self) private var store
    @Environment(Browser.self) private var browser

    /// Nom d'utilisateur enregistré (`nil` : rien dans le trousseau).
    @State private var storedUsername: String?
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var saved = false

    private var hasStored: Bool { storedUsername != nil }
    private var canSave: Bool {
        if hasStored { return username != storedUsername || !password.isEmpty }
        return !password.isEmpty
    }

    var body: some View {
        Section {
            Picker("Remplissage", selection: store.binding(service.id, \.autoLogin, fallback: .off)) {
                Text("Désactivé").tag(AutoLogin.off)
                Text("Remplir").tag(AutoLogin.fill)
                Text("Remplir et valider").tag(AutoLogin.fillAndSubmit)
            }

            TextField("Identifiant", text: $username)
                .textContentType(.username)
            SecureField("Mot de passe", text: $password, prompt: hasStored ? Text("Inchangé") : nil)
                .textContentType(.password)
                .onSubmit(save)

            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if saved {
                    Label("Enregistré dans le trousseau", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if hasStored {
                    Label("Rangé dans le trousseau", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasStored {
                    Button("Supprimer", role: .destructive, action: remove)
                }
                Button("Enregistrer", action: save)
                    .disabled(!canSave)
            }
            .font(.callout)
        } header: {
            Text("Connexion automatique")
        } footer: {
            Text("L'identifiant est rangé dans le trousseau de ton Mac, et n'est donné qu'aux pages de l'hôte de ce service. Après un échec, le formulaire n'est pas revalidé avant deux minutes, pour ne pas bloquer ton compte. Le réglage s'applique au prochain chargement de la page ; « Remplir l'identifiant » (⌥⌘L) remplit la page affichée à tout moment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onChange(of: service.id) { load() }
        .onChange(of: username) { saved = false; error = nil }
        .onChange(of: password) { saved = false; error = nil }
    }

    private func load() {
        storedUsername = CredentialStore.username(for: service.id)
        username = storedUsername ?? ""
        password = ""
        error = nil
        saved = false
    }

    private func save() {
        guard canSave else { return }
        do {
            try CredentialStore.save(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password.isEmpty ? nil : password,
                for: service.id, label: service.name
            )
            storedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            username = storedUsername ?? ""
            password = ""
            saved = true
            error = nil
            browser.session(service.id)?.credentialsChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        CredentialStore.delete(service.id)
        browser.session(service.id)?.credentialsChanged()
        store.update(service.id) { $0.autoLogin = .off }
        load()
    }
}
