import 'dart:io';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (Aufgabe 10a) — vucko woertlich:
///
/// „dass community ein enzelnes badge bekommen [...] und man dafuer bei den
/// analytics ein badge bekommt aber nur eins das heisst Gruende eine Community
/// wenn man draufklickt und sonnst nur Community heisst wenn es das nicht
/// schon gibt."
///
/// GEPRUEFT am 24.08.: Es gab KEIN solches Abzeichen. „Community-Stimme"
/// (badge_36) heisst zwar aehnlich, ist aber etwas anderes — fuenfzehn
/// geteilte Routen.
///
/// Vor dieser Aenderung waere jede Erwartung hier rot: die Konstante
/// `Badge.communityGruenderBadgeId` gab es nicht, der Test haette gar nicht
/// erst kompiliert.
void main() {
  Badge dasAbzeichen() =>
      Badge.all.firstWhere((b) => b.id == Badge.communityGruenderBadgeId);

  group('Das Abzeichen selbst', () {
    test('Kachelname „Community", Anleitung „Gründe eine Community"', () {
      final b = dasAbzeichen();
      // „sonnst nur Community heisst" — der Kachelname.
      expect(b.name, 'Community');
      // „das heisst Gruende eine Community wenn man draufklickt" — das
      // Detail-Blatt zeigt `Badge.resolveDescription`.
      expect(Badge.resolveDescription(b), 'Gründe eine Community.');
    });

    test('stufenlos, wie badge_15 und badge_16 — „aber nur eins"', () {
      final b = dasAbzeichen();
      expect(b.familie, isNull);
      expect(b.stufe, 0);
      // Und es steht in keiner Stufen-Tabelle: sonst waere daraus spaeter
      // eine Leiter „drei Communities", „zehn Communities" geworden.
      expect(badgeBedingungFuer(b.id), isNull);
      for (final familie in badgeFamilien) {
        for (final stufe in familie.alleStufen) {
          expect(stufe.id, isNot(b.id));
        }
      }
    });

    test('genau EIN Abzeichen fuer die Community-Gruendung', () {
      final treffer = Badge.all
          .where(
            (b) =>
                b.description.toLowerCase().contains('community') &&
                b.description.toLowerCase().contains('gründe'),
          )
          .map((b) => b.id)
          .toList();
      expect(treffer, [Badge.communityGruenderBadgeId]);
    });

    test('die ID ueberlebt die Datenbank', () {
      // normalize_badge_ids verwirft alles, was nicht `badge_NN` ist —
      // ein badge_100 waere im Profil unsichtbar (Migration 20260818230000).
      expect(RegExp(r'^badge_[0-9]{2}$').hasMatch(dasAbzeichen().id), isTrue);
      expect(
        Badge.all.map((b) => b.id).toList().length,
        Badge.all.map((b) => b.id).toSet().length,
        reason: 'die neue ID darf keine bestehende doppeln',
      );
    });

    test('es ist nicht dasselbe wie „Community-Stimme"', () {
      final stimme = Badge.getById('badge_36')!;
      expect(stimme.id, isNot(Badge.communityGruenderBadgeId));
      expect(stimme.name, 'Community-Stimme');
      expect(stimme.description, contains('Routen'));
    });
  });

  group('Die Bedingung kommt aus der Datenbank, nicht aus dem Client', () {
    final dienst = File(
      'lib/data/services/gamification_service.dart',
    ).readAsStringSync();

    test('der Sync fragt die RPC und vergibt das Abzeichen', () {
      expect(dienst.contains("_db.rpc('meine_community_gruendung')"), isTrue);
      expect(
        dienst.contains('Badge.communityGruenderBadgeId'),
        isTrue,
        reason: 'ohne diese Zeile bekommt es nie jemand',
      );
    });

    test('KEIN Rueckfall auf owner_id oder die Admin-Rolle', () {
      // Migration 20260824103000 erklaert es ausfuehrlich:
      //  * `community_members.role = owner` ist die ADMIN-Rolle. Gemessen am
      //    24.08.: 7 Zeilen auf 6 Communities, eine Community hat zwei. Ueber
      //    diese Rolle bekaemen mehrere Leute je Community das Abzeichen.
      //  * `communities.owner_id` wird umgeschrieben, sobald der Gruender die
      //    Community verlaesst (ensure_community_primary_admin), und jeder
      //    Admin darf sie per UPDATE aendern.
      expect(
        dienst.contains("from('communities')"),
        isFalse,
        reason:
            'eine eigene Abfrage auf communities wuerde am Gruender vorbei '
            'zielen und private Communities gar nicht erst sehen',
      );
    });

    test('die Datenbank haelt den Gruender wirklich fest', () {
      final sql = File(
        'supabase/migrations/'
        '20260824103000_umkreis_serverseitig_und_gruenderin_community.sql',
      ).readAsStringSync();
      expect(sql.contains('add column if not exists founder_id'), isTrue);
      expect(sql.contains('trg_guard_community_founder_id'), isTrue);
      expect(
        sql.contains('function public.meine_community_gruendung()'),
        isTrue,
      );
      expect(
        sql.contains("grant  execute on function public.meine_community_gruendung() to authenticated"),
        isTrue,
        reason: 'ohne das Recht liefert die RPC dem Client einen Fehler',
      );
    });
  });
}
