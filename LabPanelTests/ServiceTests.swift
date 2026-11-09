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
