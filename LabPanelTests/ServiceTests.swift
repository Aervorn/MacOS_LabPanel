import Foundation
import Testing

struct ServiceURLTests {
    @Test func addsHTTPSForHTTPSKinds() {
        #expect(ServiceURL.normalize("pve.local:8006", preferHTTPS: true)?.absoluteString == "https://pve.local:8006")
        #expect(ServiceURL.normalize("192.168.1.1", preferHTTPS: true)?.absoluteString == "https://192.168.1.1")
    }

    @Test func addsHTTPByDefault() {
        #expect(ServiceURL.normalize("homeassistant.local:8123", preferHTTPS: false)?.absoluteString
            == "http://homeassistant.local:8123")
    }

    @Test func recognisesUsualHTTPSPorts() {
        #expect(ServiceURL.normalize("nas.local:5001", preferHTTPS: false)?.scheme == "https")
        #expect(ServiceURL.normalize("unifi:8443", preferHTTPS: false)?.scheme == "https")
        #expect(ServiceURL.normalize("nas.local:5000", preferHTTPS: false)?.scheme == "http")
    }

    @Test func keepsExplicitScheme() {
        #expect(ServiceURL.normalize("http://pve.local:8006", preferHTTPS: true)?.scheme == "http")
        #expect(ServiceURL.normalize("  https://ha.example.com/lovelace  ", preferHTTPS: false)?.absoluteString
            == "https://ha.example.com/lovelace")
    }

    @Test func rejectsInvalidAddresses() {
        #expect(ServiceURL.normalize("", preferHTTPS: false) == nil)
        #expect(ServiceURL.normalize("   ", preferHTTPS: false) == nil)
        #expect(ServiceURL.normalize("ftp://nas.local", preferHTTPS: false) == nil)
        #expect(ServiceURL.normalize("http://", preferHTTPS: false) == nil)
        #expect(ServiceURL.normalize("nas local", preferHTTPS: false) == nil)
    }
}

struct ServiceTests {
    @Test func defaultsCoverTheNineServices() {
        let defaults = Service.defaults
        #expect(defaults.count == 9)
        #expect(!defaults.contains { $0.kind == .custom })
        #expect(defaults.allSatisfy { !$0.isConfigured && $0.isVisible })
        #expect(Set(defaults.map(\.id)).count == 9)
    }

    @Test func selfSignedAcceptedForApplianceInterfaces() {
        #expect(Service(kind: .proxmox).allowsSelfSignedCertificate)
        #expect(Service(kind: .dsm).allowsSelfSignedCertificate)
        #expect(!Service(kind: .homeAssistant).allowsSelfSignedCertificate)
    }

    @Test func roundTripsThroughJSON() throws {
        var service = Service(kind: .proxmox, address: "pve.local:8006")
        service.zoom = 1.2
        service.isVisible = false
        let data = try JSONEncoder().encode([service])
        let decoded = try JSONDecoder().decode([Service].self, from: data)
        #expect(decoded == [service])
    }

    @Test func decodesOlderSettingsWithMissingKeys() throws {
        let json = #"[{"id":"7E1F1C5A-3B7E-4C2B-9C61-2E4B0C8C2C11","kind":"homeAssistant","address":"ha:8123"}]"#
        let decoded = try JSONDecoder().decode([Service].self, from: Data(json.utf8))
        #expect(decoded.first?.name == "Home Assistant")
        #expect(decoded.first?.zoom == 1)
        #expect(decoded.first?.isVisible == true)
        #expect(decoded.first?.url?.absoluteString == "http://ha:8123")
    }

    @Test func unknownKindFallsBackToCustom() throws {
        let json = #"[{"kind":"jellyfin","name":"Jellyfin","address":"media:8096"}]"#
        let decoded = try JSONDecoder().decode([Service].self, from: Data(json.utf8))
        #expect(decoded.first?.kind == .custom)
        #expect(decoded.first?.name == "Jellyfin")
    }
}

struct HexColorTests {
    @Test func parsesAndFormats() throws {
        let c = try #require(HexColor.components("#E57000"))
        #expect(HexColor.string(red: c.red, green: c.green, blue: c.blue) == "#E57000")
        #expect(HexColor.components("12345") == nil)
        #expect(HexColor.components("zzzzzz") == nil)
    }

    @Test func everyKindHasAValidColor() {
        for kind in ServiceKind.allCases {
            #expect(HexColor.components(kind.colorHex) != nil, "\(kind)")
        }
    }
}

struct AvailabilityTests {
    @Test func classifiesResults() {
        #expect(Availability.from(error: nil, elapsed: 0.042) == .online(milliseconds: 42))
        let certificate = URLError(.serverCertificateUntrusted)
        #expect(Availability.from(error: certificate, elapsed: 0) == .untrustedCertificate)
        let timeout = URLError(.timedOut)
        #expect(Availability.from(error: timeout, elapsed: 0) == .offline(code: NSURLErrorTimedOut))
    }

    @Test func cancelledNavigationIsBenign() {
        #expect(NetworkError.isBenign(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        #expect(!NetworkError.isBenign(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
    }
}

struct IconTests {
    @Test func defaultIconsAreOfficialForKnownServices() {
        #expect(Service(kind: .proxmox).icon == .dashboard(slug: "proxmox"))
        #expect(Service(kind: .dsm).icon == .dashboard(slug: "synology-dsm"))
        #expect(Service(kind: .custom).icon == .symbol)
    }

    @Test func olderSettingsGetTheOfficialIcon() throws {
        let json = #"[{"kind":"adguard","address":"192.168.1.2:3000"}]"#
        let decoded = try JSONDecoder().decode([Service].self, from: Data(json.utf8))
        #expect(decoded.first?.icon == .dashboard(slug: "adguard-home"))
    }

    @Test func iconSourceRoundTrips() throws {
        let sources: [IconSource] = [.symbol, .dashboard(slug: "unifi"), .file(name: "abc.png")]
        let data = try JSONEncoder().encode(sources)
        #expect(try JSONDecoder().decode([IconSource].self, from: data) == sources)
    }

    @Test func picksVariantForAppearance() {
        let available: Set = ["proxmox", "proxmox-light", "unifi", "unifi-dark", "home-assistant"]
        #expect(IconKey.resolve(.dashboard(slug: "proxmox"), dark: true, available: available) == .dashboard("proxmox-light"))
        #expect(IconKey.resolve(.dashboard(slug: "proxmox"), dark: false, available: available) == .dashboard("proxmox"))
        #expect(IconKey.resolve(.dashboard(slug: "unifi"), dark: false, available: available) == .dashboard("unifi-dark"))
        #expect(IconKey.resolve(.dashboard(slug: "unifi"), dark: true, available: available) == .dashboard("unifi"))
        #expect(IconKey.resolve(.dashboard(slug: "home-assistant"), dark: true, available: []) == .dashboard("home-assistant"))
        #expect(IconKey.resolve(.symbol, dark: true, available: available) == nil)
        #expect(IconKey.resolve(.dashboard(slug: "  "), dark: true, available: available) == nil)
    }

    @Test func cleansPastedNames() {
        #expect(DashboardIcons.clean(" Proxmox.PNG ") == "proxmox")
        #expect(DashboardIcons.pngURL("home-assistant").absoluteString
            == "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/home-assistant.png")
    }

    @Test func readsTreeAndSearches() {
        let tree = #"{"png":["proxmox.png","proxmox-backup-server.png","synology-dsm.png","pve-light.png"],"svg":["proxmox.svg"]}"#
        let names = DashboardIcons.names(fromTree: Data(tree.utf8))
        #expect(names == ["proxmox", "proxmox-backup-server", "pve-light", "synology-dsm"])
        #expect(DashboardIcons.search("prox", in: names) == ["proxmox", "proxmox-backup-server"])
        #expect(DashboardIcons.search("dsm", in: names) == ["synology-dsm"])
        #expect(DashboardIcons.search("backup server", in: names) == ["proxmox-backup-server"])
        #expect(DashboardIcons.names(fromTree: Data("nope".utf8)).isEmpty)
    }

    @Test func proxmoxStaysLoadedByDefault() {
        #expect(Service(kind: .proxmox).keepsAlive)
        #expect(!Service(kind: .homeAssistant).keepsAlive)
    }
}

struct AutoLoginTests {
    @Test func offByDefaultAndDecodedFromOlderSettings() throws {
        #expect(Service(kind: .proxmox).autoLogin == .off)
        let json = #"[{"kind":"proxmox","address":"pve:8006"}]"#
        let decoded = try JSONDecoder().decode([Service].self, from: Data(json.utf8))
        #expect(decoded.first?.autoLogin == .off)
    }

    @Test func roundTrips() throws {
        let service = Service(kind: .proxmox, autoLogin: .fillAndSubmit)
        let data = try JSONEncoder().encode(service)
        #expect(try JSONDecoder().decode(Service.self, from: data).autoLogin == .fillAndSubmit)
    }

    @Test func submitsAtMostOncePerPeriod() {
        var guardrail = AutoSubmitGuard(period: 120)
        let start = Date(timeIntervalSince1970: 1_000)
        // `allow` est mutating : on l'appelle hors de #expect, qui évalue son expression dans une closure.
        let first = guardrail.allow(at: start)
        let tooSoon = guardrail.allow(at: start.addingTimeInterval(5))
        let stillTooSoon = guardrail.allow(at: start.addingTimeInterval(119))
        let afterPeriod = guardrail.allow(at: start.addingTimeInterval(121))
        #expect(first)
        #expect(!tooSoon)
        #expect(!stillTooSoon)
        #expect(afterPeriod)
    }
}

struct QuickSearchTests {
    let names = ["UniFi", "DSM", "Proxmox", "Dockhand", "AdGuard", "NPM", "NUT", "Home Assistant", "Zigbee2MQTT"]

    @Test func emptyQueryKeepsOrder() {
        #expect(QuickSearch.rank(names, query: "  ", name: { $0 }) == names)
    }

    @Test func prefixBeatsContains() {
        #expect(QuickSearch.rank(names, query: "prox", name: { $0 }) == ["Proxmox"])
        #expect(QuickSearch.rank(names, query: "d", name: { $0 }).prefix(2) == ["DSM", "Dockhand"])
    }

    @Test func wordsInitialsAndAccents() {
        #expect(QuickSearch.rank(names, query: "assist", name: { $0 }) == ["Home Assistant"])
        #expect(QuickSearch.rank(names, query: "ha", name: { $0 }).first == "Home Assistant")
        #expect(QuickSearch.score("élec", name: "Electricité") != nil)
        #expect(QuickSearch.rank(names, query: "pmx", name: { $0 }) == ["Proxmox"])
    }

    @Test func matchesAddress() {
        let score = QuickSearch.score("192.168.1.2", name: "AdGuard", detail: "192.168.1.2:3000")
        #expect(score == 200)
        #expect(QuickSearch.score("zzz", name: "Proxmox", detail: "pve.local") == nil)
    }
}
