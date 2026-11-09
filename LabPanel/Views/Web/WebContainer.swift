import AppKit
import SwiftUI
import WebKit

/// Accueille la vue web d'un service. Changer d'onglet échange seulement la vue web
/// à l'intérieur du conteneur : la page n'est ni recréée ni rechargée.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        host(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard webView.superview !== container else { return }
        host(in: container)
    }

    private func host(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        // Le clavier va à la page affichée (défilement, raccourcis du site).
        DispatchQueue.main.async { [webView] in
            webView.window?.makeFirstResponder(webView)
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        // La vue web appartient à sa session : on la détache seulement.
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
