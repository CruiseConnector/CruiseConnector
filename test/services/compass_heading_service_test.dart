import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/compass_heading_service.dart';
import 'package:cruise_connect/data/services/geo_bearing.dart';

/// 2026-07-27 (vucko „die Kameradrehung im freien Modus ist nicht 360°,
/// sondern ca. 200°"):
///
/// Der alte Dienst glättete mit festem Faktor 0,25. Ein solcher Filter hat bei
/// einer laufenden Drehung einen Nachlauf, der LINEAR mit der Drehgeschwindig-
/// keit wächst (L = ω · dt · (1−α)/α). Bei einer zügigen Drehung blieb das
/// geglättete Heading dadurch dauerhaft 30–50° hinter der Realität — die Karte
/// kam einen guten Teil der Drehung schlicht nicht mit.
///
/// Diese Tests messen genau das nach: Wie viel einer vollen Umdrehung kommt am
/// Ausgang an, und wie weit liegt der Wert unterwegs maximal zurück?
void main() {
  group('Kompass-Glättung', () {
    test('volle Umdrehung kommt praktisch vollständig an', () {
      final service = CompassHeadingService();
      final r = CompassHeadingService.simulateRamp(
        service: service,
        totalDeg: 360,
        steps: 40, // zügige Drehung: 9° pro Sensor-Event
      );
      expect(
        r.tracked,
        greaterThan(345),
        reason: 'Bei 360° Drehung dürfen höchstens ein paar Grad fehlen. '
            'Mit der alten festen Glättung (0,25) kamen deutlich weniger an.',
      );
      expect(r.tracked, lessThan(375), reason: 'kein Überschwingen');
    });

    test('Nachlauf bleibt auch bei schneller Drehung klein', () {
      final service = CompassHeadingService();
      final r = CompassHeadingService.simulateRamp(
        service: service,
        totalDeg: 360,
        steps: 20, // sehr schnell: 18° pro Event
      );
      expect(
        r.maxLag,
        lessThan(20),
        reason: 'Der alte feste Faktor 0,25 ergab hier rund 54° Rückstand',
      );
    });

    test('die alte feste Glättung wäre an diesem Test gescheitert', () {
      // Gegenprobe: derselbe Aufbau mit dem alten Verhalten (fester Faktor).
      final alt = CompassHeadingService(minSmoothing: 0.25, maxSmoothing: 0.25);
      final r = CompassHeadingService.simulateRamp(
        service: alt,
        totalDeg: 360,
        steps: 20,
      );
      expect(
        r.maxLag,
        greaterThan(30),
        reason: 'Beleg, dass der Test das frühere Problem wirklich sieht',
      );
    });

    test('ruhiges Gerät wird stark geglättet (kein Zittern)', () {
      final service = CompassHeadingService();
      service.seed(100);
      // Sensor-Rauschen von ±1,5° um 100 herum
      for (var i = 0; i < 20; i++) {
        service.feed(i.isEven ? 101.5 : 98.5);
      }
      expect(
        GeoBearing.angleDiff(service.heading, 100).abs(),
        lessThan(2.0),
        reason: 'Rauschen darf die Karte nicht wandern lassen',
      );
    });

    test('Glättungsfaktor wächst mit der Winkeländerung', () {
      final service = CompassHeadingService();
      expect(service.smoothingFor(0), closeTo(service.minSmoothing, 1e-9));
      expect(
        service.smoothingFor(CompassHeadingService.fastDeltaDeg),
        closeTo(service.maxSmoothing, 1e-9),
      );
      expect(
        service.smoothingFor(100),
        closeTo(service.maxSmoothing, 1e-9),
        reason: 'oberhalb der Schwelle gedeckelt',
      );
      expect(
        service.smoothingFor(-CompassHeadingService.fastDeltaDeg),
        closeTo(service.maxSmoothing, 1e-9),
        reason: 'Richtung egal, nur der Betrag zählt',
      );
    });

    test('ANDROID: Rueckseiten-Heading darf NIE verwendet werden', () {
      // So sieht ein echtes Android-Event aus: das Plugin sendet ein
      // double[3], setzt aber nur Index 0 (Heading) und Index 2 (Genauigkeit).
      // Index 1 bleibt der Java-Default 0.0 — es ist KEIN gemessener Wert.
      // Wer dort auf headingForCameraMode umstellt, bekommt konstant Norden
      // und eine Karte, die sich nie dreht. Genau davor schuetzt dieser Test.
      final androidEvent = CompassEvent.fromList([137.0, 0.0, 15.0]);
      final raw = CompassHeadingService.rawHeadingFor(
        androidEvent,
        cameraModeAvailable: false,
      );
      expect(raw, 137.0,
          reason: 'Auf Android zaehlt ausschliesslich das normale Heading');
    });

    test('iOS: Rueckseiten-Heading hat Vorrang', () {
      // Auf iOS rechnet das Plugin headingForCameraMode ueber die
      // Rotationsmatrix aus — das ist der Wert ohne Euler-Singularitaet und
      // damit der richtige, wenn man das Geraet aufrecht vor sich haelt.
      final iosEvent = CompassEvent.fromList([137.0, 212.0, 15.0]);
      final raw = CompassHeadingService.rawHeadingFor(
        iosEvent,
        cameraModeAvailable: true,
      );
      expect(raw, 212.0);
    });

    test('unbrauchbare Werte fallen sauber zurueck', () {
      // Rueckseiten-Heading unbrauchbar (null) -> normales Heading nehmen.
      final teilweise = CompassEvent.fromList([90.0, double.nan, 15.0]);
      expect(
        CompassHeadingService.rawHeadingFor(teilweise,
            cameraModeAvailable: true),
        90.0,
      );
      // Beide unbrauchbar -> null, der Aufrufer nutzt seine Fallback-Quelle.
      final kaputt = CompassEvent.fromList([double.nan, double.nan, 15.0]);
      expect(
        CompassHeadingService.rawHeadingFor(kaputt, cameraModeAvailable: true),
        isNull,
      );
    });

    test('Nulldurchgang wird sauber überfahren', () {
      final service = CompassHeadingService();
      service.seed(355);
      service.feed(5); // über Norden hinweg
      expect(service.heading, inInclusiveRange(0, 360));
      // Der geglättete Wert muss zwischen 355 und 5 liegen (über 0 hinweg),
      // nicht den langen Weg über 180 nehmen.
      final d = GeoBearing.angleDiff(355, service.heading);
      expect(d, greaterThan(0), reason: 'kurzer Weg vorwärts über Norden');
      expect(d, lessThan(10));
    });
  });
}
