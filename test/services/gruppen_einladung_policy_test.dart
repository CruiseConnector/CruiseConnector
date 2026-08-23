import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-23 (Auftrag Vucko, Sprachnachricht): „wenn er eine Gruppe erstellt
/// hat und er einen anderen einlaedt [...] und er ueber die Glocke bzw. ueber
/// den Quicklink dann joinen will [...] dass ein Fehler kommt. [...] wenn
/// nicht, dann umgehend fixen."
///
/// Gemessen in der Produktivdatenbank am 23.08.: Die SELECT-Policy auf
/// `public.groups` kannte drei Zweige (Ersteller, oeffentlich-und-nicht-live,
/// Mitglied) und keinen fuer Eingeladene. `can_join_group()` kannte die
/// Einladung dagegen sehr wohl. Beitreten war also erlaubt, Lesen nicht.
/// Der Eingeladene 645065af aus Gruppe ac29cf1f („latenight session") bekam
/// deshalb am 21.08. bei jedem Glocken-Tipp HTTP 200 mit leerer Liste und die
/// falsche Meldung „Diese Gruppe ist nicht mehr verfuegbar".
///
/// Der eigentliche Nachweis der Wirkung ist die Messung in der Datenbank
/// (vorher 0 Zeilen, nachher 1 Zeile, dokumentiert im Migrationskopf). Dieser
/// Test bewacht das, was eine Messung nicht bewachen kann: dass Lesen und
/// Beitreten dieselbe Bedingung benutzen und nicht wieder auseinanderlaufen.
void main() {
  late String sql;
  late String code;

  /// Kommentarzeilen entfernen, damit ein erklaerender Kommentar nicht als
  /// Treffer durchgeht.
  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('--'))
      .join('\n');

  /// Rumpf einer Funktion oder Policy ab ihrem Kopf bis zum naechsten
  /// Abschluss, auf eine Zeile normalisiert.
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
      'supabase/migrations/20260823144208_gruppen_einladung_sichtbarkeit.sql',
    ).readAsStringSync();
    code = ohneKommentare(sql);
  });

  test('Die Einladungsbedingung steht in genau einer Funktion', () {
    expect(
      code.contains('create or replace function public.ist_zu_gruppe_eingeladen'),
      isTrue,
      reason: 'Ohne eigene Funktion gibt es wieder zwei Wahrheiten.',
    );

    // can_join_group darf die Bedingung nicht noch einmal selbst formulieren.
    final canJoin = abschnitt(
      'create or replace function public.can_join_group',
      r'$$;',
    );
    expect(
      canJoin.contains('ist_zu_gruppe_eingeladen'),
      isTrue,
      reason: 'can_join_group muss die gemeinsame Funktion aufrufen.',
    );
    expect(
      canJoin.contains('notifications'),
      isFalse,
      reason:
          'can_join_group liest die Einladung nicht mehr selbst aus '
          'notifications, sonst laufen Lesen und Beitreten wieder auseinander.',
    );
  });

  test('Die Lese-Policy auf groups hat den Einladungs-Zweig', () {
    final policy = abschnitt(
      'create policy "groups_visible_before_live_or_member_or_invited"',
      ');',
    );
    expect(policy.contains('for select'), isTrue);
    expect(
      policy.contains('ist_zu_gruppe_eingeladen(id, auth.uid())'),
      isTrue,
      reason: 'Genau dieser Zweig hat gefehlt, das war der Defekt.',
    );
    // Der Zugang endet mit der Ausfahrt und wird kein Dauerzugang.
    expect(policy.contains('closed_at is null'), isTrue);
    // Die drei alten Zweige duerfen nicht verloren gehen.
    expect(policy.contains('created_by = auth.uid()'), isTrue);
    expect(policy.contains('is_group_member(id, auth.uid())'), isTrue);
  });

  test('Die alte Policy ohne Einladungs-Zweig wird abgeraeumt', () {
    expect(
      code.contains(
        'drop policy if exists "groups_visible_before_live_or_member" '
        'on public.groups',
      ),
      isTrue,
    );
    expect(
      code.contains(
        'drop policy if exists "group_members_visible_before_live_or_member" '
        'on public.group_members',
      ),
      isTrue,
    );
  });

  test('Die Mitgliederliste sieht der Eingeladene nur vor der Abfahrt', () {
    final policy = abschnitt(
      'create policy "group_members_visible_before_live_or_member_or_invited"',
      ');',
    );
    expect(
      policy.contains('ist_zu_gruppe_eingeladen(group_id, auth.uid())'),
      isTrue,
      reason: 'Ohne Mitgliederliste bleibt der Beitritts-Bildschirm leer.',
    );
    expect(
      policy.contains('gruppe_ist_in_der_lobby(group_id)'),
      isTrue,
      reason:
          'group_members traegt current_lat/current_lng. Wer nur eingeladen '
          'ist und nicht beitritt, darf die Live-Standorte der Fahrer nicht '
          'sehen.',
    );
  });

  test('Einladen prueft den Gastgeber und traegt den Gruppennamen ein', () {
    final rpc = abschnitt(
      'create or replace function public.invite_to_group',
      r'$$;',
    );
    expect(
      rpc.contains('is_group_owner(p_group_id, v_host)'),
      isTrue,
      reason:
          'Bis heute prueft niemand, wer da einlaedt. Mit dem neuen '
          'Lese-Zweig waere das ein Weg in fremde private Gruppen.',
    );
    expect(
      rpc.contains('is_group_member(p_group_id, v_host)'),
      isTrue,
      reason:
          'Mitglieder duerfen einladen, der Knopf in der Lobby ist an keine '
          'Rolle gebunden. Aussenstehende duerfen es nicht.',
    );
    expect(
      rpc.contains("'group_name'"),
      isTrue,
      reason:
          'Beide Einladungen aus dem Vorfall hatten payload = {}, deshalb '
          'stand in der Glocke nie der Gruppenname.',
    );
    expect(rpc.contains('is_blocked_pair'), isTrue);
  });

  test('Die Einladung laesst sich zuruecknehmen', () {
    final rpc = abschnitt(
      'create or replace function public.revoke_group_invite',
      r'$$;',
    );
    expect(rpc.contains('is_group_owner'), isTrue);
    expect(rpc.contains('delete from public.notifications'), isTrue);
    // Ein Rueckzug ist kein Rauswurf: an group_members wird nicht geruehrt.
    expect(rpc.contains('group_members'), isFalse);
  });

  test('Keine Gedankenstriche in den Meldungen an den Nutzer', () {
    final meldungen = RegExp(r"raise exception '([^']*)'")
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toList();
    expect(meldungen, isNotEmpty);
    for (final m in meldungen) {
      expect(
        m.contains('–') || m.contains('—'),
        isFalse,
        reason: 'Gedankenstrich in: $m',
      );
      expect(
        m.contains('ae') || m.contains('oe') || m.contains('ue'),
        isFalse,
        reason: 'Umlaut nicht ausgeschrieben in: $m',
      );
    }
  });
}
