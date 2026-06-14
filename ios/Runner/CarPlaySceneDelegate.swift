import UIKit

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayRouteCoordinator?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        let coordinator = CarPlayRouteCoordinator(
            interfaceController: interfaceController,
            window: window
        )
        self.coordinator = coordinator
        coordinator.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        coordinator = nil
    }
}

// MARK: - K4: CarPlay-Dashboard-Scene

/// 2026-06-14 (vucko K4): Ohne diese Scene erscheint die App im CarPlay-
/// Dashboard (halb Karte, halb Musik/Kalender) GAR NICHT — sie „verschwand".
/// Jetzt: dieselbe scharfe MapLibre-Karte (eigene Position) im Dashboard-Fenster
/// + zwei Shortcut-Buttons (max. 2). Der CPDashboardController wird vom System
/// bereitgestellt (NICHT selbst instanziieren), wir setzen nur die Buttons.
@available(iOS 13.4, *)
final class CarPlayDashboardSceneDelegate: UIResponder,
    CPTemplateApplicationDashboardSceneDelegate {
    private var mapViewController: UIViewController?

    func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didConnect dashboardController: CPDashboardController,
        to window: UIWindow
    ) {
        // Karte im Dashboard-Fenster (eigener Look, folgt dem Standort).
        let mapVC = CarPlayMapViewController()
        window.rootViewController = mapVC
        mapViewController = mapVC

        // Zwei Shortcut-Buttons. Tippen bringt die CarPlay-App nach vorn; der
        // Handler schreibt zusätzlich einen Befehl für die Flutter-Seite.
        let plan = CPDashboardButton(
            titleVariants: ["Route planen", "Planen"],
            subtitleVariants: ["Neue Cruise-Route"],
            image: UIImage(systemName: "map.fill") ?? UIImage()
        ) { _ in
            CarPlayDashboardSceneDelegate.writeCommand("dashboardPlan")
        }
        let go = CPDashboardButton(
            titleVariants: ["Losfahren", "Start"],
            subtitleVariants: ["Navigation starten"],
            image: UIImage(systemName: "location.north.fill") ?? UIImage()
        ) { _ in
            CarPlayDashboardSceneDelegate.writeCommand("startNavigation")
        }
        dashboardController.shortcutButtons = [plan, go]
    }

    func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didDisconnect dashboardController: CPDashboardController,
        from window: UIWindow
    ) {
        mapViewController = nil
    }

    private static func writeCommand(_ action: String) {
        let id = Int(Date().timeIntervalSince1970 * 1000)
        let json = "{\"action\":\"\(action)\",\"requestId\":\(id)}"
        UserDefaults.standard.set(json, forKey: "flutter.car_command")
    }
}
#endif
