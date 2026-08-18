import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Defekt 5 aus dem Produktionsbericht):
/// „408 von 876 Zeilen (47 %) haben kein user_id."
///
/// Nachgemessen stimmt die Zahl, aber nicht die Deutung: An 17 von 21 Tagen
/// war KEINE einzige Zeile ohne Konto. Die anonymen Zeilen ballen sich auf
/// vier Tagen mit Maschinen-Signatur — am 16.08. 399 Stück in 16 Minuten
/// (25 pro Minute), am 30.07. 52 in 11 Minuten. Das waren Messläufe, keine
/// Nutzer.
///
/// Zwei Dinge bleiben trotzdem zu tun, und die prüft dieser Test:
/// 1. Die Identität darf nicht aus dem Rate-Limit-Schlüssel zurückgerechnet
///    werden (`rl.key.slice(4)`) — eine stille Kopplung, die niemand bemerkt,
///    wenn sich das Präfix ändert.
/// 2. Jede Anfrage sagt, woher sie kommt.
void main() {
  late String edge;

  setUpAll(() {
    edge = File(
      'supabase/functions/generate-cruise-route-v2/index.ts',
    ).readAsStringSync();
  });

  test('rlExtractKey liefert die Identität getrennt vom Schlüssel', () {
    expect(edge.contains('subjectId: string | null'), isTrue);
    expect(edge.contains('subjectId: payload.sub'), isTrue);
  });

  test('Die Nutzer-ID wird nicht mehr aus dem Schlüssel geschnitten', () {
    // Nur Code prüfen — der Kommentar darf den alten Weg noch erklären.
    final codeZeilen = edge
        .split('\n')
        .where((z) => !z.trimLeft().startsWith('///'))
        .join('\n');
    expect(
      codeZeilen.contains('rl.key.slice(4)'),
      isFalse,
      reason: 'Ein Rate-Limit-Schlüssel ist keine Identität.',
    );
    expect(edge.contains('user_id: rl.subjectId'), isTrue);
  });

  test('Die Herkunft wird mitgeschrieben und ist auf vier Werte begrenzt', () {
    expect(edge.contains("origin: normalizeOrigin("), isTrue);
    expect(
      edge.contains("if (v === 'app' || v === 'test' || v === 'worker')"),
      isTrue,
    );
  });

  test('Die App kennzeichnet sich als App', () {
    final client = File(
      'lib/data/services/route_service.dart',
    ).readAsStringSync();
    expect(client.contains("'origin': body['origin'] ?? 'app'"), isTrue);
  });

  test('Das Messharness kennzeichnet sich als Test', () {
    final harness = File(
      'test/route/a2b_umweg_live_probe_test.dart',
    ).readAsStringSync();
    expect(harness.contains("'origin': 'test'"), isTrue);
  });

  test('Die Spalte liegt als Migration im Repo', () {
    final sql = File(
      'supabase/migrations/20260818140000_route_events_origin.sql',
    ).readAsStringSync();
    expect(sql.contains('add column if not exists origin'), isTrue);
    expect(
      sql.contains("origin in ('app', 'test', 'worker', 'unknown')"),
      isTrue,
    );
  });
}
