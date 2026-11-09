import Foundation
import Observation
import SwiftUI

/// Liste des services (ordre des onglets compris) et onglet sélectionné, enregistrés dans les préférences.
@MainActor
@Observable
final class ServiceStore {
    var services: [Service] {
        didSet {
            guard services != oldValue else { return }
            save()
        }
    }

    /// Onglet choisi ; `selected` retombe sur le premier onglet visible s'il a disparu.
    var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectionKey)
        }
    }

    /// Service ouvert dans les Réglages (« Modifier… » depuis un onglet).
    var editingID: UUID?

    nonisolated static let servicesKey = "services.v1"
    nonisolated static let selectionKey = "services.selected"

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.servicesKey),
           let stored = try? JSONDecoder().decode([Service].self, from: data) {
            services = stored
        } else {
            services = Service.defaults
        }
        selectedID = defaults.string(forKey: Self.selectionKey).flatMap(UUID.init(uuidString:))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(services) else { return }
        UserDefaults.standard.set(data, forKey: Self.servicesKey)
    }

    // MARK: - Lecture

    var visibleServices: [Service] { services.filter(\.isVisible) }

    var selected: Service? {
        let visible = visibleServices
        return visible.first { $0.id == selectedID } ?? visible.first
    }

    func service(_ id: UUID?) -> Service? {
        guard let id else { return nil }
        return services.first { $0.id == id }
    }

    // MARK: - Modification

    func update(_ id: UUID, _ change: (inout Service) -> Void) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        var service = services[index]
        change(&service)
        services[index] = service
    }

    /// Liaison vers un champ d'un service, pour les formulaires.
    func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<Service, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.service(id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.update(id) { $0[keyPath: keyPath] = value } }
        )
    }

    @discardableResult
    func add(_ kind: ServiceKind) -> Service {
        var service = Service(kind: kind)
        if kind == .custom { service.name = String(localized: "Nouveau service") }
        services.append(service)
        return service
    }

    func remove(_ id: UUID) {
        services.removeAll { $0.id == id }
        if editingID == id { editingID = nil }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        services.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefaults() {
        services = Service.defaults
        selectedID = nil
        editingID = nil
    }

    // MARK: - Navigation entre onglets

    func select(_ id: UUID) {
        selectedID = id
    }

    func selectNext() { step(+1) }
    func selectPrevious() { step(-1) }

    private func step(_ offset: Int) {
        let visible = visibleServices
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = visible[(current + offset + visible.count) % visible.count].id
    }
}
