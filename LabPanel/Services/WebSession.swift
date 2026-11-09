import AppKit
import Foundation
import Observation
import WebKit

/// Échec du chargement d'une page, affiché par-dessus la vue web.
struct LoadFailure: Equatable {
    let message: String
    let code: Int
    let isCertificate: Bool
    let url: URL?
}

/// Une page web gardée en vie pour un service : changer d'onglet ne la recharge pas.
///
/// Chaque service a son propre stockage (cookies, localStorage…) : les cookies ne tiennent pas
/// compte du port, et sans cette séparation DSM (nas:5001) et Dockhand (nas:3000) se marcheraient
/// dessus. Les données sont gardées sur disque d'un lancement à l'autre.
@MainActor
@Observable
final class WebSession {
    let serviceID: UUID
    private(set) var service: Service
    let webView: WKWebView

    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var currentURL: URL?
    /// Vrai après le premier chargement réussi : l'écran d'attente laisse alors place à la page.
    private(set) var hasLoadedOnce = false
    var failure: LoadFailure?

    @ObservationIgnored weak var browser: Browser?
    @ObservationIgnored private let delegate = WebDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// Identifiant de Safari ajouté à celui de WebKit : certaines interfaces refusent un navigateur inconnu.
    static let applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"

    init(service: Service, browser: Browser?) {
        self.serviceID = service.id
        self.service = service
        self.browser = browser

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)
        configuration.applicationNameForUserAgent = Self.applicationNameForUserAgent
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // Clic droit › Inspecter l'élément, et Safari › Développement
        webView.isInspectable = true
        webView.pageZoom = CGFloat(service.zoom)
        webView.autoresizingMask = [.width, .height]
        self.webView = webView

        delegate.session = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        observe()
    }

    private func observe() {
        func watch<Value>(_ keyPath: KeyPath<WKWebView, Value>, _ apply: @escaping (WebSession, Value) -> Void) {
            observations.append(webView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView[keyPath: keyPath]
                MainActor.assumeIsolated {
                    guard let self else { return }
                    apply(self, value)
                }
            })
        }
        watch(\.isLoading) { $0.isLoading = $1 }
        watch(\.estimatedProgress) { $0.progress = $1 }
        watch(\.canGoBack) { $0.canGoBack = $1 }
        watch(\.canGoForward) { $0.canGoForward = $1 }
        watch(\.url) { $0.currentURL = $1 }
    }

    // MARK: - Actions

    func loadHome() {
        guard let url = service.url else { return }
        failure = nil
        webView.load(URLRequest(url: url))
    }

    func reload(fromOrigin: Bool = false) {
        failure = nil
        // Après un échec, la vue web n'a souvent rien à recharger : on repart de l'adresse du service.
        if webView.url == nil || !hasLoadedOnce {
            loadHome()
        } else if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    /// Applique les changements faits dans les Réglages.
    func apply(_ updated: Service) {
        let previous = service
        service = updated
        if CGFloat(updated.zoom) != webView.pageZoom {
            webView.pageZoom = CGFloat(updated.zoom)
        }
        if updated.url != previous.url {
            hasLoadedOnce = false
            loadHome()
        } else if updated.allowsSelfSignedCertificate && !previous.allowsSelfSignedCertificate,
                  failure?.isCertificate == true {
            reload()
        }
    }

    /// Page affichée : celle du site, sinon l'adresse du service.
    var displayedURL: URL? { currentURL ?? service.url }

    // MARK: - Appelé par le délégué

    fileprivate func didStart() {
        failure = nil
    }

    fileprivate func didFinish() {
        hasLoadedOnce = true
        failure = nil
    }

    fileprivate func didFail(_ error: Error) {
        let nsError = error as NSError
        guard !NetworkError.isBenign(domain: nsError.domain, code: nsError.code) else { return }
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url ?? service.url
        failure = LoadFailure(
            message: nsError.localizedDescription,
            code: nsError.code,
            isCertificate: NetworkError.isCertificateError(code: nsError.code),
            url: failingURL
        )
    }

    /// Le certificat d'un hôte est accepté s'il s'agit de celui du service et que l'option est cochée.
    fileprivate func trustsCertificate(of host: String) -> Bool {
        guard service.allowsSelfSignedCertificate, let serviceHost = service.url?.host else { return false }
        return host.caseInsensitiveCompare(serviceHost) == .orderedSame
    }

    fileprivate func isSameHost(_ url: URL?) -> Bool {
        guard let host = url?.host, let serviceHost = service.url?.host else { return false }
        return host.caseInsensitiveCompare(serviceHost) == .orderedSame
    }
}

// MARK: - Délégué WebKit

/// Délégué de la page principale et de ses fenêtres surgissantes (console noVNC de Proxmox…).
/// Les fenêtres surgissantes partagent les règles de la page : même certificat accepté, mêmes dialogues.
@MainActor
final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    weak var session: WebSession?

    private func isMain(_ webView: WKWebView) -> Bool { webView === session?.webView }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if isMain(webView) { session?.didStart() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isMain(webView) { session?.didFinish() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if isMain(webView) { session?.didFail(error) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isMain(webView) { session?.didFail(error) }
    }

    /// Le processus de la page a planté (mémoire, veille…) : on la recharge plutôt que de laisser un écran blanc.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url else { return .allow }

        // mailto:, ssh:, liens vers d'autres apps : confiés à macOS
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        // ⌘-clic sur un lien : dans le navigateur par défaut, comme dans Safari
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command),
           navigationAction.targetFrame?.isMainFrame ?? true {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType { return .download }
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: Certificats et authentification HTTP

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            if let trust = space.serverTrust, session?.trustsCertificate(of: space.host) == true {
                return (.useCredential, URLCredential(trust: trust))
            }
            return (.performDefaultHandling, nil)

        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            // Accès protégé par mot de passe (Nginx Proxy Manager, interface NUT…)
            guard challenge.previousFailureCount < 3,
                  let credential = await Dialogs.askCredential(for: space, in: webView.window)
            else { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, credential)

        default:
            return (.performDefaultHandling, nil)
        }
    }

    // MARK: Fenêtres et liens « nouvel onglet »

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        // Lien vers un autre site (documentation, GitHub…) : navigateur par défaut.
        if navigationAction.navigationType == .linkActivated, let url, session?.isSameHost(url) == false {
            NSWorkspace.shared.open(url)
            return nil
        }
        // window.open() ou lien du même service (console Proxmox, aperçu DSM…) : fenêtre surgissante.
        guard let browser = session?.browser else {
            if let url { NSWorkspace.shared.open(url) }
            return nil
        }
        return browser.openPopup(configuration: configuration, features: windowFeatures,
                                 delegate: self, parent: webView.window)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard !isMain(webView) else { return }
        session?.browser?.closePopup(showing: webView)
    }

    // MARK: Dialogues JavaScript et choix de fichiers

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await Dialogs.alert(message, host: frame.securityOrigin.host, in: webView.window)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Dialogs.confirm(message, host: frame.securityOrigin.host, in: webView.window)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await Dialogs.prompt(prompt, defaultText: defaultText, host: frame.securityOrigin.host, in: webView.window)
    }

    /// Sans ce délégué, un champ « Choisir un fichier » (sauvegarde HA, import DSM…) ne fait rien.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            return await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
        }
        return panel.runModal() == .OK ? panel.urls : nil
    }

    // MARK: Téléchargements (dans le dossier Téléchargements)

    /// Destination de chaque téléchargement en cours.
    private var destinations: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let destination = Downloads.uniqueDestination(for: suggestedFilename)
        destinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Downloads.announce(url)
        session?.browser?.lastDownload = url
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        session?.browser?.downloadError = error.localizedDescription
    }
}

/// Destination des fichiers téléchargés.
@MainActor
enum Downloads {
    static func uniqueDestination(for suggestedFilename: String) -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let numbered = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appending(path: numbered)
            index += 1
        }
        return candidate
    }

    /// Fait rebondir la pile Téléchargements du Dock, comme Safari.
    static func announce(_ url: URL) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.DownloadFileFinished"),
            object: url.path(percentEncoded: false)
        )
    }
}
