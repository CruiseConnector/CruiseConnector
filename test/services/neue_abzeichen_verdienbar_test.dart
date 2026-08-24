import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 — die zwoelf neuen Abzeichen sind verdienbar.
///
/// ANLASS: In der Nacht auf den 24.08. sind badge_59 … badge_70 angelegt
/// worden (Garage, Beitraege, Hashtags, Meldungen, je drei Stufen). Der Agent,
/// der sie angelegt hat, meldete selbst, dass im Aufruf von `badgeMetriken(…)`
/// in `calculateAndSync` vier Zeilen fehlen. Solange sie fehlten, stand jede
/// der zwoelf Stufen dauerhaft auf 0 — gesperrt fuer alle, fuer immer.
///
/// VOR DER AENDERUNG waeren rot:
///  * „jeder Kennwert von badgeMetriken wird auch uebergeben" (vier fehlten),
///  * alle Tests der Gruppe „die Zahl kommt aus der Datenbank" (die RPC gab es
///    nicht, die Hashtag-Abfrage lieferte ein Ja/Nein),
///  * die Tests zu [badgeKennzahlenAusAntwort] (die Funktion gab es nicht).
void main() {
  final dienstQuelle = File(
    'lib/data/services/gamification_service.dart',
  ).readAsStringSync();

  group('Die Freischaltung kennt alle Kennwerte', () {
    /// QUELLWACHE gegen genau den Fehler vom 24.08.: `badgeMetriken` bekommt
    /// einen neuen benannten Kennwert, der Aufruf in `calculateAndSync` wird
    /// vergessen — und die daran haengende Familie ist unerreichbar, ohne dass
    /// irgendetwas rot wird. Der Test vergleicht beide Listen, so wie
    /// `laender_klassifikation_test` Client und Edge vergleicht.
    test('jeder Kennwert von badgeMetriken wird in calculateAndSync '
        'uebergeben', () {
      final badgeQuelle = File(
        'lib/domain/models/badge.dart',
      ).readAsStringSync();

      // Die Parameterliste von badgeMetriken({ … }) aus badge.dart lesen.
      final kopfStart = badgeQuelle.indexOf(
        'Map<BadgeMetrik, double> badgeMetriken({',
      );
      expect(kopfStart, greaterThan(0), reason: 'badgeMetriken nicht gefunden');
      final kopfEnde = badgeQuelle.indexOf('}) {', kopfStart);
      final kopf = badgeQuelle.substring(kopfStart, kopfEnde);
      final erwartet = RegExp(r'(\w+) = ')
          .allMatches(kopf)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        erwartet.length,
        greaterThanOrEqualTo(21),
        reason: 'Parameterliste nicht erkannt',
      );

      // Und den Aufruf in calculateAndSync.
      final aufrufStart = dienstQuelle.indexOf('final metriken = badgeMetriken(');
      expect(aufrufStart, greaterThan(0), reason: 'Aufruf nicht gefunden');
      final aufruf = dienstQuelle.substring(
        aufrufStart,
        dienstQuelle.indexOf('\n    );', aufrufStart),
      );

      final fehlend = erwartet
          .where((name) => !aufruf.contains('$name:'))
          .toList()
        ..sort();
      expect(
        fehlend,
        isEmpty,
        reason:
            'Diese Kennwerte werden nie befuellt, die daran haengenden '
            'Abzeichen sind unerreichbar: ${fehlend.join(', ')}',
      );
    });

    test('mit den Zahlen fallen alle zwoelf neuen Abzeichen', () {
      final ids = erfuellteBadgeIds(
        badgeMetriken(
          fahrzeuge: 5,
          beitraege: 20,
          hashtagBeitraege: 20,
          meldungen: 20,
        ),
      );
      for (var nr = 59; nr <= 70; nr++) {
        expect(ids, contains('badge_$nr'), reason: 'badge_$nr fehlt');
      }
    });

    test('ohne die Zahlen faellt keines davon', () {
      final ids = erfuellteBadgeIds(badgeMetriken(totalKm: 99999, level: 100));
      for (var nr = 59; nr <= 70; nr++) {
        expect(ids, isNot(contains('badge_$nr')), reason: 'badge_$nr');
      }
    });
  });

  group('Die Zahl kommt aus der Datenbank, nicht aus der Tabelle', () {
    /// GEMESSEN am 24.08. in der Produktivdatenbank: Die aktivste meldende
    /// Person hat 7 Meldungen abgesetzt; unter der Sichtbarkeitsregel
    /// `ri_select` (active AND expires_at > now()) sieht sie davon 2. Eine
    /// Meldung hat eine Lebensdauer. Wer diesen Zaehler auf ein SELECT
    /// umstellt, macht „Setze zwanzig Meldungen ab" wieder unerreichbar —
    /// man muesste zwanzig Meldungen gleichzeitig gueltig halten.
    test('Meldungen werden NICHT direkt aus road_incidents gelesen', () {
      expect(
        dienstQuelle.contains("from('road_incidents')"),
        isFalse,
        reason:
            'Ein direktes SELECT sieht nur die gerade gueltigen Meldungen '
            '(gemessen: 2 von 7). Die Zahl gehoert in die RPC.',
      );
      expect(dienstQuelle, contains("_db.rpc('meine_badge_kennzahlen')"));
    });

    /// Dieselbe Falle in Gruen: Beitraege mit Raute sind
    /// `count(distinct post_id)`. `post_hashtags` hat eine Zeile je Raute —
    /// ein Beitrag mit fuenf Schlagworten haette Stufe 5 sofort geoeffnet.
    test('Hashtags werden NICHT mehr aus post_hashtags gezaehlt', () {
      expect(dienstQuelle.contains("from('post_hashtags')"), isFalse);
    });

    test('die Migration zaehlt beides serverseitig und ehrlich', () {
      final sql = File(
        'supabase/migrations/'
        '20260824180000_badge_kennzahlen_beitraege_und_meldungen.sql',
      ).readAsStringSync();

      expect(sql, contains('create or replace function '
          'public.meine_badge_kennzahlen()'));
      // SECURITY DEFINER ist der ganze Zweck: sonst greift dieselbe
      // Sichtbarkeitsregel, die den Client blind macht.
      expect(sql, contains('security definer'));
      expect(sql, contains("set search_path to 'public', 'pg_temp'"));
      // Nur eigene Zeilen — die Funktion gibt nichts preis.
      expect(sql, contains('ri.reported_by = (select auth.uid())'));
      expect(sql, contains('p.user_id = (select auth.uid())'));
      // Beitraege, nicht Rauten.
      expect(sql, contains('count(distinct ph.post_id)'));
      // Zurueckgezogene Meldungen zaehlen nicht mit, sonst waeren zwanzig
      // Meldungen mit zwanzig Widerrufen zu haben.
      expect(sql, contains('ri.retracted_at is null'));
      // Ohne Anmeldung gibt es hier nichts zu holen.
      expect(sql, contains('revoke execute on function '
          'public.meine_badge_kennzahlen() from anon;'));
      expect(sql, contains('grant  execute on function '
          'public.meine_badge_kennzahlen() to authenticated;'));
    });

    /// `calculateAndSync` laeuft bei JEDEM Start der Startseite. Die
    /// bestehenden Zaehler werden alle zuerst gestartet und erst danach
    /// abgewartet — ein Wartetakt fuer alle statt einer pro Abfrage. Der neue
    /// Aufruf muss in diesem Muster bleiben.
    test('der neue Aufruf laeuft neben den anderen, nicht dahinter', () {
      final start = dienstQuelle.indexOf('final kennzahlenZaehler =');
      final erstesWarten = dienstQuelle.indexOf(
        'final createdGroupCount = await',
      );
      expect(start, greaterThan(0), reason: 'Zaehler nicht gefunden');
      expect(erstesWarten, greaterThan(0));
      expect(
        start,
        lessThan(erstesWarten),
        reason:
            'Der Aufruf wird erst nach dem ersten await gestartet — das ist '
            'ein zusaetzlicher Wartetakt beim Start der Startseite.',
      );
    });

    /// Eine RPC, nicht zwei: sonst waere aus einem Wartetakt wieder zwei.
    test('es bleibt bei EINEM zusaetzlichen Netzweg', () {
      expect(
        RegExp("_db.rpc\\('meine_badge_kennzahlen'\\)")
            .allMatches(dienstQuelle)
            .length,
        1,
      );
    });
  });

  group('badgeKennzahlenAusAntwort', () {
    test('liest beide Zahlen aus dem Objekt', () {
      final k = badgeKennzahlenAusAntwort({
        'hashtag_beitraege': 7,
        'meldungen': 21,
      });
      expect(k.hashtagBeitraege, 7);
      expect(k.meldungen, 21);
    });

    test('vertraegt die einelementige Liste mancher Client-Fassungen', () {
      final k = badgeKennzahlenAusAntwort([
        {'hashtag_beitraege': 2, 'meldungen': 3},
      ]);
      expect(k.hashtagBeitraege, 2);
      expect(k.meldungen, 3);
    });

    test('bigint kommt als Text an — auch dann stimmt die Zahl', () {
      // count() ist bigint; je nach Fassung liefert der Client dafuer einen
      // String. Wer das nicht liest, sperrt die Abzeichen still auf 0.
      final k = badgeKennzahlenAusAntwort({
        'hashtag_beitraege': '5',
        'meldungen': '20',
      });
      expect(k.hashtagBeitraege, 5);
      expect(k.meldungen, 20);
    });

    test('fehlende, leere und kaputte Antworten ergeben 0, nie eine Ausnahme',
        () {
      for (final antwort in <dynamic>[
        null,
        <dynamic>[],
        'Fehler',
        <String, dynamic>{},
        {'hashtag_beitraege': null, 'meldungen': 'viele'},
      ]) {
        final k = badgeKennzahlenAusAntwort(antwort);
        expect(k.hashtagBeitraege, 0, reason: '$antwort');
        expect(k.meldungen, 0, reason: '$antwort');
      }
    });

    test('negative Zahlen werden gekappt', () {
      final k = badgeKennzahlenAusAntwort({
        'hashtag_beitraege': -3,
        'meldungen': -1,
      });
      expect(k.hashtagBeitraege, 0);
      expect(k.meldungen, 0);
    });

    test('eine Null schaltet nichts frei, eine Eins die erste Stufe', () {
      final leer = badgeKennzahlenAusAntwort(null);
      expect(
        erfuellteBadgeIds(
          badgeMetriken(
            hashtagBeitraege: leer.hashtagBeitraege,
            meldungen: leer.meldungen,
          ),
        ),
        isEmpty,
      );
      final eins = badgeKennzahlenAusAntwort({
        'hashtag_beitraege': 1,
        'meldungen': 1,
      });
      final ids = erfuellteBadgeIds(
        badgeMetriken(
          hashtagBeitraege: eins.hashtagBeitraege,
          meldungen: eins.meldungen,
        ),
      );
      expect(ids, containsAll(<String>['badge_65', 'badge_68']));
      expect(ids, isNot(contains('badge_66')));
      expect(ids, isNot(contains('badge_69')));
    });
  });

  group('Die Starter-Aufgabe „Hashtag" haengt an derselben Zahl', () {
    /// Die Aufgabe vom 24.08. fragt nur „hat je eine Raute gesetzt". Sie darf
    /// dafuer keine zweite Abfrage aufmachen, sondern liest dieselbe Zahl.
    test('hashtagBenutzt wird aus der Zahl abgeleitet', () {
      expect(
        dienstQuelle,
        contains('final hashtagBenutzt = hashtagBeitragsAnzahl > 0;'),
      );
      expect(dienstQuelle, contains('hashtagBenutzt: hashtagBenutzt'));
    });
  });
}
