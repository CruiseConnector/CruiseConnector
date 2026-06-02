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
        // 2026-06-02 (vucko v2): Apple verlangt bei Navi-Apps (carplay-maps)
        // zwingend ein CPMapTemplate als Root — ein anderes Root-Template crasht
        // zur Laufzeit. Das Login-Gate ist daher KEIN eigenes Root, sondern:
        // (a) eine persistente Sperr-Leiste auf der Karte + (b) ein Alert, der
        // ZWINGEND verzögert (DispatchQueue.main.async) präsentiert wird — sonst
        // racet er beim Scene-Connect und erscheint nie („es kommt nichts wenn
        // ausgeloggt"). refresh() wechselt live, sobald man sich am Handy einloggt.
        interfaceController.setRootTemplate(mapTemplate, animated: false)
        if isLoggedIn() {
            loggedOut = false
            showSafetyNoticeIfNeeded()
        } else {
            loggedOut = true
            applyLoggedOutState()
            presentLoginAlertIfNeeded()
        }
        refresh()
        startTimer()
    }

    private func isLoggedIn() -> Bool {
        return UserDefaults.standard.string(forKey: "flutter.cc_logged_in") == "1"
    }

    private var loggedOut = false
    private var loginAlertShown = false

    /// Sperr-Zustand auf der Karte, wenn niemand eingeloggt ist: klare Leiste
    /// oben, keine Route, einfach der eigenen Position folgen (unsere Tiles).
    private func applyLoggedOutState() {
        mapTemplate.leadingNavigationBarButtons = [
            CPBarButton(title: "🔒 Erst in der App einloggen") { [weak self] _ in
                self?.loginAlertShown = false
                self?.presentLoginAlertIfNeeded()
            }
        ]
        mapTemplate.trailingNavigationBarButtons = []
        lastRouteSignature = nil
        mapViewController.clearRoute()
        mapViewController.followUser()
    }

    /// 2026-06-02 (vucko): Alert MUSS verzögert kommen, sonst erscheint er beim
    /// Scene-Connect nicht (Race gegen CarPlays interne Initialisierung).
    private func presentLoginAlertIfNeeded() {
        guard !isLoggedIn(), !loginAlertShown else { return }
        loginAlertShown = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isLoggedIn() else { return }
            let ok = CPAlertAction(title: "Verstanden", style: .default) { _ in }
            let alert = CPAlertTemplate(
                titleVariants: [
                    "Bitte zuerst in der CruiseConnect-App am iPhone einloggen — dann lädt deine Route hier.",
                    "Bitte zuerst in der App einloggen, dann Route hier laden.",
                    "Erst in der App einloggen",
                ],
                actions: [ok]
            )
            self.interfaceController.presentTemplate(alert, animated: true)
        }
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
        // 2026-06-02 (vucko v2): Login-Gate live. Loggt man sich am Handy ein/aus,
        // wechselt CarPlay beim nächsten 2s-Tick automatisch — ohne Reconnect.
        // Karte bleibt Root (Apple-Pflicht), nur der Inhalt ändert sich.
        if !isLoggedIn() {
            if !loggedOut {
                loggedOut = true
                loginAlertShown = false
                endNavigationSession(cancel: true)
                applyLoggedOutState()
                presentLoginAlertIfNeeded()
            }
            return
        }
        if loggedOut {
            loggedOut = false
            showSafetyNoticeIfNeeded()
        }
        guard let snapshot = routeStore.readSnapshot() else {
            applyIdleState()
            endNavigationSession(cancel: true)
            return
        }
        // 2026-06-02 (vucko): Veraltet-Backstop. Ein nach App-Neustart noch in
        // UserDefaults liegender Snapshot darf KEINE Geister-Navigation starten
        // („Navigation läuft" mit alter Route, obwohl das Handy idle ist). Beim
        // aktiven Fahren schreibt das Handy alle ~3s frisch — alles älter als 90s
        // ist ein Relikt. Flutter löscht die Keys zwar beim Start, aber dieser
        // Guard gewinnt auch den Race beim Scene-Connect. So sieht CarPlay nach
        // einem Neustart IMMER frisch aus.
        if isStaleSnapshot(snapshot) {
            applyIdleState()
            endNavigationSession(cancel: true)
            return
        }
        updateMapRoute(snapshot)
        updateBarButtons(snapshot)
        updateNavigation(snapshot)
    }

    /// True, wenn der Snapshot zu alt ist, um noch echt zu sein (Relikt eines
    /// früheren App-Laufs). Fehlt updatedAtMs (alte Schreiber), gilt er als
    /// frisch genug — dann greift Flutters Clear-on-Launch.
    private func isStaleSnapshot(_ snapshot: CarPlayRouteSnapshot) -> Bool {
        guard let ms = snapshot.updatedAtMs else { return false }
        let ageSeconds = Date().timeIntervalSince1970 - ms / 1000.0
        return ageSeconds > 90
    }

    // MARK: - Karte

    private func updateMapRoute(_ snapshot: CarPlayRouteSnapshot) {
        // Nur neu zeichnen, wenn sich die Route wirklich geändert hat (Reroute),
        // nicht bei jedem 2s-Tick.
        let signature =
            "\(snapshot.routeId ?? "")|\(snapshot.fingerprint ?? "")|\(snapshot.coordinates.count)"
        guard signature != lastRouteSignature else { return }
        lastRouteSignature = signature
        // Frisch gefundene Route (Vorschau) → mit Zeichen-Animation; sonst direkt.
        if snapshot.status == "found" {
            mapViewController.animateRouteDraw(coordinates: snapshot.coordinates)
        } else {
            mapViewController.updateRoute(coordinates: snapshot.coordinates)
        }
    }

    // MARK: - Navigationsleiste (Info wenn keine Navi-Session läuft)

    private func applyIdleState() {
        dismissPostRouteIfShowing() // kein hängender Abschluss-Screen im Idle
        // 2026-06-02 (vucko Task #115): Im Auto direkt eine Route planen können
        // (Stil → km → Autobahn). Apple erlaubt listen-basierte Auswahl auch
        // während der Fahrt — kein Freitext, daher Rundkurs.
        mapTemplate.leadingNavigationBarButtons = [
            CPBarButton(title: "🧭 Route planen") { [weak self] _ in
                self?.presentStylePicker()
            }
        ]
        mapTemplate.trailingNavigationBarButtons = []
        lastRouteSignature = nil
        mapViewController.clearRoute()
        // Keine Route → Live-„Wo bin ich"-Ansicht: der eigenen Position folgen.
        mapViewController.followUser()
    }

    private func updateBarButtons(_ snapshot: CarPlayRouteSnapshot) {
        // Gefundene Route = Vorschau: „Losfahren" (Navigation starten) oder
        // „Neu konfigurieren" — wie der Bestätigen/Neu-Konfigurieren-Schritt
        // in der App.
        if snapshot.status == "found" {
            mapTemplate.leadingNavigationBarButtons = [
                CPBarButton(title: "🏍️ Losfahren") { [weak self] _ in
                    self?.startNavigationFromPreview()
                }
            ]
            mapTemplate.trailingNavigationBarButtons = [
                CPBarButton(title: "Neu konfigurieren") { [weak self] _ in
                    self?.presentStylePicker()
                }
            ]
            return
        }
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
            // Distanz für den späteren Abschluss-Screen merken (ended-Snapshot
            // hat oft keine mehr).
            lastNavDistanceMeters = snapshot.distanceMeters ?? lastNavDistanceMeters
            dismissPostRouteIfShowing() // neue Fahrt → alter Abschluss-Screen weg
            // Flüssig mit dem Standort mitführen + in Fahrtrichtung drehen.
            mapViewController.followWithHeading()
            if navigationSession == nil {
                beginNavigationSession(snapshot)
            } else {
                updateManeuver(snapshot)
            }
        } else if snapshot.status == "ended" {
            endNavigationSession(cancel: false) // angekommen → finishTrip
            showPostRouteScreenIfNeeded(snapshot)
        } else {
            // Nicht mehr „ended" (Handy hat z.B. die Bewertung abgeschlossen) →
            // Abschluss-Screen hier auch schließen (beidseitige Sync).
            dismissPostRouteIfShowing()
            endNavigationSession(cancel: true)
        }
    }

    /// 2026-06-02 (vucko Task #115): Abschluss-Screen im Auto, wenn die Tour
    /// fertig ist — kurzer Glückwunsch + zurück zur „Route planen"-Karte. Pro
    /// beendeter Route nur einmal (Signatur-Guard). Synchron mit dem Handy:
    /// „Fertig" schließt den Screen UND meldet es dem Handy (completionDone);
    /// schließt umgekehrt das Handy die Bewertung zuerst, dismisst refresh()
    /// den Screen hier automatisch (dismissPostRouteIfShowing).
    private var postRouteShownSignature: String?
    private var postRouteAlert: CPAlertTemplate?
    /// Letzte bekannte Routendistanz während der Navigation — der „ended"-
    /// Snapshot hat oft keine Distanz mehr (→ war „-- gefahren").
    private var lastNavDistanceMeters: Double?

    private func showPostRouteScreenIfNeeded(_ snapshot: CarPlayRouteSnapshot) {
        let sig = "\(snapshot.routeId ?? "")|\(snapshot.updatedAt ?? "")"
        guard postRouteShownSignature != sig else { return }
        postRouteShownSignature = sig
        let meters = snapshot.distanceMeters ?? lastNavDistanceMeters
        let titleMain: String
        if let m = meters, m > 0 {
            titleMain = "Tour beendet — \(formatDistance(m)) gefahren. Gute Fahrt war's!"
        } else {
            titleMain = "Tour beendet. Gute Fahrt war's!"
        }
        let ok = CPAlertAction(title: "Fertig", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.postRouteAlert = nil
            // Beidseitige Sync: Handy soll seine Bewertung auch schließen.
            self.writeCommand(["action": "completionDone"])
            self.interfaceController.dismissTemplate(animated: true, completion: nil)
            self.applyIdleState()
        }
        let alert = CPAlertTemplate(
            titleVariants: [titleMain, "Tour beendet. Gute Fahrt war's!", "Tour beendet"],
            actions: [ok]
        )
        postRouteAlert = alert
        DispatchQueue.main.async { [weak self] in
            self?.interfaceController.presentTemplate(alert, animated: true, completion: nil)
        }
    }

    /// Schließt den Abschluss-Screen, falls er noch offen ist — z.B. weil das
    /// Handy die Bewertung schon abgeschlossen hat (Snapshot ist nicht mehr
    /// „ended"). So verschwindet er auf beiden Geräten synchron.
    private func dismissPostRouteIfShowing() {
        guard postRouteAlert != nil else { return }
        postRouteAlert = nil
        interfaceController.dismissTemplate(animated: true, completion: nil)
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

    // MARK: - Config-Flow (Route im Auto planen)

    private var commandRequestId = 0
    private let availableStyles = ["Sport Mode", "Kurvenjagd", "Abendrunde", "Entdecker"]
    private let availableDistances = [30, 50, 75, 100]

    /// Schreibt einen Befehl für die Flutter-Seite (CarCommandListener) in
    /// UserDefaults. Monoton steigende requestId, damit Flutter nur neue
    /// Befehle ausführt. Key mit `flutter.`-Präfix (shared_preferences-Konvention).
    private func writeCommand(_ payload: [String: Any]) {
        commandRequestId += 1
        var dict = payload
        dict["requestId"] = commandRequestId
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: "flutter.car_command")
        }
    }

    private func styleDisplayName(_ style: String) -> String {
        switch style {
        case "Sport Mode": return "Sport — flüssig & schnell"
        case "Kurvenjagd": return "Kurvenjagd — maximale Kurven"
        case "Abendrunde": return "Abendrunde — ruhig & entspannt"
        case "Entdecker": return "Entdecker — neue Strecken"
        default: return style
        }
    }

    /// Schritt 1: Fahrstil.
    private func presentStylePicker() {
        guard isLoggedIn() else { presentLoginAlertIfNeeded(); return }
        let items: [CPListItem] = availableStyles.map { style in
            let item = CPListItem(text: styleDisplayName(style), detailText: nil)
            item.handler = { [weak self] _, completion in
                self?.presentDistancePicker(style: style)
                completion()
            }
            return item
        }
        let template = CPListTemplate(
            title: "Fahrstil wählen",
            sections: [CPListSection(items: items)]
        )
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// Schritt 2: Distanz.
    private func presentDistancePicker(style: String) {
        let items: [CPListItem] = availableDistances.map { km in
            let item = CPListItem(text: "\(km) km", detailText: nil)
            item.handler = { [weak self] _, completion in
                self?.presentHighwayPicker(style: style, km: km)
                completion()
            }
            return item
        }
        let template = CPListTemplate(
            title: "Distanz wählen",
            sections: [CPListSection(items: items)]
        )
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// Schritt 3: Autobahn an/aus (User-Terminologie: voll ausschreiben).
    private func presentHighwayPicker(style: String, km: Int) {
        let on = CPListItem(text: "Autobahn an", detailText: "Autobahn erlaubt")
        on.handler = { [weak self] _, completion in
            self?.submitPlan(style: style, km: km, avoidHighways: false)
            completion()
        }
        let off = CPListItem(text: "Autobahn aus", detailText: "Autobahn vermeiden")
        off.handler = { [weak self] _, completion in
            self?.submitPlan(style: style, km: km, avoidHighways: true)
            completion()
        }
        let template = CPListTemplate(
            title: "Autobahn",
            sections: [CPListSection(items: [on, off])]
        )
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// Schickt die Konfiguration an Flutter und kehrt zur Karte zurück. Der
    /// Snapshot wechselt dann auf „searching" → „found" (Vorschau).
    private func submitPlan(style: String, km: Int, avoidHighways: Bool) {
        writeCommand([
            "action": "planRoute",
            "style": style,
            "distanceKm": km,
            "avoidHighways": avoidHighways,
        ])
        lastRouteSignature = nil // erzwingt Neu-Zeichnen der kommenden Route
        interfaceController.popToRootTemplate(animated: true, completion: nil)
    }

    /// „Losfahren" aus der Vorschau → Navigation starten (Flutter übernimmt
    /// GPS-Tracking, falls die Cruise-Page offen ist; sonst Auto-Navi pur).
    private func startNavigationFromPreview() {
        writeCommand(["action": "startNavigation"])
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
    private var drawTimer: Timer?

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
        // 2026-06-02 (vucko v2): Zoom-Untergrenze auf ~z12 angehoben (2400m).
        // Grund: bei z13+ überzoomt die Karte unsere z12-Tiles → (a) dunkel/
        // unscharf, (b) die Overzoom-Subklasse muss JEDE Kachel croppen+skalieren
        // (CPU-Last pro Tile → ruckelt, „es kracht"). Bei ≤z12 werden die Tiles
        // NATIV geladen (gestochen scharf wie auf dem Handy) und der Overzoom-
        // Pfad entfällt komplett → flüssig. Fürs Cruisen sieht man so auch mehr
        // von der kommenden Strecke. Rauszoomen bleibt frei (Route-Übersicht).
        mapView.setCameraZoomRange(
            MKMapView.CameraZoomRange(minCenterCoordinateDistance: 2400),
            animated: false
        )
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
        // 2026-06-02 (vucko): DACH ist als z6–12 gerendert (kein flächiges z13).
        // maxRenderedZ=12 → z6–12 direkt, z13+ überzoomt aus z12 (überall gültig,
        // kein 404/Apple-Grün). Vorher 13 → z13 außerhalb Vorarlberg fehlte.
        let overlay = OverzoomTileOverlay(urlTemplate: template, maxRenderedZ: 12)
        // 2026-06-02 (vucko): canReplaceMapContent=true → MapKit zeichnet seine
        // EIGENE Karte gar nicht erst darunter. Vorher (false) blitzte beim
        // Zoomen/Pannen die Apple-Karte durch, bis unsere Kacheln nachgeladen
        // waren („Apple-Style poppt auf, höherer Kontrast"). Jetzt nur noch
        // unser Look (dort wo gerendert) bzw. dunkler Grund beim Nachladen.
        overlay.canReplaceMapContent = true
        overlay.tileSize = CGSize(width: 512, height: 512)
        overlay.minimumZ = 6
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

    /// 2026-06-02 (vucko Task #115): Route-Vorschau mit „Zeichen-Animation" wie
    /// in der App — die Linie wächst in ~0,7s vom Start zum Ziel. Umgesetzt als
    /// progressives Reveal (wachsende Polyline), da MapKit kein natives
    /// Linien-Stroke-Animieren bietet.
    func animateRouteDraw(coordinates: [[Double]]) {
        drawTimer?.invalidate()
        clearRoute()
        let pts = coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard pts.count >= 2 else { return }
        mapView.setUserTrackingMode(.none, animated: false)
        let full = MKPolyline(coordinates: pts, count: pts.count)
        mapView.setVisibleMapRect(
            full.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
            animated: true
        )
        let steps = 18
        var step = 1
        let timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if step >= steps {
                t.invalidate()
                if let existing = self.routeOverlay { self.mapView.removeOverlay(existing) }
                self.mapView.addOverlay(full)
                self.routeOverlay = full
                return
            }
            let count = max(2, Int(Double(pts.count) * Double(step) / Double(steps)))
            let slice = Array(pts.prefix(count))
            if let existing = self.routeOverlay { self.mapView.removeOverlay(existing) }
            let pl = MKPolyline(coordinates: slice, count: slice.count)
            self.mapView.addOverlay(pl)
            self.routeOverlay = pl
            step += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        drawTimer = timer
    }

    func clearRoute() {
        drawTimer?.invalidate()
        drawTimer = nil
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
