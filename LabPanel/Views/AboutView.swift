import AppKit
import SwiftUI

/// Fenêtre « À propos de LabPanel », dans le même style que celles de Flux et Vestora.
struct AboutView: View {
    static let windowID = "about"
    static let repositoryURL = URL(string: "https://github.com/Aervorn/MacOS_LabPanel")!
    static let sparkleURL = URL(string: "https://sparkle-project.org")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.top, 8)

            Text(verbatim: "LabPanel")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 6)
            Text(verbatim: version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("Les interfaces web de ton homelab réunies dans une seule fenêtre, un onglet par service.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Divider().padding(.vertical, 16)

            VStack(spacing: 6) {
                Text("Créé par Aervorn, avec l'aide de Claude.")
                HStack(spacing: 4) {
                    Text("Mises à jour :")
                    Link("Sparkle", destination: Self.sparkleURL)
                    Text(verbatim: "(MIT)")
                }
                Text("Sans lien avec les éditeurs des services affichés.")
                    .padding(.top, 4)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Link(destination: Self.repositoryURL) {
                Label("Code source sur GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.callout)
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .frame(width: 360)
    }
}

/// Entrée « À propos de LabPanel » du menu de l'application.
struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("À propos de LabPanel") { openWindow(id: AboutView.windowID) }
    }
}
