import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): Onboarding-Schritt „Finde Mitfahrer".
///
/// Der Nutzer hat diese Massnahme gewaehlt, aber das Abbruchrisiko war die
/// ausdrueckliche Sorge. Diese Pruefungen halten die Entscheidungen fest, mit
/// denen genau das vermieden wird — sie liegen in der Struktur der Datei, nicht
/// im sichtbaren Verhalten, und wuerden bei einem spaeteren Umbau sonst
/// unbemerkt verlorengehen.
void main() {
  final datei = File(
    'lib/presentation/pages/onboarding/onboarding_wizard_page.dart',
  );
  late String quelle;

  setUpAll(() {
    expect(datei.existsSync(), isTrue);
    quelle = datei.readAsStringSync();
  });

  test('es kommt KEIN zusaetzlicher Schritt dazu', () {
    // Die Fortschrittsbalken oben kommen aus _steps.length. Ein zehnter Balken
    // liesse das Onboarding laenger wirken — genau das wollte der Nutzer nicht.
    final schritte = RegExp(
      r'enum _Step \{(.*?)\}',
      dotAll: true,
    ).firstMatch(quelle);
    expect(schritte, isNotNull);
    final namen = schritte!
        .group(1)!
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    expect(
      namen,
      ['welcome', 'account', 'verifyEmail', 'username', 'displayName', 'region',
        'photo', 'garage', 'finish'],
      reason: 'die Vorschlaege haengen am bestehenden Abschluss-Schritt',
    );
  });

  test('die Vorschlaege werden vorab geladen, aber nicht abgewartet', () {
    expect(
      quelle.contains('_mitfahrerVorschlaege ??= SocialService.getSuggestedUsers'),
      isTrue,
      reason: 'sonst sieht der Nutzer beim Ankommen einen Ladekringel',
    );
    // Kein await: Weiterblaettern darf nie an einer Netzabfrage haengen.
    expect(
      quelle.contains('await SocialService.getSuggestedUsers'),
      isFalse,
      reason: 'das Weiterblaettern darf nicht auf das Netz warten',
    );
  });

  test('leere Liste zeigt gar nichts statt eines leeren Kastens', () {
    final start = quelle.indexOf('Widget _mitfahrerListe(');
    expect(start, greaterThan(-1));
    final rumpf = quelle.substring(start, start + 900);
    expect(
      rumpf.contains('leute.isEmpty'),
      isTrue,
      reason: 'bei ~78 Nutzern ist die Liste oft leer',
    );
    expect(rumpf.contains('SizedBox.shrink()'), isTrue);
    expect(
      rumpf.contains('CircularProgressIndicator'),
      isFalse,
      reason: 'kein Ladekringel im Abschluss-Schritt',
    );
  });

  test('Folgen scheitert leise', () {
    final start = quelle.indexOf('Future<void> _folgeMitfahrer(');
    expect(start, greaterThan(-1));
    final rumpf = quelle.substring(start, start + 700);
    expect(
      rumpf.contains('catch'),
      isTrue,
      reason:
          'im Onboarding jemandem eine Fehlermeldung vorzusetzen, waere der '
          'falsche Moment',
    );
    expect(rumpf.contains('_folgenLaeuft.remove'), isTrue);
  });
}
