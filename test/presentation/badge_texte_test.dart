import 'dart:io';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-19, nach dem Blick auf den Simulator. Drei Textfehler, die man erst
/// auf dem Gerät sieht:
///  - „Frueh unterwegs" und „Gegruendete Gruppen" ohne Umlaute
///  - „noch 1 Fahrten" statt „noch 1 Fahrt"
///  - Wörter, die in der engen Kachel mitten im Wort umbrachen
void main() {
  group('Deutsche Texte haben Umlaute', () {
    test('kein Badge-Text schreibt ue, oe, ae oder ss statt des Umlauts', () {
      // Die typischen Ersatzschreibungen. Wörter wie „Steuer",
      // „Dauerbrenner" oder „Abgeschlossene" enthalten dieselben
      // Buchstabenfolgen völlig zu Recht und stehen deshalb NICHT hier.
      const verdaechtig = [
        'fuenf', 'ueber', 'Stueck', 'stueck', 'dreissig', 'zwoelf',
        'waehrend', 'taeglich', 'naechste', 'zurueck', 'laeuft',
        'Gegruendete', 'Frueh', 'schliesst', 'groesste',
      ];
      final treffer = <String>[];
      for (final b in Badge.all) {
        for (final text in [b.name, b.description]) {
          for (final v in verdaechtig) {
            if (text.contains(v)) treffer.add('${b.id}: "$text"');
          }
        }
      }
      for (final f in badgeFamilien) {
        for (final v in verdaechtig) {
          if (f.titel.contains(v)) treffer.add('Familie: "${f.titel}"');
        }
        for (final s in f.stufen) {
          for (final v in verdaechtig) {
            if (s.anleitung.contains(v)) {
              treffer.add('${s.id}: "${s.anleitung}"');
            }
          }
        }
      }
      expect(
        treffer,
        isEmpty,
        reason:
            'Diese Texte sieht der Nutzer. Ersatzschreibungen gehören in '
            'Kommentare, nicht in die Oberfläche: $treffer',
      );
    });
  });

  group('Einzahl und Mehrzahl', () {
    test('bei genau einem fehlenden Schritt steht die Einzahl', () {
      expect(badgeEinheit('Fahrten', 1), 'Fahrt');
      expect(badgeEinheit('Gruppen', 1), 'Gruppe');
      expect(badgeEinheit('Gruppenfahrten', 1), 'Gruppenfahrt');
      expect(badgeEinheit('Routen', 1), 'Route');
      expect(badgeEinheit('Rundkurse', 1), 'Rundkurs');
      expect(badgeEinheit('Tage', 1), 'Tag');
    });

    test('ab zwei bleibt die Mehrzahl', () {
      expect(badgeEinheit('Fahrten', 2), 'Fahrten');
      expect(badgeEinheit('Tage', 7), 'Tage');
      expect(badgeEinheit('Fahrten', 0), 'Fahrten');
    });

    test('unveränderliche Einheiten bleiben immer gleich', () {
      for (final e in ['km', 'Std', 'Level']) {
        expect(badgeEinheit(e, 1), e);
        expect(badgeEinheit(e, 5), e);
      }
    });
  });

  group('Kachel-Titel brechen nicht mitten im Wort', () {
    test('lange Namen haben eine kurze Fassung für die Kachel', () {
      // Im Simulator stand „Abgeschlosse ne Fahrten" und „Gruppenfahrte n".
      // Bei drei Spalten ist eine Kachel rund 90 Punkte breit; ab etwa 15
      // Zeichen bricht Flutter mitten im Wort.
      for (final f in badgeFamilien) {
        final kurz = badgeKurzTitel(f.titel);
        final laengstesWort = kurz
            .split(' ')
            .map((w) => w.length)
            .fold<int>(0, (a, b) => a > b ? a : b);
        expect(
          laengstesWort,
          lessThanOrEqualTo(14),
          reason:
              'Das längste Wort in "$kurz" (aus "${f.titel}") ist '
              '$laengstesWort Zeichen und bricht in der Kachel um. '
              'Kurzfassung in badgeKurzTitel ergänzen.',
        );
      }
    });

    test('die Kurzfassung verliert den Sinn nicht', () {
      // Sie darf kürzen, aber nicht etwas anderes bedeuten.
      expect(badgeKurzTitel('Abgeschlossene Fahrten'), 'Fahrten');
      expect(badgeKurzTitel('Kurvenjagd'), 'Kurvenjagd');
      expect(badgeKurzTitel('Level'), 'Level');
    });
  });

  test('die Changelog-Texte haben ebenfalls Umlaute', () {
    final quelle = File('lib/core/app_changelog.dart').readAsStringSync();
    for (final v in ['fuenf', 'ueber ', 'zurueck', 'naechste', 'taeglich']) {
      expect(
        quelle.contains("'$v"),
        isFalse,
        reason: 'Ersatzschreibung "$v" im Changelog gefunden',
      );
    }
  });
}
