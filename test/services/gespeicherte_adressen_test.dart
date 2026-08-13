import 'dart:io';

import 'package:cruise_connect/data/services/gespeicherte_adressen_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-14 (vucko, P4): „Beim A-nach-B-Modus will ich, dass man Adressen
/// speichern kann für Schnellsuche."
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dienst = GespeicherteAdressenService.instance;

  GespeicherteAdresse adresse({
    String label = 'Zuhause',
    double lat = 47.2692,
    double lng = 9.6041,
  }) => GespeicherteAdresse(
    label: label,
    placeName: 'Feldkirch, Vorarlberg, Österreich',
    latitude: lat,
    longitude: lng,
    context: 'Vorarlberg',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
  });

  test('Speichern und Laden ueberleben den Neustart', () async {
    await dienst.load();
    await dienst.speichern(adresse());

    dienst.resetForTests();
    await dienst.load();
    expect(dienst.alle, hasLength(1));
    expect(dienst.alle.first.label, 'Zuhause');
    expect(dienst.alle.first.latitude, closeTo(47.2692, 1e-9));
  });

  test('gleicher Ort ersetzt statt dupliziert', () async {
    await dienst.load();
    await dienst.speichern(adresse(label: 'Alt'));
    await dienst.speichern(adresse(label: 'Neu'));
    expect(dienst.alle, hasLength(1));
    expect(dienst.alle.first.label, 'Neu');
  });

  test('beim Ueberlauf fliegt der aelteste Eintrag', () async {
    await dienst.load();
    for (var i = 0; i < 12; i++) {
      await dienst.speichern(adresse(label: 'Ort $i', lat: 47.0 + i * 0.1));
    }
    expect(dienst.alle, hasLength(GespeicherteAdressenService.maxEintraege));
    expect(
      dienst.alle.first.label,
      'Ort 2',
      reason: 'Ort 0 und Ort 1 sind verdraengt',
    );
  });

  test('entfernen und umbenennen', () async {
    await dienst.load();
    await dienst.speichern(adresse());
    await dienst.umbenennen(dienst.alle.first, 'Daheim');
    expect(dienst.alle.first.label, 'Daheim');
    await dienst.entfernen(dienst.alle.first);
    expect(dienst.alle, isEmpty);
  });

  test('korruptes JSON legt den Dienst nicht lahm', () async {
    SharedPreferences.setMockInitialValues({
      'gespeicherte_adressen_v1': '{kaputt',
    });
    await dienst.load();
    expect(dienst.alle, isEmpty);
    // Und Speichern funktioniert danach trotzdem.
    await dienst.speichern(adresse());
    expect(dienst.alle, hasLength(1));
  });

  test('zuVorschlag liefert Mapbox-Reihenfolge [lng, lat]', () {
    final v = adresse().zuVorschlag();
    expect(v.coordinates[0], closeTo(9.6041, 1e-9), reason: 'longitude zuerst');
    expect(v.coordinates[1], closeTo(47.2692, 1e-9));
    expect(v.placeName, contains('Feldkirch'));
  });

  group('Verdrahtung in der Setup-Karte', () {
    late String karte;
    setUpAll(() {
      karte = File(
        'lib/presentation/widgets/cruise/cruise_setup_card.dart',
      ).readAsStringSync();
    });

    test('der Chip nimmt denselben Pfad wie ein Suchtreffer', () {
      expect(
        karte.contains('widget.onDestinationSelected(adresse.zuVorschlag())'),
        isTrue,
        reason:
            'nur so verhalten sich Einzel-Cruise UND Gruppe automatisch '
            'gleich — beide Seiten reichen onDestinationSelected durch',
      );
    });

    test('der Stern sitzt auf der Zielkarte', () {
      expect(karte.contains('_zielMerkenUmschalten'), isTrue);
      expect(karte.contains("'Ziel merken'"), isTrue);
    });

    test('ohne Favoriten kein toter Platz', () {
      expect(
        karte.contains('if (adressen.isEmpty) return const SizedBox.shrink();'),
        isTrue,
      );
    });
  });
}
