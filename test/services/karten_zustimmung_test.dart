import 'dart:io';

import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-28 (Fehler 11, Vucko): "ganz wichtig, dass der Nutzer die Option
/// hat gleich am Anfang, wenn er die App installiert, dass nichts ohne seiner
/// Zustimmung gedownloadet wird."
///
/// Zwei Sorten Absicherung:
///  1. Verhalten: die dritte Stellung "aus" wird gelesen und ueberlebt.
///  2. Quelltext-Waechter: das Zustimmungs-Tor steht im Automatik-Pfad VOR
///     dem Download-Aufruf, und das Blatt setzt das Gesehen-Flag beim
///     Speichern. Faellt eines davon einem Umbau zum Opfer, wird dieser
///     Test rot, bevor ein Nutzer ungewollt Gigabytes zieht.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Politik-Stellung aus', () {
    test('wird aus den Prefs gelesen', () async {
      SharedPreferences.setMockInitialValues({
        'offline_map_auto_download_policy_v1': 'aus',
      });
      await MapStyleService.instance.loadAutoDownloadSettings();
      expect(
        MapStyleService.instance.autoDownloadPolicy,
        MapAutoDownloadPolicy.aus,
      );
    });

    test('unbekannter Wert faellt auf WLAN zurueck, nie auf aus', () {
      // Direkt gegen die Werteliste: der Rueckfall in
      // loadAutoDownloadSettings ist wifiOnly (orElse). Hier festgehalten,
      // damit niemand den Default versehentlich auf aus dreht — sonst
      // wuerden Bestandsnutzer nach einem Update still den Download
      // verlieren.
      expect(
        MapAutoDownloadPolicy.values.firstWhere(
          (p) => p.name == 'gibtsnicht',
          orElse: () => MapAutoDownloadPolicy.wifiOnly,
        ),
        MapAutoDownloadPolicy.wifiOnly,
      );
    });
  });

  group('Quelltext-Waechter', () {
    final service = File(
      'lib/data/services/map_style_service.dart',
    ).readAsStringSync();
    final blatt = File(
      'lib/presentation/widgets/map_download_preference_sheet.dart',
    ).readAsStringSync();
    final home = File(
      'lib/presentation/pages/home_page.dart',
    ).readAsStringSync();

    test('das Zustimmungs-Tor steht im Automatik-Pfad vor dem Download', () {
      final start = service.indexOf('Future<void> maybeAutoDownloadDach');
      expect(start, greaterThan(0),
          reason: 'maybeAutoDownloadDach muss existieren.');
      final rumpf = service.substring(start);
      final tor = rumpf.indexOf('hasSeenAutoDownloadPrompt');
      final ausTor = rumpf.indexOf('MapAutoDownloadPolicy.aus');
      final download = rumpf.indexOf('downloadDach(');
      expect(tor, greaterThan(0),
          reason:
              'Der Automatik-Pfad muss pruefen, ob die Zustimmungsfrage '
              'beantwortet wurde.');
      expect(ausTor, greaterThan(0),
          reason: 'Der Automatik-Pfad muss die Stellung aus respektieren.');
      expect(download, greaterThan(tor),
          reason:
              'Das Zustimmungs-Tor muss VOR dem Download-Aufruf stehen — '
              'sonst laedt die App, bevor jemand gefragt wurde.');
      expect(download, greaterThan(ausTor),
          reason: 'Auch das aus-Tor muss vor dem Download stehen.');
    });

    test('das Blatt setzt das Gesehen-Flag und laedt bei aus nichts', () {
      expect(blatt.contains('markAutoDownloadPromptSeen'), isTrue,
          reason: 'Speichern muss die Frage als beantwortet vermerken.');
      // Der Zeitplan-Aufruf darf nur unter der Bedingung != aus stehen.
      final bedingung = blatt.indexOf(
        '_policy != MapAutoDownloadPolicy.aus',
      );
      final zeitplan = blatt.indexOf('ensureAutoDownloadScheduled');
      expect(bedingung, greaterThan(0),
          reason: 'Bei aus darf kein Download angestossen werden.');
      expect(zeitplan, greaterThan(bedingung),
          reason:
              'ensureAutoDownloadScheduled muss hinter der aus-Bedingung '
              'stehen.');
      expect(blatt.contains('Keine Offlinekarte'), isTrue,
          reason: 'Die Wahl, NEIN zu sagen, muss sichtbar sein.');
    });

    test('die Startseite stellt die Frage beim ersten Oeffnen', () {
      expect(home.contains('_pruefeKartenZustimmung'), isTrue,
          reason:
              'Die Zustimmungsfrage muss am Home-Einstieg haengen — der '
              'einzige Ort, den jeder neue Nutzer sicher sieht.');
      expect(home.contains('showMapDownloadPreferenceSheet'), isTrue);
    });

    // 2026-08-28 (Abnahmefunde): zwei Ehrlichkeitsregeln, die beim ersten
    // Bauen gefehlt haben.
    test('wer die Karte schon hat, wird nicht gefragt', () {
      final start = home.indexOf('Future<void> _pruefeKartenZustimmung');
      expect(start, greaterThan(0));
      final rumpf = home.substring(start, start + 1200);
      final geprueft = rumpf.indexOf('isDachDownloaded');
      final gefragt = rumpf.indexOf('showMapDownloadPreferenceSheet');
      expect(geprueft, greaterThan(0),
          reason:
              'Ein Bestandsnutzer mit vollstaendiger Karte darf die Frage '
              'nicht sehen: sie kuendigt einen Download an, der nie kommt.');
      expect(gefragt, greaterThan(geprueft),
          reason: 'Die Pruefung muss VOR dem Blatt stehen.');
    });

    test('die Wahl aus raeumt angefangene Dateien weg', () {
      expect(blatt.contains('deleteOffline'), isTrue,
          reason:
              'Sonst bleibt eine halb geladene .part fuer immer liegen, '
              'mehrere Gigabyte, genau bei dem Nutzer, dem der Platz ausgeht.');
      final ausZweig = blatt.indexOf('MapAutoDownloadPolicy.aus');
      final loeschen = blatt.indexOf('deleteOffline');
      expect(loeschen, greaterThan(ausZweig),
          reason: 'Geloescht wird nur im aus-Zweig, nie bei einer Zusage.');
    });
  });
}
