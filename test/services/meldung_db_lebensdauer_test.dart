import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-20, Vucko: "Die neue Funktion mit Unfaelle melden, Baustellen und
/// auch Stau ist leider noch nicht so funktional. [...] Ich habe es gemeldet,
/// und dann bin ich spaeter wieder diese Strasse gefahren, wo eine Baustelle
/// ist, und mir wurde nichts angezeigt von meiner vorherigen Meldung."
///
/// GEMESSEN am 20.08. an allen sechs Zeilen in `road_incidents`: es war nie ein
/// Synchronisationsfehler. Die Meldungen kamen an, sie waren beim naechsten
/// Vorbeifahren nur schon abgelaufen. Drei Baustellen lebten genau 15 Minuten
/// (kein Ortsnachweis), zwei genau 12 Stunden, ein Unfall 3 Stunden. In
/// `road_incident_votes` stand seit dem 24.07. keine einzige Zeile, weil vor
/// jeder moeglichen Bestaetigung schon alles tot war.
///
/// Die Regeln liegen in der Datenbank, nicht in Dart. Dieser Test kann sie
/// deshalb nicht ausfuehren, aber er haelt die Migration fest, die sie setzt.
/// Er ist die Sperre gegen den Rueckfall, der den Fehler verursacht hat: eine
/// GLOBALE Obergrenze fuer alle Meldungsarten. Solange die existierte, konnte
/// eine Baustelle nie laenger leben als einen Tag, egal wie oft sie bestaetigt
/// wurde. Ohne die Migration ist dieser Test rot.
void main() {
  final datei = File(
    'supabase/migrations/20260820175500_meldung_lebensdauer_und_bestaetigung.sql',
  );

  late String sql;

  setUpAll(() {
    expect(
      datei.existsSync(),
      isTrue,
      reason: 'Die Migration mit den Lebensdauern fehlt: ${datei.path}',
    );
    sql = datei.readAsStringSync();
  });

  /// Liest einen Wert aus dem `update road_incident_settings set ...`-Block.
  int wert(String spalte) {
    final treffer = RegExp(
      '$spalte\\s*=\\s*(\\d+)',
      multiLine: true,
    ).firstMatch(sql);
    expect(
      treffer,
      isNotNull,
      reason: 'In der Migration wird $spalte nie gesetzt.',
    );
    return int.parse(treffer!.group(1)!);
  }

  const stunde = 3600;
  const tag = 24 * stunde;

  group('Lebensdauern je Meldungsart', () {
    test('Eine Baustelle steht Wochen, nicht einen halben Tag', () {
      // Der eigentliche Defekt: 12 h Grundfrist. Vuckos Baustelle vom 19.08.
      // 14:53 war um 02:53 nachts weg, obwohl sie natuerlich noch stand.
      expect(
        wert('ttl_baustelle_sec'),
        14 * tag,
        reason: 'Baustelle braucht 14 Tage Grundfrist, vorher waren es 12 h.',
      );
    });

    test('Ein Stau loest sich in Minuten bis Stunden auf', () {
      expect(wert('ttl_stau_sec'), 1 * stunde);
    });

    test('Ein Unfall blockiert Stunden, nicht Wochen', () {
      expect(wert('ttl_unfall_sec'), 4 * stunde);
    });

    test('Die Grundfristen stehen in der richtigen Reihenfolge', () {
      expect(wert('ttl_stau_sec'), lessThan(wert('ttl_unfall_sec')));
      expect(wert('ttl_unfall_sec'), lessThan(wert('ttl_baustelle_sec')));
    });
  });

  group('Obergrenze je Art statt global', () {
    test('Die Baustellen-Obergrenze liegt weit ueber einem Tag', () {
      // Das ist der Kern. Der alte globale Deckel war 89.000 s (24,7 h) und
      // machte jede Bestaetigung einer Baustelle folgenlos.
      expect(wert('ttl_cap_baustelle_sec'), 90 * tag);
      expect(
        wert('ttl_cap_baustelle_sec'),
        greaterThan(89000),
        reason: 'Der alte globale Deckel von 24,7 h darf nicht zurueckkehren.',
      );
    });

    test('Jede Art hat eine eigene Obergrenze', () {
      for (final spalte in const [
        'ttl_cap_stau_sec',
        'ttl_cap_unfall_sec',
        'ttl_cap_baustelle_sec',
      ]) {
        expect(wert(spalte), greaterThan(0));
      }
    });

    test('Keine Obergrenze liegt unter ihrer eigenen Grundfrist', () {
      expect(wert('ttl_cap_stau_sec'),
          greaterThanOrEqualTo(wert('ttl_stau_sec')));
      expect(wert('ttl_cap_unfall_sec'),
          greaterThanOrEqualTo(wert('ttl_unfall_sec')));
      expect(wert('ttl_cap_baustelle_sec'),
          greaterThanOrEqualTo(wert('ttl_baustelle_sec')));
    });

    test('Der Tabellen-Deckel gilt je Art, nicht pauschal', () {
      // Die alte Pruefung war `expires_at <= created_at + interval '25:00:00'`
      // fuer ALLES und haette jede laengere Baustelle schon beim Anlegen
      // abgewiesen.
      expect(
        sql.contains("when 'baustelle' then interval '100 days'"),
        isTrue,
        reason: 'road_incidents_expires_sane muss je Art unterscheiden.',
      );
    });
  });

  group('Ortsnachweis', () {
    test('Ohne Nachweis ist eine Baustelle nicht nach 15 Minuten weg', () {
      // 15 Minuten waren praktisch dasselbe wie verwerfen. Der Melde-Knopf ist
      // schon sichtbar, sobald die Route bestaetigt ist, also VOR dem
      // Fahrtstart: wer dort meldet, hat nie eine Position gesendet und kann
      // gar keinen Ortsnachweis haben. Genau so entstanden drei der sechs
      // gemessenen Zeilen.
      expect(wert('ttl_unverified_baustelle_sec'), 1 * tag);
      expect(
        wert('ttl_unverified_baustelle_sec'),
        greaterThan(900),
        reason: 'Die alten 15 Minuten duerfen nicht zurueckkehren.',
      );
    });

    test('Ungeprueft ist immer deutlich kuerzer als geprueft', () {
      expect(wert('ttl_unverified_stau_sec'), lessThan(wert('ttl_stau_sec')));
      expect(
          wert('ttl_unverified_unfall_sec'), lessThan(wert('ttl_unfall_sec')));
      expect(wert('ttl_unverified_baustelle_sec'),
          lessThan(wert('ttl_baustelle_sec')));
    });

    test('Ungeprueft ist lang genug fuer eine zweite Sichtung', () {
      // Untergrenze 30 Minuten: kuerzer kann niemand sonst die Meldung
      // ueberhaupt zu Gesicht bekommen.
      for (final spalte in const [
        'ttl_unverified_stau_sec',
        'ttl_unverified_unfall_sec',
        'ttl_unverified_baustelle_sec',
      ]) {
        expect(wert(spalte), greaterThanOrEqualTo(30 * 60));
      }
    });

    test('Die Naehe wird mit der Zeit seit der letzten Position verrechnet', () {
      // set_live_position laeuft nur einmal pro 60 s. Ab 30 km/h ist die letzte
      // bekannte Position weiter als die alten 500 m entfernt, der Nachweis
      // scheiterte also fast immer.
      expect(wert('proximity_speed_mps'), 36); // 129,6 km/h
      expect(wert('proximity_hard_max_m'), 3000);
      expect(
        sql.contains('s.proximity_max_m + v_pos_age * s.proximity_speed_mps'),
        isTrue,
        reason: 'Der Geschwindigkeits-Ausgleich fehlt in report_road_incident.',
      );
    });
  });

  group('Auf- und Abwertung durch Bestaetigungen', () {
    test('Eine Bestaetigung kann eine Frist nur verlaengern, nie kuerzen', () {
      expect(
        sql.contains('least(greatest(expires_at,'),
        isTrue,
        reason: 'Bestaetigen muss greatest(expires_at, ...) benutzen.',
      );
    });

    test('Bestaetigen laeuft gegen die Obergrenze der Art', () {
      expect(sql.contains('road_incident_cap_sec(inc.type)'), isTrue);
      // Wortgrenze, sonst trifft die Suche auch den erklaerenden
      // `comment on column ... settings.ttl_cap_sec`.
      expect(
        RegExp(r'\bs\.ttl_cap_sec\b').hasMatch(sql),
        isFalse,
        reason: 'Der globale Deckel darf nirgends mehr gelesen werden.',
      );
    });

    test('Ablehnungen kuerzen gestaffelt statt sofort abzuschalten', () {
      expect(sql.contains('w_dism > w_conf'), isTrue);
      expect(sql.contains("interval '10 minutes'"), isTrue);
    });

    test('Eine einzelne Ablehnung legt nichts still', () {
      expect(
        sql.contains('w_dism >= greatest(2.0, w_conf + 2.0)'),
        isTrue,
        reason: 'Zweitkonten duerfen keine gut bestaetigte Warnung ausknipsen.',
      );
    });

    test('Die Naehe haengt an der Stimme, nicht am Aufruf', () {
      // Vorher wurde nur die GERADE abgegebene Stimme abgewertet, jede aeltere
      // zaehlte beim naechsten Aufruf wieder voll.
      expect(sql.contains('voted_near'), isTrue);
      expect(sql.contains('case when v.voted_near then 1.0 else 0.5 end'), isTrue);
    });

    test('Erneutes eigenes Melden derselben Stelle verlaengert die Frist', () {
      // Woertlich Vuckos Fall. Vorher passierte in diesem Zweig gar nichts.
      expect(sql.contains("'refreshed'"), isTrue);
      expect(sql.contains('road_incident_ttl_sec(p_type, true)'), isTrue);
    });

    test('Abgelaufene Meldungen nehmen keine Stimme mehr an', () {
      expect(sql.contains('if not inc.active or inc.expires_at <= now() then'),
          isTrue);
    });
  });

  group('Absicherung', () {
    test('Die neuen Hilfsfunktionen haengen nicht an PUBLIC', () {
      // EXECUTE-Leck vom 27.06.
      for (final fn in const [
        'road_incident_ttl_sec(text, boolean)',
        'road_incident_cap_sec(text)',
      ]) {
        expect(
          RegExp('revoke execute on function public\\.${RegExp.escape(fn)}'
                  '\\s*\\n?\\s*from public, anon, authenticated')
              .hasMatch(sql),
          isTrue,
          reason: 'Rechte auf $fn nicht entzogen.',
        );
      }
    });

    test('Der Missbrauchsschutz vom 26.07. bleibt unangetastet', () {
      for (final regel in const [
        's.report_min_interval_sec',
        's.self_repeat_window_sec',
        's.max_plausible_kmh',
        'report_daily_limit_high',
        'vote_daily_limit',
        's.trust_shadow_below',
        's.min_account_age_sec',
      ]) {
        expect(
          sql.contains(regel),
          isTrue,
          reason: 'Die Bremse $regel wurde beim Umbau verloren.',
        );
      }
    });

    test('Der Aufraeum-Job bleibt eingeplant', () {
      expect(sql.contains("cron.schedule('road-incident-trust'"), isTrue);
    });
  });

  group('Probe an den sechs gemessenen Zeilen', () {
    test('Vuckos Baustelle vom 19.08. lebt jetzt 28 mal so lange', () {
      // Gemessen: 19.08. 14:53 gemeldet, 20.08. 02:53 abgelaufen = 720 Minuten.
      const gemessenSek = 12 * stunde;
      expect(wert('ttl_baustelle_sec') / gemessenSek, 28);
    });

    test('Die drei 15-Minuten-Zeilen leben jetzt 96 mal so lange', () {
      const gemessenSek = 15 * 60;
      expect(wert('ttl_unverified_baustelle_sec') / gemessenSek, 96);
    });
  });
}
