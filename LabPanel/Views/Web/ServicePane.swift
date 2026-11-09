import AppKit
import SwiftUI

/// Contenu d'un onglet : la page du service, ou l'écran qui la remplace (adresse à saisir,
/// connexion en cours, erreur), et le fil de progression du chargement.
struct ServicePane: View {
    let service: Service
    @Environment(Browser.self) private var browser

    var body: some View {
        let session = browser.session(service.id)
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !service.isConfigured {
                SetupView(service: service)
            } else if let session {
                WebContainer(webView: session.webView)
                if let failure = session.failure {
                    FailureView(service: service, session: session, failure: failure)
                        .transition(.opacity)
                } else if !session.hasLoadedOnce {
                    LoadingView(service: service)
                        .transition(.opacity)
                }
            } else {
                LoadingView(service: service)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session?.hasLoadedOnce)
        .animation(.easeInOut(duration: 0.2), value: session?.failure)
        .overlay(alignment: .top) {
            if let session, session.isLoading {
                ProgressLine(progress: session.progress, color: service.color)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: session?.isLoading)
    }
}

/// Fil fin à la couleur du service, sous la barre d'onglets.
private struct ProgressLine: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(proxy.size.width * progress, 24))
                .shadow(color: color.opacity(0.6), radius: 3)
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(height: 2.5)
        .allowsHitTesting(false)
    }
}

/// Pendant le premier chargement d'un service.
private struct LoadingView: View {
    let service: Service
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 16) {
            ServiceIcon(service: service, size: 64)
                .shadow(color: service.color.opacity(pulsing ? 0.55 : 0.15), radius: pulsing ? 22 : 8)
                .scaleEffect(pulsing ? 1.04 : 1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulsing)
            Text("Connexion à \(service.name)…")
                .font(.title3.weight(.medium))
            if let url = service.url {
                Text(verbatim: url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { pulsing = true }
    }
}

/// Premier passage sur un onglet dont l'adresse n'est pas encore connue : on la saisit ici.
private struct SetupView: View {
    let service: Service
    @Environment(ServiceStore.self) private var store
    @State private var address = ""
    @State private var acceptsSelfSigned = false
    @FocusState private var focused: Bool

    private var normalized: URL? { ServiceURL.normalize(address, preferHTTPS: service.kind.prefersHTTPS) }
    private var showsInvalid: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && normalized == nil }

    var body: some View {
        VStack(spacing: 18) {
            ServiceIcon(service: service, size: 72)
                .shadow(color: service.color.opacity(0.35), radius: 16, y: 6)
            VStack(spacing: 6) {
                Text("Où se trouve \(service.name) ?")
                    .font(.title2.weight(.semibold))
                Text("Saisis l'adresse de son interface web, telle que tu l'ouvres dans ton navigateur.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField("Adresse", text: $address, prompt: Text(verbatim: service.kind.addressExample))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .font(.body.monospaced())
                    .focused($focused)
                    .onSubmit(save)
                if showsInvalid {
                    Label("Adresse non valable : http(s)://hôte[:port]", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let normalized, normalized.absoluteString != address {
                    Text("Sera ouverte comme \(normalized.absoluteString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Accepter son certificat s'il est auto-signé", isOn: $acceptsSelfSigned)
                    .font(.callout)
            }
            .frame(width: 380)
            Button(action: save) {
                Text("Ouvrir \(service.name)")
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(service.color)
            .controlSize(.large)
            .disabled(normalized == nil)
            .keyboardShortcut(.defaultAction)

            Text("Tu pourras la modifier plus tard dans les Réglages.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            address = service.address
            acceptsSelfSigned = service.allowsSelfSignedCertificate
            focused = true
        }
        .onChange(of: service.id) {
            address = service.address
            acceptsSelfSigned = service.allowsSelfSignedCertificate
        }
    }

    private func save() {
        guard normalized != nil else { return }
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(service.id) {
            $0.address = address
            $0.allowsSelfSignedCertificate = acceptsSelfSigned
        }
    }
}

/// La page n'a pas pu être chargée.
private struct FailureView: View {
    let service: Service
    let session: WebSession
    let failure: LoadFailure
    @Environment(ServiceStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    private var host: String { failure.url?.host ?? service.url?.host ?? "" }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: failure.isCertificate ? "lock.trianglebadge.exclamationmark" : "network.slash")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(failure.isCertificate ? .orange : service.color)
                .symbolRenderingMode(.hierarchical)
            Group {
                if failure.isCertificate {
                    Text("Certificat non reconnu")
                } else {
                    Text("Impossible de joindre \(service.name)")
                }
            }
            .font(.title2.weight(.semibold))
            Text(verbatim: failure.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if let url = failure.url {
                Text(verbatim: url.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if failure.isCertificate {
                Text("Les interfaces de Proxmox, DSM ou UniFi utilisent souvent un certificat auto-signé. Si tu reconnais cette adresse, tu peux lui faire confiance pour ce service uniquement.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 10) {
                if failure.isCertificate && !service.allowsSelfSignedCertificate {
                    Button("Faire confiance à \(host)") {
                        store.update(service.id) { $0.allowsSelfSignedCertificate = true }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                }
                Button("Réessayer") { session.reload() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.defaultAction)
                Button("Modifier l'adresse…") {
                    store.editingID = service.id
                    openSettings()
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
