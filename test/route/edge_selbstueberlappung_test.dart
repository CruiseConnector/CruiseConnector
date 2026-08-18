// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Aufgabe 1.4 + 1.3) — Vucko am 16.08.:
/// „Die Strecken muessen sauber sein und nicht in eine Richtung und dann die
/// gleiche Strasse wieder zurueckfinden."
///
/// Gemessen vor dieser Aenderung: Das Wort „overlap" kam in
/// generate-cruise-route-v2/index.ts KEIN EINZIGES Mal vor. Serverseitig gab
/// es nur `u_turn_count` aus den GraphHopper-Vorzeichen -8/8/-98 und die
/// Strafe darauf. Eine Strecke, die ohne signalisierte Wende hin und zurueck
/// ueber dieselbe Strasse laeuft, konnte als bester Kandidat gewinnen und
/// musste erst im Client verworfen werden.
///
/// Diese Datei prueft die EDGE-Seite. Sie fasst absichtlich keinen Dart-Code
/// an, sondern:
///   1. laesst die reine Rechenprobe edge_ueberlappung_rechenprobe.ts laufen,
///      die die Formel direkt aus index.ts ausschneidet und mit bekannten
///      Geometrien durchrechnet, und
///   2. prueft am Quelltext, dass die Kennzahl auch wirklich in der AUSWAHL
///      wirkt und nicht nur berechnet und weggeworfen wird.
void main() {
  final repo = Directory.current.path;
  final edge = File(
    '$repo/supabase/functions/generate-cruise-route-v2/index.ts',
  );

  test('Rechenprobe der Ueberlappungsformel laeuft gruen', () {
    final deno = Process.runSync('sh', ['-c', 'command -v deno']);
    if (deno.exitCode != 0) {
      fail(
        'deno ist nicht installiert. Diese Pruefung braucht es, weil die '
        'Formel in der Edge-Funktion (TypeScript) liegt.',
      );
    }
    final r = Process.runSync('deno', [
      'run',
      '--allow-read',
      '$repo/test/route/edge_ueberlappung_rechenprobe.ts',
    ], workingDirectory: repo);
    print(r.stdout);
    if (r.exitCode != 0) print(r.stderr);
    expect(
      r.exitCode,
      0,
      reason: 'Mindestens eine Rechenprobe war rot, siehe Ausgabe oben.',
    );
  });

  test('Kennzahl existiert, steht im Meta und wirkt im Scoring', () {
    final src = edge.readAsStringSync();

    // 1.4: die Kennzahl selbst
    expect(
      src.contains('function selbstUeberlappungAnteil('),
      isTrue,
      reason: 'Die richtungsbewusste Selbst-Ueberlappung fehlt.',
    );
    expect(
      src.contains('self_overlap_fraction: selbstUeberlappung,'),
      isTrue,
      reason: 'self_overlap_fraction steht nicht im Kandidaten-Meta.',
    );

    // 1.4: sie muss in die SUMME einfliessen, nicht nur berechnet werden.
    final scoreZeile = RegExp(
      r'uTurnPenalty \+ ueberlappStrafe \+ countryScorePenalty',
    );
    expect(
      scoreZeile.hasMatch(src),
      isTrue,
      reason:
          'Die Ueberlappung fliesst nicht in den Score ein. Sie soll in der '
          'AUSWAHL wirken, nicht erst in der Ablehnung im Client.',
    );

    // Gewicht in der Groessenordnung der Wende-Strafe (60), ab 0,15 steiler.
    expect(
      src.contains('selbstUeberlappung * 60 +'),
      isTrue,
      reason: 'Grundgewicht der Ueberlappungsstrafe stimmt nicht mehr.',
    );
    expect(
      src.contains('Math.max(0, selbstUeberlappung - 0.15) * 300'),
      isTrue,
      reason: 'Der steilere Teil ab Anteil 0,15 fehlt.',
    );
  });

  test('1.3: Stufe 1 hat nicht mehr die wenigsten Kandidaten', () {
    final src = edge.readAsStringSync();
    final m = RegExp(
      r'const limit = detourLevel === 1 \? (\d+) : detourLevel === 2 \? (\d+) : (\d+);',
    ).firstMatch(src);
    expect(m, isNotNull, reason: 'Kandidaten-Limit nicht gefunden.');
    final stufe1 = int.parse(m!.group(1)!);
    final stufe2 = int.parse(m.group(2)!);
    final stufe3 = int.parse(m.group(3)!);
    expect(
      stufe1,
      greaterThanOrEqualTo(stufe2),
      reason:
          'Stufe 1 („kleiner Umweg") hatte mit 8 gegen 12 und 14 die WENIGSTEN '
          'Kandidaten — ausgerechnet dort, wo wendefreie Kandidaten am '
          'knappsten sind. Sie laufen parallel in EINEM Promise.all, die '
          'Latenz ist die laengste Einzelanfrage.',
    );
    expect(stufe3, greaterThanOrEqualTo(stufe2));
  });

  test('1.3: der tote baseFactor-Term ist weg, die Untergrenze ist benannt', () {
    final src = edge.readAsStringSync();
    expect(
      src.contains('const baseFactor = detourLevel === 1 ? 0.15'),
      isFalse,
      reason:
          'baseFactor stand in einem Math.max, konnte dort aber nie gewinnen '
          '(0,15/0,30/0,50 gegen 0,55/1,10/1,65 aus dem Client-Faktor). Der '
          'Kommentar behauptete das Gegenteil.',
    );
    expect(
      src.contains('export function umwegBasisKm('),
      isTrue,
      reason: 'Die nachrechenbare Umweg-Basisdistanz fehlt.',
    );
    expect(
      src.contains('detour_base_term: detourBasisTerm,'),
      isTrue,
      reason:
          'Ohne den Term im Meta ist im Feld nicht zu sehen, welcher Summand '
          'die Umwegweite wirklich bestimmt.',
    );
  });

  test('1.3: max_candidate_attempts ist kein stiller toter Parameter mehr', () {
    final src = edge.readAsStringSync();
    expect(
      src.contains('max_candidate_attempts?: number;'),
      isTrue,
      reason:
          'Der Client sendet max_candidate_attempts (route_service.dart:3242 '
          'und :3323), die Edge kannte das Feld nicht einmal.',
    );
    expect(
      src.contains('client_candidate_budget_ignored:'),
      isTrue,
      reason:
          'Dass der Wert bewusst ignoriert wird, muss im Meta sichtbar sein.',
    );
  });
}
