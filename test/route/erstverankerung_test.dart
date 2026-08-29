import 'dart:io';

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-08-29, Videobefund vom 28.08. 22:24 und 22:26.
///
/// FEHLERBILD: Auf beiden Bildschirmaufnahmen stehen "950 m" und "57 km
/// verbleibend" absolut still, ueber zwei Minuten hinweg, waehrend die Karte
/// nachweislich mitscrollt (gemessen: 8 bis 16 Pixel je Sekunde). Nur die
/// Ankunftszeit laeuft mit der Wanduhr mit. Die Fahrt selbst ist in der
/// Datenbank verbucht: 57,89 km, 90 Minuten. Die angezeigten 57 km waren also
/// die VOLLE Streckenlaenge, die Anzeige stand auf dem Startwert.
///
/// URSACHE: Der Fahrer begann die Fahrt kilometerweit vom Routenanfang
/// entfernt. Die Anfahrt dorthin haette die App berechnen muessen, das
/// braucht aber Netz, und das Geraet hatte keines ("SIM fehlt"). Damit blieb
/// `_currentRouteIndex` auf 0 stehen:
///
///  * Das Suchfenster reicht nur 80 Punkte voraus und findet den Fahrer nie.
///  * Der globale Re-Snap findet ihn, verweigert den Sprung aber am
///    Teleport-Budget (beim ersten Fix rund 95 Meter).
///
/// Banner, Restweg und Leitlinie sind reine Funktionen dieses Index und
/// stehen deshalb still.
///
/// Diese Tests nageln beide Haelften fest: den Fehler und die Reparatur.
void main() {
  /// Eine Route schnurgerade nach Norden, Punkte im Abstand von etwa 100 m.
  /// Punkt 0 liegt bei 47.400, Punkt i bei 47.400 + i * 0.0009.
  List<List<double>> geradeNachNorden(int punkte) => [
    for (var i = 0; i < punkte; i++)
      <double>[9.700, 47.400 + i * 0.0009],
  ];

  geo.Position fixBei(double lat, double lng, {double genauigkeit = 8}) =>
      geo.Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime(2026, 8, 28, 22, 24),
        accuracy: genauigkeit,
        altitude: 400,
        altitudeAccuracy: 5,
        heading: 0,
        headingAccuracy: 5,
        speed: 12,
        speedAccuracy: 1,
      );

  group('So entsteht der eingefrorene Zustand', () {
    test(
      'das Suchfenster findet einen Fahrer weit voraus NICHT und bleibt am Index',
      () {
        final route = geradeNachNorden(200);
        // Der Fahrer steht auf Punkt 120, also weit hinter dem Fenster
        // [0, 80]. Genau die Lage aus dem Video: Index 0, Fahrer km voraus.
        final treffer = findNearestInWindow(
          position: fixBei(route[120][1], route[120][0]),
          coordinates: route,
          currentIndex: 0,
          windowSize: 80,
          maxJumpMeters: 75,
        );

        expect(
          treffer.index,
          0,
          reason:
              'Der Index bleibt am Anfang kleben — daraus entsteht der '
              'konstante Restweg.',
        );
        expect(
          treffer.distanceMeters,
          greaterThan(1000),
          reason: 'Der Fahrer ist ueber einen Kilometer entfernt.',
        );
        expect(
          treffer.segmentIndex,
          isNull,
          reason:
              'Ohne Segmentangabe faellt die Restweg-Rechnung auf die reine '
              'Index-Schleife zurueck und liefert die volle Routenlaenge.',
        );
      },
    );
  });

  group('Die Erstverankerung holt den Fahrer', () {
    test('findet ihn auf der ganzen Route, auch weit voraus', () {
      final route = geradeNachNorden(200);
      final treffer = findNearestOnRoutePreferIndex(
        position: fixBei(route[120][1], route[120][0]),
        coordinates: route,
        referenceIndex: 0,
        corridorMeters: 60,
      );

      expect(
        treffer.distanceMeters,
        lessThanOrEqualTo(60),
        reason: 'Er steht auf der Linie, also muss der Treffer im Korridor sein.',
      );
      expect(
        (treffer.index - 120).abs(),
        lessThanOrEqualTo(1),
        reason: 'Und zwar an der Stelle, an der er wirklich ist.',
      );
    });

    test('neben der Route bleibt sie aus', () {
      final route = geradeNachNorden(200);
      // 300 m oestlich der Linie: das ist echtes Abseits, da darf nicht
      // verankert werden, sonst waere der Off-Route-Fall entschaerft.
      final treffer = findNearestOnRoutePreferIndex(
        position: fixBei(route[120][1], route[120][0] + 0.004),
        coordinates: route,
        referenceIndex: 0,
        corridorMeters: 60,
      );
      expect(treffer.distanceMeters, greaterThan(60));
    });

    test(
      'auf einem Rundkurs mit Selbstueberlapp nicht auf das Rueckweg-Leg',
      () {
        // Hinweg Punkt 0 bis 99 nach Norden, Rueckweg 100 bis 199 auf
        // derselben Strasse zurueck. Geografisch liegen Punkt 40 und Punkt
        // 159 fast aufeinander.
        final hin = geradeNachNorden(100);
        final zurueck = [
          for (var i = 99; i >= 0; i--) <double>[9.700, 47.400 + i * 0.0009],
        ];
        final route = <List<double>>[...hin, ...zurueck];

        // Der Fahrer ist auf dem HINWEG bei Punkt 40. Der Anker steht noch
        // am Anfang, die Praeferenz muss deshalb den Hinweg waehlen.
        final treffer = findNearestOnRoutePreferIndex(
          position: fixBei(hin[40][1], hin[40][0]),
          coordinates: route,
          referenceIndex: 0,
          corridorMeters: 60,
        );

        expect(
          treffer.index,
          lessThan(100),
          reason:
              'Sonst springt das Banner auf den Rueckweg und zeigt Manoever, '
              'die erst in 26 km kommen (Befund vom 13.06.).',
        );
        expect((treffer.index - 40).abs(), lessThanOrEqualTo(1));
      },
    );
  });

  group('Quelltext-Waechter', () {
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();

    test('die Erstverankerung steht VOR dem Suchfenster', () {
      final verankerung = quelle.indexOf('if (!_hatJeVerankert &&');
      final fenster = quelle.indexOf('final rawMatch = findNearestInWindow(');
      expect(verankerung, greaterThan(0),
          reason: 'Die Erstverankerung muss es geben.');
      expect(fenster, greaterThan(0));
      expect(
        verankerung,
        lessThan(fenster),
        reason:
            'Danach waere sie wirkungslos: das Fenster hat den Index dann '
            'schon auf den alten Wert festgenagelt.',
      );
    });

    test('sie gilt nur EINMAL je Fahrt', () {
      // Sonst wird aus dem Sonderrecht ein Dauerfreibrief und der
      // Teleport-Schutz vom 18.06. ist ausgehebelt.
      expect(
        RegExp(r'_hatJeVerankert = true;').allMatches(quelle).length,
        greaterThanOrEqualTo(4),
        reason:
            'Jeder angenommene Vorschub muss das Flag setzen, nicht nur die '
            'Erstverankerung selbst.',
      );
      expect(
        RegExp(r'_hatJeVerankert = false;').allMatches(quelle).length,
        greaterThanOrEqualTo(5),
        reason: 'Und jede neue Route muss es zuruecksetzen.',
      );
    });

    test('sie benutzt die Selbstueberlapp-sichere Suche', () {
      final start = quelle.indexOf('if (!_hatJeVerankert &&');
      final block = quelle.substring(start, start + 900);
      expect(
        block.contains('findNearestOnRoutePreferIndex'),
        isTrue,
        reason:
            'Der global naechste Punkt waere auf Rundkursen falsch — er kann '
            'auf das Rueckweg-Leg zeigen.',
      );
    });

    test('der Neu-Anker greift in beide Richtungen', () {
      expect(
        quelle.contains('globalMatch.index != _currentRouteIndex'),
        isTrue,
        reason:
            'Mit `<` fing er nur den Index, der zu weit voraus sprang. Der '
            'Fall aus dem Video ist der umgekehrte.',
      );
    });

    test('der Verweigerungs-Zaehler wird nicht im selben Tick genullt', () {
      // Er wird beim globalen Re-Snap erhoeht; die Null-Zeile unten darf nur
      // greifen, wenn der Fenster-Treffer wirklich im Korridor lag. Sonst
      // erreicht der Zaehler die 5 nie und der Anker ist toter Code.
      final stelle = quelle.indexOf(
        'Kein Vorwärts-Match (Puck nicht vor dem Index)',
      );
      expect(stelle, greaterThan(0));
      final block = quelle.substring(stelle, stelle + 900);
      expect(
        block.contains('if (match.distanceMeters <= offRouteCorridor)'),
        isTrue,
        reason: 'Ohne diese Bedingung bleibt der Rueckwaerts-Anker wirkungslos.',
      );
    });
  });

  _linienWaechter();

}

/// Nachtrag: Der Neu-Anker muss die LINIE mitziehen, nicht nur die Zahlen.
///
/// Auf den Aufnahmen vom 28.08. war genau diese Halbheit zu sehen: Die helle
/// Leitlinie klebte am Routenanfang. Zog man nur den Index nach, waeren
/// Banner und Restweg richtig, die Linie aber weiter falsch.
void _linienWaechter() {
  test('nach einem Neu-Anker wird auch die Render-Sperre neu gesetzt', () {
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    expect(
      quelle.contains('(canCommitGlobalProgress || neuVerankert) &&'),
      isTrue,
      reason:
          'Sonst zieht die Linie nur nach einem regulaeren Commit mit, nicht '
          'nach der Rettung durch den Neu-Anker.',
    );
    // Und die Erstverankerung muss sie ebenfalls setzen.
    final start = quelle.indexOf('if (!_hatJeVerankert &&');
    final block = quelle.substring(start, start + 1800);
    expect(
      block.contains('_reanchorRenderLockToDistance'),
      isTrue,
      reason: 'Auch beim ersten Anheften muss die Linie zum Fahrer springen.',
    );
    expect(
      block.contains('_lastTrimDistM = -1'),
      isTrue,
      reason: 'Ohne geleerte Trim-Zwischenspeicher bleibt der Schnitt stehen.',
    );
  });
}
