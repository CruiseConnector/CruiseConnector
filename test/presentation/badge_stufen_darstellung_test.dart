import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_stufen_stil.dart';
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';

/// 2026-08-19 (vucko woertlich): „und baue die Badges weiter aus schau das sie
/// andere Farben andere Formen andere Symbole haben die Aufteilung gefaellt
/// mir sehr gut. das die niedrigste Stufe Bronze / Rot ist, die beste lila
/// oder blau ist und das man wirklich einen ueberblick hat"
///
/// Dieser Test haelt genau das fest, was man sonst nur „sieht": dass die drei
/// Stufen sich in Farbe UND Form UND Symbol unterscheiden, dass sie auf dem
/// dunklen App-Hintergrund lesbar sind, dass sie auch ohne Farbe noch
/// auseinandergehen und dass ein gesperrtes Badge seine Stufe nicht verliert.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Der Hintergrund, auf dem die Badges tatsaechlich stehen.
  const grund = Color(0xFF0B0E14);

  double kanal(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double leuchtdichte(Color c) =>
      0.2126 * kanal(c.r) + 0.7152 * kanal(c.g) + 0.0722 * kanal(c.b);

  double kontrast(Color a, Color b) {
    final la = leuchtdichte(a);
    final lb = leuchtdichte(b);
    final hell = math.max(la, lb);
    final dunkel = math.min(la, lb);
    return (hell + 0.05) / (dunkel + 0.05);
  }

  /// Malt einen Stufen-Rahmen und liefert die Deckkraft je Bildpunkt zurueck.
  Future<List<int>> deckkraft(
    BadgeStufenStil stil, {
    required bool freigeschaltet,
    int kante = 64,
  }) async {
    final aufnahme = ui.PictureRecorder();
    final leinwand = Canvas(aufnahme);
    BadgeStufenRahmenPainter(
      stil: stil,
      freigeschaltet: freigeschaltet,
    ).paint(leinwand, Size(kante.toDouble(), kante.toDouble()));
    final bild = await aufnahme.endRecording().toImage(kante, kante);
    final rohdaten = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = rohdaten!.buffer.asUint8List();
    return [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
  }

  group('Die Skala steht wie besprochen', () {
    test('drei Stufen, aufsteigend, mit den Ziffern aus dem Modell', () {
      expect(badgeStufenSkala, hasLength(3));
      for (var i = 0; i < badgeStufenSkala.length; i++) {
        expect(badgeStufenSkala[i].stufe, i + 1);
        // Die Rangfolge-Wahrheit steht im Modell. Laufen die Dateien
        // auseinander, faellt es hier auf.
        expect(badgeStufenSkala[i].ziffer, app.Badge.stufenZeichen[i + 1]);
      }
    });

    test('die Leiter heisst Bronze, Silber, Gold', () {
      // 2026-09-01 (Vucko, neue Badge-Serie aus Figma): Hier stand bis heute
      // „niedrigste Stufe ist rot/bronze, hoechste lila/blau" — genau so hatte
      // er es am 19.08. gewuenscht. Mit der neuen Serie hat er sich anders
      // entschieden, und die Embleme tragen die neue Leiter bereits:
      // Bronzekreis, Silberwappen, Goldsechseck. Auf dem Board steht
      // ausdruecklich: „Es gibt KEINE violetten Stufenbadges mehr."
      //
      // Violett bleibt der Serie erhalten, aber nur fuer die Sonderbadges.
      expect(badgeStufenSkala.map((s) => s.name).toList(), [
        'Bronze',
        'Silber',
        'Gold',
      ]);

      final unten = badgeStufenSkala.first.farbe;
      expect(
        unten.r > unten.g && unten.r > unten.b,
        isTrue,
        reason: 'Stufe I bleibt der warme, rote Pol',
      );

      final oben = badgeStufenSkala.last.farbe;
      expect(
        oben.r > oben.b && oben.g > oben.b,
        isTrue,
        reason: 'Stufe III muss golden sein, also warm und nicht blau',
      );
      expect(
        oben.b < oben.g * 0.7,
        isTrue,
        reason:
            'Bei Gold muss Blau der schwaechste Kanal sein und deutlich unter '
            'Gruen liegen, sonst kippt der Ton ins Fahle.',
      );

      // Die Mitte ist neutral: Silber trennt sich von beiden Polen, ohne
      // selbst einen Farbstich zu haben.
      final mitte = badgeStufenSkala[1].farbe;
      expect(
        (mitte.r - mitte.b).abs() < 0.16,
        isTrue,
        reason: 'Silber muss neutral bleiben, nicht tuerkis',
      );
    });

    test('keine Stufe teilt Farbe, Form oder Symbol mit einer anderen', () {
      expect(
        badgeStufenSkala.map((s) => s.farbe.toARGB32()).toSet(),
        hasLength(3),
      );
      expect(badgeStufenSkala.map((s) => s.form).toSet(), hasLength(3));
      expect(
        badgeStufenSkala.map((s) => s.symbol.codePoint).toSet(),
        hasLength(3),
      );
      expect(badgeStufenSkala.map((s) => s.name).toSet(), hasLength(3));
    });

    test('keine Gedankenstriche in den sichtbaren Stufennamen', () {
      for (final stil in badgeStufenSkala) {
        expect(stil.name.contains('—'), isFalse, reason: stil.name);
      }
    });
  });

  group('Lesbar auf dunklem Grund', () {
    test('Leitfarbe und Textfarbe heben sich deutlich vom Grund ab', () {
      for (final stil in badgeStufenSkala) {
        expect(
          kontrast(stil.farbe, grund),
          greaterThanOrEqualTo(3.0),
          reason: '${stil.name}: Leitfarbe zu blass fuer Rand und Balken',
        );
        expect(
          kontrast(stil.farbeHell, grund),
          greaterThanOrEqualTo(4.5),
          reason: '${stil.name}: Textfarbe unter der Lesbarkeitsschwelle',
        );
      }
    });

    test('die Stufen trennen sich auch ohne Farbe', () {
      // Wer Rot und Gruen schlecht trennt, sieht vor allem noch Helligkeit.
      // Jedes Paar muss deshalb einen messbaren Helligkeitsabstand haben.
      for (var i = 0; i < badgeStufenSkala.length; i++) {
        for (var j = i + 1; j < badgeStufenSkala.length; j++) {
          final a = badgeStufenSkala[i];
          final b = badgeStufenSkala[j];
          expect(
            kontrast(a.farbe, b.farbe),
            greaterThanOrEqualTo(1.4),
            reason: '${a.name} und ${b.name} sind in Graustufen zu aehnlich',
          );
        }
      }
    });
  });

  group('Die Formen sind wirklich verschieden', () {
    test('jede Stufe deckt eine andere Flaeche ab', () async {
      final flaechen = <BadgeStufenForm, List<int>>{};
      for (final stil in badgeStufenSkala) {
        flaechen[stil.form] = await deckkraft(stil, freigeschaltet: true);
      }
      final formen = flaechen.keys.toList();
      for (var i = 0; i < formen.length; i++) {
        for (var j = i + 1; j < formen.length; j++) {
          final a = flaechen[formen[i]]!;
          final b = flaechen[formen[j]]!;
          var verschieden = 0;
          for (var p = 0; p < a.length; p++) {
            if ((a[p] > 10) != (b[p] > 10)) verschieden++;
          }
          final anteil = verschieden / a.length;
          expect(
            anteil,
            greaterThan(0.03),
            reason:
                '${formen[i]} und ${formen[j]} unterscheiden sich nur um '
                '${(anteil * 100).toStringAsFixed(1)} Prozent der Flaeche',
          );
        }
      }
    });

    test('der Umriss bleibt im zugewiesenen Feld', () {
      const feld = Rect.fromLTWH(0, 0, 50, 50);
      for (final form in BadgeStufenForm.values) {
        final grenzen = badgeStufenPfad(form, feld).getBounds();
        expect(feld.inflate(0.5).contains(grenzen.topLeft), isTrue);
        expect(feld.inflate(0.5).contains(grenzen.bottomRight), isTrue);
      }
    });
  });

  group('Die Stufe steckt auch INNEN drin', () {
    /// 2026-08-24 (vucko woertlich): „das schlechteste soll nicht nur im kreis
    /// die andere farbe haben sondern auch innen drinnen".
    ///
    /// Vorher war die Fuellung bei jeder Stufe derselbe Hauch Leitfarbe auf
    /// dem dunklen Grund — Stufe I und Stufe III lagen innen nur 1,23 : 1
    /// auseinander, und Stufe II war heller als Stufe III. Wer die Stufe
    /// erkennen wollte, musste die RAENDER vergleichen.

    /// Wie die Fuellung am Ende wirklich aussieht: der Farbwert, ueber den
    /// dunklen App-Grund gelegt.
    Color aufGrund(Color farbe) => Color.alphaBlend(farbe, grund);

    List<Color> fuellung(BadgeStufenStil stil, {required bool offen}) => [
      for (final c in badgeStufenInnenFarben(stil, freigeschaltet: offen))
        aufGrund(c),
    ];

    test('die unterste Stufe ist INNEN dunkler als jede andere', () {
      // Das ist Vuckos Satz, in eine Zahl uebersetzt: „das schlechteste"
      // erkennt man an der Flaeche, ohne die Raender zu vergleichen.
      final unterste = fuellung(badgeStufenSkala.first, offen: true).first;
      for (final stil in badgeStufenSkala.skip(1)) {
        final andere = fuellung(stil, offen: true).first;
        expect(
          leuchtdichte(unterste),
          lessThan(leuchtdichte(andere)),
          reason: '${stil.name} ist innen nicht heller als Bronze',
        );
        final abstand = kontrast(unterste, andere);
        expect(
          abstand,
          greaterThanOrEqualTo(1.45),
          reason:
              'Bronze und ${stil.name} liegen innen nur '
              '${abstand.toStringAsFixed(2)} : 1 auseinander',
        );
      }
    });

    test('keine zwei Stufen sehen innen gleich aus', () {
      // Tuerkis und Violett liegen in der HELLIGKEIT nah beieinander. Sie
      // muessen sich deshalb im Farbton trennen — Summe der Kanalabstaende,
      // 3,0 waere Schwarz gegen Weiss.
      double kanalabstand(Color a, Color b) =>
          (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

      for (var i = 0; i < badgeStufenSkala.length; i++) {
        for (var j = i + 1; j < badgeStufenSkala.length; j++) {
          final a = fuellung(badgeStufenSkala[i], offen: true).first;
          final b = fuellung(badgeStufenSkala[j], offen: true).first;
          final abstand = kanalabstand(a, b);
          expect(
            abstand,
            greaterThanOrEqualTo(0.45),
            reason:
                '${badgeStufenSkala[i].name} und ${badgeStufenSkala[j].name} '
                'haben innen fast dieselbe Farbe '
                '(Abstand ${abstand.toStringAsFixed(2)} von 3,0)',
          );
        }
      }
    });

    test('die Fuellung hebt sich ueberhaupt vom Grund ab', () {
      for (final stil in badgeStufenSkala) {
        for (final farbe in fuellung(stil, offen: true)) {
          expect(
            kontrast(farbe, grund),
            greaterThanOrEqualTo(1.3),
            reason: '${stil.name}: das Innere verschwindet im Hintergrund',
          );
        }
      }
    });

    test('das Symbol bleibt auf der neuen Fuellung lesbar', () {
      // Die Falle bei der hellen Stufe: fuellt man mit der satten Leitfarbe,
      // faellt das helle Symbol darin zusammen. 3 : 1 ist die Schwelle fuer
      // grafische Elemente.
      for (final stil in badgeStufenSkala) {
        for (final farbe in fuellung(stil, offen: true)) {
          final wert = kontrast(stil.farbeHell, farbe);
          expect(
            wert,
            greaterThanOrEqualTo(3.0),
            reason:
                '${stil.name}: Symbol auf der Fuellung nur '
                '${wert.toStringAsFixed(2)} : 1',
          );
        }
      }
    });

    test('gesperrt sieht nicht aus wie eine niedrige Stufe', () {
      for (final stil in badgeStufenSkala) {
        final zu = fuellung(stil, offen: false);
        for (final farbe in zu) {
          expect(
            kontrast(farbe, grund),
            lessThan(1.2),
            reason: '${stil.name}: gesperrt wirkt gefuellt statt hohl',
          );
        }
        // Und der Abstand zur echten, freigeschalteten Stufe ist gross.
        expect(
          kontrast(zu.first, fuellung(stil, offen: true).first),
          greaterThanOrEqualTo(1.3),
          reason: '${stil.name}: gesperrt und offen sehen innen gleich aus',
        );
      }
    });
  });

  group('Gesperrt bleibt die Stufe ablesbar', () {
    test('die Form wird auch gesperrt vollstaendig gezeichnet', () async {
      for (final stil in badgeStufenSkala) {
        final offen = await deckkraft(stil, freigeschaltet: true);
        final zu = await deckkraft(stil, freigeschaltet: false);
        final flaecheOffen = offen.where((a) => a > 10).length;
        final flaecheZu = zu.where((a) => a > 10).length;
        expect(
          flaecheZu,
          greaterThan(flaecheOffen * 0.9),
          reason: '${stil.name}: die gesperrte Kachel verliert ihre Silhouette',
        );
        // Der Rand behaelt genug Deckkraft, um die Stufe zu erkennen.
        expect(
          zu.where((a) => a >= 90).length,
          greaterThan(50),
          reason: '${stil.name}: gesperrter Rand zu fahl',
        );
      }
    });
  });

  group('Die Uebersicht rechnet richtig', () {
    Map<app.BadgeMetrik, double> werte({double km = 0, int kurven = 0}) =>
        app.badgeMetriken(totalKm: km, kurvenjagdFahrten: kurven);

    test('hoechstens drei Ziele, das naechste zuerst', () {
      final ziele = badgeNaechsteZiele(
        erreichteIds: const {},
        metriken: werte(km: 400, kurven: 2),
      );
      expect(ziele.length, lessThanOrEqualTo(3));
      for (var i = 1; i < ziele.length; i++) {
        expect(
          ziele[i - 1].fortschritt.anteil,
          greaterThanOrEqualTo(ziele[i].fortschritt.anteil),
        );
      }
      // 400 von 500 km ist naeher dran als 2 von 3 Kurvenfahrten.
      expect(ziele.first.familie.schluessel, 'distanz');
    });

    test('der genannte Name gehoert zum gezeigten Balken', () {
      // Regression: `Badge.naechsteStufe` geht nach Stufe, der Fortschritt
      // nach kleinster offener Schwelle. Bei „Kilometer" faellt das nach
      // 500 km auseinander (Meilenstein 1.000 vor Stufe II mit 2.500). Vorher
      // haette die Uebersicht „2.500 km" ueber einem Balken gezeigt, der
      // gegen 1.000 rechnet.
      final ziele = badgeNaechsteZiele(
        erreichteIds: {'badge_06'},
        metriken: werte(km: 700),
        anzahl: 20,
      );
      for (final ziel in ziele) {
        final bedingung = app.badgeBedingungFuer(ziel.badge.id)!;
        expect(
          bedingung.stufe.schwelle,
          ziel.fortschritt.ziel,
          reason:
              '${ziel.badge.name} passt nicht zum Balken der Familie '
              '${ziel.familie.schluessel}',
        );
      }
      final distanz = ziele.firstWhere(
        (z) => z.familie.schluessel == 'distanz',
      );
      expect(distanz.badge.id, 'badge_31');
      expect(distanz.fortschritt.ziel, 1000);
    });

    test('erreichte Familien tauchen nicht mehr als Ziel auf', () {
      final alle = app.Badge.familienBadges('kurven').map((b) => b.id).toSet();
      final ziele = badgeNaechsteZiele(
        erreichteIds: alle,
        metriken: werte(kurven: 99),
        anzahl: 20,
      );
      expect(ziele.any((z) => z.familie.schluessel == 'kurven'), isFalse);
    });

    test('der Restweg sagt, was fehlt, nicht was schon da ist', () {
      final fortschritt = app.badgeFamilienFortschritt(
        familie: 'distanz',
        erreichteBadgeIds: const {},
        metriken: werte(km: 274),
      )!;
      expect(badgeRestweg(fortschritt), 'noch 226 km');
    });

    test('jede Familie hat ein Ziel, solange etwas offen ist', () {
      final ziele = badgeNaechsteZiele(
        erreichteIds: const {},
        metriken: werte(),
        anzahl: 99,
      );
      expect(ziele, hasLength(app.badgeFamilien.length));
    });
  });

  group('Die alte Bronze/Silber/Gold-Tabelle ist weg', () {
    test('die Sammlung faerbt Stufen nur noch ueber die neue Skala', () {
      final seite = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      expect(
        seite.contains('_stufenFarbe'),
        isFalse,
        reason: 'Zwei Stufen-Farbtabellen wuerden wieder auseinanderlaufen',
      );
      expect(seite.contains('0xFFCD7F32'), isFalse, reason: 'altes Bronze');
      expect(seite.contains('badgeStufenStil'), isTrue);
    });

    test('auch das Detail-Blatt nutzt die gemeinsame Skala', () {
      final blatt = File(
        'lib/presentation/widgets/profile_badge_showcase.dart',
      ).readAsStringSync();
      expect(blatt.contains('0xFFCD7F32'), isFalse);
      expect(blatt.contains('badgeStufenStil'), isTrue);
    });
  });
}
