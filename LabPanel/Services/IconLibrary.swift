import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Icônes des services : téléchargées une fois depuis Dashboard Icons puis gardées sur disque,
/// ou importées depuis un fichier. Rangées dans ~/Library/Application Support/<id de l'app>/Icons.
@MainActor
@Observable
final class IconLibrary {
    private(set) var images: [IconKey: NSImage] = [:]
    /// Noms des icônes de Dashboard Icons (pour la recherche et les variantes claire/sombre).
    private(set) var catalog: [String] = []
    private(set) var catalogSet: Set<String> = []

    @ObservationIgnored private var failed: Set<IconKey> = []
    @ObservationIgnored private var inFlight: Set<IconKey> = []
    @ObservationIgnored private var catalogTask: Task<Void, Never>?

    /// Taille à laquelle les icônes sont gardées (assez pour l'écran d'accueil d'un onglet en Retina).
    static let storedSize: CGFloat = 256
    /// La liste des icônes est retéléchargée au plus une fois par semaine.
    static let catalogLifetime: TimeInterval = 7 * 24 * 3600

    let folder: URL

    init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.aervorn.labpanel"
        self.folder = folder ?? support.appending(path: bundleID).appending(path: "Icons")
        try? FileManager.default.createDirectory(at: dashboardFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: customFolder, withIntermediateDirectories: true)
        loadCachedCatalog()
    }

    private var dashboardFolder: URL { folder.appending(path: "dashboard") }
    private var customFolder: URL { folder.appending(path: "custom") }
    private var catalogFile: URL { folder.appending(path: "tree.json") }

    // MARK: - Lecture

    func key(for source: IconSource, dark: Bool) -> IconKey? {
        IconKey.resolve(source, dark: dark, available: catalogSet)
    }

    func image(_ key: IconKey?) -> NSImage? {
        guard let key else { return nil }
        return images[key]
    }

    func hasFailed(_ key: IconKey?) -> Bool {
        guard let key else { return false }
        return failed.contains(key)
    }

    // MARK: - Chargement

    /// Charge l'icône depuis le disque, sinon la télécharge. Sans effet si elle est déjà là.
    func load(_ key: IconKey) async {
        guard images[key] == nil, !failed.contains(key), !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let file = localFile(for: key)
        if let image = NSImage(contentsOf: file) {
            images[key] = image
            return
        }
        guard case .dashboard(let slug) = key else {
            failed.insert(key)
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: DashboardIcons.pngURL(slug))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.isValid
            else {
                failed.insert(key)
                return
            }
            try? data.write(to: file, options: .atomic)
            images[key] = image
        } catch {
            // Hors ligne : on réessaiera au prochain affichage, sans marquer l'icône comme introuvable.
        }
    }

    private func localFile(for key: IconKey) -> URL {
        switch key {
        case .dashboard(let slug): dashboardFolder.appending(path: "\(slug).png")
        case .file(let name): customFolder.appending(path: name)
        }
    }

    /// Retélécharge les icônes officielles (après une mise à jour d'un logo, par exemple).
    func clearDownloadedIcons() {
        try? FileManager.default.removeItem(at: dashboardFolder)
        try? FileManager.default.createDirectory(at: dashboardFolder, withIntermediateDirectories: true)
        images = images.filter { if case .file = $0.key { true } else { false } }
        failed.removeAll()
    }

    // MARK: - Liste des icônes

    private func loadCachedCatalog() {
        guard let data = try? Data(contentsOf: catalogFile) else { return }
        setCatalog(DashboardIcons.names(fromTree: data))
    }

    private func setCatalog(_ names: [String]) {
        guard !names.isEmpty else { return }
        catalog = names
        catalogSet = Set(names)
    }

    /// Télécharge la liste des icônes si elle manque ou date de plus d'une semaine.
    func refreshCatalogIfNeeded() {
        let modified = (try? catalogFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let isFresh = modified.map { Date.now.timeIntervalSince($0) < Self.catalogLifetime } ?? false
        guard !(isFresh && !catalog.isEmpty), catalogTask == nil else { return }
        catalogTask = Task {
            defer { catalogTask = nil }
            guard let (data, response) = try? await URLSession.shared.data(from: DashboardIcons.treeURL),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return }
            let names = DashboardIcons.names(fromTree: data)
            guard !names.isEmpty else { return }
            try? data.write(to: catalogFile, options: .atomic)
            setCatalog(names)
        }
    }

    // MARK: - Images choisies sur le Mac

    enum ImportError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "Cette image ne peut pas être lue.")
        }
    }

    /// Types acceptés par le sélecteur de fichier.
    static let importableTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .svg, .icns, .webP]

    /// Copie l'image dans le dossier de l'app, réduite à 256 px, et rend la source à enregistrer.
    func importImage(from url: URL) throws -> IconSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url), image.isValid, let png = Self.squarePNG(image) else {
            throw ImportError.unreadable
        }
        let name = "\(UUID().uuidString).png"
        try png.write(to: customFolder.appending(path: name), options: .atomic)
        images[.file(name)] = NSImage(data: png)
        return .file(name: name)
    }

    /// Supprime une image importée qui ne sert plus.
    func removeImported(_ source: IconSource) {
        guard case .file(let name) = source else { return }
        try? FileManager.default.removeItem(at: customFolder.appending(path: name))
        images[.file(name)] = nil
    }

    /// L'image centrée dans un carré transparent de 256 px, en PNG.
    private static func squarePNG(_ image: NSImage) -> Data? {
        let side = Int(storedSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)

        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(storedSize / size.width, storedSize / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        let rect = NSRect(x: (storedSize - drawn.width) / 2, y: (storedSize - drawn.height) / 2,
                          width: drawn.width, height: drawn.height)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }
}
