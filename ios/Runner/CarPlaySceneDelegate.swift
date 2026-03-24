import CarPlay
import UIKit

/// CarPlay Scene Delegate – manages the entire CarPlay UI.
///
/// Flow (1:1 wie die Handy-App):
/// 1. Root = CPTabBarTemplate with "Strecken-Setup" and "Meine Routen"
/// 2. Strecken-Setup → Routen-Modus (Rundkurs / A nach B)
/// 3. Rundkurs → Planungs-Typ (Zufall / Wegpunkte) → Stil → Länge → Generate
/// 4. A nach B → Stil → Generate (Länge wird automatisch berechnet)
/// 5. User confirms → Navigation overlay
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    static var instance: CarPlaySceneDelegate?

    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?

    // Route creation state – mirrors cruise_setup_card.dart
    private var isRoundTrip: Bool = true
    private var selectedPlanningType: String = "Zufall"
    private var selectedStyle: String = "Sport Mode"
    private var selectedLength: String = "50 Km"

    // MARK: - Options (1:1 wie cruise_setup_card.dart)

    private let routeStyles: [(name: String, icon: String)] = [
        ("Kurvenjagd", "road.lanes"),
        ("Sport Mode", "car.fill"),
        ("Abendrunde", "moon.stars.fill"),
        ("Entdecker", "binoculars.fill"),
    ]

    private let lengths: [String] = ["50 Km", "75 Km", "100 Km", "150 Km"]

    // MARK: - Scene Lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        CarPlaySceneDelegate.instance = self
        self.interfaceController = interfaceController
        self.carWindow = window

        let rootTemplate = buildRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)

        sendToFlutter("carplayConnected", arguments: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        CarPlaySceneDelegate.instance = nil
        self.interfaceController = nil
        self.carWindow = nil

        sendToFlutter("carplayDisconnected", arguments: nil)
    }

    // MARK: - Root Template (Tab Bar)

    private func buildRootTemplate() -> CPTabBarTemplate {
        let createTab = buildCreateRouteTab()
        let savedTab = buildSavedRoutesTab()

        return CPTabBarTemplate(templates: [createTab, savedTab])
    }

    // MARK: - Tab 1: Strecken-Setup

    private func buildCreateRouteTab() -> CPListTemplate {
        // Step 1: Routen-Modus (Rundkurs / A nach B)
        let rundkursItem = CPListItem(
            text: "Rundkurs",
            detailText: "Zurück zum Startpunkt",
            image: UIImage(systemName: "arrow.triangle.swap")
        )
        rundkursItem.handler = { [weak self] _, completion in
            self?.isRoundTrip = true
            self?.showPlanningTypeSelection()
            completion()
        }

        let atobItem = CPListItem(
            text: "A nach B",
            detailText: "Von hier zu einem Ziel",
            image: UIImage(systemName: "arrow.right")
        )
        atobItem.handler = { [weak self] _, completion in
            self?.isRoundTrip = false
            self?.showStyleSelection()
            completion()
        }

        let section = CPListSection(
            items: [rundkursItem, atobItem],
            header: "Routen-Modus",
            sectionIndexTitle: nil
        )
        let template = CPListTemplate(title: "Strecken-Setup", sections: [section])
        template.tabTitle = "Strecken-Setup"
        template.tabImage = UIImage(systemName: "map.fill")
        return template
    }

    // MARK: - Step 2: Planungs-Typ (nur bei Rundkurs)

    private func showPlanningTypeSelection() {
        let zufallItem = CPListItem(
            text: "Zufall",
            detailText: "Zufällige Strecke generieren",
            image: UIImage(systemName: "dice.fill")
        )
        zufallItem.handler = { [weak self] _, completion in
            self?.selectedPlanningType = "Zufall"
            self?.showStyleSelection()
            completion()
        }

        let wegpunkteItem = CPListItem(
            text: "Wegpunkte",
            detailText: "Route über bestimmte Punkte",
            image: UIImage(systemName: "mappin.and.ellipse")
        )
        wegpunkteItem.handler = { [weak self] _, completion in
            self?.selectedPlanningType = "Wegpunkte"
            self?.showStyleSelection()
            completion()
        }

        let section = CPListSection(
            items: [zufallItem, wegpunkteItem],
            header: "Planungs-Typ",
            sectionIndexTitle: nil
        )
        let template = CPListTemplate(title: "Planungs-Typ", sections: [section])

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Step 3: Stil

    private func showStyleSelection() {
        let styleItems: [CPListItem] = routeStyles.map { style in
            let item = CPListItem(
                text: style.name,
                detailText: nil,
                image: UIImage(systemName: style.icon)
            )
            item.handler = { [weak self] _, completion in
                self?.selectedStyle = style.name
                if self?.isRoundTrip == true {
                    self?.showLengthSelection()
                } else {
                    // A nach B: Länge wird automatisch berechnet, direkt generieren
                    self?.generateRoute()
                }
                completion()
            }
            return item
        }

        let section = CPListSection(
            items: styleItems,
            header: "Stil",
            sectionIndexTitle: nil
        )
        let template = CPListTemplate(title: "Stil", sections: [section])

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Step 4: Länge (nur bei Rundkurs)

    private func showLengthSelection() {
        let lengthItems: [CPListItem] = lengths.map { length in
            let item = CPListItem(
                text: length,
                detailText: "Rundkurs",
                image: UIImage(systemName: "ruler.fill")
            )
            item.handler = { [weak self] _, completion in
                self?.selectedLength = length
                self?.generateRoute()
                completion()
            }
            return item
        }

        let section = CPListSection(
            items: lengthItems,
            header: "Länge",
            sectionIndexTitle: nil
        )
        let template = CPListTemplate(title: "Länge", sections: [section])

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Route Generation

    private func generateRoute() {
        // Parse km from length string (e.g. "50 Km" → 50)
        let distanceKm = Int(selectedLength.replacingOccurrences(of: " Km", with: "")) ?? 50

        // Show loading alert
        let loadingAction = CPAlertAction(title: "Abbrechen", style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let loadingAlert = CPAlertTemplate(
            titleVariants: ["Route wird berechnet..."],
            actions: [loadingAction]
        )
        interfaceController?.presentTemplate(loadingAlert, animated: true, completion: nil)

        // Request route generation from Flutter with all parameters
        sendToFlutter("generateRoute", arguments: [
            "style": selectedStyle,
            "distanceKm": distanceKm,
            "planningType": selectedPlanningType,
            "isRoundTrip": isRoundTrip,
        ] as [String: Any])
    }

    // MARK: - Route Result Callbacks (called from AppDelegate)

    func onRouteGenerated(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.interfaceController?.dismissTemplate(animated: true, completion: nil)

            let distanceKm = data["distanceKm"] as? Double ?? 0
            let durationMin = data["durationMin"] as? Double ?? 0
            let curves = data["curves"] as? Int ?? 0
            let style = data["style"] as? String ?? "Route"

            let distText = String(format: "%.1f km", distanceKm)
            let durText = String(format: "%.0f min", durationMin)
            let modeText = self.isRoundTrip ? "Rundkurs" : "A nach B"

            let confirmAction = CPAlertAction(title: "Route starten", style: .default) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
                self?.confirmRoute()
            }
            let cancelAction = CPAlertAction(title: "Abbrechen", style: .cancel) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
            }

            let alert = CPAlertTemplate(
                titleVariants: [
                    "\(style) · \(modeText): \(distText) · \(durText) · \(curves) Kurven",
                    "\(distText) · \(durText) · \(curves) Kurven",
                ],
                actions: [confirmAction, cancelAction]
            )
            self.interfaceController?.presentTemplate(alert, animated: true, completion: nil)
        }
    }

    func onRouteError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)

            let okAction = CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
            }
            let alert = CPAlertTemplate(
                titleVariants: ["Fehler: \(message)", "Route konnte nicht erstellt werden"],
                actions: [okAction]
            )
            self?.interfaceController?.presentTemplate(alert, animated: true, completion: nil)
        }
    }

    // MARK: - Confirm & Start Navigation

    private func confirmRoute() {
        sendToFlutter("confirmRoute", arguments: nil)

        let modeText = isRoundTrip ? "Rundkurs" : "A nach B"

        let navItems: [CPListItem] = [
            CPListItem(
                text: "Navigation aktiv",
                detailText: "Folge den Anweisungen auf deinem Handy",
                image: UIImage(systemName: "location.fill")
            ),
            CPListItem(
                text: selectedStyle,
                detailText: "\(modeText) · \(selectedLength)",
                image: UIImage(systemName: "car.fill")
            ),
        ]
        navItems.forEach { $0.handler = nil }

        let stopItem = CPListItem(
            text: "Navigation beenden",
            detailText: "Route abbrechen",
            image: UIImage(systemName: "xmark.circle.fill")
        )
        stopItem.handler = { [weak self] _, completion in
            self?.stopNavigation()
            completion()
        }

        let section1 = CPListSection(items: navItems, header: "Aktive Navigation", sectionIndexTitle: nil)
        let section2 = CPListSection(items: [stopItem], header: nil, sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Navigation", sections: [section1, section2])

        interfaceController?.popToRootTemplate(animated: false, completion: nil)
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func stopNavigation() {
        sendToFlutter("stopNavigation", arguments: nil)
        interfaceController?.popToRootTemplate(animated: true, completion: nil)
    }

    // MARK: - Tab 2: Meine Routen

    private func buildSavedRoutesTab() -> CPListTemplate {
        let placeholder = CPListItem(
            text: "Routen werden geladen...",
            detailText: nil,
            image: UIImage(systemName: "arrow.clockwise")
        )
        placeholder.handler = nil

        let section = CPListSection(items: [placeholder])
        let template = CPListTemplate(title: "Gespeicherte Routen", sections: [section])
        template.tabTitle = "Meine Routen"
        template.tabImage = UIImage(systemName: "bookmark.fill")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sendToFlutter("getSavedRoutes", arguments: nil)
        }

        return template
    }

    func updateSavedRoutes(_ routes: [[String: Any]]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var items: [CPListItem] = []

            for route in routes {
                let name = route["name"] as? String ?? "Route"
                let style = route["style"] as? String ?? ""
                let distKm = route["distanceKm"] as? Double ?? 0
                let emoji = route["emoji"] as? String ?? "🛣️"

                let item = CPListItem(
                    text: "\(emoji) \(name)",
                    detailText: "\(String(format: "%.1f", distKm)) km · \(style)",
                    image: UIImage(systemName: "map.fill")
                )

                let routeId = route["id"] as? String
                item.handler = { [weak self] _, completion in
                    if let id = routeId {
                        self?.sendToFlutter("replayRoute", arguments: ["routeId": id])

                        let loading = CPAlertAction(title: "Abbrechen", style: .cancel) { [weak self] _ in
                            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
                        }
                        let alert = CPAlertTemplate(
                            titleVariants: ["Route wird geladen..."],
                            actions: [loading]
                        )
                        self?.interfaceController?.presentTemplate(alert, animated: true, completion: nil)
                    }
                    completion()
                }

                items.append(item)
            }

            if items.isEmpty {
                let empty = CPListItem(
                    text: "Keine gespeicherten Routen",
                    detailText: "Fahre eine Route um sie zu speichern",
                    image: UIImage(systemName: "map")
                )
                empty.handler = nil
                items = [empty]
            }

            let section = CPListSection(items: items, header: "Deine Routen", sectionIndexTitle: nil)
            let template = CPListTemplate(title: "Gespeicherte Routen", sections: [section])
            template.tabTitle = "Meine Routen"
            template.tabImage = UIImage(systemName: "bookmark.fill")

            if let rootTab = self.interfaceController?.rootTemplate as? CPTabBarTemplate {
                var templates = rootTab.templates
                if templates.count > 1 {
                    templates[1] = template
                    rootTab.updateTemplates(templates)
                }
            }
        }
    }

    // MARK: - Flutter Communication

    private func sendToFlutter(_ method: String, arguments: Any?) {
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
            appDelegate?.carPlayChannel?.invokeMethod(method, arguments: arguments)
        }
    }
}
