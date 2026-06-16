import Foundation
import UIKit

#if canImport(CarPlay)
import CarPlay
import MapKit
import MapLibre

/// Planungs-Modus für die CarPlay-Routenplanung (passend zu CarRouteType auf
/// der Flutter-Seite).
enum CarPlanMode {
    static let roundtrip = "roundtrip"
    static let pointToPoint = "point_to_point"
}

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
    private var activeTrip: CPTrip?
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
        mapTemplate.mapDelegate = self
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        configureMapButtons()
        // 2026-06-02 (vucko v2): Apple verlangt bei Navi-Apps (carplay-maps)
        // zwingend ein CPMapTemplate als Root — ein anderes Root-Template crasht
        // zur Laufzeit. Das Login-Gate ist daher KEIN eigenes Root, sondern:
        // (a) eine persistente Sperr-Leiste auf der Karte + (b) ein Alert, der
        // ZWINGEND verzögert (DispatchQueue.main.async) präsentiert wird — sonst
        // racet er beim Scene-Connect und erscheint nie („es kommt nichts wenn
        // ausgeloggt"). refresh() wechselt live, sobald man sich am Handy einloggt.
        interfaceController.setRootTemplate(mapTemplate, animated: false) { [weak self] success, error in
            self?.logTemplateTransition("setRootTemplate", success: success, error: error)
        }
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
            self.presentModalTemplate(alert, reason: "loginAlert") { [weak self] in
                self?.loginAlertShown = false
            }
        }
    }

    /// Karten-Buttons im Maps-Stil: Bewegen (Panning), Zentrieren, Zoom.
    /// 2026-06-14 (vucko K2): „Bewegen"-Button öffnet die CarPlay-Panning-
    /// Schnittstelle (Pfeile + Fertig) → Karte frei bewegbar. Zoom-Buttons
    /// verlassen vorher den Follow-Modus (sonst überschreibt die Folge-Kamera
    /// den Zoom sofort → „Rauszoomen geht nicht"). „Zentrieren" stellt Follow
    /// wieder her.
    private func configureMapButtons() {
        let pan = CPMapButton { [weak self] _ in
            self?.mapTemplate.showPanningInterface(animated: true)
        }
        pan.image = UIImage(systemName: "hand.draw")
        let recenter = CPMapButton { [weak self] _ in self?.mapViewController.recenterOnRoute() }
        recenter.image = UIImage(systemName: "location.fill")
        let zoomOut = CPMapButton { [weak self] _ in self?.mapViewController.zoomOut() }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")
        let zoomIn = CPMapButton { [weak self] _ in self?.mapViewController.zoomIn() }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")
        mapTemplate.mapButtons = [pan, recenter, zoomOut, zoomIn]
    }

    private func logTemplateTransition(_ action: String, success: Bool, error: Error?) {
        guard !success else { return }
        if let error {
            NSLog("[CruiseConnect CarPlay] \(action) failed: \(error.localizedDescription)")
        } else {
            NSLog("[CruiseConnect CarPlay] \(action) failed")
        }
    }

    /// CarPlay wirft eine Objective-C-Exception, wenn Template-Operationen ohne
    /// Completion fehlschlagen. Deshalb laufen alle modalen Screens über diesen
    /// Guard: nur ein Modal gleichzeitig und Fehler werden geloggt statt App-Abbruch.
    private func presentModalTemplate(
        _ template: CPTemplate,
        reason: String,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.interfaceController.presentedTemplate == nil else {
                NSLog("[CruiseConnect CarPlay] \(reason) skipped: modal already presented")
                onFailure?()
                return
            }
            self.interfaceController.presentTemplate(template, animated: true) { [weak self] success, error in
                self?.logTemplateTransition(reason, success: success, error: error)
                if success {
                    onSuccess?()
                } else {
                    onFailure?()
                }
            }
        }
    }

    private func dismissPresentedTemplate(_ expectedTemplate: CPTemplate? = nil, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let presented = self.interfaceController.presentedTemplate else { return }
            if let expectedTemplate, presented !== expectedTemplate { return }
            self.interfaceController.dismissTemplate(animated: true) { [weak self] success, error in
                self?.logTemplateTransition(reason, success: success, error: error)
            }
        }
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        // 2026-06-14 (vucko K7 Sync straffer): 2s→1s. Zusammen mit dem 1s-Handy-
        // Throttle liegt das Auto jetzt ≤2s hinter dem Handy (vorher ~5s).
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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
        // 2026-06-14 (vucko K3): Signatur ERST setzen, wenn wirklich gezeichnet
        // wurde. War der MapLibre-Style beim Scene-Connect noch nicht geladen,
        // gibt updateRoute false zurück → der nächste 2s-Tick versucht es erneut,
        // bis der Style da ist. Vorher wurde die Signatur sofort gesetzt und die
        // Route blieb (Style-noch-nicht-bereit) für immer unsichtbar.
        let drew: Bool
        if snapshot.status == "found" {
            drew = mapViewController.animateRouteDraw(coordinates: snapshot.coordinates)
        } else {
            drew = mapViewController.updateRoute(coordinates: snapshot.coordinates)
        }
        if drew { lastRouteSignature = signature }
    }

    // MARK: - Navigationsleiste (Info wenn keine Navi-Session läuft)

    private func applyIdleState() {
        dismissPostRouteIfShowing() // kein hängender Abschluss-Screen im Idle
        // 2026-06-14 (vucko K5/K6): Modus-Toggle oben links — Rundkurs ⇄ A→B.
        // Rundkurs: Stil → km → Autobahn (Liste). A→B: Adress-Suche
        // (CPSearchTemplate, von Apple beim Fahren erlaubt). Der zweite Button
        // passt sich dem Modus an.
        let modeButton = CPBarButton(
            title: planMode == CarPlanMode.roundtrip ? "↻ Rundkurs" : "→ A nach B"
        ) { [weak self] _ in
            guard let self = self else { return }
            self.planMode = self.planMode == CarPlanMode.roundtrip
                ? CarPlanMode.pointToPoint
                : CarPlanMode.roundtrip
            self.applyIdleState() // Leiste neu zeichnen
        }
        let actionButton = CPBarButton(
            title: planMode == CarPlanMode.roundtrip ? "🧭 Route planen" : "🔍 Ziel suchen"
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.planMode == CarPlanMode.roundtrip {
                self.presentStylePicker()
            } else {
                self.presentDestinationSearch()
            }
        }
        mapTemplate.leadingNavigationBarButtons = [modeButton, actionButton]
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
        let sig = postRouteSignature(for: snapshot)
        guard postRouteAlert == nil, postRouteShownSignature != sig else { return }
        let meters = snapshot.distanceMeters ?? lastNavDistanceMeters
        let titleMain: String
        if let m = meters, m > 0 {
            titleMain = "Tour beendet — \(formatDistance(m)) gefahren. Gute Fahrt war's!"
        } else {
            titleMain = "Tour beendet. Gute Fahrt war's!"
        }
        let ok = CPAlertAction(title: "Fertig", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let alert = self.postRouteAlert
            self.postRouteAlert = nil
            // Beidseitige Sync: Handy soll seine Bewertung auch schließen.
            self.writeCommand(["action": "completionDone"])
            self.dismissPresentedTemplate(alert, reason: "postRouteActionDismiss")
            self.applyIdleState()
        }
        let alert = CPAlertTemplate(
            titleVariants: [titleMain, "Tour beendet. Gute Fahrt war's!", "Tour beendet"],
            actions: [ok]
        )
        postRouteAlert = alert
        presentModalTemplate(
            alert,
            reason: "postRouteAlert",
            onSuccess: { [weak self, weak alert] in
                guard let self = self, let alert = alert, self.postRouteAlert === alert else { return }
                self.postRouteShownSignature = sig
            },
            onFailure: { [weak self, weak alert] in
                guard let self = self else { return }
                if let alert = alert, self.postRouteAlert === alert {
                    self.postRouteAlert = nil
                }
            }
        )
    }

    private func postRouteSignature(for snapshot: CarPlayRouteSnapshot) -> String {
        if let routeId = snapshot.routeId, !routeId.isEmpty { return "route:\(routeId)" }
        if let fingerprint = snapshot.fingerprint, !fingerprint.isEmpty { return "fp:\(fingerprint)" }
        let meters = Int(((snapshot.distanceMeters ?? lastNavDistanceMeters ?? 0) / 10).rounded())
        return "fallback:\(snapshot.routeType):\(meters)"
    }

    /// Schließt den Abschluss-Screen, falls er noch offen ist — z.B. weil das
    /// Handy die Bewertung schon abgeschlossen hat (Snapshot ist nicht mehr
    /// „ended"). So verschwindet er auf beiden Geräten synchron.
    private func dismissPostRouteIfShowing() {
        guard let alert = postRouteAlert else { return }
        postRouteAlert = nil
        dismissPresentedTemplate(alert, reason: "postRouteDismiss")
    }

    private func beginNavigationSession(_ snapshot: CarPlayRouteSnapshot) {
        let trip = makeTrip(snapshot)
        let session = mapTemplate.startNavigationSession(for: trip)
        let maneuver = makeManeuver(snapshot)
        session.upcomingManeuvers = [maneuver]
        navigationSession = session
        activeManeuver = maneuver
        activeTrip = trip
        updateManeuver(snapshot)
    }

    private func updateManeuver(_ snapshot: CarPlayRouteSnapshot) {
        guard let session = navigationSession else { return }
        let info = nextManeuverDisplay(snapshot)
        // Manöver-Karte: Distanz + Zeit bis zur NÄCHSTEN Kurve.
        let maneuverEstimates = travelEstimates(
            distance: info.distance,
            seconds: info.seconds
        )
        let fresh = makeManeuver(snapshot)
        if fresh.instructionVariants != activeManeuver?.instructionVariants {
            session.upcomingManeuvers = [fresh]
            activeManeuver = fresh
        }
        if let current = activeManeuver {
            session.updateEstimates(maneuverEstimates, for: current)
        }
        // Trip-Leiste unten: Rest-Distanz + Rest-Zeit bis zum Ziel.
        if let trip = activeTrip {
            let tripEstimates = travelEstimates(
                distance: snapshot.remainingDistanceMeters ?? snapshot.distanceMeters,
                seconds: snapshot.remainingDurationSeconds ?? snapshot.durationSeconds
            )
            mapTemplate.updateEstimates(tripEstimates, for: trip)
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
        activeTrip = nil
    }

    /// 2026-06-02 (vucko): Ermittelt das nächste Manöver + Distanz dorthin
    /// CarPlay-SEITIG aus dem eigenen Standort + den Manöver-Koordinaten. So
    /// zeigt CarPlay „300m rechts abbiegen" live — auch wenn das Handy keine
    /// Progress-Updates schickt (z.B. eine auf CarPlay gestartete Route).
    /// nextManeuverDistance im Snapshot war hier null → CarPlay zeigte die
    /// VOLLE Routendistanz (75km) als Abbiege-Distanz. Fällt auf Snapshot zurück.
    private func nextManeuverDisplay(_ snapshot: CarPlayRouteSnapshot)
        -> (text: String, kind: String?, distance: Double, seconds: Double) {
        let dist = snapshot.distanceMeters ?? 0
        let dur = snapshot.durationSeconds ?? 0
        let avgSpeed = (dist > 0 && dur > 0) ? dist / dur : 13.9 // ~50 km/h Fallback
        if let user = mapViewController.currentUserCoordinate,
           snapshot.coordinates.count >= 2 {
            let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)
            var userIdx = 0
            var bestD = Double.greatestFiniteMagnitude
            for (i, p) in snapshot.coordinates.enumerated() where p.count >= 2 {
                let d = userLoc.distance(
                    from: CLLocation(latitude: p[1], longitude: p[0]))
                if d < bestD { bestD = d; userIdx = i }
            }
            let upcoming = snapshot.maneuvers
                .filter { $0.latitude != nil && $0.longitude != nil && $0.routeIndex >= userIdx }
                .min(by: { $0.routeIndex < $1.routeIndex })
            if let m = upcoming, let mlat = m.latitude, let mlng = m.longitude {
                let d = userLoc.distance(from: CLLocation(latitude: mlat, longitude: mlng))
                let text = !m.instruction.isEmpty
                    ? m.instruction
                    : (!m.announcement.isEmpty ? m.announcement : "Route folgen")
                return (text, m.kind, d, max(5, d / avgSpeed))
            }
        }
        let fallbackDist = snapshot.nextManeuverDistance
            ?? snapshot.remainingDistanceMeters ?? 0
        return (
            snapshot.nextManeuverText ?? "Route folgen",
            snapshot.nextManeuverKind,
            fallbackDist,
            snapshot.remainingDurationSeconds ?? (fallbackDist / avgSpeed)
        )
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
        let info = nextManeuverDisplay(snapshot)
        let maneuver = CPManeuver()
        maneuver.instructionVariants = [info.text]
        maneuver.initialTravelEstimates = travelEstimates(
            distance: info.distance,
            seconds: info.seconds
        )
        if let symbol = maneuverSymbol(info.kind) {
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
        presentModalTemplate(alert, reason: "safetyNotice")
    }

    // MARK: - Config-Flow (Route im Auto planen)

    private var commandRequestId = 0
    private let availableStyles = ["Sport Mode", "Kurvenjagd", "Abendrunde", "Entdecker"]
    // 2026-06-09 (vucko): exakt die App-Distanzen 25/50/75/100 km (vorher 30).
    private let availableDistances = [25, 50, 75, 100]
    // 2026-06-14 (vucko K5/K6): Planungs-Modus oben links + A→B-Adress-Suche.
    private var planMode = CarPlanMode.roundtrip
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchResultsHandler: (([CPListItem]) -> Void)?
    private var lastSearchCompletions: [MKLocalSearchCompletion] = []

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
        interfaceController.pushTemplate(template, animated: true) { [weak self] success, error in
            self?.logTemplateTransition("pushStylePicker", success: success, error: error)
        }
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
        interfaceController.pushTemplate(template, animated: true) { [weak self] success, error in
            self?.logTemplateTransition("pushDistancePicker", success: success, error: error)
        }
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
        interfaceController.pushTemplate(template, animated: true) { [weak self] success, error in
            self?.logTemplateTransition("pushHighwayPicker", success: success, error: error)
        }
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
        interfaceController.popToRootTemplate(animated: true) { [weak self] success, error in
            self?.logTemplateTransition("popToRootAfterPlan", success: success, error: error)
        }
    }

    /// „Losfahren" aus der Vorschau → Navigation starten (Flutter übernimmt
    /// GPS-Tracking, falls die Cruise-Page offen ist; sonst Auto-Navi pur).
    private func startNavigationFromPreview() {
        writeCommand(["action": "startNavigation"])
    }

    // MARK: - K6: A→B-Adress-Suche (CPSearchTemplate + MapKit-Geocoding)

    /// Öffnet die CarPlay-Suche. Adress-/POI-Vorschläge kommen nativ aus
    /// MKLocalSearchCompleter (kein Token nötig). Auswahl → A→B-Route planen.
    private func presentDestinationSearch() {
        guard isLoggedIn() else { presentLoginAlertIfNeeded(); return }
        let search = CPSearchTemplate()
        search.delegate = self
        interfaceController.pushTemplate(search, animated: true, completion: nil)
    }

    /// Schickt eine A→B-Planung an Flutter (Direktroute zum gewählten Ziel) und
    /// kehrt zur Karte zurück. Snapshot wechselt auf „searching" → „found".
    fileprivate func submitPointToPoint(destination: CLLocationCoordinate2D, name: String) {
        writeCommand([
            "action": "planRoute",
            "routeType": CarPlanMode.pointToPoint,
            "destinationLat": destination.latitude,
            "destinationLng": destination.longitude,
            "destinationName": name,
            "style": "Sport Mode",
            "avoidHighways": false,
        ])
        lastRouteSignature = nil
        interfaceController.popToRootTemplate(animated: true, completion: nil)
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

// MARK: - K2: Panning/Zoom-Steuerung (CPMapTemplateDelegate)

/// 2026-06-14 (vucko K2): Ohne gesetzten Delegate gab es KEINE CarPlay-Panning-
/// Schnittstelle → „man kann sich nicht bewegen / nicht aus dem Zentriermodus
/// raus". Jetzt: „Bewegen"-Button öffnet die Pfeil-Schnittstelle, jeder Pfeil-
/// Tipp verschiebt die Karte (Free-Mode), „Fertig" schließt sie wieder.
@available(iOS 14.0, *)
extension CarPlayRouteCoordinator: CPMapTemplateDelegate {
    func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        mapViewController.pan(direction)
    }

    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {
        mapViewController.enterFreeMode()
    }

    func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
        mapViewController.enterFreeMode()
    }
}

// MARK: - K6: A→B-Suche (CPSearchTemplate + MKLocalSearchCompleter)

@available(iOS 14.0, *)
extension CarPlayRouteCoordinator: CPSearchTemplateDelegate {
    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            lastSearchCompletions = []
            completionHandler([])
            return
        }
        // Ergebnisse kommen async in completerDidUpdateResults → dort rufen wir
        // den completionHandler. Letzten Handler merken.
        searchResultsHandler = completionHandler
        searchCompleter.queryFragment = trimmed
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        guard let idx = item.userInfo as? Int, idx < lastSearchCompletions.count else {
            completionHandler()
            return
        }
        let completion = lastSearchCompletions[idx]
        // Adresse/POI → Koordinate auflösen (MKLocalSearch), dann A→B planen.
        let request = MKLocalSearch.Request(completion: completion)
        MKLocalSearch(request: request).start { [weak self] response, _ in
            defer { completionHandler() }
            guard let self = self,
                  let coord = response?.mapItems.first?.placemark.coordinate,
                  CLLocationCoordinate2DIsValid(coord) else { return }
            DispatchQueue.main.async {
                self.submitPointToPoint(destination: coord, name: completion.title)
            }
        }
    }
}

@available(iOS 14.0, *)
extension CarPlayRouteCoordinator: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        lastSearchCompletions = completer.results
        let items = completer.results.enumerated().map { (i, r) -> CPListItem in
            let detail = r.subtitle.isEmpty ? nil : r.subtitle
            let item = CPListItem(text: r.title, detailText: detail)
            item.userInfo = i
            return item
        }
        searchResultsHandler?(items)
        searchResultsHandler = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        searchResultsHandler?([])
        searchResultsHandler = nil
    }
}

/// 2026-06-14 (vucko K1): Vektor-Karte im CarPlay-Fenster über MapLibre
/// (MLNMapView) statt der bisherigen MKMapView mit überzoomten z12-Raster-
/// Kacheln. Lädt EXAKT den Phone-Style (cruise_dark.json → PMTiles-Vektor) →
/// gestochen scharf bei JEDER Zoomstufe, identischer Look zum Handy. Die Route
/// ist ein Vektor-Linien-Layer (Casing + Akzent), die NavSession-Kamera folgt
/// kurs-orientiert. Liegt bewusst in derselben Datei wie der Coordinator, damit
/// keine neue Datei im Xcode-Projekt registriert werden muss.
@available(iOS 14.0, *)
final class CarPlayMapViewController: UIViewController, MLNMapViewDelegate {
    private let mapView: MLNMapView
    private var routeSource: MLNShapeSource?
    private var lastRouteCoords: [CLLocationCoordinate2D] = []
    private var pendingRouteCoords: [CLLocationCoordinate2D]?
    /// True wenn der Nutzer die Karte frei bewegt (Pan) → Follow ruht bis Recenter.
    private(set) var isPanning = false

    /// Der kanonische Phone-Style (Cloudflare). Verweist auf die PMTiles-
    /// Vektorquelle — MapLibre 6.26 liest `pmtiles://` nativ. So sieht CarPlay
    /// aus wie die App, nicht wie Apple Maps.
    private static let styleURL = URL(
        string: "https://tiles.cruiseconnector.at/cruise_dark.json")!
    private static let accent = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)

    init() {
        mapView = MLNMapView(frame: .zero, styleURL: CarPlayMapViewController.styleURL)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    /// Aktueller Standort des Nutzers (für CarPlay-seitige „Distanz zur nächsten
    /// Kurve"-Berechnung). Nil, solange MapLibre noch keine Position hat.
    var currentUserCoordinate: CLLocationCoordinate2D? {
        guard let loc = mapView.userLocation else { return nil }
        let c = loc.coordinate
        if !CLLocationCoordinate2DIsValid(c) || (c.latitude == 0 && c.longitude == 0) {
            return nil
        }
        return c
    }

    override func loadView() {
        view = mapView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Standort live + folgen, damit die Karte sofort nützlich ist.
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        // Chrome aus (CarPlay-Karte = vollflächig, eigene Buttons via CPMapButtons).
        mapView.compassView.isHidden = true
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.allowsRotating = true
        mapView.allowsTilting = true
        mapView.minimumZoomLevel = 3
        mapView.maximumZoomLevel = 18
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
    }

    // MARK: - Route (Vektor-Style-Layer)

    /// 2026-06-14 (vucko K3): Route als MapLibre Style-Layer (MLNShapeSource +
    /// MLNLineStyleLayer) — GENAU der Weg, den Mapbox Navigation SDK + Google
    /// Maps auf CarPlay nutzen. Style-Layer rendern im GL-Kontext (CarPlay-tauglich),
    /// im Gegensatz zu Annotationen (separater View-Pfad, auf dem CarPlay-Display
    /// unzuverlässig). Casing (dunkel) unten, Akzent oben.
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        ensureRouteLayers()
        if let pending = pendingRouteCoords {
            applyRoute(pending, fit: true)
            pendingRouteCoords = nil
        }
    }

    private func ensureRouteLayers() {
        guard let style = mapView.style, routeSource == nil else { return }
        let source = MLNShapeSource(identifier: "cc-route", shape: nil, options: nil)
        style.addSource(source)
        routeSource = source

        let casing = MLNLineStyleLayer(identifier: "cc-route-casing", source: source)
        casing.lineColor = NSExpression(
            forConstantValue: UIColor.black.withAlphaComponent(0.55))
        casing.lineWidth = NSExpression(forConstantValue: 11.0)
        casing.lineCap = NSExpression(forConstantValue: "round")
        casing.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(casing)

        let line = MLNLineStyleLayer(identifier: "cc-route-line", source: source)
        line.lineColor = NSExpression(forConstantValue: CarPlayMapViewController.accent)
        line.lineWidth = NSExpression(forConstantValue: 6.0)
        line.lineCap = NSExpression(forConstantValue: "round")
        line.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(line)
    }

    /// Zeichnet die Route. Gibt false zurück, wenn der Style noch nicht bereit
    /// war (→ Aufrufer wiederholt beim nächsten 2s-Tick), sonst true.
    @discardableResult
    private func applyRoute(_ coords: [CLLocationCoordinate2D], fit: Bool) -> Bool {
        ensureRouteLayers()
        guard let source = routeSource else {
            pendingRouteCoords = coords
            return false
        }
        lastRouteCoords = coords
        var mutable = coords
        let polyline = MLNPolylineFeature(coordinates: &mutable, count: UInt(mutable.count))
        source.shape = polyline
        if fit { fitRoute(coords) }
        return true
    }

    private func fitRoute(_ coords: [CLLocationCoordinate2D]) {
        guard coords.count >= 2 else { return }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLng = coords[0].longitude, maxLng = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng))
        mapView.userTrackingMode = .none
        isPanning = false
        mapView.setVisibleCoordinateBounds(
            bounds,
            edgePadding: UIEdgeInsets(top: 56, left: 56, bottom: 56, right: 56),
            animated: true)
    }

    @discardableResult
    func updateRoute(coordinates: [[Double]]) -> Bool {
        let coords = coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            // Snapshot-Koordinaten sind [longitude, latitude] (Mapbox-Konvention).
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard coords.count >= 2 else { clearRoute(); return true }
        return applyRoute(coords, fit: true)
    }

    /// MapLibre zeichnet die Vektor-Linie sofort scharf — kein progressives
    /// Reveal nötig (das war ein MKMapView-Workaround). Wir zeigen die ganze
    /// Route + fitten die Kamera (Vorschau).
    @discardableResult
    func animateRouteDraw(coordinates: [[Double]]) -> Bool {
        return updateRoute(coordinates: coordinates)
    }

    func clearRoute() {
        routeSource?.shape = nil
        lastRouteCoords = []
        pendingRouteCoords = nil
    }

    // MARK: - Kamera-Modi

    /// Folgt der eigenen Position (Leerlauf, keine Route) → „Wo bin ich".
    func followUser() {
        guard lastRouteCoords.isEmpty else { return }
        isPanning = false
        if mapView.userTrackingMode != .follow {
            mapView.setUserTrackingMode(.follow, animated: true)
        }
    }

    /// Aktive Navigation: Kamera folgt kurs-orientiert (course-up, wie am Handy),
    /// in Navi-Zoom. Die Route bleibt als Vektor-Linie sichtbar.
    func followWithHeading() {
        isPanning = false
        if mapView.userTrackingMode != .followWithCourse {
            mapView.setUserTrackingMode(.followWithCourse, animated: true)
        }
        // Navi-Zoom (scharf, vektor). 15.5 ≈ „nächste Kreuzungen klar lesbar".
        if mapView.zoomLevel < 14.5 || mapView.zoomLevel > 16.5 {
            mapView.setZoomLevel(15.5, animated: true)
        }
    }

    // MARK: - Karten-Steuerung (CPMapButtons + Panning)

    func zoomIn() {
        let z = min(mapView.zoomLevel + 1.0, mapView.maximumZoomLevel)
        mapView.setZoomLevel(z, animated: true)
    }

    func zoomOut() {
        // Follow würde den Zoom sofort überschreiben → erst Free-Mode.
        enterFreeMode()
        let z = max(mapView.zoomLevel - 1.0, mapView.minimumZoomLevel)
        mapView.setZoomLevel(z, animated: true)
    }

    /// K2: Zentriermodus verlassen (Karte „einfrieren", frei bewegbar). Follow
    /// hört auf, die Kamera zu steuern.
    func enterFreeMode() {
        isPanning = true
        if mapView.userTrackingMode != .none {
            mapView.setUserTrackingMode(.none, animated: false)
        }
    }

    /// K2: Pan-Schritt aus der CarPlay-Panning-Schnittstelle (Richtungstasten /
    /// Trackpad). Verschiebt das Kartenzentrum um einen Bruchteil der Sichtbreite
    /// in Pan-Richtung (links = Inhalt links aufdecken).
    func pan(_ direction: CPMapTemplate.PanDirection) {
        enterFreeMode()
        let b = mapView.bounds
        let stepX = b.width * 0.35
        let stepY = b.height * 0.35
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if direction.contains(.left) { dx = -stepX }
        if direction.contains(.right) { dx = stepX }
        if direction.contains(.up) { dy = -stepY }
        if direction.contains(.down) { dy = stepY }
        let target = CGPoint(x: b.midX + dx, y: b.midY + dy)
        let coord = mapView.convert(target, toCoordinateFrom: mapView)
        mapView.setCenter(coord, animated: true)
    }

    /// Zentrieren-Button: gibt es eine Route → ganze Route einpassen; sonst
    /// wieder dem Standort folgen. Beendet den Free-Mode.
    func recenterOnRoute() {
        if !lastRouteCoords.isEmpty {
            fitRoute(lastRouteCoords)
        } else {
            isPanning = false
            mapView.setUserTrackingMode(.follow, animated: true)
        }
    }

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
        NSLog("[CarPlay] MapLibre style load failed: \(error.localizedDescription)")
    }
}
#endif
