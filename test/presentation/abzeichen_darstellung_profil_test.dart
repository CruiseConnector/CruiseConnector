// 2026-09-01 — Vucko:
//   "ganz wichtig moechte ich das die badges bei einem Profil besser
//    angezeigt werden wie im screenshot den ich dir geschickt habe"
//
// AUF DEM BILDSCHIRMFOTO lagen fuenf Abzeichen verstreut ueber dem Titelbild:
// drei oben, EINES MITTEN AUF DEM AUTO und eines unten rechts, jedes
// zusaetzlich schraeg gestellt. Sie verdeckten genau das, was der Nutzer
// zeigen will, und wirkten hingeworfen statt gewaehlt.
//
// Die Positionen waren weder zufaellig noch berechnet, sondern eine
// handgeschriebene Tabelle. Die Vorgabe belegte die Plaetze 0, 1, 2, 6 und 8 —
// und Platz 6 liegt bei (0.48 | 0.50), also in der Bildmitte.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/widgets/profile_badge_showcase.dart';

void main() {
  group('Die Vorgabe laesst das Titelbild frei', () {
    List<BadgeSpotPlacement> vorgabe() => [
      for (var slot = 0; slot < ProfileBadgeShowcase.slotCount; slot++)
        ProfileBadgeSticker.placementForSpot(
          ProfileBadgeShowcase.defaultSpotForSlot(slot),
        ),
    ];

    test('kein Abzeichen liegt in der Bildmitte', () {
      for (final p in vorgabe()) {
        final mittigWaagrecht = (p.offset.dx - 0.5).abs() < 0.14;
        final mittigSenkrecht = (p.offset.dy - 0.5).abs() < 0.18;
        expect(
          mittigWaagrecht && mittigSenkrecht,
          isFalse,
          reason:
              'Ein Abzeichen sitzt bei (${p.offset.dx} | ${p.offset.dy}) und '
              'damit auf dem Motiv. Genau das war Vuckos Beschwerde: die '
              'Abzeichen verdeckten sein Auto.',
        );
      }
    });

    test('die untere linke Ecke bleibt frei — dort sitzt das Profilbild', () {
      for (final p in vorgabe()) {
        expect(
          p.offset.dx < 0.30 && p.offset.dy > 0.55,
          isFalse,
          reason:
              'Ein Abzeichen liegt hinter dem Profilbild bei '
              '(${p.offset.dx} | ${p.offset.dy}).',
        );
      }
    });

    test('sie stehen auf einer Linie und gleich weit auseinander', () {
      final v = vorgabe();
      final hoehen = v.map((p) => p.offset.dy).toSet();
      expect(
        hoehen.length,
        1,
        reason:
            'Unterschiedliche Hoehen sind genau der hingeworfene Eindruck, '
            'den Vucko bemaengelt hat.',
      );
      final x = v.map((p) => p.offset.dx).toList()..sort();
      final abstaende = [
        for (var i = 1; i < x.length; i++)
          double.parse((x[i] - x[i - 1]).toStringAsFixed(3)),
      ];
      expect(
        abstaende.toSet().length,
        1,
        reason: 'Ungleiche Abstaende lesen sich als Zufall, nicht als Wahl.',
      );
    });

    test('sie stehen gerade, nicht schraeg', () {
      for (final p in vorgabe()) {
        expect(
          p.angle,
          0,
          reason:
              'Die Schraeglage von bis zu 0,08 Radiant war der Hauptgrund fuer '
              'den Eindruck "zufaellig hingeworfen".',
        );
      }
    });

    test('sie sind alle gleich gross', () {
      final groessen = vorgabe().map((p) => p.scale).toSet();
      expect(groessen.length, 1);
    });
  });

  group('Die freien Plaetze bleiben erhalten', () {
    test('es gibt weiterhin zehn Plaetze zum Verteilen', () {
      expect(ProfileBadgeShowcase.placements.length, 10);
      expect(ProfileBadgeShowcase.spotCount, 10);
    });

    test('auch kein freier Platz liegt in der Bildmitte', () {
      for (final p in ProfileBadgeShowcase.placements) {
        final mittig =
            (p.offset.dx - 0.5).abs() < 0.12 && (p.offset.dy - 0.5).abs() < 0.15;
        expect(mittig, isFalse, reason: 'Platz bei ${p.offset} liegt mittig.');
      }
    });
  });

  group('Bestehende Profile werden nicht verschoben', () {
    test('ein Aufkleber speichert seine Position selbst', () {
      // Wer seine Abzeichen bewusst verteilt hat, behaelt die Anordnung: x, y
      // und scale stehen in profiles.badge_showcase. Die Platztabelle liefert
      // nur die Vorgabe fuer alle, die nie etwas verschoben haben.
      const s = ProfileBadgeSticker(
        id: 'badge_01',
        spot: 6,
        x: 0.48,
        y: 0.50,
        scale: 0.64,
      );
      final json = s.toJson();
      expect(json['x'], 0.48);
      expect(json['y'], 0.5);
      expect(json['scale'], 0.64);
    });
  });
}
