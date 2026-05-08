import Foundation

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
final class CarPlayRouteCoordinator {
    private let interfaceController: CPInterfaceController
    private let routeStore: CarPlayRouteSnapshotStore
    private let mapTemplate = CPMapTemplate()

    init(
        interfaceController: CPInterfaceController,
        routeStore: CarPlayRouteSnapshotStore = CarPlayRouteSnapshotStore()
    ) {
        self.interfaceController = interfaceController
        self.routeStore = routeStore
    }

    func start() {
        configureMapTemplate()
        interfaceController.setRootTemplate(mapTemplate, animated: false)
        showSafetyNoticeIfNeeded()
        refresh()
    }

    func refresh() {
        guard let snapshot = routeStore.readSnapshot() else {
            mapTemplate.leadingNavigationBarButtons = [
                CPBarButton(title: "Handy planen") { _ in }
            ]
            return
        }
        let title = title(for: snapshot)
        let distance = formatDistance(snapshot.remainingDistanceMeters ?? snapshot.distanceMeters)
        let duration = formatDuration(snapshot.remainingDurationSeconds ?? snapshot.durationSeconds)
        mapTemplate.leadingNavigationBarButtons = [
            CPBarButton(title: title) { _ in }
        ]
        mapTemplate.trailingNavigationBarButtons = [
            CPBarButton(title: "\(distance) • \(duration)") { _ in },
            CPBarButton(title: "Aktualisieren") { [weak self] _ in
                self?.refresh()
            }
        ]
    }

    private func configureMapTemplate() {
        mapTemplate.automaticallyHidesNavigationBar = false
        mapTemplate.mapButtons = [
            CPMapButton { [weak self] _ in
                self?.refresh()
            }
        ]
    }

    private func showSafetyNoticeIfNeeded() {
        let key = "carplay_safety_accepted"
        guard UserDefaults.standard.bool(forKey: key) == false else { return }
        let action = CPAlertAction(title: "Verstanden", style: .default) { _ in
            UserDefaults.standard.set(true, forKey: key)
        }
        let alert = CPAlertTemplate(
            titleVariants: ["Cruise Connector sicher nutzen"],
            actions: [action]
        )
        interfaceController.presentTemplate(alert, animated: true)
    }

    private func title(for snapshot: CarPlayRouteSnapshot) -> String {
        switch snapshot.status {
        case "searching":
            return "Route wird berechnet"
        case "navigating":
            return snapshot.nextManeuverText ?? "Navigation läuft"
        case "found":
            return "Route bereit"
        default:
            return snapshot.style ?? "Cruise Route"
        }
    }

    private func formatDistance(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "--" }
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
#endif
