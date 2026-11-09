import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        if let c = HexColor.components(hex) {
            self.init(.sRGB, red: c.red, green: c.green, blue: c.blue)
        } else {
            self = .gray
        }
    }

    /// `#RRGGBB` en sRGB, pour l'enregistrer.
    var hexString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return HexColor.string(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

extension Service {
    var color: Color { Color(hex: colorHex) }

    /// Le symbole choisi s'il existe, sinon celui du type.
    var resolvedSymbol: String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil ? symbolName : kind.symbolName
    }
}

/// Icône d'un service : son symbole, blanc, sur une pastille arrondie à sa couleur.
struct ServiceIcon: View {
    let service: Service
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(service.color.gradient)
            .overlay {
                Image(systemName: service.resolvedSymbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
    }
}

/// Pastille de disponibilité : verte, orange (certificat refusé), rouge ou grise.
struct StatusDot: View {
    let availability: Availability
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5).padding(-1.5))
            .opacity(availability == .unknown ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: availability)
    }

    private var color: Color {
        switch availability {
        case .unknown: .gray
        case .online: .green
        case .untrustedCertificate: .orange
        case .offline: .red
        }
    }
}

extension Availability {
    var label: String {
        switch self {
        case .unknown: String(localized: "Disponibilité inconnue")
        case .online(let ms): String(localized: "En ligne · \(ms) ms")
        case .untrustedCertificate: String(localized: "Certificat non reconnu")
        case .offline: String(localized: "Ne répond pas")
        }
    }
}

/// Ouvre une adresse dans le navigateur par défaut, ou la copie.
@MainActor
enum URLActions {
    static func openInBrowser(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    static func copy(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}
