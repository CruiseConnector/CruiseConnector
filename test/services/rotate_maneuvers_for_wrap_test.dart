import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RouteManeuver _m(int idx, {IconData icon = Icons.turn_right}) => RouteManeuver(
  latitude: 47.0,
  longitude: 9.0,
  routeIndex: idx,
  icon: icon,
  announcement: 'x',
  instruction: 'x',
);

void main() {
  group('rotateManeuversForWrap (Rundkurs-Banner-Fix)', () {
    test('rotiert Indizes statt sie zu leeren + Ankunft ans Ende', () {
      final source = [
        _m(0), // depart
        _m(3),
        _m(7),
        _m(10, icon: Icons.flag), // arrival
      ];
      final out = rotateManeuversForWrap(source, 5, 12);

      // Vorher wurde hier const [] zurückgegeben → kein Banner. Jetzt non-empty.
      expect(out, isNotEmpty);

      // Nicht-Ankunfts-Manöver werden rotiert: 0→7, 3→10, 7→2; sortiert [2,7,10].
      final nonArrival = out
          .where((m) => !m.isArrival)
          .map((m) => m.routeIndex)
          .toList();
      expect(nonArrival, [2, 7, 10]);

      // Genau eine Ankunft, ans Ende gesetzt (N-1 = 11).
      final arrival = out.where((m) => m.isArrival).toList();
      expect(arrival, hasLength(1));
      expect(arrival.first.routeIndex, 11);

      // Aufsteigend sortiert.
      for (var i = 1; i < out.length; i++) {
        expect(out[i].routeIndex >= out[i - 1].routeIndex, isTrue);
      }
    });

    test('kein Wrap (clampedStart<=0) → unverändert', () {
      final source = [_m(2), _m(5)];
      expect(rotateManeuversForWrap(source, 0, 10), same(source));
    });

    test('leere Quelle → leer', () {
      expect(rotateManeuversForWrap(const [], 3, 10), isEmpty);
    });
  });
}
