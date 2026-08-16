import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 3): „A-nach-B ist richtig
/// beschissen: kleiner/mittlerer/grosser Umweg differenzieren sich fast gar
/// nicht, und die Routenqualitaet ist richtig schlecht."
///
/// LIVE GEMESSEN (Produktion vor dem Fix, 3 Paare x 2 Stile x 3 Stufen): 17
/// von 18 Umweg-Routen hatten EINE Wende — der Umweg war ein Stachel (zum
/// Via und auf demselben Weg zurueck, bis 21 % Ueberlappung), alle Stufen
/// dieselbe Spitze im selben Korridor. Ursache: ein einziges Via senkrecht
/// zur Mitte, 4/6/8 Kandidaten, Wende-Strafe nur 14.
///
/// FIX (Edge-Funktion, deployed 16.08.): Via bei 38/50/62 % der Direktlinie,
/// 8/12/14 Kandidaten, zwei Distanzen je Peilung, GraphHopper pass_through,
/// Wende-Strafe 60 bei Umwegen, Ueberschuss ueber die Zieldistanz gewichtet.
/// Danach: 9 von 36 mit Wende, Stufen in allen Dreiergruppen geordnet,
/// Median 2,25x / 4,2x / 6,0x Luftlinie. Dieser Test haelt die Regeln im
/// Repo fest — die Messung selbst: a2b_umweg_live_probe_test.dart.
void main() {
  late String edge;
  setUpAll(() {
    edge = File(
      'supabase/functions/generate-cruise-route-v2/index.ts',
    ).readAsStringSync();
  });

  test('Umweg-Via liegt je Kandidat bei 38 / 50 / 62 % der Direktlinie', () {
    expect(edge.contains('const alongVariants = [0.5, 0.38, 0.62];'), isTrue);
    expect(edge.contains('detourAlong: spec.along,'), isTrue);
    expect(edge.contains('const along = opts.detourAlong ?? 0.5;'), isTrue);
    // Kein Bogen aus drei Vias mehr (live: mehr Wenden, laengere Routen).
    expect(edge.contains('const bogen: Array<[number, number]>'), isFalse);
  });

  test('mehr Kandidaten je Stufe, zwei Distanzen je Peilung', () {
    expect(
      edge.contains('const limit = detourLevel === 1 ? 8 : detourLevel === 2 ? 12 : 14;'),
      isTrue,
    );
    expect(
      edge.contains('? [baseKm * seedJitter, Math.max(2, baseKm * 0.68)]'),
      isTrue,
      reason: 'die 1,22-fache Variante ist raus — Ueberschuss war das Problem',
    );
  });

  test('GraphHopper darf am Umweg-Via nicht wenden (pass_through)', () {
    expect(edge.contains('...(hatUmwegBogen ? { pass_through: true } : {}),'), isTrue);
  });

  test('eine Wende kostet bei Umwegen 60, Ueberschuss wiegt schwerer', () {
    expect(edge.contains('const einzelWendeStrafe = detourLevel > 0 ? 60 : 14;'), isTrue);
    expect(
      edge.contains('? c.deltaPct * 1.6 + Math.max(0, c.deltaPct - 40) * 3'),
      isTrue,
    );
    // Rundkurse/Direkt-A→B: alte 14 bleiben.
    expect(edge.contains('? einzelWendeStrafe'), isTrue);
  });
}
