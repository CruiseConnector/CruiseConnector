// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-09-01 — Vucko nach einer Testfahrt:
/// „Ich moechte das die routenqualitaet besser ist und den nutzer niemals in
///  keiner situation dazu auffordert irgendwo auf einer strasse umzudrehen
///  oder in eine gasse zum fahren nur um gleich wieder umzudrehen."
///
/// Auf seiner Bildschirmaufnahme fuhr die Route eine Strasse hinauf, machte
/// oben eine Haarnadel und kam auf derselben Strasse zurueck — 875 Meter hin,
/// 875 zurueck. Er musste mitten auf der Fahrbahn wenden.
///
/// WAS VORHER FEHLTE: Den richtigen Test gab es serverseitig laengst
/// (`kehrtwendenZaehler`), aber das harte Tor darauf galt NUR fuer Rundkurse.
/// Bei direktem A nach B erzeugt Phase A genau EINEN Kandidaten und lieferte
/// ihn aus, sobald er ohne Fehler zurueckkam — die Kehrtwenden-Strafe im
/// Best-of-N konnte nichts auswaehlen, weil es nichts zu waehlen gab.
///
/// DIE FALLE DABEI: Ein hartes Tor auf JEDE Wende waere falsch. Liegt das Ziel
/// selbst in einer Sackgasse, MUSS man dort umkehren; ein Tor darauf machte
/// aus „musste wenden" ein „keine Route". Der Zaehler unterscheidet deshalb
/// seit heute zwischen einer Wende mittendrin und einer am Rand.
void main() {
  final repo = Directory.current.path;
  final edge = File(
    '$repo/supabase/functions/generate-cruise-route-v2/index.ts',
  );

  test('Rechenprobe des Kehrtwenden-Zaehlers laeuft gruen', () {
    final deno = Process.runSync('sh', ['-c', 'command -v deno']);
    if (deno.exitCode != 0) {
      fail(
        'deno ist nicht installiert. Diese Pruefung braucht es, weil der '
        'Zaehler in der Edge-Funktion (TypeScript) liegt.',
      );
    }
    final r = Process.runSync('deno', [
      'run',
      '--allow-read',
      'test/route/edge_kehrtwende_rechenprobe.ts',
    ], workingDirectory: repo);
    print(r.stdout);
    expect(
      r.exitCode,
      0,
      reason:
          'Die Rechenprobe schneidet den Zaehler zur Laufzeit aus index.ts '
          'aus und rechnet ihn gegen bekannte Geometrien durch. Sie kann also '
          'nicht abdriften. Fehlerausgabe:\n${r.stdout}\n${r.stderr}',
    );
  });

  group('Die Kennzahl wirkt auch wirklich in der Auswahl', () {
    late String quelle;

    setUpAll(() => quelle = edge.readAsStringSync());

    test('der Zaehler trennt Wenden mittendrin von denen am Rand', () {
      expect(
        quelle.contains('anzahlMitte'),
        isTrue,
        reason:
            'Ohne diese Trennung muesste das Tor entweder jede Wende '
            'durchlassen oder bei einer Sackgasse am Ziel „keine Route" '
            'liefern.',
      );
      expect(
        quelle.contains('kehrtwenden_mitte'),
        isTrue,
        reason: 'Die Kennzahl muss in der Meta stehen, sonst liest sie niemand.',
      );
    });

    test('sie wird an der Kante gemessen, nicht am Scheitel', () {
      // Der erste Anlauf hat am Scheitel gemessen und die 400-Meter-Sackgasse
      // am Ziel faelschlich als „mittendrin" gezaehlt. Die Rechenprobe hat das
      // aufgedeckt; dieser Waechter haelt die Korrektur fest.
      expect(
        quelle.contains('vorDemStichM') && quelle.contains('nachDerRueckkehrM'),
        isTrue,
        reason:
            'Entscheidend ist, wie viel Strecke VOR dem Stich und NACH der '
            'Rueckkehr noch kommt — nicht, wo der Scheitel liegt.',
      );
    });

    test('die A-nach-B-Phasen bevorzugen eine wendefreie Strecke', () {
      final i = quelle.indexOf('let ergebnisseMitWende');
      expect(
        i,
        greaterThanOrEqualTo(0),
        reason:
            'Die Phasenschleife lieferte aus, sobald irgendein Ergebnis ohne '
            'Fehler zurueckkam. Qualitaet spielte keine Rolle — genau so kam '
            'die Strecke mit der Wende zustande.',
      );
      final block = quelle.substring(i, i + 2200);
      expect(
        block.contains('kehrtwenden_mitte'),
        isTrue,
        reason: 'Die Schleife muss auf die Wende mittendrin schauen.',
      );
      expect(
        block.contains('wendefrei'),
        isTrue,
        reason: 'Eine Phase wird nur angenommen, wenn sie wendefrei liefert.',
      );
    });

    test('ohne wendefreie Strecke wird trotzdem geliefert', () {
      // Lieber eine Route mit Wende als gar keine. Ein Tor, das „keine Route"
      // liefert, waere schlimmer als das Problem.
      final i = quelle.indexOf('if (ergebnisseMitWende)');
      expect(
        i,
        greaterThanOrEqualTo(0),
        reason:
            'Findet KEINE Phase eine wendefreie Strecke, muss die erste '
            'brauchbare ausgeliefert werden.',
      );
    });

    test('das Rundkurs-Tor bleibt unveraendert scharf', () {
      // Bewusst NICHT gelockert: Rundkurse werfen jede Wende weiter hart weg.
      expect(
        quelle.contains(
          "if (((r.meta.kehrtwenden_count as number | undefined) ?? 0) > 0) return false;",
        ),
        isTrue,
        reason:
            'Der Rundkurs-Zweig soll strenger bleiben als der A-nach-B-Zweig. '
            'Wer ihn lockert, macht die Strecken wieder schlechter.',
      );
    });
  });
}
