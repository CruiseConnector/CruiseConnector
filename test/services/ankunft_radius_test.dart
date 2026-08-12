import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';

/// 2026-08-04 (vucko): „Was mir noch aufgefallen ist: Die Route wird gestoppt,
/// bevor man wirklich am Ziel ist. Ich möchte, dass man im Radius von 10 bis
/// 20, sagen wir mal 10 m sein muss, damit die Route dann wirklich zählt."
///
/// URSACHE: Banner und Abschluss teilten sich EINEN Wert von 50 m
/// (`_arrivalRadiusMeters`). Der Abschluss feuerte also, sobald man 50 m vom
/// Ziel entfernt war und entweder der Map-Matcher am Routenende stand oder
/// 80 % der Strecke gefahren waren. Zusätzlich wurde der Abstand aus der ROHEN
/// GPS-Position berechnet, nicht aus der geglätteten.
///
/// JETZT: zwei getrennte Werte. Das Banner behält 50 m (die Ansage soll früh
/// kommen), der Abschluss bekommt 10 m — plus die gemeldete GPS-Ungenauigkeit,
/// höchstens 25 m Zugabe.
///
/// WARUM DIE ZUGABE SEIN MUSS: Der Ankunfts-Check hat keinen
/// Genauigkeitsfilter, und an anderer Stelle behandelt derselbe Code 35 bis
/// 50 m Ungenauigkeit ausdrücklich als normal beim Fahren. Ein starrer
/// 10-m-Radius wäre in einer Häuserschlucht oder an einer Tiefgarageneinfahrt
/// nie erreichbar — die Fahrt würde NIE automatisch enden und der Nutzer säße
/// ohne Abschluss-Sheet fest. Das wäre ein schlimmerer Fehler als der, den wir
/// beheben.
void main() {
  const completionRadius = 10.0;
  const slackCap = 25.0;
  const bannerRadius = 50.0;

  /// Bildet `_abschlussRadiusFuer` ab.
  double abschlussRadius(double genauigkeitM) {
    final g = genauigkeitM.isFinite && genauigkeitM > 0 ? genauigkeitM : slackCap;
    return completionRadius + math.min(g, slackCap);
  }

  group('Der Abschluss ist deutlich strenger als vorher', () {
    test('bei gutem Empfang zaehlt erst rund 15 m', () {
      expect(abschlussRadius(5), 15);
    });

    test('40 m vom Ziel gilt bei gutem Empfang NICHT mehr als angekommen', () {
      // Genau der gemeldete Fall: frueher (50 m) haette das gezaehlt.
      const abstand = 40.0;
      expect(abstand > abschlussRadius(5), isTrue);
      expect(
        abstand <= bannerRadius,
        isTrue,
        reason: 'Das Banner darf hier weiterhin „Ziel erreicht" sagen',
      );
    });

    test('die Zugabe ist bei 25 m gedeckelt', () {
      expect(abschlussRadius(80), 35);
      expect(abschlussRadius(500), 35);
      expect(
        abschlussRadius(500) < bannerRadius,
        isTrue,
        reason: 'Selbst im schlimmsten Fall strenger als die alten 50 m',
      );
    });

    test('fehlende Genauigkeit wird nicht als perfekt gewertet', () {
      expect(abschlussRadius(0), 35);
      expect(abschlussRadius(double.nan), 35);
    });
  });

  group('Die Abschluss-Regel dahinter', () {
    test('A nach B: allein der Radius entscheidet', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: false,
          distanceToFinalTargetMeters: 12,
          drivenDistanceMeters: 8000,
          plannedDistanceMeters: 10000,
          completionRadiusMeters: abschlussRadius(5),
        ),
        isTrue,
      );
      expect(
        shouldCompleteNavigation(
          isRoundTrip: false,
          distanceToFinalTargetMeters: 40,
          drivenDistanceMeters: 9900,
          plannedDistanceMeters: 10000,
          completionRadiusMeters: abschlussRadius(5),
        ),
        isFalse,
        reason: 'Auch wer 99 % gefahren ist, ist bei 40 m noch nicht da',
      );
    });

    test('Rundkurs braucht zusaetzlich 95 Prozent Fortschritt', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 8,
          drivenDistanceMeters: 5000,
          plannedDistanceMeters: 10000,
          completionRadiusMeters: abschlussRadius(5),
          minRoundTripProgress: 0.95,
        ),
        isFalse,
        reason: 'Am Start eines Rundkurses ist man geometrisch auch am Ziel',
      );
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 8,
          drivenDistanceMeters: 9600,
          plannedDistanceMeters: 10000,
          completionRadiusMeters: abschlussRadius(5),
          minRoundTripProgress: 0.95,
        ),
        isTrue,
      );
    });
  });

  group('Der Notausgang fuer schlechten Empfang', () {
    const stehTempoMps = 1.5;
    // 2026-08-12: von 20 auf 15 Sekunden gesenkt (vucko: „mache es so, dass es
    // etwas schneller kommt, im Umkreis von 50 m 15 Sekunden"). Diese Datei
    // BAUT die Regel nach, statt sie aufzurufen — sie merkt eine Aenderung an
    // der echten Konstante also nicht von selbst. Genau darueber wacht jetzt
    // ankunft_stehend_test.dart.
    const stehDauer = Duration(seconds: 15);

    /// Bildet `_stehtLangGenugAmZiel` ab.
    ({bool angekommen, DateTime? seit}) stehPruefung({
      required double abstandM,
      required double tempoMps,
      required DateTime jetzt,
      DateTime? stehtSeit,
    }) {
      final nahGenug = abstandM <= bannerRadius;
      if (!nahGenug || tempoMps.abs() > stehTempoMps) {
        return (angekommen: false, seit: null);
      }
      final seit = stehtSeit ?? jetzt;
      return (
        angekommen: jetzt.difference(seit) >= stehDauer,
        seit: seit,
      );
    }

    final t0 = DateTime(2026, 8, 4, 12);

    test('stehen allein reicht nicht sofort', () {
      final r = stehPruefung(abstandM: 30, tempoMps: 0, jetzt: t0);
      expect(r.angekommen, isFalse);
      expect(r.seit, t0);
    });

    test('nach 15 Sekunden Stillstand in Zielnaehe gilt man als angekommen', () {
      final r = stehPruefung(
        abstandM: 30,
        tempoMps: 0,
        jetzt: t0.add(const Duration(seconds: 16)),
        stehtSeit: t0,
      );
      expect(
        r.angekommen,
        isTrue,
        reason: 'Sonst saesse man bei schlechtem GPS ohne Abschluss fest',
      );
    });

    test('Weiterfahren setzt die Uhr zurueck', () {
      final r = stehPruefung(
        abstandM: 30,
        tempoMps: 9,
        jetzt: t0.add(const Duration(seconds: 16)),
        stehtSeit: t0,
      );
      expect(r.angekommen, isFalse);
      expect(r.seit, isNull, reason: 'Die Uhr muss neu anfangen');
    });

    test('an der Ampel 300 m vor dem Ziel greift der Notausgang NICHT', () {
      final r = stehPruefung(
        abstandM: 300,
        tempoMps: 0,
        jetzt: t0.add(const Duration(minutes: 2)),
        stehtSeit: t0,
      );
      expect(
        r.angekommen,
        isFalse,
        reason: 'Der Notausgang gilt nur innerhalb des Banner-Radius',
      );
    });
  });
}
