import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24 — Aufgabe 4 aus Vuckos Auftrag.
///
/// Woertlich: „man muss die sachen wie ersten post oder benutze einen hashtag
/// wenn das noch nicht als aufgabe drinnen ist auch wirklich absolvieren".
///
/// Zwei Haelften, beide hier geprueft:
///  1. Die Hashtag-Aufgabe gab es nicht. Jetzt gibt es sie.
///  2. „auch wirklich absolvieren" — keine Aufgabe darf sich abhaken lassen,
///     bevor die Tat getan ist.
///
/// VOR DER AENDERUNG waere jeder Test hier rot: die Aufgabe 'hashtag' gab es
/// nicht, `synchronisiereAusKennzahlen` kannte weder `hashtagBenutzt` noch
/// `gespeicherteRouten`, und die Meldung „speichern" stand in
/// `SavedRoutesService` noch vor jedem Datenbankzugriff.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dienst = StarterAufgabenService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
  });

  group('die zwoelfte Aufgabe', () {
    test('„Einen Hashtag benutzen" steht in der Liste, direkt hinter „post"',
        () {
      final ids = StarterAufgabenService.aufgaben.map((a) => a.id).toList();
      expect(ids, hasLength(12));
      expect(ids.indexOf('hashtag'), ids.indexOf('post') + 1);
      expect(ids.toSet(), hasLength(ids.length), reason: 'ID doppelt');

      final aufgabe = StarterAufgabenService.aufgaben.firstWhere(
        (a) => a.id == 'hashtag',
      );
      expect(aufgabe.titel, 'Einen Hashtag benutzen');
      expect(aufgabe.beschreibung, contains('#'));
    });

    test('erfuellt sich aus dem Zustand, nicht aus einem Ereignis', () async {
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 1,
        abgeschlosseneFahrten: 0,
        abgeschlosseneGruppenfahrten: 0,
        hashtagBenutzt: true,
      );
      expect(dienst.erledigt('hashtag'), isTrue);
    });

    test('ein Beitrag OHNE Raute erfuellt sie nicht', () async {
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 3,
        abgeschlosseneFahrten: 1,
        abgeschlosseneGruppenfahrten: 0,
      );
      expect(dienst.erledigt('post'), isTrue);
      expect(dienst.erledigt('hashtag'), isFalse);
    });
  });

  group('die Boost-Schwelle wandert NICHT mit', () {
    test('acht von zwoelf', () {
      expect(StarterAufgabenService.aufgabenFuerBoost, 8);
      expect(StarterAufgabenService.aufgaben.length, 12);
    });

    test('der Weg ohne die duenn besetzten Aufgaben existiert weiter',
        () async {
      // Sechs ohne jede Fahrt, dazu eine echte Runde und ein echter Post.
      // GEMESSEN am 24.08.: 50 km haben 9 von 183, drei Abzeichen 16 von 183 —
      // keine der beiden darf zur Sperre werden.
      await dienst.load();
      await dienst.markiereAlle([
        'tutorial',
        'route',
        'favorit',
        'speichern',
        'community',
        'garage',
        'runde',
        'post',
      ]);
      expect(dienst.boostErreicht, isTrue);
      expect(dienst.erledigt('hashtag'), isFalse);
      expect(dienst.erledigt('km50'), isFalse);
      expect(dienst.erledigt('abzeichen'), isFalse);
    });
  });

  group('„auch wirklich absolvieren"', () {
    test('„Eine Route speichern" wird auch aus dem Zustand nachgetragen',
        () async {
      await dienst.load();
      expect(dienst.erledigt('speichern'), isFalse);
      await dienst.synchronisiereAusKennzahlen(
        posts: 0,
        abgeschlosseneFahrten: 0,
        abgeschlosseneGruppenfahrten: 0,
        gespeicherteRouten: 2,
      );
      expect(dienst.erledigt('speichern'), isTrue);
    });

    test('ohne gespeicherte Route bleibt sie offen', () async {
      await dienst.load();
      await dienst.synchronisiereAusKennzahlen(
        posts: 1,
        abgeschlosseneFahrten: 1,
        abgeschlosseneGruppenfahrten: 0,
      );
      expect(dienst.erledigt('speichern'), isFalse);
    });

    /// QUELLWACHE. `SavedRoutesService` haengt komplett an Supabase; ein
    /// Unit-Test muesste den Client so weit nachbauen, dass er am Ende die
    /// Nachbildung prueft. Diese Wache liest stattdessen die eine
    /// Eigenschaft ab, an der alles hing: die Meldung darf nicht mehr VOR dem
    /// Schreiben stehen.
    test('SavedRoutesService meldet erst nach dem erfolgreichen Speichern', () {
      final quelle = File(
        'lib/data/services/saved_routes_service.dart',
      ).readAsStringSync();

      // Die alte, zu fruehe Meldung ist weg.
      expect(
        quelle.contains("markiere('speichern')")
            ? quelle.split("markiere('speichern')").length - 1
            : 0,
        1,
        reason: 'Die Meldung darf es nur noch an EINER Stelle geben: in '
            '_meldeSpeichernAufgabe.',
      );

      // Und sie steht in der Hilfsmethode, nicht im Kopf von saveRoute.
      final kopf = quelle.substring(
        quelle.indexOf('static Future<String?> saveRoute('),
        quelle.indexOf('final routeType = isRoundTrip'),
      );
      expect(
        kopf.contains('markiere('),
        isFalse,
        reason: 'saveRoute hakt die Aufgabe wieder vor dem INSERT ab.',
      );
    });

    /// QUELLWACHE fuer Aufgabe 3. badge_58 darf die Aufgabe „die ersten drei
    /// Abzeichen sammeln" nicht selbst miterfuellen — sonst haengt sie an
    /// ihrem eigenen Ergebnis, genau wie es fuer badge_16 schon gilt.
    test('badge_58 wird NACH der Abzeichen-Zaehlung vergeben', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();

      final zaehlung = quelle.indexOf('final abzeichenOhneStartklar');
      final vergabe = quelle.indexOf('currentlyQualifiedBadges.add(onboardingBadgeId)');
      expect(zaehlung, greaterThan(0), reason: 'Zaehlung nicht gefunden');
      expect(vergabe, greaterThan(0), reason: 'badge_58 wird nicht vergeben');
      expect(
        vergabe,
        greaterThan(zaehlung),
        reason: 'badge_58 wuerde die Aufgabe „drei Abzeichen" mit sich selbst '
            'erfuellen.',
      );

      // Die Bedingung ist der ECHTE Abschluss (Starter-Aufgabe „tutorial"),
      // nicht das Ueberspringen.
      expect(quelle, contains("starter.erledigt('tutorial')"));
    });

    /// Aufgabe 5 (nachpruefen, nicht aendern). Vucko: „das anfangsbadge zaehlt
    /// dazu". Gemeint ist badge_15 „Gruendungszeit", das JEDE Person ohne
    /// Bedingung bekommt. Es wird VOR der Zaehlung angehaengt, zaehlt also
    /// mit — anders als badge_16 und badge_58, die Belohnungen dieser Liste
    /// sind. Ein frischer Nutzer muss damit ZWEI Abzeichen selbst verdienen.
    test('badge_15 zaehlt fuer die Abzeichen-Aufgabe mit', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      final gruendung =
          quelle.indexOf('currentlyQualifiedBadges.add(Badge.membershipBadgeId)');
      final zaehlung = quelle.indexOf('final abzeichenOhneStartklar');
      final startklar =
          quelle.indexOf('currentlyQualifiedBadges.add(Badge.starterBadgeId)');
      expect(gruendung, greaterThan(0));
      expect(gruendung, lessThan(zaehlung), reason: 'badge_15 zaehlt nicht mit');
      expect(startklar, greaterThan(zaehlung), reason: 'badge_16 zaehlt sich '
          'selbst mit');
      // Und die Zahl selbst steht unveraendert auf drei.
      expect(StarterAufgabenService.abzeichenFuerAufgabe, 3);
    });

    /// DRIFT-WACHE. Die Vergabe steht als Literal im Dienst, damit sie auch
    /// dann uebersetzt, wenn der Katalog-Eintrag noch fehlt (normalizeBadgeIds
    /// verwirft unbekannte Kennungen still). Genau deshalb waere ein
    /// Auseinanderlaufen unsichtbar — diese Zeile macht es laut.
    test('vergebene und katalogisierte Kennung sind dieselbe', () {
      expect(GamificationService.onboardingBadgeId, Badge.onboardingBadgeId);
      expect(GamificationService.onboardingBadgeId, 'badge_58');
    });
  });
}
