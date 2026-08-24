import 'dart:async';

import 'package:cruise_connect/presentation/widgets/location_always_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/notification_permission_notice_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24: Zweiter Teil der Absicherung fuer die beiden Berechtigungs-
/// Blaetter. Waehrend `berechtigungs_blatt_kein_einsperren_test.dart` den
/// gemeldeten Vorfall selbst nachstellt (System antwortet nie), pruefen die
/// Tests hier die uebrigen Stellen, an denen dasselbe Muster steckte:
///
///  * der Geraetespeicher haengt — er ist ein Plattform-Kanal wie jeder andere
///    und kann bei voller Platte oder fehlendem Plugin ewig brauchen,
///  * die App-Einstellungen gehen nicht auf,
///  * die Antwort des Systems kommt erst NACH der Zeitgrenze.
///
/// Dafuer gehen die Blaetter ueber ihre Test-Naehte auf. Die Regel, die hier
/// verteidigt wird: der Ausgang haengt an NICHTS — nicht am Netz, nicht an
/// einer Berechtigung, nicht am Speicher, nicht am System.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'Standort-Blatt: haengender Geraetespeicher haelt den Ausweg nicht auf',
    (tester) async {
      final nieFertig = Completer<void>();
      final ergebnis = await _oeffne(
        tester,
        LocationAlwaysNoticeSheet(hinweisMerken: () => nieFertig.future),
      );

      await tester.tap(find.text('Später entscheiden'));
      await tester.pumpAndSettle();

      expect(
        find.byType(LocationAlwaysNoticeSheet),
        findsNothing,
        reason:
            'Erst schliessen, dann merken. Wer vor dem `pop` auf den Speicher '
            'wartet, sperrt den Nutzer ein, sobald der Speicher haengt.',
      );
      expect(ergebnis.wert, isTrue);

      // Zeitgrenze des Speicher-Schreibens auslaufen lassen.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'Standort-Blatt: haengender Speicher blockiert auch „Weiter" nicht',
    (tester) async {
      final nieFertig = Completer<void>();
      await _oeffne(
        tester,
        LocationAlwaysNoticeSheet(
          hinweisMerken: () => nieFertig.future,
          freigabeAnfragen: () async => geo.LocationPermission.whileInUse,
          antwortGrenze: const Duration(seconds: 2),
        ),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(CupertinoActivityIndicator),
        findsNothing,
        reason:
            'Der Merker wird nebenher geschrieben — vorher stand er als '
            'erstes `await` in `_acceptPermission`, noch vor dem `try`.',
      );
      expect(find.text('In den Einstellungen öffnen'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'Standort-Blatt: Einstellungen gehen nicht auf → kein Stillstand',
    (tester) async {
      final gehenNichtAuf = Completer<bool>();
      await _oeffne(
        tester,
        LocationAlwaysNoticeSheet(
          freigabeAnfragen: () async => geo.LocationPermission.whileInUse,
          einstellungenOeffnen: () => gehenNichtAuf.future,
          hinweisMerken: () async {},
          antwortGrenze: const Duration(seconds: 2),
        ),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('In den Einstellungen öffnen'));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      // Der Ausweg bleibt bedienbar, WAEHREND wir warten.
      expect(
        _istBedienbar(tester, 'Später, mit „Beim Verwenden" fahren'),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 12));

      expect(
        find.byType(CupertinoActivityIndicator),
        findsNothing,
        reason: 'Auch ein haengender Einstellungs-Aufruf muss auslaufen.',
      );
      expect(
        find.textContaining('Das System hat nicht geantwortet'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Standort-Blatt: spaete „Immer"-Antwort wird noch angenommen', (
    tester,
  ) async {
    // Eine Zeitgrenze bricht den Plattform-Aufruf nicht ab. Antwortet das
    // System spaeter doch noch mit „Immer", waere es unhoeflich, das
    // wegzuwerfen und den Nutzer nochmal fragen zu lassen.
    final spaeteAntwort = Completer<geo.LocationPermission>();
    final ergebnis = await _oeffne(
      tester,
      LocationAlwaysNoticeSheet(
        freigabeAnfragen: () => spaeteAntwort.future,
        hinweisMerken: () async {},
        antwortGrenze: const Duration(seconds: 2),
      ),
    );

    await tester.tap(find.text('Weiter'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(
      find.textContaining('Das System hat nicht geantwortet'),
      findsOneWidget,
      reason: 'Vorbedingung: die Zeitgrenze hat zugeschlagen.',
    );

    spaeteAntwort.complete(geo.LocationPermission.always);
    await tester.pumpAndSettle();

    expect(find.byType(LocationAlwaysNoticeSheet), findsNothing);
    expect(ergebnis.wert, isTrue);
  });

  testWidgets(
    'Mitteilungs-Blatt: haengender Geraetespeicher haelt den Ausgang nicht auf',
    (tester) async {
      final nieFertig = Completer<void>();
      final ergebnis = await _oeffne(
        tester,
        NotificationPermissionNoticeSheet(
          hinweisMerken: ({required bool accepted}) => nieFertig.future,
        ),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(
        find.byType(NotificationPermissionNoticeSheet),
        findsNothing,
        reason:
            '`_close` schrieb erst in den Speicher und schloss danach — der '
            'einzige Knopf war waehrenddessen gesperrt.',
      );
      expect(ergebnis.wert, isTrue);

      await tester.pump(const Duration(seconds: 5));
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Werkzeuge
// ═══════════════════════════════════════════════════════════════════════════

class _Ergebnis {
  bool? wert;
}

Future<_Ergebnis> _oeffne(WidgetTester tester, Widget blatt) async {
  final ergebnis = _Ergebnis();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  ergebnis.wert = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => blatt,
                  ),
              child: const Text('Blatt oeffnen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Blatt oeffnen'));
  await tester.pumpAndSettle();
  return ergebnis;
}

bool _istBedienbar(WidgetTester tester, String beschriftung) {
  final knopf = find.ancestor(
    of: find.text(beschriftung),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton && w.onPressed != null,
    ),
  );
  return knopf.evaluate().isNotEmpty;
}
