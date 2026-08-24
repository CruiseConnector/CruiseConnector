import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

/// Was passiert, wenn der Speicher kaputt ist?
///
/// Hier haengt ein Speicher darunter, der bei JEDEM Zugriff wirft — Platte
/// voll, Plugin fehlt, Nutzerprofil kaputt. Anforderung: der Nutzer bleibt in
/// jedem dieser Faelle handlungsfaehig. Das Blatt darf weder haengenbleiben
/// noch im Ladekringel einfrieren.
///
/// Frueher lief `markAccepted()` ungeschuetzt: warf SharedPreferences, blieb
/// `_saving` auf true stehen — Dauer-Ladekringel, kein Ausgang.
void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _KaputterSpeicher();
    RoutingOnboardingService.releaseLock();
  });

  test(
    'hasAccepted wirft nicht, sondern meldet „noch nicht gelesen"',
    () async {
      expect(await RoutingOnboardingService.hasAccepted(), isFalse);
    },
  );

  test(
    'markAccepted wirft nicht und merkt die Zustimmung fuer die Sitzung',
    () async {
      // false = konnte nicht dauerhaft gespeichert werden ...
      expect(await RoutingOnboardingService.markAccepted(), isFalse);
      // ... trotzdem ist der Hinweis fuer diese Sitzung erledigt, sonst kaeme er
      // bei jedem Cruise-Aufruf erneut.
      expect(await RoutingOnboardingService.hasAccepted(), isTrue);
      await RoutingOnboardingService.reset();
      expect(await RoutingOnboardingService.hasAccepted(), isFalse);
    },
  );

  test('reset wirft nicht und gibt die Sperre frei', () async {
    expect(RoutingOnboardingService.tryAcquireLock(), isTrue);
    await RoutingOnboardingService.reset();
    expect(RoutingOnboardingService.isOpen, isFalse);
  });

  testWidgets('Blatt schliesst auch dann, wenn das Speichern fehlschlaegt', (
    tester,
  ) async {
    await RoutingOnboardingService.reset();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRoutingOnboardingSheet(context),
                child: const Text('Onboarding öffnen'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Onboarding öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Routing verstehen'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verstanden'));
    await tester.pumpAndSettle();

    // Kein Dauer-Ladekringel, kein offenes Blatt, keine haengende Sperre.
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Routing verstehen'), findsNothing);
    expect(RoutingOnboardingService.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });
}

/// Speicher, der bei jedem Zugriff wirft.
class _KaputterSpeicher extends SharedPreferencesStorePlatform {
  Never _fehler() => throw StateError('Kein Speicher verfügbar');

  @override
  Future<bool> clear() => _fehler();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) => _fehler();

  @override
  Future<Map<String, Object>> getAll() => _fehler();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _fehler();

  @override
  Future<bool> remove(String key) => _fehler();

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _fehler();
}
