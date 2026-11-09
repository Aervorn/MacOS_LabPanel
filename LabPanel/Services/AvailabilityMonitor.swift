import AppKit
import Foundation
import Observation

/// Vérifie chaque minute que les services répondent, pour la pastille de leur onglet.
///
/// Une simple requête GET dont on ne lit que l'en-tête : n'importe quelle réponse HTTP
/// (page de connexion, 401…) compte comme « en ligne ». Rien n'est envoyé d'autre.
@MainActor
@Observable
final class AvailabilityMonitor {
    private(set) var states: [UUID: Availability] = [:]

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastRun = Date.distantPast
    @ObservationIgnored private var services: @MainActor () -> [Service] = { [] }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static let interval: Duration = .seconds(60)

    func availability(of id: UUID) -> Availability {
        states[id] ?? .unknown
    }

    func start(services: @escaping @MainActor () -> [Service]) {
        self.services = services
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAll()
                try? await Task.sleep(for: Self.interval)
            }
        }
        // Au retour sur l'app ou après la veille : vérification immédiate (au plus toutes les 15 s).
        let names = [NSApplication.didBecomeActiveNotification]
        observers = names.map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        })
    }

    func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        states = [:]
    }

    func refreshSoon() {
        guard loop != nil, Date.now.timeIntervalSince(lastRun) > 15 else { return }
        Task { await checkAll() }
    }

    func checkAll() async {
        lastRun = .now
        let targets = services().filter { $0.isVisible && $0.isConfigured }
        // Les services retirés ou sans adresse perdent leur pastille.
        let ids = Set(targets.map(\.id))
        for id in states.keys where !ids.contains(id) { states[id] = nil }

        await withTaskGroup(of: (UUID, Availability).self) { group in
            for service in targets {
                guard let url = service.url else { continue }
                let allowSelfSigned = service.allowsSelfSignedCertificate
                group.addTask { (service.id, await Self.probe(url, allowSelfSigned: allowSelfSigned)) }
            }
            for await (id, availability) in group {
                states[id] = availability
            }
        }
    }

    nonisolated static func probe(_ url: URL, allowSelfSigned: Bool) async -> Availability {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = ProbeDelegate(allowSelfSigned: allowSelfSigned, host: url.host ?? "")
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let start = Date.now
        do {
            // Seul l'en-tête nous intéresse : le corps de la page n'est pas téléchargé.
            let (bytes, _) = try await session.bytes(for: request)
            bytes.task.cancel()
            return Availability.from(error: nil, elapsed: Date.now.timeIntervalSince(start))
        } catch {
            return Availability.from(error: error, elapsed: 0)
        }
    }
}

/// Accepte le certificat auto-signé du service si l'option est cochée, comme la page elle-même.
private final class ProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowSelfSigned: Bool
    let host: String

    init(allowSelfSigned: Bool, host: String) {
        self.allowSelfSigned = allowSelfSigned
        self.host = host
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           allowSelfSigned, space.host.caseInsensitiveCompare(host) == .orderedSame,
           let trust = space.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        // Authentification HTTP comprise : on ne s'identifie pas, la réponse 401 suffit à savoir que le service répond.
        return (.performDefaultHandling, nil)
    }
}
