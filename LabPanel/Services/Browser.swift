import AppKit
import Foundation
import Observation
import WebKit

/// Les pages ouvertes, une par service, créées à la première visite de l'onglet puis gardées en vie.
/// Elles survivent aussi à la fermeture de la fenêtre : la rouvrir retrouve chaque page où elle en était.
@MainActor
@Observable
final class Browser {
    private(set) var sessions: [UUID: WebSession] = [:]

    /// Dernier fichier téléchargé, annoncé en bas de la fenêtre.
    var lastDownload: URL?
    var downloadError: String?

    @ObservationIgnored private var popups: [PopupWindow] = []

    func session(_ id: UUID?) -> WebSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    /// Crée et charge la page d'un service la première fois que son onglet est affiché.
    func prepare(_ service: Service) {
        guard service.isConfigured else { return }
        if let session = sessions[service.id] {
            if session.webView.url == nil && session.failure == nil && !session.isLoading {
                session.loadHome()
            }
            return
        }
        let session = WebSession(service: service, browser: self)
        sessions[service.id] = session
        session.loadHome()
    }

    /// Répercute les Réglages sur les pages ouvertes, et ferme celles des services supprimés.
    func sync(with services: [Service]) {
        let byID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
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
