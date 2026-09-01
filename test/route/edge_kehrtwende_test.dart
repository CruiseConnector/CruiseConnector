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

    test('die A-nach-B-Phasen eskalieren NICHT auf gute Glueck weiter', () {
      // 2026-09-01 umgedreht, nachdem der Kritiker die Eskalation als
      // kritisch eingestuft hat und ich sie zurueckgenommen habe.
      //
      // Hier stand: die Phasenschleife soll weitersuchen, bis eine wendefreie
      // Strecke kommt. Das klingt richtig und war gefaehrlich. Die spaeten
      // Phasen verschieben Start und Ziel um bis zu 1,1 km: Phase E den
      // START — und der Client weist alles ueber 500 m Abstand hart ab, der
      // Nutzer liest "keine Route". Phase C verschiebt das ZIEL, ebenfalls um
      // 1,1 km, und das faellt gar nicht auf: der Nutzer wird woanders
      // hingeschickt als er wollte. Dazu kaeme beim Neuberechnen unterwegs
      // bis zu neun GraphHopper-Aufrufe in drei Wellen gegen eine
      // Acht-Sekunden-Grenze mit einem einzigen Versuch.
      //
      // Also: die erste brauchbare Phase liefert aus, wie vorher. Die Wende
      // mittendrin wird GEMESSEN und protokolliert, damit wir wissen, wie oft
      // sie auftritt — sie steuert aber nicht die Auswahl. Die echte Loesung
      // sind Alternativrouten mit identischen Endpunkten, nicht verschobene.
      expect(
        quelle.contains('let ergebnisseMitWende'),
        isFalse,
        reason:
            'Die Eskalation ueber die Phasen ist bewusst zurueckgenommen. '
            'Wer sie wieder einbaut, verschiebt dem Nutzer Start oder Ziel '
            'um ueber einen Kilometer.',
      );
      expect(
        quelle.contains('kehrtwenden_mitte'),
        isTrue,
        reason:
            'Gemessen wird weiter: ohne die Zahl wissen wir nicht, wie oft '
            'das Problem ueberhaupt auftritt.',
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
