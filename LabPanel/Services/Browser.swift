import AppKit
import Foundation
import Observation
import WebKit

/// Les pages ouvertes, une par service, créées à la première visite de l'onglet puis gardées en vie.
/// Elles survivent aussi à la fermeture de la fenêtre : la rouvrir retrouve chaque page où elle en était.
///
/// Comme dans Safari ou Chrome, une page restée longtemps en arrière-plan peut être déchargée
/// pour libérer sa mémoire : on note la page où elle en était, et on y revient au retour sur l'onglet.
/// Les cookies restent, donc la connexion aussi tant que le service ne l'a pas expirée.
@MainActor
@Observable
final class Browser {
    private(set) var sessions: [UUID: WebSession] = [:]

    /// Page où en était chaque onglet déchargé, et adresse du service à ce moment-là.
    private(set) var unloaded: [UUID: (page: URL, home: URL?)] = [:]

    /// Délai d'inactivité avant de décharger un onglet ; `nil` : jamais.
    @ObservationIgnored var unloadAfter: Duration?
    /// Dernière fois que chaque onglet a été affiché.
    @ObservationIgnored private var lastShown: [UUID: Date] = [:]
    @ObservationIgnored private var unloadLoop: Task<Void, Never>?
    @ObservationIgnored private var memoryPressure: DispatchSourceMemoryPressure?

    /// Dernier fichier téléchargé, annoncé en bas de la fenêtre.
    var lastDownload: URL?
    var downloadError: String?

    @ObservationIgnored private var popups: [PopupWindow] = []

    func session(_ id: UUID?) -> WebSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    func isUnloaded(_ id: UUID) -> Bool { unloaded[id] != nil }

    /// Crée et charge la page d'un service la première fois que son onglet est affiché,
    /// ou la recrée à la page où elle en était si elle avait été déchargée.
    func prepare(_ service: Service) {
        guard service.isConfigured else { return }
        lastShown[service.id] = .now
        if let session = sessions[service.id] {
            if session.webView.url == nil && session.failure == nil && !session.isLoading {
                session.loadHome()
            }
            return
        }
        let session = WebSession(service: service, browser: self)
        sessions[service.id] = session
        if let restore = unloaded.removeValue(forKey: service.id), restore.home == service.url {
            session.load(restore.page)
        } else {
            session.loadHome()
        }
    }

    /// À appeler quand on quitte un onglet, pour dater sa dernière utilisation.
    func noteShown(_ id: UUID?) {
        guard let id else { return }
        lastShown[id] = .now
    }

    // MARK: - Déchargement des onglets inactifs

    /// Lance la vérification périodique, et l'écoute des alertes mémoire du système.
    /// `context` donne l'onglet affiché et la liste des services au moment de la vérification.
    func startUnloading(context: @escaping @MainActor () -> (selected: UUID?, services: [Service])) {
        guard unloadLoop == nil else { return }
        unloadLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                guard let delay = self.unloadAfter else { continue }
                let (selected, services) = context()
                self.unloadInactive(olderThan: delay, selected: selected, services: services)
            }
        }

        // Le système manque de mémoire : on décharge tout ce qui n'est pas affiché, sans attendre.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.unloadAfter != nil else { return }
                let (selected, services) = context()
                self.unloadInactive(olderThan: .zero, selected: selected, services: services)
            }
        }
        source.resume()
        memoryPressure = source
    }

    func unloadInactive(olderThan delay: Duration, selected: UUID?, services: [Service]) {
        let byID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        let limit = Date.now.addingTimeInterval(-delay.timeInterval)
        for id in sessions.keys where id != selected {
            guard let service = byID[id], !service.keepsAlive else { continue }
            if (lastShown[id] ?? .distantPast) <= limit {
                unload(id)
            }
        }
    }

    /// Décharge un onglet : sa page est fermée, et sera rouverte au même endroit au retour.
    /// Les onglets qui ont une fenêtre surgissante ouverte (console…) ou une page en cours de chargement sont épargnés.
    func unload(_ id: UUID) {
        guard let session = sessions[id], !session.isLoading,
              !popups.contains(where: { $0.serviceID == id }) else { return }
        if let page = session.currentURL ?? session.service.url, session.hasLoadedOnce {
            unloaded[id] = (page, session.service.url)
        }
        close(id)
    }

    /// Répercute les Réglages sur les pages ouvertes, et ferme celles des services supprimés.
    func sync(with services: [Service]) {
        let byID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        for id in unloaded.keys where byID[id]?.url == nil {
            unloaded[id] = nil
        }
        for (id, session) in sessions {
            if let service = byID[id], service.isConfigured {
                if service != session.service { session.apply(service) }
            } else {
                close(id)
            }
        }
    }


    private func close(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.webView.stopLoading()
        session.webView.removeFromSuperview()
        popups.filter { $0.serviceID == id }.forEach { $0.window.close() }
    }

    /// Ferme la page d'un service et efface ses cookies et ses données (déconnexion complète).
    func forgetData(for id: UUID) async {
        close(id)
        unloaded[id] = nil
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: id)
        } catch {
            // Le stockage est encore utilisé par une page qui se ferme : on vide son contenu à la place.
            let store = WKWebsiteDataStore(forIdentifier: id)
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
    }

    // MARK: - Fenêtres surgissantes

    func openPopup(configuration: WKWebViewConfiguration, features: WKWindowFeatures,
                   delegate: WebDelegate, parent: NSWindow?) -> WKWebView {
        let popup = PopupWindow(configuration: configuration, features: features, delegate: delegate, parent: parent)
        popup.serviceID = delegate.session?.serviceID
        popup.onClose = { [weak self, weak popup] in
            self?.popups.removeAll { $0 === popup }
        }
        popups.append(popup)
        popup.window.makeKeyAndOrderFront(nil)
        return popup.webView
    }

    func closePopup(showing webView: WKWebView) {
        popups.first { $0.webView === webView }?.window.close()
    }
}

/// Fenêtre ouverte par une page avec window.open() (console de Proxmox, lecteur de DSM…).
@MainActor
final class PopupWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    var serviceID: UUID?
    var onClose: (() -> Void)?
    private var titleObservation: NSKeyValueObservation?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures, delegate: WebDelegate, parent: NSWindow?) {
        let width = features.width.map { CGFloat(truncating: $0) } ?? 1024
        let height = features.height.map { CGFloat(truncating: $0) } ?? 720
        let rect = NSRect(x: 0, y: 0, width: max(width, 320), height: max(height, 240))

        // La configuration fournie par WebKit doit être utilisée telle quelle (elle relie la fenêtre à sa page).
        webView = WKWebView(frame: rect, configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.isInspectable = true
        webView.allowsMagnification = true

        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.title = String(localized: "Chargement…")
        super.init()
        window.delegate = self

        if let parent {
            let origin = NSPoint(x: parent.frame.midX - rect.width / 2, y: parent.frame.midY - rect.height / 2)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            let title = webView.title
            MainActor.assumeIsolated {
                if let title, !title.isEmpty { self?.window.title = title }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        titleObservation = nil
        onClose?()
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
