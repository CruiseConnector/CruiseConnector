import 'dart:async';

import 'package:cruise_connect/data/services/location_permission_helper.dart';
import 'package:cruise_connect/presentation/widgets/location_always_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/notification_permission_notice_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24 (Vucko, nach dem eingesperrten Nutzer auf dem iPhone 15 Pro Max):
/// „schau das es bei keinem Handy sich aufhaengen kann".
///
/// Diese Datei stellt die beiden Berechtigungs-Blaetter nach, die dieselbe
/// Bauart hatten wie die gemeldete Sackgasse: ein Blatt ohne Wisch- und
/// Tipp-Ausweg, aus dem genau EIN Weg herausfuehrte — und dieser Weg hing an
/// einer Antwort des Betriebssystems.
///
/// Das Standort-Blatt war das gefaehrlichere der beiden, weil es direkt nach
/// der Anmeldung automatisch aufgeht (`home_page.dart`, `_runFirstLoginGuidance`).
/// Es setzte `_busy = true`, rief zweimal `Geolocator.requestPermission()` ohne
/// jede Zeitgrenze und setzte `_busy` erst danach zurueck. Auf iOS ist die
/// Hochstufung auf „Immer" genau der Fall, der spaet oder nie beantwortet wird.
/// Ergebnis: `_busy` blieb fuer immer `true`, ALLE Knoepfe grau — auch der
/// Ausweg „Später" —, kein Wischen, kein Tippen daneben, auf iOS kein Zurueck.
///
/// Die Tests hier brauchen KEINE Test-Naht im Widget: sie tauschen die
/// Geolocator-Plattform aus und stellen damit exakt das her, was auf dem Geraet
/// passiert — ein Berechtigungs-Aufruf, der nie zurueckkommt, und einer, der
/// wirft. Sie liefen deshalb schon gegen die alte Fassung und waren dort rot.
void main() {
  final echteGeolocator = geo.GeolocatorPlatform.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    geo.GeolocatorPlatform.instance = echteGeolocator;
  });

  group('Standort-Blatt', () {
    testWidgets('Der Ausweg ist schon im ersten Bild da und ist bedienbar', (
      tester,
    ) async {
      geo.GeolocatorPlatform.instance = _FakeGeolocator();
      await _oeffneStandortBlatt(tester);

      expect(
        find.text('Später entscheiden'),
        findsOneWidget,
        reason:
            'Vor dem Fix erschien der Ausweg erst im ZWEITEN Schritt — also '
            'erst nach einer Antwort des Systems. Kam die nie, gab es nie '
            'einen Ausweg.',
      );
      expect(
        _istBedienbar(tester, 'Später entscheiden'),
        isTrue,
        reason: 'Der Ausweg darf nie gesperrt sein.',
      );
    });

    testWidgets(
      'System antwortet NIE: der Nutzer kommt trotzdem aus dem Blatt heraus',
      (tester) async {
        // Genau der gemeldete Fall: der Plattform-Aufruf kehrt nie zurueck.
        final nieEineAntwort = Completer<geo.LocationPermission>();
        geo.GeolocatorPlatform.instance = _FakeGeolocator(
          beiAnfrage: () => nieEineAntwort.future,
        );
        final ergebnis = await _oeffneStandortBlatt(tester);

        await tester.tap(find.text('Weiter'));
        await tester.pump();

        // Vorbedingung: das Blatt wartet wirklich (Knopf zeigt den Spinner).
        expect(
          find.byType(CupertinoActivityIndicator),
          findsOneWidget,
          reason: 'Der Test soll den Wartezustand pruefen.',
        );

        expect(
          _istBedienbar(tester, 'Später entscheiden'),
          isTrue,
          reason:
              'ALLE Knoepfe hingen an `_busy` — auch der Ausweg. Genau so sass '
              'der Nutzer fest.',
        );

        await tester.tap(find.text('Später entscheiden'));
        await tester.pumpAndSettle();

        expect(
          find.byType(LocationAlwaysNoticeSheet),
          findsNothing,
          reason:
              'Der Ausweg muss ohne jede Antwort des Systems funktionieren.',
        );
        expect(ergebnis.wert, isNotNull, reason: 'Das Blatt hat sich beendet.');

        // Wachhunde auslaufen lassen, sonst meldet der Test „pending timer".
        await tester.pump(_grosszuegig);
      },
    );

    testWidgets(
      'System antwortet NIE: nach der Zeitgrenze ist der Knopf wieder frei',
      (tester) async {
        final nieEineAntwort = Completer<geo.LocationPermission>();
        geo.GeolocatorPlatform.instance = _FakeGeolocator(
          beiAnfrage: () => nieEineAntwort.future,
        );
        await _oeffneStandortBlatt(tester);

        await tester.tap(find.text('Weiter'));
        await tester.pump();
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

        await tester.pump(_grosszuegig);

        expect(
          find.byType(CupertinoActivityIndicator),
          findsNothing,
          reason:
              '`_busy` muss nach der Zeitgrenze zurueckgesetzt sein — vorher '
              'blieb es fuer immer true.',
        );
        expect(
          find.textContaining('Das System hat nicht geantwortet'),
          findsOneWidget,
          reason:
              'Ehrlich sagen, was los ist, statt still weiter grau zu bleiben.',
        );
        expect(_istBedienbar(tester, 'Nochmal versuchen'), isTrue);
        expect(_istBedienbar(tester, 'Später entscheiden'), isTrue);
      },
    );

    testWidgets('Berechtigungs-Aufruf wirft: kein stiller Falschzustand', (
      tester,
    ) async {
      geo.GeolocatorPlatform.instance = _FakeGeolocator(
        beiAnfrage: () => Future<geo.LocationPermission>.error(
          const _KanalKaputt('Kanal antwortet nicht'),
        ),
      );
      await _oeffneStandortBlatt(tester);

      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(CupertinoActivityIndicator),
        findsNothing,
        reason:
            '`_busy` gehoert in ein `finally` — sonst haelt ein Fehler fest.',
      );
      expect(
        find.textContaining('Das System hat nicht geantwortet'),
        findsOneWidget,
        reason:
            'Vorher landete der Nutzer im Einstellungs-Schritt mit dem Satz '
            '„Du hast den Standort nur Beim Verwenden freigegeben" — das ist '
            'schlicht gelogen, wenn der Aufruf gar nicht durchkam.',
      );
      expect(_istBedienbar(tester, 'Später entscheiden'), isTrue);

      await tester.pump(_grosszuegig);
    });

    testWidgets(
      'Die Zeitgrenze laeuft NICHT, waehrend der System-Dialog offen ist',
      (tester) async {
        // Waehrend iOS/Android den Berechtigungs-Dialog zeigen, ist unsere App
        // nicht mehr vorne. Der Nutzer darf sich dort so viel Zeit lassen wie
        // er will — eine Zeitgrenze, die dabei zuschlaegt, wuerde ihn aus
        // seiner eigenen Entscheidung werfen.
        final nieEineAntwort = Completer<geo.LocationPermission>();
        geo.GeolocatorPlatform.instance = _FakeGeolocator(
          beiAnfrage: () => nieEineAntwort.future,
        );
        await _oeffneStandortBlatt(tester);

        await tester.tap(find.text('Weiter'));
        await tester.pump();

        await _lebenszustand(tester, AppLifecycleState.inactive);
        await tester.pump(_grosszuegig);
        await tester.pump(_grosszuegig);

        expect(
          find.byType(CupertinoActivityIndicator),
          findsOneWidget,
          reason:
              'Der Nutzer steht im System-Dialog. Hier abzubrechen waere '
              'falsch — die Uhr muss stillstehen, solange wir nicht vorne sind.',
        );

        await _lebenszustand(tester, AppLifecycleState.resumed);
        await tester.pump(_grosszuegig);

        expect(
          find.byType(CupertinoActivityIndicator),
          findsNothing,
          reason:
              'Zurueck im Vordergrund und immer noch keine Antwort: JETZT ist '
              'es ein Haenger und die Zeitgrenze muss greifen.',
        );
      },
    );
  });

  group('LocationPermissionHelper', () {
    // Der Helfer wird auch beim Start einer Gruppenfahrt benutzt
    // (`cruise_mode_page.dart`). Dort wartet ebenfalls jemand auf die Antwort.
    testWidgets('requestAlways haengt nicht, wenn das System nie antwortet', (
      tester,
    ) async {
      geo.GeolocatorPlatform.instance = _FakeGeolocator(
        beiAnfrage: () => Completer<geo.LocationPermission>().future,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      geo.LocationPermission? antwort;
      unawaited(
        LocationPermissionHelper.requestAlways(
          openSettingsIfNeeded: false,
        ).then((p) => antwort = p),
      );

      await tester.pump();
      expect(
        antwort,
        isNull,
        reason: 'Vorbedingung: es antwortet noch nichts.',
      );

      await tester.pump(_grosszuegig);
      expect(
        antwort,
        geo.LocationPermission.unableToDetermine,
        reason:
            'Keine Antwort ist NICHT dasselbe wie „abgelehnt" — und vor allem '
            'darf der Aufruf nicht ewig offen bleiben.',
      );
    });

    testWidgets('requestAlways wirft nie, auch wenn der Kanal kaputt ist', (
      tester,
    ) async {
      geo.GeolocatorPlatform.instance = _FakeGeolocator(
        beiAnfrage: () => Future<geo.LocationPermission>.error(
          const _KanalKaputt('Kanal antwortet nicht'),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      // Wuerde hier etwas fliegen, faellt der Test ueber den unbehandelten
      // Fehler — genau das passierte vorher im Gruppen-Zweig.
      final antwort = await LocationPermissionHelper.requestAlways(
        openSettingsIfNeeded: false,
      );
      expect(antwort, geo.LocationPermission.unableToDetermine);
    });
  });

  group('Mitteilungs-Blatt', () {
    testWidgets('Es gibt einen zweiten Ausgang und beide sind nie gesperrt', (
      tester,
    ) async {
      final ergebnis = await _oeffneMitteilungsBlatt(tester);

      expect(
        find.text('Jetzt nicht'),
        findsOneWidget,
        reason:
            'Vorher fuehrte genau EIN Knopf heraus, und der hing an `_busy`, '
            'das erst nach einem Schreibzugriff auf den Geraetespeicher wieder '
            'freigegeben wurde.',
      );
      expect(_istBedienbar(tester, 'Jetzt nicht'), isTrue);
      expect(_istBedienbar(tester, 'Weiter'), isTrue);

      await tester.tap(find.text('Jetzt nicht'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationPermissionNoticeSheet), findsNothing);
      expect(
        ergebnis.wert,
        isFalse,
        reason: '„Jetzt nicht" darf keine Mitteilungs-Anfrage ausloesen.',
      );
    });

    testWidgets('„Weiter" schliesst sofort, nicht erst nach dem Speicher', (
      tester,
    ) async {
      final ergebnis = await _oeffneMitteilungsBlatt(tester);

      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(NotificationPermissionNoticeSheet), findsNothing);
      expect(ergebnis.wert, isTrue);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Werkzeuge
// ═══════════════════════════════════════════════════════════════════════════

/// Deutlich mehr als jede Zeitgrenze im Blatt (die groesste ist heute 20 s) —
/// damit auch die Wachhunde sicher ausgelaufen sind, wenn ein Test endet.
/// Bewusst eine feste Zahl statt der Konstante aus dem Helfer: so laesst sich
/// diese Datei unveraendert gegen die ALTE Fassung laufen (Gegenprobe).
const Duration _grosszuegig = Duration(seconds: 60);

/// Sammelt das Ergebnis des Blattes, damit der Test es nach dem Schliessen
/// nachschauen kann.
class _Ergebnis {
  bool? wert;
}

class _KanalKaputt implements Exception {
  const _KanalKaputt(this.text);
  final String text;
  @override
  String toString() => 'KanalKaputt: $text';
}

/// Geolocator-Plattform, die sich wie ein haengendes oder kaputtes System
/// verhaelt. Kein Method-Channel, keine Test-Naht im Widget noetig.
class _FakeGeolocator extends geo.GeolocatorPlatform {
  _FakeGeolocator({this.beiAnfrage, this.dienstAn = true, this.stand});

  /// Was `requestPermission()` tut. Standard: sofort „nur beim Verwenden".
  final Future<geo.LocationPermission> Function()? beiAnfrage;
  final bool dienstAn;

  /// Was `checkPermission()` liefert. Standard: noch nichts erteilt.
  final geo.LocationPermission? stand;

  @override
  Future<bool> isLocationServiceEnabled() async => dienstAn;

  @override
  Future<geo.LocationPermission> checkPermission() async =>
      stand ?? geo.LocationPermission.denied;

  @override
  Future<geo.LocationPermission> requestPermission() =>
      beiAnfrage?.call() ??
      Future<geo.LocationPermission>.value(geo.LocationPermission.whileInUse);

  @override
  Future<bool> openAppSettings() async => true;
}

Future<_Ergebnis> _oeffneStandortBlatt(WidgetTester tester) async {
  final ergebnis = _Ergebnis();
  await _oeffne(
    tester,
    ergebnis,
    (context) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LocationAlwaysNoticeSheet(),
    ),
  );
  return ergebnis;
}

Future<_Ergebnis> _oeffneMitteilungsBlatt(WidgetTester tester) async {
  final ergebnis = _Ergebnis();
  await _oeffne(
    tester,
    ergebnis,
    (context) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationPermissionNoticeSheet(),
    ),
  );
  return ergebnis;
}

/// Baut eine echte Seite mit echtem Navigator und oeffnet das Blatt darueber —
/// nur so laesst sich pruefen, ob der Ausweg das Blatt WIRKLICH schliesst.
Future<void> _oeffne(
  WidgetTester tester,
  _Ergebnis ergebnis,
  Future<bool?> Function(BuildContext context) zeigen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => ergebnis.wert = await zeigen(context),
              child: const Text('Blatt oeffnen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Blatt oeffnen'));
  await tester.pumpAndSettle();
}

/// Gibt es einen Knopf mit dieser Beschriftung, den der Nutzer JETZT druecken
/// kann? `find.byType` vergleicht den exakten Laufzeittyp, deshalb ueber die
/// Vorfahren des Textes suchen.
bool _istBedienbar(WidgetTester tester, String beschriftung) {
  final knopf = find.ancestor(
    of: find.text(beschriftung),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton && w.onPressed != null,
    ),
  );
  return knopf.evaluate().isNotEmpty;
}

/// Schickt den Lebenszustand ueber denselben Kanal wie das echte System.
Future<void> _lebenszustand(
  WidgetTester tester,
  AppLifecycleState zustand,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(zustand.toString()),
    (_) {},
  );
  await tester.pump();
}
