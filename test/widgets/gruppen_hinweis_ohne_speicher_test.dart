import 'dart:async';

import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

/// Was passiert, wenn der Speicher kaputt ist oder haengt?
///
/// Der Gruppenfahrt-Hinweis liegt zwischen dem Knopf „Gruppe erstellen" und
/// dem Schreibvorgang. Er fragt den Speicher zweimal: vor dem Oeffnen
/// („schon zugestimmt?") und beim Zustimmen („merken"). Beide Zugriffe liefen
/// bis zum 24.08. ungeschuetzt:
///
///  * Wirft der erste, kommt der Fehler aus `_createGroup` heraus — Knopf
///    gedrueckt, nichts passiert, keine Meldung. Genau das Bild vom 18.08.
///  * Haengt der zweite, bleibt `_saving` auf true: Dauer-Ladekringel in
///    einem Blatt, das man frueher nicht schliessen konnte.
///
/// Beides darf niemanden mehr aufhalten.
void main() {
  Future<_Lauf> hinweisOeffnen(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(430, 932);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    return _Lauf(showGroupSafetyNoticeSheet(ctx));
  }

  group('Kaputter Speicher (wirft bei jedem Zugriff)', () {
    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _KaputterSpeicher();
    });

    testWidgets('Der Hinweis erscheint trotzdem — kein stummer Abbruch', (
      tester,
    ) async {
      final lauf = await hinweisOeffnen(tester);
      await tester.pumpAndSettle();

      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsOneWidget,
        reason:
            'Wirft die Speicherabfrage, muss der Hinweis trotzdem kommen. '
            'Ein durchgereichter Fehler beendet _createGroup lautlos.',
      );

      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();
      expect(await lauf.ergebnis, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zustimmen schliesst das Blatt, auch wenn nichts gespeichert '
        'werden kann', (tester) async {
      final lauf = await hinweisOeffnen(tester);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.square));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verstanden'));
      await tester.pumpAndSettle();

      expect(
        find.byType(CupertinoActivityIndicator),
        findsNothing,
        reason: 'Kein Dauer-Ladekringel',
      );
      expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
      expect(
        await lauf.ergebnis,
        isTrue,
        reason:
            'Der Nutzer hat zugestimmt. Dass wir es nicht merken konnten, '
            'ist sein Problem nicht — der Hinweis kommt eben nochmal.',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Haengender Speicher (antwortet nie)', () {
    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _HaengenderSpeicher();
    });

    testWidgets('REPRO: Der Hinweis kommt trotzdem, nach der Zeitgrenze', (
      tester,
    ) async {
      final lauf = await hinweisOeffnen(tester);
      await tester.pump();
      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsNothing,
        reason: 'Vorbedingung: der Speicher antwortet noch nicht',
      );

      // Zeitgrenze abwarten.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsOneWidget,
        reason:
            'Ohne Zeitgrenze wartet der Aufruf ewig — der Knopf „Gruppe '
            'erstellen" tut dann nie etwas.',
      );

      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();
      expect(await lauf.ergebnis, isFalse);
    });

    testWidgets('REPRO: Zustimmen bleibt nicht im Ladekringel stehen', (
      tester,
    ) async {
      final lauf = await hinweisOeffnen(tester);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.square));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verstanden'));
      await tester.pump();

      // Genau hier stand der Nutzer frueher fuer immer.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.byType(GroupSafetyNoticeSheet), findsNothing);
      expect(await lauf.ergebnis, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Haelt das noch laufende Ergebnis fest — ein `async`-Helfer koennte es
/// nicht zurueckgeben, weil Dart verschachtelte Futures faltet.
class _Lauf {
  _Lauf(this.ergebnis);

  final Future<bool> ergebnis;
}

/// Speicher, der bei jedem Zugriff wirft (Plugin fehlt, Platte voll).
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

/// Speicher, der nie antwortet — der Plattform-Kanal haengt.
class _HaengenderSpeicher extends SharedPreferencesStorePlatform {
  Future<T> _nie<T>() => Completer<T>().future;

  @override
  Future<bool> clear() => _nie();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) => _nie();

  @override
  Future<Map<String, Object>> getAll() => _nie();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _nie();

  @override
  Future<bool> remove(String key) => _nie();

  @override
  Future<bool> setValue(String valueType, String key, Object value) => _nie();
}
