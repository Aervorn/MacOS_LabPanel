import Foundation

/// Type de service, qui donne un nom, une icône (SF Symbol), une couleur et des habitudes réseau par défaut.
///
/// Tout reste modifiable service par service : le type ne sert qu'à pré-remplir.
enum ServiceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case unifi
    case dsm
    case proxmox
    case dockhand
    case adguard
    case npm
    case nut
    case homeAssistant
    case zigbee2mqtt
    case custom

    var id: Self { self }

    /// Nom du produit (identique dans toutes les langues, sauf pour un service personnalisé).
    var productName: String {
        switch self {
        case .unifi: "UniFi"
        case .dsm: "DSM"
        case .proxmox: "Proxmox"
        case .dockhand: "Dockhand"
        case .adguard: "AdGuard"
        case .npm: "NPM"
        case .nut: "NUT"
        case .homeAssistant: "Home Assistant"
        case .zigbee2mqtt: "Zigbee2MQTT"
        case .custom: "Service"
        }
    }

    var symbolName: String {
        switch self {
        case .unifi: "wifi.router"
        case .dsm: "externaldrive.connected.to.line.below"
        case .proxmox: "server.rack"
        case .dockhand: "shippingbox"
        case .adguard: "shield.lefthalf.filled"
        case .npm: "arrow.triangle.branch"
        case .nut: "bolt.batteryblock"
        case .homeAssistant: "house"
        case .zigbee2mqtt: "dot.radiowaves.left.and.right"
        case .custom: "globe"
        }
    }

    /// Couleur de l'onglet, proche de celle de la marque.
    var colorHex: String {
        switch self {
        case .unifi: "#006FFF"
        case .dsm: "#4A5BD4"
        case .proxmox: "#E57000"
        case .dockhand: "#1D9BF0"
        case .adguard: "#3DAA5C"
        case .npm: "#F15833"
        case .nut: "#9B5DE5"
        case .homeAssistant: "#18BCF2"
        case .zigbee2mqtt: "#E8B100"
        case .custom: "#6B7280"
        }
    }

    /// Schéma ajouté quand l'adresse saisie n'en a pas.
    var prefersHTTPS: Bool {
        switch self {
        case .unifi, .dsm, .proxmox: true
        default: false
        }
    }

    /// Ces interfaces arrivent avec un certificat auto-signé : on l'accepte d'office pour elles.
    var usuallySelfSigned: Bool { prefersHTTPS }

    /// Exemple d'adresse, affiché dans le champ vide.
    var addressExample: String {
        switch self {
        case .unifi: "https://192.168.1.1"
        case .dsm: "https://nas.local:5001"
        case .proxmox: "https://pve.local:8006"
        case .dockhand: "http://nas.local:3000"
        case .adguard: "http://192.168.1.2:3000"
        case .npm: "http://nas.local:81"
        case .nut: "http://nas.local:8080"
        case .homeAssistant: "http://homeassistant.local:8123"
        case .zigbee2mqtt: "http://nas.local:8080"
        case .custom: "http://192.168.1.10:8080"
        }
    }
}

/// Un service du homelab, affiché dans un onglet.
struct Service: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: ServiceKind
    var name: String
    /// Adresse telle que saisie (le schéma est complété par `url`).
    var address: String
    var symbolName: String
    var colorHex: String
    var isVisible: Bool
    var allowsSelfSignedCertificate: Bool
    /// Zoom de la page (1 = 100 %).
    var zoom: Double

    init(id: UUID = UUID(), kind: ServiceKind, name: String? = nil, address: String = "",
         symbolName: String? = nil, colorHex: String? = nil, isVisible: Bool = true,
         allowsSelfSignedCertificate: Bool? = nil, zoom: Double = 1) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.productName
        self.address = address
        self.symbolName = symbolName ?? kind.symbolName
        self.colorHex = colorHex ?? kind.colorHex
        self.isVisible = isVisible
        self.allowsSelfSignedCertificate = allowsSelfSignedCertificate ?? kind.usuallySelfSigned
        self.zoom = zoom
    }

    /// Adresse complète, ou `nil` si elle n'est pas encore renseignée ou pas valable.
    var url: URL? { ServiceURL.normalize(address, preferHTTPS: kind.prefersHTTPS) }

    var isConfigured: Bool { url != nil }

    /// Les neuf services de départ, sans adresse.
    static var defaults: [Service] {
        ServiceKind.allCases.filter { $0 != .custom }.map { Service(kind: $0) }
    }

    // Décodage tolérant : une clé ajoutée dans une version future ne casse pas les réglages existants.
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, address, symbolName, colorHex, isVisible, allowsSelfSignedCertificate, zoom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(ServiceKind.self, forKey: .kind)) ?? .custom
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: kind,
            name: try c.decodeIfPresent(String.self, forKey: .name),
            address: try c.decodeIfPresent(String.self, forKey: .address) ?? "",
            symbolName: try c.decodeIfPresent(String.self, forKey: .symbolName),
            colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex),
            isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            allowsSelfSignedCertificate: try c.decodeIfPresent(Bool.self, forKey: .allowsSelfSignedCertificate),
            zoom: try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        )
    }
}

/// Mise en forme des adresses saisies.
enum ServiceURL {
    /// Ports habituellement servis en HTTPS dans un homelab.
    static let httpsPorts: Set<Int> = [443, 5001, 8006, 8443, 9443]

    /// Complète l'adresse saisie : `pve.local:8006` → `https://pve.local:8006`.
    /// Rend `nil` pour une adresse vide, sans hôte, ou d'un autre schéma que http(s).
    static func normalize(_ input: String, preferHTTPS: Bool) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if !text.contains("://") {
            let scheme = preferHTTPS || usesHTTPSPort(text) ? "https" : "http"
            text = "\(scheme)://\(text)"
        }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    private static func usesHTTPSPort(_ text: String) -> Bool {
        guard let port = URLComponents(string: "http://\(text)")?.port else { return false }
        return httpsPorts.contains(port)
    }
}

/// Couleur `#RRGGBB` décomposée, sans dépendre d'AppKit.
enum HexColor {
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
