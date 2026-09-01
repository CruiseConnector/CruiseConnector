// 2026-09-01 — Vucko:
//   "die routen die jetzt im routenpool gespeichert sind und genehmigt werden
//    von der app keine wendepunkte mitten auf den strassen erlauben"
//
// Die Wende-Erkennung gibt es jetzt ZWEIMAL: in TypeScript auf dem Server
// (generate-cruise-route-v2, fuer frisch erzeugte Routen) und in Dart in der
// App (fuer alles, was nicht frisch vom Server kommt).
//
// Zwei Fassungen derselben Rechnung sind eine Falle. Laufen sie auseinander,
// faellt dieselbe Strecke je nach Weg mal durch das Tor und mal nicht — und
// das merkt niemand, weil beide Fassungen fuer sich genommen richtig
// aussehen. Genau dieses Muster gab es hier schon einmal bei der
// Laender-Klassifikation; der Test dazu (laender_klassifikation_test.dart)
// ist das Vorbild fuer diesen hier.
//
// Dieser Test vergleicht die KONSTANTEN beider Dateien Zeichen fuer Zeichen
// und prueft die portierte Rechnung an Geometrien mit bekanntem Ergebnis.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/kehrtwenden_zaehler.dart';

/// Baut eine Strecke aus [longitude, latitude] mit gleichmaessigem Abstand.
///
/// [meterProSchritt] entlang der angegebenen Richtung, damit die Testdaten
/// dieselbe Groessenordnung haben wie echte GraphHopper-Geometrien.
List<List<double>> gerade({
  required double startLng,
  required double startLat,
  required double kursGrad,
  required double laengeM,
  double meterProSchritt = 20,
}) {
  final punkte = <List<double>>[];
  final mProLng = 111320 * math.cos(startLat * math.pi / 180);
  const mProLat = 110540.0;
  final rad = kursGrad * math.pi / 180;
  // Kurs 0 = Norden, 90 = Osten.
  final ostAnteil = math.sin(rad);
  final nordAnteil = math.cos(rad);
  final schritte = (laengeM / meterProSchritt).round();
  for (var i = 0; i <= schritte; i++) {
    final m = i * meterProSchritt;
    punkte.add([
      startLng + (m * ostAnteil) / mProLng,
      startLat + (m * nordAnteil) / mProLat,
    ]);
  }
  return punkte;
}

/// Haengt eine Strecke an eine andere, ohne den Nahtpunkt zu verdoppeln.
List<List<double>> anhaengen(List<List<double>> a, List<List<double>> b) {
  return <List<double>>[...a, ...b.skip(1)];
}

/// Kehrt eine Strecke um — das ist der Rueckweg auf DERSELBEN Strasse.
List<List<double>> rueckwaerts(List<List<double>> a) =>
    a.reversed.toList(growable: false);

void main() {
  group('Die Dart-Fassung rechnet wie die Server-Fassung', () {
    late String tsQuelle;
    late String poolQuelle;

    setUpAll(() {
      tsQuelle = File(
        'supabase/functions/generate-cruise-route-v2/index.ts',
      ).readAsStringSync();
      // Es gibt ZWEI Fassungen derselben Rechnung: eine fuer den Server
      // (`_gemeinsam/kehrtwenden.ts`, benutzt von der Pool-Messung und vom
      // Healing-Worker) und eine fuer die App. Die Routen-Erzeugung
      // `generate-cruise-route-v2` traegt aus historischen Gruenden noch eine
      // eigene Kopie; auch die muss mitlaufen. Alle muessen dasselbe Ergebnis
      // liefern, sonst faellt eine Strecke je nach Weg mal durch das Tor und
      // mal nicht.
      poolQuelle = File(
        'supabase/functions/_gemeinsam/kehrtwenden.ts',
      ).readAsStringSync();
    });

    // Jede Konstante EINZELN, damit die Fehlermeldung sagt, welche
    // auseinandergelaufen ist — eine Sammelpruefung wuerde nur "ungleich"
    // melden und man suchte von Hand.
    final paare = <String, ({String tsName, num dartWert})>{
      'Rasterweite': (tsName: 'KEHRTWENDE_RASTER_M', dartWert: kehrtwendeRasterM),
      'Naehe': (tsName: 'KEHRTWENDE_NAEHE_M', dartWert: kehrtwendeNaeheM),
      'Mindestweg': (tsName: 'KEHRTWENDE_MIN_WEG_M', dartWert: kehrtwendeMinWegM),
      'Hoechstweg': (tsName: 'KEHRTWENDE_MAX_WEG_M', dartWert: kehrtwendeMaxWegM),
      'Gegenlaeufigkeit': (
        tsName: 'KEHRTWENDE_GEGENLAEUFIG_COS',
        dartWert: kehrtwendeGegenlaeufigCos,
      ),
      'Zellengroesse': (tsName: 'KEHRTWENDE_ZELLE_M', dartWert: kehrtwendeZelleM),
      'Buendel-Toleranz': (
        tsName: 'KEHRTWENDE_BUENDEL_TOLERANZ',
        dartWert: kehrtwendeBuendelToleranz,
      ),
      'Randbreite': (tsName: 'KEHRTWENDE_RAND_M', dartWert: kehrtwendeRandM),
      'Punkt-Obergrenze': (
        tsName: 'UEBERLAPP_MAX_PUNKTE',
        dartWert: ueberlappMaxPunkte,
      ),
      'Drehfenster': (
        tsName: 'KEHRTWENDE_DREH_FENSTER_M',
        dartWert: kehrtwendeDrehFensterM,
      ),
      'Drehwinkel': (
        tsName: 'KEHRTWENDE_DREH_GRAD',
        dartWert: kehrtwendeDrehGrad,
      ),
    };

    paare.forEach((bezeichnung, paar) {
      test('$bezeichnung stimmt mit ${paar.tsName} ueberein', () {
        final treffer = RegExp(
          'const ${paar.tsName}\\s*=\\s*(-?[0-9.]+)',
        ).firstMatch(tsQuelle);
        expect(
          treffer,
          isNotNull,
          reason:
              '${paar.tsName} steht nicht mehr in der Edge-Funktion. Wurde sie '
              'umbenannt, muss die Dart-Fassung mitwandern.',
        );
        final ausTs = num.parse(treffer!.group(1)!);
        expect(
          paar.dartWert,
          ausTs,
          reason:
              'Server rechnet mit $ausTs, die App mit ${paar.dartWert}. Dann '
              'faellt dieselbe Strecke je nach Weg mal durch das Tor und mal '
              'nicht.',
        );

        final imPool = RegExp(
          'const ${paar.tsName}\\s*=\\s*(-?[0-9.]+)',
        ).firstMatch(poolQuelle);
        expect(
          imPool,
          isNotNull,
          reason:
              '${paar.tsName} fehlt im gemeinsamen Server-Modul. Dann misst '
              'der Server den Pool anders, als die App ihn beurteilt.',
        );
        expect(
          num.parse(imPool!.group(1)!),
          ausTs,
          reason:
              'Das gemeinsame Modul rechnet mit einem anderen Wert als die '
              'Routen-Erzeugung.',
        );
      });
    });

    test('nur EIN Server-Modul rechnet, der Rest holt es sich', () {
      // 2026-09-01: Es gab kurzzeitig drei Kopien. Drei Kopien heisst: eine
      // Strecke faellt je nach Weg mal durch das Tor und mal nicht, und
      // niemand merkt es. Wer die Rechnung wieder in eine Funktion kopiert,
      // faellt hier auf.
      final pool = File(
        'supabase/functions/route-pool-wenden/index.ts',
      ).readAsStringSync();
      final worker = File(
        'supabase/functions/tools/route_pool_healing_worker.ts',
      ).readAsStringSync();
      for (final entry in {'route-pool-wenden': pool, 'healing-worker': worker}
          .entries) {
        expect(
          entry.value.contains("_gemeinsam/kehrtwenden.ts"),
          isTrue,
          reason:
              '${entry.key} holt die Rechnung nicht aus dem gemeinsamen '
              'Modul.',
        );
        expect(
          entry.value.contains('const KEHRTWENDE_RASTER_M'),
          isFalse,
          reason:
              '${entry.key} traegt wieder eine eigene Kopie der Konstanten.',
        );
      }
    });

    test('alle Fassungen pruefen die Drehung am Scheitel', () {
      // Die Bedingung selbst, nicht nur ihre Konstanten. Wer sie in einer der
      // drei Dateien herausnimmt, bekommt wieder jede dritte Meldung falsch.
      expect(tsQuelle.contains('drehtDortWirklich(xs, ys, n, scheitel)'), isTrue);
      expect(poolQuelle.contains('drehtDortWirklich(xs, ys, n, scheitel)'), isTrue);
      final dartQuelle = File(
        'lib/data/services/kehrtwenden_zaehler.dart',
      ).readAsStringSync();
      expect(
        dartQuelle.contains('_drehtDortWirklich(xs, ys, n, scheitel)'),
        isTrue,
      );
    });

    test('die Rasterfunktion benutzt dieselben Erdmasse', () {
      // 111320 m je Laengengrad am Aequator, 110540 m je Breitengrad. Andere
      // Werte verschieben jede Distanz um Prozente.
      expect(tsQuelle.contains('111320 * Math.cos'), isTrue);
      expect(tsQuelle.contains('const mProLat = 110540'), isTrue);
      final dartQuelle = File(
        'lib/data/services/kehrtwenden_zaehler.dart',
      ).readAsStringSync();
      expect(dartQuelle.contains('111320 * math.cos'), isTrue);
      expect(dartQuelle.contains('mProLat = 110540'), isTrue);
    });
  });

  group('Die Rechnung erkennt, was sie erkennen soll', () {
    test('eine durchgehende Gerade hat keine Wende', () {
      final strecke = gerade(
        startLng: 9.7471,
        startLat: 47.5031,
        kursGrad: 90,
        laengeM: 8000,
      );
      final befund = kehrtwendenZaehler(strecke);
      expect(befund.anzahl, 0);
      expect(befund.anzahlMitte, 0);
      expect(befund.hatWendeMittendrin, isFalse);
    });

    test('ein Stich mitten in der Strecke zaehlt als Wende MITTENDRIN', () {
      // 3 km nach Osten, dann 1 km nach Norden abbiegen und auf derselben
      // Strasse zurueck, dann weitere 3 km nach Osten. Vor und nach der Wende
      // liegt also reichlich Strecke — genau der Fall, den Vucko gefahren ist.
      final hin = gerade(
        startLng: 9.7471,
        startLat: 47.5031,
        kursGrad: 90,
        laengeM: 3000,
      );
      final stich = gerade(
        startLng: hin.last[0],
        startLat: hin.last[1],
        kursGrad: 0,
        laengeM: 1000,
      );
      final weiter = gerade(
        startLng: hin.last[0],
        startLat: hin.last[1],
        kursGrad: 90,
        laengeM: 3000,
      );
      final strecke = anhaengen(
        anhaengen(anhaengen(hin, stich), rueckwaerts(stich)),
        weiter,
      );

      final befund = kehrtwendenZaehler(strecke);
      expect(
        befund.anzahl,
        greaterThanOrEqualTo(1),
        reason: 'Der Stich muss ueberhaupt als Wende auffallen.',
      );
      expect(
        befund.anzahlMitte,
        greaterThanOrEqualTo(1),
        reason:
            'Vor dem Stich liegen 3 km und danach 3 km. Das ist keine '
            'Sackgasse am Ziel, das ist ein Routenfehler.',
      );
      expect(befund.hatWendeMittendrin, isTrue);
      expect(
        befund.maxLaengeM,
        greaterThan(800),
        reason: 'Der Stich ist rund 1000 m lang.',
      );
    });

    test('eine Sackgasse AM ZIEL zaehlt NICHT als Wende mittendrin', () {
      // Dieselbe Wende, aber ganz am Ende. Wohnt jemand in einer Sackgasse,
      // kann keine Route der Welt das wegplanen — sie deshalb abzulehnen
      // hiesse, ihm "keine Route" statt einer Route zu geben.
      final hin = gerade(
        startLng: 9.7471,
        startLat: 47.5031,
        kursGrad: 90,
        laengeM: 6000,
      );
      final stich = gerade(
        startLng: hin.last[0],
        startLat: hin.last[1],
        kursGrad: 0,
        laengeM: 200,
      );
      final strecke = anhaengen(anhaengen(hin, stich), rueckwaerts(stich));

      final befund = kehrtwendenZaehler(strecke);
      expect(
        befund.anzahlMitte,
        0,
        reason:
            'Nach der Rueckkehr kommt nichts mehr. Das ist die Lage des Ziels, '
            'kein Routenfehler.',
      );
      expect(befund.hatWendeMittendrin, isFalse);
    });

    test('eine enge Serpentine ist keine Wende', () {
      // Zwei Haarnadeln direkt hintereinander: raeumlich nah und gegenlaeufig,
      // aber unter dem Mindestweg von 150 m. Wuerde die Rechnung das als Wende
      // zaehlen, waere jede Passstrasse ausgeschlossen.
      final hin = gerade(
        startLng: 9.7471,
        startLat: 47.5031,
        kursGrad: 90,
        laengeM: 60,
        meterProSchritt: 10,
      );
      final zurueck = gerade(
        startLng: hin.last[0],
        startLat: hin.last[1],
        kursGrad: 270,
        laengeM: 60,
        meterProSchritt: 10,
      );
      var strecke = <List<double>>[];
      for (var i = 0; i < 20; i++) {
        strecke = strecke.isEmpty
            ? anhaengen(hin, zurueck)
            : anhaengen(strecke, i.isEven ? hin : zurueck);
      }
      final befund = kehrtwendenZaehler(strecke);
      expect(
        befund.anzahlMitte,
        0,
        reason: 'Unter 150 m ist es eine Kehre, keine Kehrtwende.',
      );
    });

    test('eine leere oder zu kurze Geometrie ergibt null Wenden', () {
      expect(kehrtwendenZaehler(const []).anzahl, 0);
      expect(
        kehrtwendenZaehler(const [
          [9.7, 47.5],
        ]).anzahl,
        0,
      );
      expect(
        kehrtwendenZaehler(const [
          [9.7, 47.5],
          [9.7, 47.5],
        ]).anzahl,
        0,
      );
    });

    test('doppelte Stuetzpunkte machen die Rechnung nicht kaputt', () {
      // GraphHopper liefert gelegentlich denselben Punkt zweimal. Ohne die
      // len-groesser-null-Bedingung im Raster waere das Ergebnis NaN.
      final strecke = <List<double>>[];
      for (final p in gerade(
        startLng: 9.7471,
        startLat: 47.5031,
        kursGrad: 90,
        laengeM: 2000,
      )) {
        strecke.add(p);
        strecke.add(<double>[p[0], p[1]]);
      }
      final befund = kehrtwendenZaehler(strecke);
      expect(befund.anzahl, isA<int>());
      expect(befund.maxLaengeM.isFinite, isTrue);
    });
  });
}
