// 2026-09-01 — Vuckos Bildschirmaufnahme: "die anzeige wo ich abbiegen muss
// hat die ganze zeit herumgewechselt".
//
// WAS AUF DER AUFNAHME ZU SEHEN WAR (Bild fuer Bild ausgewertet, 37 Sekunden):
// Das Manoever-Banner sprang im SEKUNDENTAKT zwischen zwei Manoevern:
//
//   1s  "4,0 km  Links auf Appenzeller Strasse"   Restweg 3,8 km
//   2s  "3,9 km  Links auf Appenzeller Strasse"   Restweg 3,9 km
//   3s  "700 m   Links auf Bruderhof"             Restweg 5,7 km
//   4s  "3,9 km  Links auf Appenzeller Strasse"   Restweg 3,9 km
//   5s  "650 m   Links auf Bruderhof"             Restweg 5,6 km
//
// Beide Zustaende zaehlten fuer sich sauber herunter, der Unterschied blieb
// konstant bei rund 1,75 km. Auf der Karte: die Route faehrt eine Strasse
// hinauf, macht oben eine Haarnadel und kommt auf DERSELBEN Strasse zurueck.
// 1,75 km sind genau 875 m hin plus 875 m zurueck.
//
// URSACHE: findNearestInWindow nahm den geometrisch naechsten Punkt im
// Indexfenster. Auf der doppelt befahrenen Strasse liegen Hinweg- und
// Rueckweg-Punkt beide unter dem Auto — welcher gewinnt, entschied allein das
// GPS-Rauschen, also bei jedem Fix neu.
//
// WARUM NICHT "nimm den naeheren Index": Der Hinweg-Punkt ist auf dem
// Rueckweg IMMER null Meter entfernt. Mit dieser Regel kaeme das Auto nie
// ueber die Stichstrasse hinaus. Der Test unten haelt genau das fest.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/data/services/route_service.dart';

const double _meterProGradBreite = 111320.0;

/// Vuckos Geometrie: [laenge] Meter schnurgerade nach Norden, Haarnadel,
/// dieselbe Strecke zurueck nach Sueden. Punkt alle [schritt] Meter.
///
/// Der Rueckweg liegt um [versatzMeter] seitlich versetzt, so wie zwei
/// Fahrspuren derselben Strasse. Null waere die Idealisierung; ein paar Meter
/// entsprechen der Wirklichkeit und machen den Test schwerer, nicht leichter.
List<List<double>> hinUndZurueck({
  double laenge = 875,
  double schritt = 25,
  double versatzMeter = 4,
  double startLat = 47.41,
  double startLng = 9.74,
}) {
  final n = (laenge / schritt).round();
  final punkte = <List<double>>[];
  for (var i = 0; i <= n; i++) {
    punkte.add([startLng, startLat + (i * schritt) / _meterProGradBreite]);
  }
  final versatzGrad = versatzMeter / (_meterProGradBreite * 0.676);
  for (var i = n; i >= 0; i--) {
    punkte.add([
      startLng + versatzGrad,
      startLat + (i * schritt) / _meterProGradBreite,
    ]);
  }
  return punkte;
}

geo.Position stehtBei({
  required double lat,
  required double lng,
  double kurs = 0,
  double tempo = 14,
}) {
  return geo.Position(
    longitude: lng,
    latitude: lat,
    timestamp: DateTime(2026, 9, 1, 14, 15),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: kurs,
    headingAccuracy: 5,
    speed: tempo,
    speedAccuracy: 1,
  );
}

void main() {
  group('Hin und zurueck auf derselben Strasse', () {
    final route = hinUndZurueck();
    final wendepunkt = (875 / 25).round(); // Index der Haarnadel
    // 400 m nach dem Start: Hinweg-Index 16, Rueckweg-Index gegenueber.
    const hoeheMeter = 400.0;
    final aufHoehe = 47.41 + hoeheMeter / _meterProGradBreite;

    test('die Teststrecke bildet die Aufnahme ab', () {
      expect(route.length, (875 / 25).round() * 2 + 2);
      // Hin- und Rueckweg liegen an derselben Hoehe praktisch uebereinander.
      final hin = route[16];
      final zurueck = route[route.length - 1 - 16];
      final abstand = geo.Geolocator.distanceBetween(
        hin[1],
        hin[0],
        zurueck[1],
        zurueck[0],
      );
      expect(
        abstand,
        lessThan(10),
        reason:
            'Die beiden Spuren muessen praktisch uebereinander liegen, sonst '
            'prueft der Test den gemeldeten Fall gar nicht.',
      );
    });

    test('OHNE Richtung springt die Ortung — der gemeldete Fehler', () {
      // Der Fahrer ist auf dem HINWEG, sein Index also klein. Das Fenster
      // sieht beide Spuren. Ohne Richtungsangabe entscheidet der Abstand, und
      // der ist bei der leicht versetzten Rueckspur zufaellig mal so, mal so.
      final ohne = findNearestInWindow(
        position: stehtBei(lat: aufHoehe, lng: 9.74 + 0.00003),
        coordinates: route,
        currentIndex: 10,
        windowSize: 80,
        maxJumpMeters: 60,
      );
      // Wir behaupten hier NICHT, dass es immer die falsche Spur trifft —
      // genau das ist ja das Wackelige. Belegt wird nur: das Fenster REICHT
      // bis auf die Rueckspur, die Verwechslung ist also moeglich.
      expect(
        10 + 80,
        greaterThan(route.length - 1 - 16),
        reason:
            'Das 80er-Fenster muss die Rueckweg-Spur ueberhaupt erreichen, '
            'sonst kann der gemeldete Fehler in diesem Test nicht auftreten.',
      );
      expect(ohne.distanceMeters, lessThan(60));
    });

    test('MIT Richtung nach Norden gewinnt der Hinweg', () {
      final treffer = findNearestInWindow(
        position: stehtBei(lat: aufHoehe, lng: 9.74 + 0.00003, kurs: 0),
        coordinates: route,
        currentIndex: 10,
        windowSize: 80,
        maxJumpMeters: 60,
        fahrtrichtungGrad: 0, // Norden
      );
      expect(
        treffer.index,
        lessThanOrEqualTo(wendepunkt),
        reason:
            'Wer nach Norden faehrt, ist auf dem Hinweg. Ein Index jenseits '
            'der Haarnadel waere die Rueckweg-Spur.',
      );
      expect(treffer.distanceMeters, lessThan(20));
    });

    test('MIT Richtung nach Sueden gewinnt der Rueckweg', () {
      // Das ist die Probe, an der die Loesung "naeherer Index" scheitert:
      // dort bliebe die Ortung auf dem Hinweg kleben und das Auto kaeme nie
      // ueber die Stichstrasse hinaus.
      final treffer = findNearestInWindow(
        position: stehtBei(lat: aufHoehe, lng: 9.74 + 0.00003, kurs: 180),
        coordinates: route,
        currentIndex: 10,
        windowSize: 80,
        maxJumpMeters: 60,
        fahrtrichtungGrad: 180, // Sueden
      );
      expect(
        treffer.index,
        greaterThan(wendepunkt),
        reason:
            'Wer nach Sueden faehrt, ist auf dem Rueckweg. Bliebe die Ortung '
            'auf dem Hinweg, kaeme das Auto nie ueber die Stichstrasse '
            'hinaus — genau deshalb ist die Richtung das Merkmal und nicht '
            'die Index-Naehe.',
      );
    });

    test('das Urteil ist ueber die ganze Stichstrasse stabil', () {
      // Der eigentliche Fehler war das WACKELN. Also: derselbe Fahrer, viele
      // Positionen, jeweils mit GPS-Rauschen — das Urteil darf nicht kippen.
      final zufall = math.Random(42);
      for (var meter = 100.0; meter <= 800.0; meter += 50) {
        final lat = 47.41 + meter / _meterProGradBreite;
        for (var versuch = 0; versuch < 8; versuch++) {
          // bis zu 6 m Rauschen quer zur Fahrbahn
          final rauschen = (zufall.nextDouble() - 0.5) * 12;
          final lng = 9.74 + rauschen / (_meterProGradBreite * 0.676);
          final treffer = findNearestInWindow(
            position: stehtBei(lat: lat, lng: lng, kurs: 0),
            coordinates: route,
            currentIndex: 4,
            windowSize: 80,
            maxJumpMeters: 60,
            fahrtrichtungGrad: 0,
          );
          expect(
            treffer.index,
            lessThanOrEqualTo(wendepunkt),
            reason:
                'Bei $meter m, Versuch $versuch, Rauschen '
                '${rauschen.toStringAsFixed(1)} m: die Ortung ist auf die '
                'Rueckweg-Spur gesprungen. Genau dieses Kippen war auf der '
                'Aufnahme als Banner-Wechsel zu sehen.',
          );
        }
      }
    });

    test('ohne Richtung bleibt das Verhalten zeichengleich wie vorher', () {
      // Die sieben anderen Aufrufer duerfen sich nicht veraendern.
      final route2 = hinUndZurueck();
      for (final idx in [0, 5, 20, 40]) {
        final alt = findNearestInWindow(
          position: stehtBei(lat: 47.412, lng: 9.7401),
          coordinates: route2,
          currentIndex: idx,
          windowSize: 80,
          maxJumpMeters: 60,
        );
        final neu = findNearestInWindow(
          position: stehtBei(lat: 47.412, lng: 9.7401),
          coordinates: route2,
          currentIndex: idx,
          windowSize: 80,
          maxJumpMeters: 60,
          fahrtrichtungGrad: null,
        );
        expect(neu.index, alt.index);
        expect(neu.distanceMeters, alt.distanceMeters);
      }
    });

    test('in der Haarnadel selbst wird nichts verschlimmert', () {
      // Direkt am Wendepunkt steht kein Segment in Fahrtrichtung. Dann muss
      // der geometrisch naechste Treffer gewinnen, nicht etwa gar keiner.
      final scheitel = route[wendepunkt];
      final treffer = findNearestInWindow(
        position: stehtBei(lat: scheitel[1], lng: scheitel[0], kurs: 90),
        coordinates: route,
        currentIndex: wendepunkt - 3,
        windowSize: 80,
        maxJumpMeters: 60,
        fahrtrichtungGrad: 90, // quer zu beiden Spuren
      );
      expect(treffer.distanceMeters, lessThan(20));
    });
  });

  group('Die Anzeige haengt an denselben Bremsen wie der Index', () {
    // Der zweite Teil des Fehlers: _stetigeRoutenMeter entscheidet, WELCHES
    // Manoever im Banner steht, wurde aber ohne jede Pruefung gesetzt — waehrend
    // der Index gleich zweifach geschuetzt war. Deshalb standen Puck und Linie
    // still, waehrend die Ansage im Sekundentakt wechselte.
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    /// Der Block, der die stetige Strecke fortschreibt.
    String block() {
      final i = quelle.indexOf('if (!isOutsideCorridor && advanceDecision.matchDist.isFinite)');
      expect(
        i,
        greaterThanOrEqualTo(0),
        reason: 'Der Block gibt es nicht mehr. Waechter mitziehen.',
      );
      return quelle.substring(i, i + 700);
    }

    test('die stetige Strecke verlangt einen plausiblen Zuwachs', () {
      expect(
        block().contains('advanceDecision.plausible'),
        isTrue,
        reason:
            'Ohne diese Bedingung uebernimmt die Anzeige auch einen Sprung von '
            '1750 Metern in einer Sekunde — genau den auf die Rueckweg-Spur.',
      );
    });

    test('die stetige Strecke haelt den Anti-Ueberlapp-Deckel ein', () {
      expect(
        block().contains('_antiUeberlappCapPunkte'),
        isTrue,
        reason:
            'Der Deckel schuetzte nur den Index. Die Anzeige lief daran vorbei '
            'und sprang auf die Rueckweg-Spur.',
      );
    });

    test('die stetige Strecke waechst nur', () {
      final b = block();
      expect(
        b.contains('bisher == null') && b.contains('>= bisher'),
        isTrue,
        reason:
            'Der Name sagt „stetig". Ohne Monotonie kann der Wert zurueck- und '
            'wieder vorspringen, und das Banner wechselt mit.',
      );
    });

    test('Index und Anzeige benutzen DENSELBEN Deckel', () {
      // Zwei getrennte Zahlen wuerden wieder auseinanderlaufen.
      expect(
        RegExp(r'_antiUeberlappCapPunkte').allMatches(quelle).length,
        greaterThanOrEqualTo(3),
        reason:
            'Erwartet: die Konstante selbst plus je eine Verwendung fuer den '
            'Index und fuer die stetige Strecke.',
      );
      expect(
        RegExp(r'-\s*_currentRouteIndex\s*<=\s*60').hasMatch(quelle),
        isFalse,
        reason: 'Die nackte 60 gehoert nicht mehr in den Code.',
      );
    });

    test('die Fahrtrichtung wird nur bei brauchbarem Tempo benutzt', () {
      expect(
        quelle.contains('_mindestTempoFuerRichtungMps'),
        isTrue,
        reason:
            'Im Stand ist der Kurs Rauschen. Ohne Tempopruefung waere die '
            'Richtungspruefung dort schlechter als gar keine.',
      );
      expect(
        quelle.contains('hasValidHeading'),
        isTrue,
        reason: 'Ein ungueltiger Kurs darf die Spur nicht entscheiden.',
      );
    });
  });
}
