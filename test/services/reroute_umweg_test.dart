import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-14 (vucko, P1): „Im A-nach-B-Modus greift beim Rerouting die vorher
/// getroffene Umwegs-Auswahl nicht mehr. Wenn vorher ein mittlerer Umweg
/// ausgewaehlt wurde, springt die Navigation beim Rerouting direkt auf den
/// Endpunkt — die Route veraendert sich direkt von 30 km auf bspw. 10."
///
/// URSACHE (belegt): Der Ziel-Zweig in _runRerouteCycle rechnet Position ->
/// Ziel neu, mit hart codiertem mode 'Standard' und routeVariant 0. Die
/// Umweg-Auswahl war zwar in _activeDetourVariant/_activePointToPointScenic
/// vorhanden, wurde aber nicht gelesen. Der Rejoin-Pfad, der die RESTLICHE
/// Originalroute anhaengt und den Umweg damit von selbst erhaelt, kam nie zum
/// Zug, weil der Ziel-Zweig Vorrang hatte.
///
/// WARUM NICHT der naheliegende Weg (Umweg-Parameter durchreichen): Die
/// Varianten-Suche laeuft beim Reroute mit Budget 1 und 4,5 s und fiele fast
/// immer auf direkt zurueck. Und Faktor 3 auf die REST-Luftlinie ergaebe
/// mitten in der Fahrt eine voellig neue Schleife statt der gewaehlten.
void main() {
  late String quelle;

  setUpAll(() {
    quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
  });

  test('bei aktivem Umweg wird der Ziel-Zweig uebersprungen', () {
    expect(
      quelle.contains('final umwegAktiv ='),
      isTrue,
      reason: 'ohne dieses Flag rechnet der Reroute wieder direkt zum Ziel',
    );
    expect(
      quelle.contains(
        '(_activeDetourVariant > 0 || _activePointToPointScenic)',
      ),
      isTrue,
    );
    expect(
      quelle.contains('!umwegAktiv'),
      isTrue,
      reason: 'das Flag muss die Bedingung des Ziel-Zweigs erweitern',
    );
  });

  test('Trips mit Zwischenstopps behalten den Ziel-Zweig', () {
    // Das bewusste Ueberspringen verpasster Stopps haengt am Ziel-Zweig
    // (_remainingWaypointsForReroute). Der Umweg-Bypass darf nur fuer
    // A nach B OHNE Zwischenstopps gelten.
    expect(
      quelle.contains('_activeIntermediateWaypoints.isEmpty'),
      isTrue,
      reason:
          'sonst verliert der Trip-Modus das Stopp-Ueberspringen beim Reroute',
    );
  });

  test('der Bypass steht VOR dem Ziel-Zweig', () {
    final flag = quelle.indexOf('final umwegAktiv =');
    final zweig = quelle.indexOf(
      '!accessLegMode &&\n          !umwegAktiv',
    );
    expect(flag, greaterThan(0));
    expect(
      zweig,
      greaterThan(flag),
      reason: 'das Flag muss vor seiner Verwendung gebildet werden',
    );
  });

  test('kein Direkt-Fallback, der den Umweg durch die Hintertuer verwirft', () {
    // Der garantierte Re-Dock haengt den Original-Rest an einen erzwungenen
    // Verbinder — der Umweg bleibt auch im Notfall erhalten. Bei Scheitern
    // bleibt die alte Route sichtbar und der naechste Tick versucht es
    // erneut. Ein Direkt-Fallback wuerde bei jedem voruebergehenden
    // Rejoin-Fehler den Umweg wieder verlieren — genau der gemeldete Fehler.
    final start = quelle.indexOf('final umwegAktiv =');
    final rumpf = quelle.substring(start, start + 3000);
    expect(
      rumpf.contains('umwegDirektFallback'),
      isFalse,
      reason: 'bewusste Entscheidung, dokumentiert im Kommentar',
    );
  });
}
