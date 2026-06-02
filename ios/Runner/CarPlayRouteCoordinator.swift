import Foundation
import UIKit

#if canImport(CarPlay)
import CarPlay
import MapKit

/// Steuert die CarPlay-Oberfläche.
///
/// 2026-06-01 (vucko): Aus der statischen Info-Anzeige (CPMapTemplate +
/// Bar-Buttons, manueller "Aktualisieren"-Button, keine echte Navigation) wurde
/// eine echte CarPlay-Navigation:
///  - **Live-Update** per 2-Sekunden-Timer statt Tippen.
///  - **Echte Karte**: eine MKMapView im CPWindow zeichnet die Route-Polylinie.
///  - **Echte Navi-Session**: `startNavigationSession` + `CPManeuver` (mit
///    richtungsabhängigem Symbol) + laufende `CPTravelEstimates`. Damit zeigt
///    CarPlay echte Abbiege-Hinweise — Voraussetzung für Apples Navi-Freigabe.
///
/// Hinweis: Die volle Navi-Session ist erst nach Freigabe des
/// `com.apple.developer.carplay-maps`-Entitlements auf echter Hardware aktiv
/// (Apple-Antrag läuft). Der Code kompiliert und läuft unabhängig davon.
@available(iOS 14.0, *)
final class CarPlayRouteCoordinator: NSObject {
    private let interfaceController: CPInterfaceController
    private let window: CPWindow
    private let routeStore: CarPlayRouteSnapshotStore
    private let mapTemplate = CPMapTemplate()
    private let mapViewController = CarPlayMapViewController()

    private var refreshTimer: Timer?
    private var navigationSession: CPNavigationSession?
    private var activeManeuver: CPManeuver?
    private var lastRouteSignature: String?

    init(
        interfaceController: CPInterfaceController,
        window: CPWindow,
        routeStore: CarPlayRouteSnapshotStore = CarPlayRouteSnapshotStore()
    ) {
        self.interfaceController = interfaceController
        self.window = window
        self.routeStore = routeStore
        super.init()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func start() {
        window.rootViewController = mapViewController
        mapTemplate.automaticallyHidesNavigationBar = false
        configureMapButtons()
        interfaceController.setRootTemplate(mapTemplate, animated: false)
        showSafetyNoticeIfNeeded()
        refresh()
        startTimer()
    }

    /// Karten-Buttons im Maps-Stil: Zentrieren, Zoom raus, Zoom rein.
    private func configureMapButtons() {
        let recenter = CPMapButton { [weak self] _ in self?.mapViewController.recenterOnRoute() }
        recenter.image = UIImage(systemName: "location.fill")
        let zoomOut = CPMapButton { [weak self] _ in self?.mapViewController.zoomOut() }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")
        let zoomIn = CPMapButton { [weak self] _ in self?.mapViewController.zoomIn() }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")
        mapTemplate.mapButtons = [recenter, zoomOut, zoomIn]
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refresh() {
        // Meldet der Handy-App, dass CarPlay verbunden ist → reduzierte
        // Manöver-Ansicht am Handy (Key mit flutter.-Präfix wie shared_preferences).
        UserDefaults.standard.set(
            ISO8601DateFormatter().string(from: Date()),
            forKey: "flutter.car_connected_at"
        )
        guard let snapshot = routeStore.readSnapshot() else {
            applyIdleState()
            endNavigationSession(cancel: true)
            return
        }
        updateMapRoute(snapshot)
        updateBarButtons(snapshot)
        updateNavigation(snapshot)
    }

    // MARK: - Karte

    private func updateMapRoute(_ snapshot: CarPlayRouteSnapshot) {
        // Nur neu zeichnen, wenn sich die Route wirklich geändert hat (Reroute),
        // nicht bei jedem 2s-Tick.
        let signature =
            "\(snapshot.routeId ?? "")|\(snapshot.fingerprint ?? "")|\(snapshot.coordinates.count)"
        guard signature != lastRouteSignature else { return }
        lastRouteSignature = signature
        mapViewController.updateRoute(coordinates: snapshot.coordinates)
    }

    // MARK: - Navigationsleiste (Info wenn keine Navi-Session läuft)

    private func applyIdleState() {
        mapTemplate.leadingNavigationBarButtons = [
            CPBarButton(title: "Route am Handy starten – erscheint hier") { _ in }
        ]
        mapTemplate.trailingNavigationBarButtons = []
        lastRouteSignature = nil
        mapViewController.clearRoute()
        // Keine Route → Live-„Wo bin ich"-Ansicht: der eigenen Position folgen.
        mapViewController.followUser()
    }

    private func updateBarButtons(_ snapshot: CarPlayRouteSnapshot) {
        let distance = formatDistance(snapshot.remainingDistanceMeters ?? snapshot.distanceMeters)
        let duration = formatDuration(snapshot.remainingDurationSeconds ?? snapshot.durationSeconds)
        mapTemplate.leadingNavigationBarButtons = [
            CPBarButton(title: title(for: snapshot)) { _ in }
        ]
        mapTemplate.trailingNavigationBarButtons = [
            CPBarButton(title: "\(distance) • \(duration)") { _ in }
        ]
    }

    // MARK: - Echte Navi-Session

    private func updateNavigation(_ snapshot: CarPlayRouteSnapshot) {
        let navigating = snapshot.status == "navigating" && snapshot.hasRoute
        if navigating {
            // Flüssig mit dem Standort mitführen + in Fahrtrichtung drehen.
            mapViewController.followWithHeading()
            if navigationSession == nil {
                beginNavigationSession(snapshot)
            } else {
                updateManeuver(snapshot)
            }
        } else if snapshot.status == "ended" {
            endNavigationSession(cancel: false) // angekommen → finishTrip
        } else {
            endNavigationSession(cancel: true)
        }
    }

    private func beginNavigationSession(_ snapshot: CarPlayRouteSnapshot) {
        let trip = makeTrip(snapshot)
        let session = mapTemplate.startNavigationSession(for: trip)
        let maneuver = makeManeuver(snapshot)
        session.upcomingManeuvers = [maneuver]
        navigationSession = session
        activeManeuver = maneuver
        updateManeuver(snapshot)
    }

    private func updateManeuver(_ snapshot: CarPlayRouteSnapshot) {
        guard let session = navigationSession else { return }
        let estimates = travelEstimates(
            distance: snapshot.nextManeuverDistance ?? snapshot.remainingDistanceMeters,
            seconds: snapshot.remainingDurationSeconds
        )
        let fresh = makeManeuver(snapshot)
        // Manöver nur austauschen, wenn sich der Hinweis geändert hat.
        if fresh.instructionVariants != activeManeuver?.instructionVariants {
            session.upcomingManeuvers = [fresh]
            activeManeuver = fresh
        }
        if let current = activeManeuver {
            session.updateEstimates(estimates, for: current)
        }
    }

    private func endNavigationSession(cancel: Bool) {
        guard let session = navigationSession else { return }
        if cancel {
            session.cancelTrip()
        } else {
            session.finishTrip()
        }
        navigationSession = nil
        activeManeuver = nil
    }

    // MARK: - Bau-Helfer

    private func makeTrip(_ snapshot: CarPlayRouteSnapshot) -> CPTrip {
        let originCoord = snapshot.coordinates.first.flatMap(coordinate) ?? CLLocationCoordinate2D()
        let destCoord = snapshot.coordinates.last.flatMap(coordinate) ?? originCoord
        let origin = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        destination.name = title(for: snapshot)
        let summary =
            "\(formatDistance(snapshot.distanceMeters)) • \(formatDuration(snapshot.durationSeconds))"
        let routeChoice = CPRouteChoice(
            summaryVariants: [summary],
            additionalInformationVariants: [snapshot.style ?? "Cruise Route"],
            selectionSummaryVariants: [title(for: snapshot)]
        )
        return CPTrip(origin: origin, destination: destination, routeChoices: [routeChoice])
    }

    private func makeManeuver(_ snapshot: CarPlayRouteSnapshot) -> CPManeuver {
        let maneuver = CPManeuver()
        maneuver.instructionVariants = [snapshot.nextManeuverText ?? "Route folgen"]
        maneuver.initialTravelEstimates = travelEstimates(
            distance: snapshot.nextManeuverDistance ?? snapshot.remainingDistanceMeters,
            seconds: snapshot.remainingDurationSeconds
        )
        if let symbol = maneuverSymbol(snapshot.nextManeuverKind) {
            maneuver.symbolImage = symbol
        }
        return maneuver
    }

    private func travelEstimates(distance: Double?, seconds: Double?) -> CPTravelEstimates {
        return CPTravelEstimates(
            distanceRemaining: Measurement(value: max(0, distance ?? 0), unit: UnitLength.meters),
            timeRemaining: max(0, seconds ?? 0)
        )
    }

    private func coordinate(_ pair: [Double]) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else { return nil }
        // Snapshot-Koordinaten sind [longitude, latitude] (Mapbox-Konvention).
        return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
    }

    /// Übersetzt den Manöver-Kind in ein SF-Symbol für die CarPlay-Abbiegekarte.
    private func maneuverSymbol(_ kind: String?) -> UIImage? {
        let name: String
        switch kind {
        case "turnLeft": name = "arrow.turn.up.left"
        case "turnRight": name = "arrow.turn.up.right"
        case "slightLeft": name = "arrow.up.left"
        case "slightRight": name = "arrow.up.right"
        case "sharpLeft": name = "arrow.turn.up.left"
        case "sharpRight": name = "arrow.turn.up.right"
        case "uturn": name = "arrow.uturn.down"
        case "roundabout": name = "arrow.triangle.2.circlepath"
        case "rampLeft", "forkLeft": name = "arrow.up.left"
        case "rampRight", "forkRight": name = "arrow.up.right"
        case "merge": name = "arrow.merge"
        case "arrive": name = "flag.checkered"
        default: name = "arrow.up"
        }
        return UIImage(systemName: name)
    }

    // MARK: - Sicherheitshinweis

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

    // MARK: - Formatierung

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

/// Vollflächige MKMapView im CarPlay-Fenster, die die aktive Route als dunkle
/// Karte mit roter Linie zeichnet. Liegt bewusst in derselben Datei wie der
/// Coordinator, damit keine neue Datei im Xcode-Projekt registriert werden muss.
@available(iOS 14.0, *)
final class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    private let mapView = MKMapView()
    private var routeOverlay: MKPolyline?

    override func loadView() {
        view = mapView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.pointOfInterestFilter = .excludingAll
        // 2026-06-02 (vucko): Standort live anzeigen + ihm folgen, damit die
        // CarPlay-Karte sofort nützlich ist (User sah nach dem Disclaimer eine
        // leere Karte). Wie die Cruise-Mode-Page: Karte + eigene Position immer
        // sichtbar. Route-Planung bleibt bewusst am Handy (Apple-Guideline) —
        // eine geplante Route erscheint hier automatisch.
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        if #available(iOS 13.0, *) {
            mapView.overrideUserInterfaceStyle = .dark
        }
        addCruiseTileOverlay()
    }

    /// 2026-06-02 (vucko): UNSER eigener Karten-Look in CarPlay. Wir legen die
    /// gerasterten Cruise-Dark-Tiles (aus R2, gerendert aus unserem PMTiles-
    /// Style) als Overlay über die Apple-Karte. So sieht CarPlay aus wie unsere
    /// App, nicht wie Apple Maps. canReplaceMapContent=false → außerhalb der
    /// gerenderten Abdeckung fällt es auf die Apple-Karte zurück (kein Schwarz).
    /// tileSize 512 passt zum 512er-Rendering (retina über @2x-PNG).
    private func addCruiseTileOverlay() {
        let template =
            "https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/raster/{z}/{x}/{y}.png"
        // 2026-06-02 (vucko): Eigene Overzoom-Overlay. MKTileOverlay überzoomt
        // NICHT von selbst über maximumZ hinaus → bei Navi-Zoom (z14+) gab's
        // keine Kachel → Apple-Grün (genau der Bug nach Routenbestätigung).
        // Die Subklasse holt bei hohem Zoom die höchste gerenderte Kachel (z13),
        // schneidet den passenden Teilbereich aus + skaliert ihn → unser Look
        // bleibt bei JEDER Zoomstufe. maximumZ hoch (19) damit MapKit überhaupt
        // anfragt; minimumZ = unterste gerenderte Stufe.
        let overlay = OverzoomTileOverlay(urlTemplate: template, maxRenderedZ: 13)
        // 2026-06-02 (vucko): canReplaceMapContent=true → MapKit zeichnet seine
        // EIGENE Karte gar nicht erst darunter. Vorher (false) blitzte beim
        // Zoomen/Pannen die Apple-Karte durch, bis unsere Kacheln nachgeladen
        // waren („Apple-Style poppt auf, höherer Kontrast"). Jetzt nur noch
        // unser Look (dort wo gerendert) bzw. dunkler Grund beim Nachladen.
        overlay.canReplaceMapContent = true
        overlay.tileSize = CGSize(width: 512, height: 512)
        overlay.minimumZ = 9
        overlay.maximumZ = 19
        mapView.addOverlay(overlay, level: .aboveLabels)
    }

    /// Folgt der eigenen Position (nur wenn keine Route aktiv ist) → „Wo bin
    /// ich"-Live-Ansicht im Leerlauf.
    func followUser() {
        guard routeOverlay == nil else { return }
        if mapView.userTrackingMode != .follow {
            mapView.setUserTrackingMode(.follow, animated: true)
        }
    }

    /// 2026-06-02 (vucko): Aktive Navigation → Kamera führt flüssig mit dem
    /// Standort mit und dreht in Fahrtrichtung (heading-up), wie die
    /// Cruise-Mode-Page am Handy. MapKit animiert den blauen Punkt + die
    /// Kamerafahrt nativ weich bei jedem GPS-Update.
    func followWithHeading() {
        if mapView.userTrackingMode != .followWithHeading {
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }

    func updateRoute(coordinates: [[Double]]) {
        clearRoute()
        let points = coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard points.count >= 2 else { return }
        // Route aktiv → nicht mehr dem Standort folgen, sondern die Route zeigen.
        mapView.setUserTrackingMode(.none, animated: false)
        let polyline = MKPolyline(coordinates: points, count: points.count)
        mapView.addOverlay(polyline)
        routeOverlay = polyline
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
            animated: true
        )
    }

    func clearRoute() {
        if let existing = routeOverlay {
            mapView.removeOverlay(existing)
            routeOverlay = nil
        }
    }

    // MARK: - Karten-Steuerung (CPMapButtons)

    func zoomIn() {
        var region = mapView.region
        region.span.latitudeDelta = max(region.span.latitudeDelta * 0.5, 0.001)
        region.span.longitudeDelta = max(region.span.longitudeDelta * 0.5, 0.001)
        mapView.setRegion(region, animated: true)
    }

    func zoomOut() {
        var region = mapView.region
        region.span.latitudeDelta = min(region.span.latitudeDelta * 2.0, 80.0)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 2.0, 80.0)
        mapView.setRegion(region, animated: true)
    }

    func recenterOnRoute() {
        guard let overlay = routeOverlay else { return }
        mapView.setVisibleMapRect(
            overlay.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
            animated: true
        )
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        // Unsere gerasterten Cruise-Dark-Kacheln.
        if let tileOverlay = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        renderer.lineWidth = 6
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }
}

/// 2026-06-02 (vucko): Raster-Overlay, das über die höchste gerenderte Zoom-
/// stufe hinaus „überzoomt", indem es die Vorfahr-Kachel ausschneidet +
/// skaliert. So zeigt CarPlay unseren eigenen Cruise-Dark-Look bei JEDER
/// Zoomstufe (auch Navi z14+), statt auf die Apple-Karte zu fallen.
@available(iOS 14.0, *)
final class OverzoomTileOverlay: MKTileOverlay {
    private let maxRenderedZ: Int
    private let session = URLSession(configuration: .default)

    init(urlTemplate: String?, maxRenderedZ: Int) {
        self.maxRenderedZ = maxRenderedZ
        super.init(urlTemplate: urlTemplate)
    }

    private func tileURL(_ z: Int, _ x: Int, _ y: Int) -> URL? {
        guard let t = urlTemplate else { return nil }
        let s = t
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
        return URL(string: s)
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        // Innerhalb des gerenderten Bereichs: Kachel direkt laden.
        if path.z <= maxRenderedZ {
            guard let url = tileURL(path.z, path.x, path.y) else {
                result(nil, nil); return
            }
            session.dataTask(with: url) { data, _, err in result(data, err) }.resume()
            return
        }
        // Überzoom: Vorfahr-Kachel auf maxRenderedZ holen, Teilbereich ausschneiden.
        let dz = path.z - maxRenderedZ
        let factor = 1 << dz
        let ax = path.x >> dz
        let ay = path.y >> dz
        guard let url = tileURL(maxRenderedZ, ax, ay) else { result(nil, nil); return }
        let subX = path.x - (ax << dz)
        let subY = path.y - (ay << dz)
        let tile = tileSize
        session.dataTask(with: url) { data, _, err in
            guard let data, let img = UIImage(data: data), let cg = img.cgImage else {
                result(data, err); return
            }
            let w = CGFloat(cg.width) / CGFloat(factor)
            let h = CGFloat(cg.height) / CGFloat(factor)
            let rect = CGRect(x: CGFloat(subX) * w, y: CGFloat(subY) * h, width: w, height: h)
            guard let sub = cg.cropping(to: rect) else { result(data, nil); return }
            let renderer = UIGraphicsImageRenderer(size: tile)
            let out = renderer.image { ctx in
                ctx.cgContext.interpolationQuality = .high
                UIImage(cgImage: sub).draw(in: CGRect(origin: .zero, size: tile))
            }
            result(out.pngData() ?? data, nil)
        }.resume()
    }
}
#endif
