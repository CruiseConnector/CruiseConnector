// 2026-09-01 — Vucko:
//   "auch muessen wir schauen wie wir das loesen wenn sich der weg
//    ueberschneidet und der hinweg sich mit dem rueckweg ueberschneidet weil
//    so sieht es wie in der bildschirmaufnahme auch sehr verbuggt aus"
//
// Auf der Aufnahme fuhr die Route eine Strasse hinauf, machte oben eine
// Haarnadel und kam auf DERSELBEN Strasse zurueck. Beide Spuren liegen
// geometrisch uebereinander, also zeichnet die Karte EINE Linie, wo zwei
// sind. Fuer den Fahrer sieht es aus, als ende die Strecke oben einfach.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/ueberlappung_versatz.dart';

const double _meterProGradBreite = 111320.0;

double meterZwischen(List<double> a, List<double> b) {
  final mittlereBreite = (a[1] + b[1]) / 2 * math.pi / 180.0;
  final dx = (b[0] - a[0]) * _meterProGradBreite * math.cos(mittlereBreite);
  final dy = (b[1] - a[1]) * _meterProGradBreite;
  return math.sqrt(dx * dx + dy * dy);
}

/// Vuckos Geometrie: gerade nach Norden, Haarnadel, dieselbe Strecke zurueck.
List<List<double>> hinUndZurueck({double laenge = 875, double schritt = 25}) {
  final n = (laenge / schritt).round();
  final p = <List<double>>[];
  for (var i = 0; i <= n; i++) {
    p.add([9.74, 47.41 + (i * schritt) / _meterProGradBreite]);
  }
  for (var i = n; i >= 0; i--) {
    p.add([9.74, 47.41 + (i * schritt) / _meterProGradBreite]);
  }
  return p;
}

void main() {
  group('Hin- und Rueckweg werden auseinandergezogen', () {
    test('vorher liegen die Spuren exakt uebereinander', () {
      final roh = hinUndZurueck();
      final n = (875 / 25).round();
      // Punkt 10 auf dem Hinweg und sein Gegenstueck auf dem Rueckweg.
      final abstand = meterZwischen(roh[10], roh[roh.length - 1 - 10]);
      expect(
        abstand,
        lessThan(0.5),
        reason:
            'Die Teststrecke muss den gemeldeten Fall abbilden: beide Spuren '
            'auf demselben Punkt.',
      );
      expect(n, greaterThan(ueberlappMindestAbstandPunkte));
    });

    test('nachher liegen sie sichtbar nebeneinander', () {
      final versetzt = mitUeberlappungsVersatz(hinUndZurueck());
      final abstand = meterZwischen(
        versetzt[10],
        versetzt[versetzt.length - 1 - 10],
      );
      expect(
        abstand,
        greaterThan(ueberlappVersatzMeter * 0.8),
        reason:
            'Der Rueckweg muss sichtbar neben dem Hinweg liegen, sonst sieht '
            'man weiterhin nur eine Linie.',
      );
      expect(
        abstand,
        lessThan(ueberlappVersatzMeter * 2.5),
        reason:
            'Zu weit versetzt loest die Linie sich sichtbar von der Strasse.',
      );
    });

    test('der HINWEG bleibt unveraendert auf der Strasse', () {
      // Nur die zweite Vorbeifahrt rueckt zur Seite. Die erste muss genau
      // dort bleiben, wo die Strasse ist.
      final roh = hinUndZurueck();
      final versetzt = mitUeberlappungsVersatz(roh);
      final n = (875 / 25).round();
      for (var i = 0; i <= n; i++) {
        expect(
          meterZwischen(roh[i], versetzt[i]),
          lessThan(0.01),
          reason: 'Hinweg-Punkt $i wurde verschoben.',
        );
      }
    });

    test('die Punktzahl bleibt gleich', () {
      final roh = hinUndZurueck();
      expect(mitUeberlappungsVersatz(roh).length, roh.length);
    });
  });

  group('Was NICHT versetzt werden darf', () {
    test('eine gerade Strecke bleibt unangetastet', () {
      final gerade = [
        for (var i = 0; i < 200; i++)
          [9.74, 47.41 + (i * 25) / _meterProGradBreite],
      ];
      expect(
        identical(mitUeberlappungsVersatz(gerade), gerade),
        isTrue,
        reason:
            'Ohne Ueberlappung soll dieselbe Liste zurueckkommen — dann '
            'erkennt der Aufrufer, dass sich nichts geaendert hat, und die '
            'Karte muss nichts neu zeichnen.',
      );
    });

    test('eine enge Kurve gilt nicht als Ueberlappung', () {
      // In einer Serpentine liegen aufeinanderfolgende Punkte naturgemaess
      // nah beieinander. Ohne den Mindestabstand wuerde jede Kehre versetzt.
      final kurve = <List<double>>[];
      for (var i = 0; i < 40; i++) {
        final t = i / 40 * math.pi;
        kurve.add([
          9.74 + 0.00012 * math.sin(t),
          47.41 + (i * 6) / _meterProGradBreite,
        ]);
      }
      expect(
        identical(mitUeberlappungsVersatz(kurve), kurve),
        isTrue,
        reason: 'Eine Kurve ist keine zweite Vorbeifahrt.',
      );
    });

    test('ein Rundkurs ohne Ueberlappung bleibt unangetastet', () {
      final runde = <List<double>>[];
      for (var i = 0; i <= 120; i++) {
        final t = i / 120 * 2 * math.pi;
        runde.add([
          9.74 + 0.012 * math.cos(t),
          47.41 + 0.009 * math.sin(t),
        ]);
      }
      expect(identical(mitUeberlappungsVersatz(runde), runde), isTrue);
    });

    test('zu kurze Listen werden durchgereicht', () {
      final kurz = [
        [9.74, 47.41],
        [9.75, 47.42],
      ];
      expect(identical(mitUeberlappungsVersatz(kurz), kurz), isTrue);
      expect(mitUeberlappungsVersatz(const []), isEmpty);
    });
  });

  group('Die aktive Linie wird nicht angefasst', () {
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('der Versatz steht an genau EINER Stelle', () {
      expect(
        RegExp(r'mitUeberlappungsVersatz\(').allMatches(quelle).length,
        1,
        reason:
            'Der Versatz gehoert ausschliesslich in '
            '_fullRouteBackgroundLatLngs.',
      );
    });

    test('die versetzte Linie wird NUR als Hintergrund gezeichnet', () {
      // 2026-09-01, nachgebessert: Die erste Fassung dieses Waechters zaehlte
      // nur die AUFRUFE der Versatz-Funktion. Sie hat dadurch uebersehen, dass
      // _fullRouteBackgroundLatLngs an zwei weiteren Stellen als AKTIVE Linie
      // diente — waehrend eines Reroutes und als Rueckfall in der Uebersicht.
      // Dort sitzt der Standortpunkt darauf; eine versetzte Linie haette ihn
      // sichtbar danebenstehen lassen. Nicht der Aufruf zaehlt, sondern wer
      // den Getter VERBRAUCHT.
      final verwendungen = <int>[];
      var ab = 0;
      while (true) {
        final i = quelle.indexOf('_fullRouteBackgroundLatLngs', ab);
        if (i < 0) break;
        verwendungen.add(i);
        ab = i + 1;
      }
      // Jede Verwendung muss entweder die Definition sein, ein Kommentar, oder
      // in der Hintergrund-Zeichenschicht stehen.
      for (final i in verwendungen) {
        final zeilenanfang = quelle.lastIndexOf('\n', i) + 1;
        final zeile = quelle.substring(
          zeilenanfang,
          quelle.indexOf('\n', i),
        );
        final istKommentar = zeile.trimLeft().startsWith('//');
        final istDefinition = zeile.contains('get _fullRouteBackgroundLatLngs');
        if (istKommentar || istDefinition) continue;
        // Sonst muss unmittelbar danach die gedimmte Hintergrundschicht
        // stehen: eine PolylineLayer mit halbdurchsichtiger Farbe. Genau die
        // traegt keinen Standortpunkt.
        final danach = quelle.substring(
          i,
          math.min(quelle.length, i + 420),
        );
        expect(
          danach.contains('PolylineLayer') && danach.contains('withValues'),
          isTrue,
          reason:
              'Die versetzte Linie wird ausserhalb der gedimmten '
              'Hintergrundschicht benutzt (Zeile "$zeile"). Sitzt dort der '
              'Standortpunkt drauf, steht er sichtbar neben der Linie.',
        );
      }
    });

    test('es gibt eine unversetzte Fassung fuer die aktive Linie', () {
      expect(
        quelle.contains('_fullRouteLatLngsOhneVersatz'),
        isTrue,
        reason:
            'Ohne sie muesste die aktive Linie die versetzte Fassung nehmen.',
      );
      // Sie darf den Versatz NICHT anwenden.
      final i = quelle.indexOf('get _fullRouteLatLngsOhneVersatz');
      expect(i, greaterThan(-1));
      final block = quelle.substring(i, i + 700);
      expect(
        block.contains('mitUeberlappungsVersatz'),
        isFalse,
        reason: 'Die unversetzte Fassung darf nicht versetzen.',
      );
    });
  });
}
