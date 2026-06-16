import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/domain/models/route_maneuver.dart';

/// Kleinstmöglicher Winkelunterschied zweier Himmelsrichtungen in Grad (0..180).
double headingDeltaDegrees(double headingA, double headingB) {
  final normalizedA = headingA % 360;
  final normalizedB = headingB % 360;
  final raw = (normalizedA - normalizedB).abs();
  return raw > 180 ? 360 - raw : raw;
}

/// Erkennung eines faktischen Wendemanövers anhand der Richtungsänderung.
bool isUTurnHeadingChange(
  double fromHeading,
  double toHeading, {
  double thresholdDegrees = 145.0,
}) {
  return headingDeltaDegrees(fromHeading, toHeading) >= thresholdDegrees;
}

/// Bearing zwischen zwei Punkten in [lng, lat] in Grad.
double bearingFromCoordinates(List<double> from, List<double> to) {
  final lat1 = from[1] * math.pi / 180;
  final lat2 = to[1] * math.pi / 180;
  final dLon = (to[0] - from[0]) * math.pi / 180;

  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Bearing eines Routenabschnitts an einer Stelle [index] (von index -> index+1).
double routeHeadingAt(List<List<double>> coordinates, int index) {
  if (coordinates.length < 2) return 0;
  final safeIndex = index.clamp(0, coordinates.length - 2);
  return bearingFromCoordinates(
    coordinates[safeIndex],
    coordinates[safeIndex + 1],
  );
}

/// Wählt einen Rejoin-Index, der möglichst in Fahrtrichtung liegt.
///
/// Der Algorithmus schaut nur nach vorne und bevorzugt Kandidaten mit geringer
/// Richtungsabweichung zur aktuellen Fahrzeugausrichtung.
int selectForwardRejoinIndex({
  required List<List<double>> coordinates,
  required int nearestIndex,
  required double currentHeadingDegrees,
  int minLookAheadPoints = 90,
  int maxLookAheadPoints = 320,
  double maxAlignmentDeltaDegrees = 100.0,
}) {
  if (coordinates.length < 2) return 0;

  final safeNearest = nearestIndex.clamp(0, coordinates.length - 2);
  final minIndex = math.min(
    safeNearest + minLookAheadPoints,
    coordinates.length - 2,
  );
  final maxIndex = math.min(
    safeNearest + maxLookAheadPoints,
    coordinates.length - 2,
  );

  if (minIndex >= maxIndex) return minIndex;

  int? bestIndex;
  double bestScore = -double.infinity;

  for (var idx = minIndex; idx <= maxIndex; idx++) {
    final candidateHeading = routeHeadingAt(coordinates, idx);
    final delta = headingDeltaDegrees(currentHeadingDegrees, candidateHeading);
    if (delta > maxAlignmentDeltaDegrees) continue;

    // Hohe Ausrichtungstreue und moderaten Look-Ahead bevorzugen.
    final alignmentScore = math.cos(delta * math.pi / 180);
    final proximityPenalty = (idx - minIndex) * 0.001;
    final score = alignmentScore - proximityPenalty;

    if (score > bestScore) {
      bestScore = score;
      bestIndex = idx;
    }
  }

  return bestIndex ?? minIndex;
}

/// Prüft ob der Übergang von Reroute -> Originalroute zu einem U-Turn führt.
bool isUTurnJoin({
  required List<List<double>> rerouteCoordinates,
  required List<List<double>> originalCoordinates,
  required int rejoinIndex,
  double thresholdDegrees = 145.0,
}) {
  if (rerouteCoordinates.length < 2 || originalCoordinates.length < 2) {
    return false;
  }

  final safeRejoin = rejoinIndex.clamp(0, originalCoordinates.length - 2);
  final rerouteHeading = bearingFromCoordinates(
    rerouteCoordinates[rerouteCoordinates.length - 2],
    rerouteCoordinates.last,
  );
  final originalHeading = routeHeadingAt(originalCoordinates, safeRejoin);

  return isUTurnHeadingChange(
    rerouteHeading,
    originalHeading,
    thresholdDegrees: thresholdDegrees,
  );
}

/// 2026-06-08 (vucko Task #47): Prüft, ob sich die ZUSAMMENGESETZTE Reroute-
/// Geometrie (Connector A→Rejoin + Original-Rest ab Rejoin) an der NAHT
/// zurückfaltet oder selbst überschneidet — die „Bat-Wing"-Signatur aus dem
/// Bug-Report (chaotischer Zickzack nach Reroute).
///
/// Warum nötig: Connector und Original-Tail sind je für sich validiert/sauber,
/// aber die NAHT zwischen ihnen prüfte bisher nichts Hartes. Die Round-Trip-
/// Shape-Guards (severeRoundTripShape …) sind `isRoundTrip`-gated und sehen
/// Reroutes (route_type POINT_TO_POINT) nie; P2P akzeptiert allein „Ziel
/// erreicht"; der `forceAcceptDirect`-Redock umging selbst den schwachen
/// `isUTurnJoin`. Folge: ein Connector, der den Rejoin-Punkt „erreicht", ihn
/// aber von hinten/seitlich anläuft, erzeugt beim Merge eine Schleife/Faltung,
/// die committet und gerendert wird. Reiner Geometrie-Test → unit-testbar.
bool rerouteMergeFoldsBack({
  required List<List<double>> connector,
  required List<List<double>> tail,
  double reversalThresholdDegrees = 125.0,
  int seamWindowPoints = 28,
}) {
  if (connector.length < 2 || tail.length < 2) return false;
  // 1. Heading-Reversal an der Naht — über ein kleines Fenster gemittelt (robust
  //    gegen GPS-Zacken), schärfer als der Einzelsegment-isUTurnJoin: läuft der
  //    Original-Rest entgegen der Connector-Anfahrt, faltet die Linie zurück.
  final approachFrom = connector[math.max(0, connector.length - 4)];
  final approachTo = connector.last;
  final leaveFrom = tail.first;
  final leaveTo = tail[math.min(tail.length - 1, 3)];
  final approachHeading = bearingFromCoordinates(approachFrom, approachTo);
  final leaveHeading = bearingFromCoordinates(leaveFrom, leaveTo);
  if (headingDeltaDegrees(approachHeading, leaveHeading) >=
      reversalThresholdDegrees) {
    return true;
  }
  // 2. Echte (proper) Selbstüberschneidung im Naht-Fenster: die letzten K
  //    Connector-Segmente gegen die ersten K Tail-Segmente. Fängt die Schleife,
  //    wenn der Connector über den Tail-Anfang hinweg läuft.
  final cFrom = math.max(0, connector.length - 1 - seamWindowPoints);
  final tTo = math.min(tail.length - 1, seamWindowPoints);
  for (var i = cFrom; i < connector.length - 1; i++) {
    for (var j = 0; j < tTo; j++) {
      if (segmentsProperlyIntersect(
        connector[i],
        connector[i + 1],
        tail[j],
        tail[j + 1],
      )) {
        return true;
      }
    }
  }
  return false;
}

/// Echte („proper") Überschneidung zweier Segmente in [lng, lat]. Gemeinsame
/// Endpunkte zählen NICHT als Überschneidung (die Reroute-Naht teilt sich einen
/// Punkt). Orientierungs-Test (Vorzeichen der Kreuzprodukte), planar — für die
/// kurzen Distanzen am Naht-Fenster völlig ausreichend.
bool segmentsProperlyIntersect(
  List<double> p1,
  List<double> p2,
  List<double> p3,
  List<double> p4,
) {
  double orient(List<double> a, List<double> b, List<double> c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  final d1 = orient(p3, p4, p1);
  final d2 = orient(p3, p4, p2);
  final d3 = orient(p1, p2, p3);
  final d4 = orient(p1, p2, p4);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Distanz in Metern von einer Position zu einem [lng, lat]-Zielpunkt.
double distanceToCoordinateMeters({
  required geo.Position position,
  required List<double> coordinate,
}) {
  if (coordinate.length < 2) return double.infinity;
  return geo.Geolocator.distanceBetween(
    position.latitude,
    position.longitude,
    coordinate[1],
    coordinate[0],
  );
}

/// Erkennt, ob die letzten Samples eine sinnvolle Annäherung an das Ziel zeigen.
bool isApproachingDestination(
  List<double> recentDistancesMeters, {
  double minImprovementMeters = 12.0,
}) {
  if (recentDistancesMeters.length < 3) return false;

  final oldest = recentDistancesMeters.first;
  final newest = recentDistancesMeters.last;
  final improvement = oldest - newest;
  final dynamicThreshold = math.max(minImprovementMeters, oldest * 0.015);

  return improvement >= dynamicThreshold;
}

bool shouldShowArrivalManeuver({
  required double? remainingRouteDistanceMeters,
  required double? distanceToFinalTargetMeters,
  double arrivalRadiusMeters = 50.0,
}) {
  if (remainingRouteDistanceMeters == null ||
      distanceToFinalTargetMeters == null) {
    return false;
  }
  return remainingRouteDistanceMeters <= arrivalRadiusMeters &&
      distanceToFinalTargetMeters <= arrivalRadiusMeters;
}

bool shouldCompleteNavigation({
  required bool isRoundTrip,
  required double distanceToFinalTargetMeters,
  required double drivenDistanceMeters,
  required double? plannedDistanceMeters,
  double completionRadiusMeters = 50.0,
  double minRoundTripProgress = 0.95,
}) {
  if (distanceToFinalTargetMeters > completionRadiusMeters) return false;
  if (!isRoundTrip) return true;
  if (plannedDistanceMeters == null || plannedDistanceMeters <= 0) return true;
  final progress = (drivenDistanceMeters / plannedDistanceMeters).clamp(
    0.0,
    1.0,
  );
  return progress >= minRoundTripProgress;
}

bool violatesNoHighwayPolicy({
  required bool avoidHighways,
  required Map<String, dynamic> edgeMeta,
}) {
  if (!avoidHighways) return false;

  final motorwayViolation =
      _boolMeta(edgeMeta, 'motorwayViolation') ??
      _boolMeta(edgeMeta, 'motorway_violation') ??
      false;
  if (motorwayViolation) return true;

  final hasHighway =
      _boolMeta(edgeMeta, 'actual_has_highway') ??
      _boolMeta(edgeMeta, 'has_highway') ??
      _boolMeta(edgeMeta, 'motorway_present') ??
      false;
  if (hasHighway) return true;

  final avoidRequested = _boolMeta(edgeMeta, 'avoid_highways_requested');
  if (avoidRequested == false) return true;

  final highwayAllowed = _boolMeta(edgeMeta, 'highway_allowed');
  if (highwayAllowed == true) return true;

  final motorwayPolicy = _stringMeta(edgeMeta, 'motorway_policy');
  if (motorwayPolicy == 'allowed_not_required') return true;

  final effectiveExcludes = _stringMeta(edgeMeta, 'effective_excludes');
  if (effectiveExcludes != null &&
      !_containsExclude(effectiveExcludes, 'motorway')) {
    return true;
  }

  return false;
}

int? selectActiveGuidanceManeuverIndex({
  required List<RouteManeuver> maneuvers,
  required int currentRouteIndex,
  required double? remainingRouteDistanceMeters,
  required double? distanceToFinalTargetMeters,
  int startIndex = 0,
  double arrivalRadiusMeters = 50.0,
}) {
  if (maneuvers.isEmpty) return null;

  final safeStart = startIndex.clamp(0, maneuvers.length - 1).toInt();
  for (var i = safeStart; i < maneuvers.length; i++) {
    final maneuver = maneuvers[i];
    if (maneuver.routeIndex < currentRouteIndex) continue;
    if (maneuver.isArrival) {
      return shouldShowArrivalManeuver(
            remainingRouteDistanceMeters: remainingRouteDistanceMeters,
            distanceToFinalTargetMeters: distanceToFinalTargetMeters,
            arrivalRadiusMeters: arrivalRadiusMeters,
          )
          ? i
          : null;
    }
    return i;
  }

  final lastIndex = maneuvers.length - 1;
  final last = maneuvers[lastIndex];
  if (last.isArrival) {
    return shouldShowArrivalManeuver(
          remainingRouteDistanceMeters: remainingRouteDistanceMeters,
          distanceToFinalTargetMeters: distanceToFinalTargetMeters,
          arrivalRadiusMeters: arrivalRadiusMeters,
        )
        ? lastIndex
        : null;
  }
  return lastIndex;
}

/// 2026-06-15 (vucko N1): Darf dieser GPS-Fix für ein Reroute „voten"?
/// Mapbox-/Apple-Gating gegen Kaltstart-Phantom-Reroutes (Geräte-Fahrt 23min:
/// der gesnappte Puck wirkt dead-on, während ROHES GPS am Fahrtbeginn seitlich
/// ausreißt und grundlose „Neuberechnung" auslöst). Zwei Sperren:
///   1. Mapbox `isQualified`: Accuracy ≤0 oder >[maxQualifiedAccuracyMeters] →
///      Fix bewegt den Puck, votet aber NIE für ein Reroute.
///   2. Apple Departure-Suppression (US9835469B2): solange der Puck noch nicht auf
///      der Route eingerastet ist ([routeLockedOn] == false), nur bei KLAREM,
///      gut-vermessenem Verfahren rerouten (Abstand > 2× Korridor & Accuracy ≤
///      [lockOnMaxAccuracyMeters]). Sonst Kaltstart-Rauschen.
/// Sobald einmal eingerastet, gilt die normale (schnelle) Off-Route-Logik für die
/// ganze Fahrt. Pur, damit unit-testbar.
bool rerouteVoteAllowed({
  required double accuracyMeters,
  required bool routeLockedOn,
  required double offRouteDistanceMeters,
  required double corridorMeters,
  bool everLockedOn = true,
  double maxQualifiedAccuracyMeters = 100.0,
  double lockOnMaxAccuracyMeters = 35.0,
}) {
  final qualifiedFix =
      accuracyMeters > 0 && accuracyMeters <= maxQualifiedAccuracyMeters;
  if (!qualifiedFix) return false;
  if (routeLockedOn) return true;
  final goodAccuracy =
      accuracyMeters > 0 && accuracyMeters <= lockOnMaxAccuracyMeters;
  // 2026-06-17 (vucko Kaltstart-Reroute, Video 0:16-0:27): War der Puck in DIESER
  // Sitzung NOCH NIE eingerastet (echtes Kaltstart-Fenster, z.B. Route startete
  // seitlich vom Standort weil der Nutzer zwischen Suche und „Fahrt starten"
  // angefahren ist), genügt schon ein klar gut-vermessenes Verfahren > 1,4×
  // Korridor zum Voten — sonst wartete der Reroute bis zur 90s-Grace-Decke (~11s
  // im Video). Nach dem ersten Einrasten (everLockedOn=true, auch nach Reroutes,
  // wo routeLockedOn vorübergehend false ist) bleibt es bei der strengen 2×-
  // Schwelle → kein Re-Reroute-Loop, Kaltstart-Phantom-Schutz unberührt
  // (echtes Rauschen zappelt < 1× Korridor).
  final divergenceFactor = everLockedOn ? 2.0 : 1.4;
  final clearGenuineDivergence =
      offRouteDistanceMeters > corridorMeters * divergenceFactor && goodAccuracy;
  return clearGenuineDivergence;
}

/// 2026-06-15 (vucko N-Runde-2): DIE klar definierte On-Route-Regel (Mapbox/Google).
/// Gilt dieser GPS-Fix als „auf der Route"? Wenn ja, wird der Zähler
/// aufeinanderfolgender Off-Route-Fixes auf 0 gesetzt — d.h. ein einzelner
/// in-Korridor-/kurs-passender/Fortschritts-Fix beendet jeden Off-Streak sofort.
/// Genau das macht einen 2-3s-Multipath-Ausreißer (Kurve/Auffahrt/Baumdecke)
/// harmlos: er erreicht nie die nötigen ≥4 Fixes am Stück.
/// - [perpMeters] = SNAP-FIRST Senkrechte (window ODER globaler Re-Snap, der
///   kleinere) — NICHT die rohe GPS-Distanz, sonst zählt der gesnappte Puck falsch.
/// - bis 2× Korridor + passender Kurs gilt noch als on-route (Kurven-/Parallel-
///   Toleranz); darüber zählt es als off, auch wenn der Kurs zufällig passt
///   (echtes Verfahren auf eine Parallelstraße).
bool fixIsOnRoute({
  required bool isOutsideCorridor,
  required double perpMeters,
  required double corridorMeters,
  required bool courseAligned,
  required bool makingForwardProgress,
  required bool approachingDestination,
  required bool nearRouteEnd,
}) {
  return !isOutsideCorridor ||
      (perpMeters <= corridorMeters * 2.0 && courseAligned) ||
      makingForwardProgress ||
      approachingDestination ||
      nearRouteEnd;
}

/// 2026-06-15 (vucko N-Runde-2): Wie viele aufeinanderfolgende Off-Route-Fixes
/// sind nötig, bevor ein Reroute ausgelöst wird? Mapbox: max(4, accuracy/4) —
/// schlechtes GPS braucht MEHR Fixes (träger, aber nie hart blockiert). Bei
/// EINDEUTIGEM Verfahren ([clearWrongTurn]: Manöver-Overshoot/klar gegenläufiger
/// Kurs) auf 3 verkürzt (≈3s) — entspricht der J1/L2-Latenzvorgabe.
int requiredOffRouteFixes({
  required double accuracyMeters,
  required bool clearWrongTurn,
}) {
  final accForScale = (accuracyMeters.isFinite && accuracyMeters > 0)
      ? math.min(accuracyMeters, 100.0)
      : 16.0;
  final base = math.max(4, (accForScale / 4).floor());
  return clearWrongTurn ? math.min(3, base) : base;
}

/// Baut kompakte Telemetrie für einen echten Straßen-Reroute.
Map<String, dynamic> buildRerouteTelemetry({
  required String rerouteReason,
  required String rerouteMode,
  required double? remainingDistanceBeforeMeters,
  required double? remainingDistanceAfterMeters,
  required double? etaBeforeSeconds,
  required double? etaAfterSeconds,
  double? rerouteDistanceMeters,
  double? rejoinPointDistanceMeters,
  bool rerouteFailed = false,
}) {
  double? roundKm(double? meters) => meters == null
      ? null
      : double.parse((meters / 1000.0).toStringAsFixed(2));
  double? roundSeconds(double? seconds) =>
      seconds == null ? null : double.parse(seconds.toStringAsFixed(1));

  return {
    'reroute_triggered': true,
    'reroute_reason': rerouteReason,
    'reroute_mode': rerouteMode,
    'reroute_distance_km': roundKm(rerouteDistanceMeters),
    'rejoin_point_distance_km': roundKm(rejoinPointDistanceMeters),
    'remaining_distance_before': roundKm(remainingDistanceBeforeMeters),
    'remaining_distance_after': roundKm(remainingDistanceAfterMeters),
    'eta_before': roundSeconds(etaBeforeSeconds),
    'eta_after': roundSeconds(etaAfterSeconds),
    'reroute_failed': rerouteFailed,
  };
}

bool? _boolMeta(Map<String, dynamic> meta, String key) {
  final value = meta[key];
  return value is bool ? value : null;
}

String? _stringMeta(Map<String, dynamic> meta, String key) {
  final value = meta[key];
  if (value == null) return null;
  final text = value.toString().trim().toLowerCase();
  return text.isEmpty ? null : text;
}

bool _containsExclude(String excludes, String token) {
  return excludes
      .split(',')
      .map((entry) => entry.trim().toLowerCase())
      .contains(token);
}
