import 'dart:io';

import 'package:cruise_connect/data/services/kamera_tangente.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Aufgabe 3.3, Vucko-Sprachnachricht 10 vom 18.08.):
/// „Bei der Gruppenfahrt hat sich die Kamera die ganze Zeit gedreht, aus
/// irgendeinem Grund."
///
/// Die im Auftrag vermutete Ursache — konkurrierende Kamera-Updates aus
/// Gruppen-Sync und lokalem Heading-Tracking — existiert nicht. Nachgemessen:
/// kein einziger Gruppen-Timer und kein Gruppen-Stream fasst die Kamera an.
///
/// Der echte Fehler war indirekt: Im Gruppenmodus sprang der Routenindex beim
/// Übernehmen der Leader-Route auf 0, also auf den fernen Routenanfang. Die
/// Tangente peilte dann einen FESTEN geografischen Punkt kilometerweit weg an
/// — und wer daran vorbeifährt, dessen Karte dreht sich stetig weiter, obwohl
/// er geradeaus fährt. Im Video waren mehrfach rund 180 Grad in zwei Sekunden
/// zu sehen, auch im Stand.
///
/// Der Schutz dagegen (09.08., Commit 2c3f563) lebte bis heute ungetestet
/// mitten in einer 20.000-Zeilen-Datei. Dieser Test nagelt ihn fest.
void main() {
  /// Eine gerade Strecke Richtung Osten, rund 20 m je Punkt.
  /// Koordinaten im Mapbox-Format [longitude, latitude].
  List<List<double>> geradeNachOsten({int punkte = 200}) => List.generate(
    punkte,
    (i) => [9.7414 + i * 0.00026, 47.4125],
  );

  group('Fernpeilung wird abgewehrt', () {
    test(
      'Fahrer 5 km vom Ankerpunkt entfernt: keine Peilung (der Fall aus dem Video)',
      () {
        final route = geradeNachOsten();
        // Der Fahrer ist längst weitergefahren, der Index steht aber noch auf
        // dem Routenanfang. Genau so sah es im Gruppenmodus aus.
        final peilung = KameraTangente.peilung(
          kopfLat: 47.4125,
          kopfLng: 9.8078, // rund 5 km östlich vom Anfang
          koordinaten: route,
          index: 0,
          offRoute: false,
        );
        expect(
          peilung,
          isNull,
          reason:
              'Ohne diesen Anker peilt die Kamera einen festen Punkt in 5 km '
              'Entfernung und dreht sich beim Vorbeifahren stetig weiter',
        );
      },
    );

    test('genau an der 80-Meter-Grenze kippt das Verhalten', () {
      final route = geradeNachOsten();
      // 70 m entfernt: noch glaubwürdig.
      final knappDrin = KameraTangente.peilung(
        kopfLat: 47.4125,
        kopfLng: 9.7414 + 0.00093, // rund 70 m
        koordinaten: route,
        index: 0,
        offRoute: false,
      );
      expect(knappDrin, isNotNull);

      // 120 m entfernt: nicht mehr.
      final knappDraussen = KameraTangente.peilung(
        kopfLat: 47.4125,
        kopfLng: 9.7414 + 0.0016, // rund 120 m
        koordinaten: route,
        index: 0,
        offRoute: false,
      );
      expect(knappDraussen, isNull);
    });
  });

  group('Normalbetrieb bleibt unberührt', () {
    test('Fahrer auf der Route: Peilung zeigt in Fahrtrichtung', () {
      final route = geradeNachOsten();
      const idx = 42;
      final peilung = KameraTangente.peilung(
        kopfLat: route[idx][1],
        kopfLng: route[idx][0],
        koordinaten: route,
        index: idx,
        offRoute: false,
      );
      expect(peilung, isNotNull);
      // Osten sind 90 Grad. Eine Toleranz von 2 Grad ist reichlich.
      expect(peilung!, closeTo(90.0, 2.0));
    });

    test('Kurve nach Norden wird erkannt', () {
      // Erst nach Osten, dann nach Norden abbiegen.
      final route = <List<double>>[
        for (var i = 0; i < 50; i++) [9.7414 + i * 0.00026, 47.4125],
        for (var i = 1; i < 50; i++) [9.7414 + 49 * 0.00026, 47.4125 + i * 0.00018],
      ];
      final peilung = KameraTangente.peilung(
        kopfLat: route[52][1],
        kopfLng: route[52][0],
        koordinaten: route,
        index: 52,
        offRoute: false,
      );
      expect(peilung, isNotNull);
      // Norden sind 0 Grad.
      expect(peilung! < 5.0 || peilung > 355.0, isTrue,
          reason: 'Nach der Kurve muss die Kamera nach Norden zeigen, war $peilung');
    });
  });

  group('Abbruchbedingungen', () {
    test('abgekommen von der Route: keine Peilung, GPS-Kurs übernimmt', () {
      final route = geradeNachOsten();
      expect(
        KameraTangente.peilung(
          kopfLat: route[10][1],
          kopfLng: route[10][0],
          koordinaten: route,
          index: 10,
          offRoute: true,
        ),
        isNull,
      );
    });

    test('zu kurze Route: keine Peilung', () {
      expect(
        KameraTangente.peilung(
          kopfLat: 47.4125,
          kopfLng: 9.7414,
          koordinaten: const [
            [9.7414, 47.4125],
          ],
          index: 0,
          offRoute: false,
        ),
        isNull,
      );
    });

    test('Route endet direkt vor dem Fahrer: zu kurzer Vorlauf, keine Peilung', () {
      // Nur zwei Punkte, 2 m auseinander — unter der Mindestvorlauf-Schwelle.
      final peilung = KameraTangente.peilung(
        kopfLat: 47.4125,
        kopfLng: 9.7414,
        koordinaten: const [
          [9.7414, 47.4125],
          [9.741427, 47.4125],
        ],
        index: 0,
        offRoute: false,
      );
      expect(peilung, isNull);
    });

    test('Index außerhalb der Route stürzt nicht ab', () {
      final route = geradeNachOsten(punkte: 10);
      expect(
        () => KameraTangente.peilung(
          kopfLat: route[0][1],
          kopfLng: route[0][0],
          koordinaten: route,
          index: 9999,
          offRoute: false,
        ),
        returnsNormally,
      );
    });
  });

  test('Die Cruise-Seite benutzt die herausgezogene Rechnung', () {
    // Waechter: Wer die Logik zurueck in die Seite kopiert, verliert die
    // Testbarkeit und damit den Schutz gegen den Drehfehler.
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    expect(
      quelle.contains('KameraTangente.peilung('),
      isTrue,
      reason: 'cruise_mode_page muss die geprüfte Rechnung aufrufen',
    );
    expect(
      quelle.contains('anchorGap'),
      isFalse,
      reason:
          'Die alte, ungetestete Kopie der Tangenten-Rechnung darf nicht '
          'zurueckkommen',
    );
  });
}
