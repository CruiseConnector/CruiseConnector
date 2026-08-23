import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/gruppen_umkreis_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';

/// 2026-08-24 — Aufgabe 3.1 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 4 [00:11] und [00:24]: „bei der Gruppenfahrt, dass man
/// einstellen kann, in welchem Umkreis man Gruppen machen will. Also wenn
/// Gruppen im Umkreis von 50 Kilometer sind, sollen die angezeigt werden —
/// oder alle. […] wenn man jetzt in Süddeutschland wäre, dass Leute in
/// Norddeutschland angezeigt werden und sonst nicht."
///
/// Zwei Mängel waren zu beheben, beide werden hier bewacht:
///
///   a) Akzeptanzkriterium 3: „Die Einstellung überlebt einen App-Neustart."
///      Sie lag als reines Widget-Feld in community_page.dart (Z. 93 bis 95)
///      und war nach jedem Neuaufbau weg.
///
///   b) Gefiltert wurde ERST NACH dem Abschneiden. social_service.dart holte
///      `.limit(80)` und schnitt auf `.take(40)`, beides entfernungsblind.
///      Gemessen (Migration 20260824103000, 100 fiktive Gruppen, 5 davon im
///      50-km-Umkreis um Bregenz):
///          erst abschneiden, dann filtern -> 0 Treffer
///          erst filtern                   -> 5 Treffer
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('3.1 a) Die Einstellung überlebt den App-Neustart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      GruppenUmkreisService.instance.zuruecksetzenFuerTest();
    });

    test('Vorgabe ist „alle": Filter aus, damit nichts stumm verschwindet', () {
      expect(GruppenUmkreisService.vorgabeAktiv, isFalse);
      expect(GruppenUmkreisService.instance.radiusMeterFuerAbfrage, isNull);
    });

    test(
      '50 km einstellen, Dienst neu starten, Einstellung ist noch da',
      () async {
        final dienst = GruppenUmkreisService.instance;
        await dienst.laden();
        await dienst.setzeAktiv(true);
        await dienst.setzeRadiusKm(50);

        // Genau das, was ein App-Neustart tut: der Zustand im Arbeitsspeicher
        // ist weg, SharedPreferences bleibt.
        dienst.zuruecksetzenFuerTest();
        expect(dienst.aktiv, isFalse, reason: 'vor dem Laden Vorgabe');

        await dienst.laden();
        expect(dienst.aktiv, isTrue);
        expect(dienst.radiusKm, 50);
      },
    );

    test('„alle" überlebt genauso wie ein Radius', () async {
      final dienst = GruppenUmkreisService.instance;
      await dienst.laden();
      await dienst.setzeAktiv(true);
      await dienst.setzeAktiv(false);

      dienst.zuruecksetzenFuerTest();
      await dienst.laden();
      expect(dienst.aktiv, isFalse);
    });

    test(
      'p_radius_m ist in METERN, der Regler in Kilometern — 50 km sind '
      '50000, nicht 50',
      () async {
        final dienst = GruppenUmkreisService.instance;
        await dienst.laden();
        await dienst.setzeAktiv(true);
        await dienst.setzeRadiusKm(50);
        expect(dienst.radiusMeterFuerAbfrage, 50000.0);
      },
    );

    test('ausgeschaltet heißt null, also „alle" für die RPC', () async {
      final dienst = GruppenUmkreisService.instance;
      await dienst.laden();
      await dienst.setzeAktiv(false);
      expect(dienst.radiusMeterFuerAbfrage, isNull);
    });

    test('ein verbogener gespeicherter Wert wirft den Regler nicht raus', () {
      expect(GruppenUmkreisService.begrenze(-5), 10);
      expect(GruppenUmkreisService.begrenze(0), 10);
      expect(GruppenUmkreisService.begrenze(5000), 100);
      expect(GruppenUmkreisService.begrenze(double.nan), 100);
      // Zwischenwerte rasten auf die 5er-Stufen ein.
      expect(GruppenUmkreisService.begrenze(52), 50);
      expect(GruppenUmkreisService.begrenze(53), 55);
    });

    test('ein Wert aus alter Ablage wird beim Laden begrenzt', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'gruppen_umkreis_aktiv_v1': true,
        'gruppen_umkreis_km_v1': 4711.0,
      });
      GruppenUmkreisService.instance.zuruecksetzenFuerTest();
      await GruppenUmkreisService.instance.laden();
      expect(GruppenUmkreisService.instance.radiusKm, 100);
    });

    test('der Dienst meldet Änderungen, sonst friert die Liste ein', () async {
      final dienst = GruppenUmkreisService.instance;
      await dienst.laden();
      var meldungen = 0;
      void zaehlen() => meldungen++;
      dienst.addListener(zaehlen);
      await dienst.setzeAktiv(true);
      await dienst.setzeRadiusKm(25);
      dienst.removeListener(zaehlen);
      expect(meldungen, 2);
    });
  });

  group('3.1 b) Entfernung anzeigen, niemals „0 km" erfinden', () {
    Map<String, dynamic> vomServer(Object? meter) => <String, dynamic>{
      'id': 'g1',
      SocialService.umkreisServerseitigKey: true,
      'entfernung_m': meter,
    };

    test('ohne Entfernung steht „Entfernung unbekannt" da', () {
      expect(
        SocialService.entfernungText(vomServer(null)),
        'Entfernung unbekannt',
      );
    });

    test('NIEMALS „0 km" — darunter wird auf Meter umgestellt', () {
      final text = SocialService.entfernungText(vomServer(120));
      expect(text, isNotNull);
      expect(text!.contains('0 km'), isFalse);
      expect(text, '100 m entfernt');
    });

    test('sehr nah bleibt ehrlich statt null', () {
      expect(
        SocialService.entfernungText(vomServer(20)),
        'unter 100 m entfernt',
      );
    });

    test('unter 10 km mit einer Nachkommastelle', () {
      expect(SocialService.entfernungText(vomServer(4300)), '4.3 km entfernt');
    });

    test('darüber gerundet auf ganze Kilometer', () {
      expect(SocialService.entfernungText(vomServer(51400)), '51 km entfernt');
    });

    test(
      'Zeilen vom alten Weg bekommen keine erfundene Entfernung',
      () {
        expect(
          SocialService.entfernungText(<String, dynamic>{
            'id': 'g1',
            'start_location': {'lat': 47.5, 'lng': 9.7},
          }),
          isNull,
        );
      },
    );
  });

  group('3.1 b) Die flache RPC-Zeile wird auf die alte Form zurückgebaut', () {
    // Die RPC liefert flach (mitglieder_anzahl, gastgeber_username,
    // gastgeber_avatar_url). Die Kachel-Widgets lesen dagegen seit jeher
    // group_members (nur die LÄNGE) und profiles. Diese Widgets liegen in
    // anderen Dateien — deshalb wird die alte Form hier nachgebaut.
    Map<String, dynamic> rpcZeile({int mitglieder = 3}) => <String, dynamic>{
      'id': 'g1',
      'name': 'Bodensee-Runde',
      'created_by': 'u1',
      'mitglieder_anzahl': mitglieder,
      'gastgeber_username': 'vucko',
      'gastgeber_avatar_url': 'https://beispiel/bild.png',
      'entfernung_m': 12000.0,
    };

    test('group_members hat die richtige Länge, die Kacheln zählen sie', () {
      final gruppe = SocialService.entdeckenGruppeAusRpcFuerTest(rpcZeile());
      expect((gruppe['group_members'] as List).length, 3);
    });

    test('null oder fehlende Anzahl ergibt eine leere Liste, keinen Absturz',
        () {
      final ohne = SocialService.entdeckenGruppeAusRpcFuerTest(
        <String, dynamic>{'id': 'g1', 'created_by': 'u1'},
      );
      expect((ohne['group_members'] as List), isEmpty);
    });

    test(
      'group_members erfindet KEINE user_id — eine Liste, die so tut, als '
      'kenne sie die Mitglieder, liest irgendwann jemand aus',
      () {
        final gruppe = SocialService.entdeckenGruppeAusRpcFuerTest(rpcZeile());
        for (final m in gruppe['group_members'] as List) {
          expect((m as Map).containsKey('user_id'), isFalse);
        }
      },
    );

    test('profiles wird so gebaut, wie die Kacheln es lesen', () {
      final gruppe = SocialService.entdeckenGruppeAusRpcFuerTest(rpcZeile());
      final profil = gruppe['profiles'] as Map<String, dynamic>;
      expect(profil['id'], 'u1');
      expect(profil['username'], 'vucko');
      expect(profil['avatar_url'], 'https://beispiel/bild.png');
    });

    test('die Zeile trägt den Merker, dass der Server schon gefiltert hat', () {
      final gruppe = SocialService.entdeckenGruppeAusRpcFuerTest(rpcZeile());
      expect(gruppe[SocialService.umkreisServerseitigKey], isTrue);
      expect(SocialService.entfernungText(gruppe), '12 km entfernt');
    });
  });

  group('3.1 b) Die Reihenfolge im Code: filtern vor abschneiden', () {
    late String service;
    late String page;

    /// Die Kommentare erklaeren den ALTEN Zustand und zitieren ihn woertlich
    /// („.limit(80)", „bool _groupRadiusEnabled = false;"). Ohne dieses
    /// Ausblenden wuerde der Test seine eigene Begruendung als Fund werten.
    String ohneKommentare(String quelle) => quelle
        .split('\n')
        .where((zeile) {
          final t = zeile.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join('\n');

    setUpAll(() {
      service = ohneKommentare(
        File('lib/data/services/social_service.dart').readAsStringSync(),
      );
      page = ohneKommentare(
        File('lib/presentation/pages/community_page.dart').readAsStringSync(),
      );
    });

    test('die Entdecken-Liste fragt die RPC gruppen_in_der_naehe', () {
      expect(service.contains("'gruppen_in_der_naehe'"), isTrue);
      expect(service.contains("'p_radius_m'"), isTrue);
      expect(service.contains("'p_limit'"), isTrue);
    });

    test(
      'das entfernungsblinde limit(80) steht nur noch im Rückfallweg',
      () {
        final anfang = service.indexOf('getDiscoverGroups({');
        final alterWeg = service.indexOf('_getDiscoverGroupsAlterWeg({');
        expect(anfang, greaterThan(0));
        expect(alterWeg, greaterThan(anfang));

        // Der Hauptweg reicht vom Kopf von getDiscoverGroups bis zum Kopf des
        // Rueckfallwegs. Dort darf kein entfernungsblindes Abschneiden mehr
        // stehen — genau das war der gemessene Fehler.
        final hauptweg = service.substring(anfang, alterWeg);
        expect(hauptweg.contains('.limit(80)'), isFalse);
        expect(hauptweg.contains('.take(40)'), isFalse);

        // Im Rueckfallweg darf es bleiben: ohne die RPC ist eine
        // entfernungsblinde Liste immer noch besser als eine leere.
        expect(service.substring(alterWeg).contains('.limit(80)'), isTrue);
      },
    );

    test(
      'die Oberfläche filtert nicht noch einmal, wenn der Server schon '
      'gefiltert hat — sonst fielen Gruppen ohne Startpunkt raus',
      () {
        expect(
          page.contains('SocialService.umkreisServerseitigKey'),
          isTrue,
        );
        expect(page.contains('serverHatGefiltert'), isTrue);
      },
    );

    test(
      'die nach Entfernung sortierte Liste wird nicht mehr durchgemischt, '
      'solange der Filter aktiv ist',
      () {
        expect(page.contains('if (!_umkreis.aktiv) gruppen.shuffle();'), isTrue);
      },
    );

    test(
      'die Einstellung liegt nicht mehr als Widget-Feld in der Seite',
      () {
        expect(page.contains('bool _groupRadiusEnabled = false;'), isFalse);
        expect(page.contains('double _groupRadiusKm = 100;'), isFalse);
        expect(page.contains('GruppenUmkreisService.instance'), isTrue);
      },
    );

    test('das Umschalten laedt neu, sonst bliebe der alte Ausschnitt', () {
      final stelle = page.indexOf('Future<void> _setzeUmkreisAktiv(');
      expect(stelle, greaterThan(0));
      final block = page.substring(stelle, stelle + 400);
      expect(block.contains('_loadData()'), isTrue);
    });

    test('Umlaute ausgeschrieben, keine Gedankenstriche im Nutzertext', () {
      expect(page.contains('Stell den Umkreis größer'), isTrue);
      expect(page.contains('Umkreis groesser'), isFalse);
    });
  });
}
