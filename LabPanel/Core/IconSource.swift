import Foundation

/// D'où vient l'icône d'un service.
enum IconSource: Codable, Hashable, Sendable {
    /// Le symbole SF du service, blanc sur une pastille à sa couleur.
    case symbol
    /// Une icône officielle de Dashboard Icons (github.com/homarr-labs/dashboard-icons), par son nom.
    case dashboard(slug: String)
    /// Une image choisie sur le Mac, copiée dans le dossier de l'app sous ce nom de fichier.
    case file(name: String)
}

/// Icône à afficher, une fois choisie la variante claire ou sombre : sert de clé au cache.
enum IconKey: Hashable, Sendable {
    case dashboard(String)
    case file(String)

    /// Variante claire ou sombre : en mode sombre, Dashboard Icons propose parfois une version
    /// `-light` (logo clair pour fond sombre), et en mode clair parfois une version `-dark`.
    static func resolve(_ source: IconSource, dark: Bool, available: Set<String>) -> IconKey? {
        switch source {
        case .symbol:
            return nil
        case .file(let name):
            return .file(name)
        case .dashboard(let slug):
            let slug = DashboardIcons.clean(slug)
            guard !slug.isEmpty else { return nil }
            let variant = dark ? "\(slug)-light" : "\(slug)-dark"
            return .dashboard(available.contains(variant) ? variant : slug)
        }
    }
}

/// Adresses du dépôt Dashboard Icons, servi par jsDelivr.
enum DashboardIcons {
    static let base = URL(string: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons")!
    static let projectURL = URL(string: "https://dashboardicons.com")!

    static func pngURL(_ slug: String) -> URL {
        base.appending(path: "png").appending(path: "\(clean(slug)).png")
    }

    /// Liste de toutes les icônes : `{"png": ["proxmox.png", …], "svg": […], …}`.
    static let treeURL = base.appending(path: "tree.json")

    /// `Proxmox.PNG ` → `proxmox` : on accepte un nom de fichier collé tel quel.
    static func clean(_ slug: String) -> String {
        var text = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for ext in [".png", ".svg", ".webp"] where text.hasSuffix(ext) {
            text.removeLast(ext.count)
        }
        return text
    }

    /// Noms des icônes PNG à partir de tree.json.
    static func names(fromTree data: Data) -> [String] {
        guard let tree = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = tree["png"] as? [String]
        else { return [] }
        return files.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
    }

    /// Recherche : les noms qui commencent par le texte d'abord, puis ceux qui le contiennent.
    static func search(_ query: String, in names: [String], limit: Int = 60) -> [String] {
        let query = clean(query).replacingOccurrences(of: " ", with: "-")
        guard !query.isEmpty else { return Array(names.prefix(limit)) }
        let prefix = names.filter { $0.hasPrefix(query) }
        let contains = names.filter { !$0.hasPrefix(query) && $0.contains(query) }
        return Array((prefix + contains).prefix(limit))
    }
}
