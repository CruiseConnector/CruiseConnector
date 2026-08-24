import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (Auftrag Vucko): „man soll seine Nachrichten bis zu 6h nach
/// abschicken bearbeiten koennen danach gehts nicht mehr [...] und nicht durch
/// zeit zurueckstellen oder datum zurueckstellen irgendwie manipuliert werden
/// kann."
///
/// Der Nachweis der Wirkung ist die Messung an der Datenbank
/// (test/sql/20260824_community_chat_nachweis.sql, Gegenprobe vorher/nachher).
/// Dieser Test bewacht das, was eine einmalige Messung nicht bewachen kann:
/// dass die Frist auch morgen noch gegen die SERVERUHR rechnet und nicht gegen
/// einen Wert, den das Geraet mitschickt.
///
/// Ohne die Migration ist dieser Test rot: die Datei existiert nicht.
void main() {
  late String sql;
  late String code;

  /// Kommentarzeilen entfernen, damit ein erklaerender Kommentar nicht als
  /// Treffer durchgeht (uebernommen aus gruppen_einladung_policy_test.dart).
  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('--'))
      .join('\n');

  /// Abschnitt ab einem Kopf bis zum naechsten Abschluss, auf eine Zeile
  /// normalisiert.
  String abschnitt(String start, String ende) {
    final von = code.indexOf(start);
    expect(von, isNot(-1), reason: 'Abschnitt fehlt: $start');
    final bis = code.indexOf(ende, von + start.length);
    expect(bis, isNot(-1), reason: 'Abschluss fehlt nach: $start');
    return code
        .substring(von, bis + ende.length)
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  setUpAll(() {
    sql = File(
      'supabase/migrations/'
      '20260824160000_community_verlauf_bearbeiten_loeschen.sql',
    ).readAsStringSync();
    code = ohneKommentare(sql);
  });

  group('Die Frist entscheidet der Server', () {
    test('rechnet gegen now() und old.created_at, nicht gegen den Client', () {
      final waechter = abschnitt(
        'create or replace function public.wacht_ueber_community_nachricht()',
        r'$$;',
      );

      // Die Frist selbst.
      expect(
        waechter.contains("now() - old.created_at > interval '6 hours'"),
        isTrue,
        reason:
            'Die 6-Stunden-Frist muss gegen now() der Datenbank und gegen '
            'old.created_at gerechnet werden. Jeder andere Bezugspunkt kaeme '
            'vom Geraet.',
      );

      // Und der Grund, warum old.created_at ueberhaupt vertrauenswuerdig ist:
      // es laesst sich per UPDATE nicht verschieben.
      expect(
        waechter.contains('new.created_at := old.created_at'),
        isTrue,
        reason:
            'Ohne diese Zeile koennte man created_at in die Zukunft schieben '
            'und die Frist beliebig verlaengern.',
      );
    });

    test('created_at wird auch beim Schreiben auf die Serverzeit gesetzt', () {
      final schreiber = abschnitt(
        'create or replace function public.setze_community_nachricht_grundwerte()',
        r'$$;',
      );
      expect(
        schreiber.contains('new.created_at := now()'),
        isTrue,
        reason:
            'Wer created_at beim INSERT frei waehlen kann, hat die Frist '
            'ausgehebelt, bevor sie beginnt.',
      );
    });

    test('der Loeschzeitpunkt kommt nie vom Geraet', () {
      final waechter = abschnitt(
        'create or replace function public.wacht_ueber_community_nachricht()',
        r'$$;',
      );
      expect(
        waechter.contains('new.deleted_at := now()'),
        isTrue,
        reason:
            'Die alte App schickt DateTime.now() des Geraets mit. Der Wert '
            'muss ueberschrieben werden.',
      );
      expect(
        waechter.contains('new.deleted_at := old.deleted_at'),
        isTrue,
        reason:
            'Eine einmal geloeschte Nachricht darf nicht wieder auftauchen '
            'und nicht umdatiert werden.',
      );
    });

    test('die Kennzeichnung als bearbeitet setzt nur der Server', () {
      final waechter = abschnitt(
        'create or replace function public.wacht_ueber_community_nachricht()',
        r'$$;',
      );
      expect(waechter.contains('new.bearbeitet_am := old.bearbeitet_am'), isTrue);
      expect(waechter.contains('new.original_body := old.original_body'), isTrue);
      expect(waechter.contains('new.bearbeitet_am := now()'), isTrue);
      expect(
        waechter.contains(
          'new.original_body := coalesce(old.original_body, old.body)',
        ),
        isTrue,
        reason:
            'Die ERSTE Fassung muss erhalten bleiben, nicht die vorletzte - '
            'sonst laesst sich der Nachweis in zwei Schritten ausspuelen.',
      );
    });
  });

  group('Die Regel gilt auch an der Funktion vorbei', () {
    test('der Waechter haengt am Trigger, nicht nur im RPC', () {
      final trigger = abschnitt(
        'create trigger trg_wacht_ueber_community_nachricht',
        ';',
      );
      expect(trigger.contains('before update on public.community_messages'), isTrue);
      expect(trigger.contains('for each row'), isTrue);
    });

    test('die UPDATE-Policy laesst geloeschte Zeilen nicht mehr durch', () {
      final policy = abschnitt(
        'create policy "authors_update_community_messages"',
        ';',
      );
      expect(
        policy.contains('deleted_at is null'),
        isTrue,
        reason:
            'Bisher erlaubte die Policy dem Verfasser JEDES Update - auch an '
            'einer bereits fuer alle geloeschten Nachricht.',
      );
    });

    test('hartes Loeschen und TRUNCATE sind entzogen', () {
      expect(
        code.contains('revoke delete on public.community_messages'),
        isTrue,
      );
      expect(
        RegExp(
          r'revoke\s+truncate[^;]*on\s+public\.community_messages',
        ).hasMatch(code.replaceAll(RegExp(r'\s+'), ' ')),
        isTrue,
        reason: 'TRUNCATE umgeht Row Level Security vollstaendig.',
      );
      final sperre = abschnitt(
        'create policy "community_messages_kein_hartes_loeschen"',
        ';',
      );
      expect(sperre.contains('using (false)'), isTrue);
    });
  });

  group('Der Urspruchstext bleibt unter Verschluss', () {
    test('original_body steht nicht im spaltenweisen Leserecht', () {
      final einzeilig = code.replaceAll(RegExp(r'\s+'), ' ');
      final von = einzeilig.indexOf('grant select (');
      expect(von, isNot(-1), reason: 'Das spaltenweise Leserecht fehlt.');
      final bis = einzeilig.indexOf(
        ') on public.community_messages to authenticated',
        von,
      );
      expect(bis, isNot(-1));
      final spalten = einzeilig.substring(von, bis);

      expect(
        spalten.contains('original_body'),
        isFalse,
        reason:
            'Wer den Urspruchstext lesen kann, macht das Bearbeiten sinnlos.',
      );
      // Alles, was der Client heute abfragt, muss drin sein
      // (community_chat_service.dart, _messageSelect).
      for (final spalte in [
        'id',
        'community_id',
        'user_id',
        'body',
        'created_at',
        'updated_at',
        'deleted_at',
        'reply_to_message_id',
        'route_attachment',
        'pinned_at',
        'pinned_by',
        'bearbeitet_am',
      ]) {
        expect(
          spalten.contains(spalte),
          isTrue,
          reason:
              'Spalte $spalte fehlt im Leserecht - der Client bekaeme '
              '"permission denied" statt Daten.',
        );
      }
    });
  });

  group('Der Verlauf ist ein Protokoll, kein Gaestebuch', () {
    test('nur SELECT fuer angemeldete Nutzer, kein Schreibrecht', () {
      final einzeilig = code.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        einzeilig.contains(
          'revoke all on table public.community_mitglieder_verlauf '
          'from anon, authenticated',
        ),
        isTrue,
      );
      expect(
        einzeilig.contains(
          'grant select on table public.community_mitglieder_verlauf '
          'to authenticated',
        ),
        isTrue,
      );
      // Es darf KEINE Schreib-Policy geben: wer den Verlauf glaetten kann,
      // macht ihn wertlos.
      for (final art in ['for insert', 'for update', 'for delete']) {
        expect(
          RegExp(
            'create policy[^;]*on public\\.community_mitglieder_verlauf'
            '[^;]*$art',
          ).hasMatch(einzeilig),
          isFalse,
          reason: 'Der Verlauf darf keine $art-Policy haben.',
        );
      }
    });

    test('haengt am Trigger, damit kein Beitrittsweg vergessen wird', () {
      final trigger = abschnitt(
        'create trigger trg_community_mitgliedschaft_protokoll',
        ';',
      );
      expect(
        trigger.contains('after insert or delete on public.community_members'),
        isTrue,
        reason:
            'Es gibt sechs Wege hinein und drei hinaus. Nur der Trigger sieht '
            'alle.',
      );
    });

    test('die Missbrauchsbremse ist gerade und zeitbezogen', () {
      final funktion = abschnitt(
        'create or replace function public.protokolliere_community_mitgliedschaft()',
        r'$$;',
      );
      expect(funktion.contains("interval '24 hours'"), isTrue);
      expect(
        funktion.contains('v_anzahl >= 6'),
        isTrue,
        reason:
            'Die Obergrenze muss GERADE sein, sonst endet der Verlauf mitten '
            'in einem Beitritt-Austritt-Paar.',
      );
    });
  });

  group('Die Aufrufe stehen nicht offen', () {
    test('anon und public bekommen kein EXECUTE', () {
      final einzeilig = code.replaceAll(RegExp(r'\s+'), ' ');
      for (final funktion in [
        'public.community_nachricht_bearbeiten(uuid, text)',
        'public.community_nachricht_loeschen(uuid, boolean)',
      ]) {
        expect(
          einzeilig.contains('revoke all on function $funktion from public'),
          isTrue,
          reason: 'EXECUTE von public entziehen - wiederkehrende Falle.',
        );
        expect(
          einzeilig.contains('revoke all on function $funktion from anon'),
          isTrue,
        );
        expect(
          einzeilig.contains(
            'grant execute on function $funktion to authenticated',
          ),
          isTrue,
        );
      }
      // Die drei Triggerfunktionen duerfen gar nicht aufrufbar sein.
      for (final funktion in [
        'public.protokolliere_community_mitgliedschaft()',
        'public.wacht_ueber_community_nachricht()',
        'public.setze_community_nachricht_grundwerte()',
      ]) {
        expect(
          einzeilig.contains(
            'revoke all on function $funktion from authenticated',
          ),
          isTrue,
          reason:
              'Triggerfunktionen brauchen kein EXECUTE und duerfen nicht als '
              'RPC offenstehen.',
        );
      }
    });

    test('jede neue Funktion hat einen festen search_path', () {
      final einzeilig = code.replaceAll(RegExp(r'\s+'), ' ');
      final funktionen = RegExp(
        r'create or replace function (public\.\w+)',
      ).allMatches(einzeilig).map((m) => m.group(1)!).toSet();
      expect(funktionen, isNotEmpty);
      for (final funktion in funktionen) {
        final von = einzeilig.indexOf('create or replace function $funktion');
        final kopf = einzeilig.substring(von, von + 400);
        expect(
          kopf.contains("set search_path to 'public', 'pg_temp'"),
          isTrue,
          reason: '$funktion hat keinen festen search_path.',
        );
      }
    });
  });

  group('Die Chat-Art haengt am Konto', () {
    test('schlanke Spalte auf profiles mit CHECK', () {
      final einzeilig = code.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        einzeilig.contains(
          'alter table public.profiles add column if not exists '
          'chat_darstellung text',
        ),
        isTrue,
      );
      expect(
        einzeilig.contains(
          "check (chat_darstellung is null or chat_darstellung in "
          "('standard', 'nachrichten'))",
        ),
        isTrue,
        reason:
            'Ohne CHECK landet jeder Tippfehler des Clients dauerhaft in der '
            'Zeile.',
      );
    });
  });
}
