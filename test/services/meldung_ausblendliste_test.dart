import 'dart:io';

import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-28 (Abnahmefund zu Fehler 10): Wer eine Baustelle als weg meldet,
/// sieht sie selbst nicht mehr. Diese Liste MUSS am Konto haengen, nicht am
/// Geraet.
///
/// Der Fund: Meldet A auf einem Handy eine Baustelle als weg und meldet sich
/// danach B auf demselben Handy an (Testgeraet, Familienauto, zweites Konto),
/// bekam B diese Baustelle nie zu sehen — keinen Marker, keine Vorwarnung,
/// keine Nachfrage. Und zwar bei einer Warnung, die serverseitig noch aktiv
/// ist. Abmelden loescht die SharedPreferences nicht, und der Service ist ein
/// Singleton, dessen Zwischenspeicher den Kontowechsel ueberlebt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const basis = 'road_incidents_selbst_weggemeldet_v1';

  tearDown(() => NutzerPrefsSchluessel.nutzerIdFuerTests = null);

  test('zwei Konten auf einem Geraet teilen die Liste NICHT', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // A blendet eine Meldung aus.
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-a';
    await prefs.setStringList(
      NutzerPrefsSchluessel.fuer(basis),
      <String>['meldung-1'],
    );

    // B sieht davon nichts.
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-b';
    expect(
      prefs.getStringList(NutzerPrefsSchluessel.fuer(basis)),
      isNull,
      reason:
          'Die Ausblendliste von A darf bei B keine aktive Warnung '
          'verschlucken.',
    );

    // Und A behaelt seine.
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-a';
    expect(
      prefs.getStringList(NutzerPrefsSchluessel.fuer(basis)),
      <String>['meldung-1'],
    );
  });

  test('ohne Anmeldung bleibt es beim kontolosen Schluessel', () {
    NutzerPrefsSchluessel.nutzerIdFuerTests = () => null;
    expect(NutzerPrefsSchluessel.fuer(basis), basis);
  });

  test('Quelltext-Waechter: der Service fuehrt die Liste kontogebunden', () {
    final quelle = File(
      'lib/data/services/road_incident_service.dart',
    ).readAsStringSync();

    expect(
      quelle.contains('NutzerPrefsSchluessel.fuer('),
      isTrue,
      reason:
          'Die Ausblendliste muss ueber NutzerPrefsSchluessel laufen, sonst '
          'gilt sie wieder fuer alle Konten des Geraets.',
    );
    // Der Zwischenspeicher darf einen Kontowechsel im laufenden Prozess nicht
    // ueberleben: der Service ist ein Singleton.
    expect(
      quelle.contains('_cacheGehoertZu'),
      isTrue,
      reason:
          'Ohne Kontopruefung am Zwischenspeicher wirkt die Liste des '
          'Vorgaengers weiter, bis die App neu startet.',
    );
  });
}
