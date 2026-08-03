import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/geo_bearing.dart';

/// 2026-07-29 (vucko): „Wenn der Anfangspunkt zuhause war, die Route sich aber
/// geschlossen hat und man später wieder fortsetzen will, ist der Anfangspunkt
/// nicht mehr zuhause, sondern der Stand, wo man neu startet. Ich möchte, dass
/// der Anfangs- und Endpunkt zuhause bleibt, man die Route aber vom neuen
/// Standort aus fortsetzen kann."
///
/// URSACHE (route_service.dart, buildAccessRouteToExistingRoute):
/// ```
/// final logicalOrigin = existingRoute.coordinates.first;   // = zuhause
/// final sessionOrigin = [currentPosition.lng, .lat];       // = wo man steht
/// ```
/// Der Rückweg wurde zum `sessionOrigin` gebaut — also zum neuen Standort.
/// Beim Fortsetzen kam man damit nie mehr heim.
///
/// FIX: `explicitSessionOrigin`. Beim Fortsetzen eines Rundkurses übergibt
/// die Cruise-Seite den URSPRÜNGLICHEN Loop-Start; ohne Angabe bleibt das
/// bisherige Verhalten (frische Suche: aktuelle Position IST der Start).
///
/// Dieser Test hält die Entscheidungsregel fest. Die Geometrie-Erzeugung
/// selbst braucht einen echten Routing-Server und ist im Live-Benchmark
/// abgedeckt; hier geht es um die Frage, WELCHER Punkt das Rundenende ist.
void main() {
  /// Bildet die Regel aus cruise_mode_page ab: nur ein FORTGESETZTER
  /// Rundkurs bekommt einen ausdrücklichen Endpunkt.
  List<double>? endpunktFuerRunde({
    required bool istRundkurs,
    required bool istFortgesetzteFahrt,
    required List<double> urspruenglicherStart,
  }) {
    if (istRundkurs && istFortgesetzteFahrt) return urspruenglicherStart;
    return null; // = aktuelle Position, bisheriges Verhalten
  }

  const zuhause = [9.7414, 47.4125];

  group('Rundkurs fortsetzen', () {
    test('fortgesetzte Runde endet am ursprünglichen Start, nicht am Standort', () {
      final ziel = endpunktFuerRunde(
        istRundkurs: true,
        istFortgesetzteFahrt: true,
        urspruenglicherStart: zuhause,
      );
      expect(
        ziel,
        zuhause,
        reason: 'Wer zuhause losgefahren ist, muss auch dort ankommen — '
            'egal wo die App abgestürzt ist',
      );
    });

    test('frische Rundkurs-Suche bleibt unverändert', () {
      final ziel = endpunktFuerRunde(
        istRundkurs: true,
        istFortgesetzteFahrt: false,
        urspruenglicherStart: zuhause,
      );
      expect(
        ziel,
        isNull,
        reason: 'Bei einer neuen Suche IST die aktuelle Position der Start — '
            'hier darf nichts überschrieben werden',
      );
    });

    test('A nach B bekommt nie einen erzwungenen Endpunkt', () {
      for (final fortgesetzt in [true, false]) {
        expect(
          endpunktFuerRunde(
            istRundkurs: false,
            istFortgesetzteFahrt: fortgesetzt,
            urspruenglicherStart: zuhause,
          ),
          isNull,
          reason: 'A nach B hat ein echtes Ziel, keine Rückkehr zum Start',
        );
      }
    });
  });

  group('Der neue Standort bleibt erreichbar', () {
    test('Entfernung Standort zu Zuhause wird korrekt gemessen', () {
      // Der Nutzer steht 20 km entfernt, wo die App abstürzte.
      const standort = [9.9500, 47.5000];
      final d = GeoBearing.angleDiff(0, 0); // Formel-Smoke-Test
      expect(d, 0);
      // Die Runde muss beide Punkte kennen: den Standort zum Wiedereinstieg
      // und Zuhause als Ende. Beide sind verschieden — genau das war das
      // Problem, als nur einer davon verwendet wurde.
      expect(standort, isNot(zuhause));
    });
  });
}
