import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:cruise_connect/data/services/saved_routes_cache_service.dart';

/// 2026-08-31 — Vucko: „wenn man sich ausloggen, moechte ich nicht, dass wenn
/// ich wieder zurueck in die App gehe, dass ich noch mal die ganzen Map Daten
/// herunterladen muss in den Einstellungen weil dann kommt das Pop-up nicht
/// mehr und dann muss ich das immer machen."
///
/// DIE REGEL, die dieser Test festhaelt: Die Offlinekarte und die Zustimmung
/// dazu gehoeren dem GERAET. Sie belegen mehrere Gigabyte auf genau diesem
/// Handy; welches Konto gerade angemeldet ist, hat damit nichts zu tun.
///
/// DIE FALLE, gegen die er gebaut ist: Seit dem 24.08. haengen viele
/// Einstellungen ueber [NutzerPrefsSchluessel] am Konto — richtig fuer die
/// Kachel-Anordnung, den Startseiten-Schnappschuss und den Tutorial-Stand.
/// Wuerde jemand die beiden Kartenschluessel „der Ordnung halber" mit
/// umstellen, waere die Wirkung fuer den Nutzer verheerend und im Code kaum
/// zu sehen: nach jedem Abmelden gilt die Zustimmung als nie gegeben, die
/// Frage kommt aber trotzdem nicht wieder (das Blatt kommt nur einmal), und
/// der Download beginnt von vorn. Genau das beschreibt Vucko oben.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
  });

  tearDown(() {
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
  });

  test(
    'Zustimmung und Wahl liegen unter dem geraeteweiten Schluessel, nicht am '
    'Konto',
    () async {
      // Ein angemeldetes Konto vortaeuschen. Wuerde der Dienst durch
      // NutzerPrefsSchluessel gehen, bekaemen die Werte jetzt ein
      // `::<Konto>` angehaengt.
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-eins';

      await MapStyleService.instance.setAutoDownloadPolicy(
        MapAutoDownloadPolicy.wifiAndMobile,
      );
      await MapStyleService.instance.markAutoDownloadPromptSeen();

      final prefs = await SharedPreferences.getInstance();
      for (final schluessel in MapStyleService.geraeteSchluessel) {
        expect(
          prefs.containsKey(schluessel),
          isTrue,
          reason:
              '$schluessel muss unter dem geraeteweiten Namen liegen. Liegt '
              'er am Konto, faengt der mehrere Gigabyte grosse Download nach '
              'jedem Abmelden von vorn an.',
        );
        expect(
          prefs.getKeys().any((k) => k.startsWith('$schluessel::')),
          isFalse,
          reason: '$schluessel darf keine Kontokennung tragen.',
        );
      }
    },
  );

  test('das Abmelden raeumt die Kartenschluessel nicht mit weg', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MapStyleService.autoDownloadPolicyKey: 'wifiOnly',
      MapStyleService.autoDownloadPromptSeenKey: true,
      SavedRoutesCacheService.legacyCacheKey: '[]',
      SavedRoutesCacheService.cacheKeyForUser('konto-eins'): '[]',
    });

    // Das ist der einzige lokale Aufraeumschritt, den AuthService.signOut
    // ausfuehrt. Alles Weitere dort ist Supabase und Google.
    await SavedRoutesCacheService.clearAll();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MapStyleService.autoDownloadPolicyKey),
      'wifiOnly',
      reason: 'Die getroffene Wahl muss das Abmelden ueberleben.',
    );
    expect(
      prefs.getBool(MapStyleService.autoDownloadPromptSeenKey),
      isTrue,
      reason:
          'Die beantwortete Zustimmungsfrage muss das Abmelden ueberleben — '
          'sonst wartet der Automatik-Pfad auf eine Antwort, die nie wieder '
          'abgefragt wird.',
    );
    // Und das, was dem KONTO gehoert, ist trotzdem weg.
    expect(
      prefs.containsKey(SavedRoutesCacheService.cacheKeyForUser('konto-eins')),
      isFalse,
    );
  });

  test(
    'signOut stoesst den Kartendownload wieder an und loescht keine '
    'Geraetewerte',
    () {
      // Quelltextpruefung statt Netzaufruf: signOut braucht Supabase, laesst
      // sich hier also nicht ausfuehren. Nachgewiesen wird deshalb, dass in
      // dieser Methode nur der kontogebundene Zwischenspeicher geleert wird.
      final quelle = File(
        'lib/data/services/auth_service.dart',
      ).readAsStringSync();
      final start = quelle.indexOf('static Future<void> signOut() async {');
      expect(start, greaterThan(0), reason: 'signOut nicht gefunden.');
      final rumpf = quelle.substring(
        start,
        quelle.indexOf('\n  }', start) + 4,
      );

      expect(rumpf.contains('SavedRoutesCacheService.clearAll()'), isTrue);
      expect(
        rumpf.contains('ensureAutoDownloadScheduled'),
        isTrue,
        reason:
            'Eine angefangene Offlinekarte muss auch ohne angemeldetes Konto '
            'weiterladen.',
      );
      for (final schluessel in MapStyleService.geraeteSchluessel) {
        expect(
          rumpf.contains(schluessel),
          isFalse,
          reason: 'signOut darf $schluessel nicht anfassen.',
        );
      }
      expect(
        rumpf.contains('deleteOffline'),
        isFalse,
        reason: 'Die geladene Karte darf das Abmelden nicht loeschen.',
      );
      expect(
        rumpf.contains('prefs.clear()'),
        isFalse,
        reason:
            'Ein pauschales Leeren der Einstellungen wuerde alle '
            'Geraetewerte mitnehmen.',
      );
    },
  );
}
