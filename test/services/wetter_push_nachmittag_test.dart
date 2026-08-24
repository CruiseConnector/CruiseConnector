// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24, Vucko: „ich moechte das die taeglichen benachrichtigungen fuer
/// eine strecke erst am nachmittag kommen sollen zwischen 13 - 20 uhr und
/// immer unterschiedlich sein sollen ohne bindestrich und immer anlockend
/// fuer den nutzer die app zu benutzen"
///
/// GEMESSEN am 24.08. in `notifications`, ueber 20 Tage: jede einzelne
/// Wetter-Meldung lag zwischen 08:00:03 und 08:01:29 Wiener Zeit — am 24.08.
/// waren das 183 Zeilen in 53 Sekunden. Ursache war der pg_cron-Job
/// `daily_weather_push` mit `0 6 * * *`. Weil pg_cron in UTC rechnet, war das
/// im Sommer 08:00 und im Winter 07:00 Wiener Zeit.
///
/// Diese Datei prueft die beiden Stellen, an denen die Uhrzeit jetzt haengt:
///   1. die Rechenlogik in der Edge Function (ueber die Deno-Rechenprobe), und
///   2. die Migration, die den Cron-Job ersetzt und die Idempotenz absichert.
///
/// Ohne die Aenderung ist sie rot: die Migration existiert nicht, und in
/// index.ts gibt es weder Versandfenster noch Streuung.
void main() {
  final repo = Directory.current.path;
  final edgeDatei = File(
    '$repo/supabase/functions/daily-weather-push/index.ts',
  );
  final migrationDatei = File(
    '$repo/supabase/migrations/20260824200000_wetter_push_nachmittagsfenster.sql',
  );

  late String edge;
  late String sql;

  /// Die Migration ohne Kommentarzeilen. Fuer Reihenfolge-Pruefungen: sonst
  /// findet indexOf die Woerter im erklaerenden Text statt im Befehl.
  late String sqlOhneKommentare;

  setUpAll(() {
    expect(
      edgeDatei.existsSync(),
      isTrue,
      reason: 'Die Edge Function fehlt: ${edgeDatei.path}',
    );
    expect(
      migrationDatei.existsSync(),
      isTrue,
      reason: 'Die Migration fuer den Cron-Job fehlt: ${migrationDatei.path}',
    );
    edge = edgeDatei.readAsStringSync();
    sql = migrationDatei.readAsStringSync();
    sqlOhneKommentare = sql
        .split('\n')
        .where((z) => !z.trimLeft().startsWith('--'))
        .join('\n');
  });

  group('Rechenlogik des Versandfensters', () {
    test('Die Deno-Rechenprobe laeuft gruen', () {
      final deno = Process.runSync('sh', ['-c', 'command -v deno']);
      if (deno.exitCode != 0) {
        fail(
          'deno ist nicht installiert. Diese Pruefung braucht es, weil die '
          'Streuung in der Edge Function (TypeScript) liegt.',
        );
      }
      final r = Process.runSync('deno', [
        'run',
        '--allow-read',
        '$repo/test/services/wetter_versandfenster_rechenprobe.ts',
      ], workingDirectory: repo);
      print(r.stdout);
      if (r.exitCode != 0) print(r.stderr);
      expect(
        r.exitCode,
        0,
        reason: 'Mindestens eine Rechenprobe war rot, siehe Ausgabe oben.',
      );
    });
  });

  group('Der Cron-Job trifft ganzjaehrig Vuckos Fenster', () {
    /// Der Ausdruck aus `select cron.schedule('daily_weather_push', '...', ...)`.
    String cronAusdruck() {
      final treffer = RegExp(
        r"""cron\.schedule\(\s*'daily_weather_push',\s*'([^']+)'""",
        multiLine: true,
      ).firstMatch(sql);
      expect(
        treffer,
        isNotNull,
        reason: 'Die Migration legt keinen Job daily_weather_push an.',
      );
      return treffer!.group(1)!;
    }

    /// Alle Minuten-seit-Mitternacht (UTC), zu denen der Job tickt.
    /// Versteht die beiden Formen, die hier vorkommen: `*/n` und `a-b`.
    Set<int> utcTicks(String ausdruck) {
      final felder = ausdruck.trim().split(RegExp(r'\s+'));
      expect(felder.length, 5, reason: 'Kein 5-teiliger Cron-Ausdruck.');

      Set<int> feld(String f, int max) {
        if (f == '*') return {for (var i = 0; i <= max; i++) i};
        final schritt = RegExp(r'^\*/(\d+)$').firstMatch(f);
        if (schritt != null) {
          final n = int.parse(schritt.group(1)!);
          return {for (var i = 0; i <= max; i += n) i};
        }
        final bereich = RegExp(r'^(\d+)-(\d+)$').firstMatch(f);
        if (bereich != null) {
          final a = int.parse(bereich.group(1)!);
          final b = int.parse(bereich.group(2)!);
          return {for (var i = a; i <= b; i++) i};
        }
        return f.split(',').map(int.parse).toSet();
      }

      final minuten = feld(felder[0], 59);
      final stunden = feld(felder[1], 23);
      return {
        for (final h in stunden)
          for (final m in minuten) h * 60 + m,
      };
    }

    test('Der Job laeuft nicht mehr morgens', () {
      final ticks = utcTicks(cronAusdruck());
      // 06:00 UTC war der alte Zeitpunkt.
      expect(
        ticks.contains(6 * 60),
        isFalse,
        reason: 'Der Job tickt weiterhin um 06:00 UTC — das war der Fehler.',
      );
    });

    test('Sommer wie Winter ist 13:00 bis 19:55 vollstaendig abgedeckt', () {
      final ticks = utcTicks(cronAusdruck());
      // Die Falle: pg_cron rechnet in UTC. Wien ist im Sommer UTC+2 und im
      // Winter UTC+1. Ein fester UTC-Zeitpunkt wandert also zweimal im Jahr
      // um eine Stunde. Der Job muss deshalb in BEIDEN Zeitrechnungen das
      // ganze Fenster erreichen — verworfen wird spaeter in Wiener Zeit.
      for (final versatz in [60, 120]) {
        final wien = ticks.map((t) => (t + versatz) % 1440).toSet();
        for (var m = 13 * 60; m <= 19 * 60 + 55; m += 5) {
          expect(
            wien.contains(m),
            isTrue,
            reason:
                'Bei Versatz +${versatz ~/ 60} h fehlt der Tick um '
                '${(m ~/ 60).toString().padLeft(2, '0')}:'
                '${(m % 60).toString().padLeft(2, '0')} Wiener Zeit.',
          );
        }
      }
    });

    test('Die Schranke rechnet in Wiener Zeit, nicht in UTC', () {
      expect(
        sql.contains("now() at time zone 'Europe/Vienna'"),
        isTrue,
        reason:
            'Die Torwaechter-Funktion prueft nicht in Wiener Zeit. Damit '
            'wandert das Fenster mit der Sommerzeit.',
      );
      expect(RegExp(r"time '13:00'").hasMatch(sql), isTrue);
      expect(RegExp(r"time '20:00'").hasMatch(sql), isTrue);
    });

    test('Der alte Job wird entfernt, nicht verdoppelt', () {
      final unschedule = sqlOhneKommentare.indexOf('cron.unschedule');
      final schedule = sqlOhneKommentare.indexOf('select cron.schedule(');
      expect(
        unschedule,
        greaterThan(-1),
        reason:
            'Die Migration raeumt den alten Job nicht ab. Dann stehen zwei '
            'Jobs nebeneinander und jeder Nutzer bekommt zweimal etwas.',
      );
      expect(
        unschedule,
        lessThan(schedule),
        reason: 'Erst abraeumen, dann anlegen — sonst loescht die Migration '
            'ihren eigenen neuen Job.',
      );
      expect(sql.contains("'daily_weather_push'"), isTrue);
    });

    test('Kein zweiter Wetter-Job in einer anderen Migration', () {
      final ordner = Directory('$repo/supabase/migrations');
      final andere = ordner
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .where((f) => f.path != migrationDatei.path)
          .where((f) => f.readAsStringSync().contains('daily_weather_push'))
          .map((f) => f.path.split('/').last)
          .toList();
      expect(
        andere,
        isEmpty,
        reason: 'Weitere Migrationen fassen denselben Job an: $andere',
      );
    });
  });

  group('Idempotenz: pro Nutzer und Tag genau eine Meldung', () {
    test('Es gibt einen UNIQUE-Index — nicht nur einen Kommentar', () {
      // Der Kommentar in index.ts behauptete seit Mai "(UNIQUE)". Den Index
      // gab es nie; abgesichert war nur ein SELECT vor dem INSERT. Der
      // Bestand zeigte vier Nutzer-Tage mit zwei bzw. drei Meldungen.
      expect(
        RegExp(
          r'create\s+unique\s+index[\s\S]*?on\s+public\.notifications',
          caseSensitive: false,
        ).hasMatch(sql),
        isTrue,
        reason: 'Die Migration legt keinen UNIQUE-Index auf notifications an.',
      );
      expect(
        sql.contains("timezone('Europe/Vienna', created_at)"),
        isTrue,
        reason:
            'Der Index rechnet nicht in Wiener Tagen. created_at::date haengt '
            'an der TimeZone-Einstellung der Sitzung und die ist UTC.',
      );
      expect(
        RegExp(r"where\s+type\s*=\s*'weather_recommendation'").hasMatch(sql),
        isTrue,
        reason:
            'Der Index ist nicht auf Wetter-Meldungen eingeschraenkt und '
            'wuerde andere Benachrichtigungen blockieren.',
      );
    });

    test('Der Bestand wird vor dem Index bereinigt', () {
      final aufraeumen =
          sqlOhneKommentare.indexOf('delete from public.notifications');
      final index = sqlOhneKommentare.indexOf('create unique index');
      expect(
        aufraeumen,
        greaterThan(-1),
        reason:
            'Ohne Aufraeumen scheitert das Anlegen des Index an den vier '
            'Doppel-Tagen im Bestand.',
      );
      expect(aufraeumen, lessThan(index));
    });

    test('Die Edge Function rechnet den Tag nicht mehr in UTC', () {
      // Der alte Code filterte mit `${today}T00:00:00Z`. Ein Lauf um 01:03
      // Wiener Zeit lag damit in UTC noch im Vortag — genau so entstand am
      // 24.05. die zweite Meldung.
      expect(
        edge.contains('T00:00:00Z'),
        isFalse,
        reason:
            'Die Tagesgrenze steht weiterhin auf UTC-Mitternacht. In Wien ist '
            'das 01:00 bzw. 02:00 nachts.',
      );
      expect(
        edge.contains('wienTagesbeginn'),
        isTrue,
        reason: 'Die Tagesgrenze wird nicht in Wiener Zeit gebildet.',
      );
    });

    test('Die Tagespruefung steht VOR der Budgetgrenze', () {
      // Gemessen am ersten Tick nach der Umstellung, 24.08. um 19:50:
      // {"sent":0,"skipped":60,"vertagt":126,"verarbeitet":60,"total":186}.
      // Die Grenze stand vor der Tagespruefung, also haben 60 laengst
      // erledigte Nutzer das ganze Budget aufgebraucht — wer weiter hinten
      // in der Liste steht, waere nie an die Reihe gekommen.
      final tagespruefung = edge.indexOf('erledigt.has(userId)');
      final budget = edge.indexOf('verarbeitet >= MAX_PRO_LAUF');
      expect(tagespruefung, greaterThan(-1));
      expect(budget, greaterThan(-1));
      expect(
        tagespruefung,
        lessThan(budget),
        reason:
            'Die Budgetgrenze steht wieder vor der Tagespruefung. Dann '
            'verbrauchen erledigte Nutzer das Budget und die hinteren '
            'Nutzer bekommen nie etwas.',
      );
    });

    test('Wer heute schon eine hat, wird in EINER Abfrage geholt', () {
      final sammelabfrage = edge.indexOf('const erledigt = new Set<string>(');
      final schleife = edge.indexOf('for (const u of users) {');
      expect(
        sammelabfrage,
        greaterThan(-1),
        reason: 'Die Tagespruefung fragt wieder je Nutzer einzeln nach.',
      );
      expect(
        sammelabfrage,
        lessThan(schleife),
        reason: 'Die Sammelabfrage steht in der Schleife statt davor.',
      );
    });

    test('Ein Unique-Verstoss zaehlt als uebersprungen, nicht als Fehler', () {
      expect(
        edge.contains('23505'),
        isTrue,
        reason:
            'Der zweite von zwei gleichzeitigen Laeufen wuerde als Fehler '
            'gezaehlt statt als das, was er ist: sauber abgewehrt.',
      );
    });
  });
}
