import 'dart:io';

import 'package:cruise_connect/data/services/rangliste_service.dart';
import 'package:cruise_connect/presentation/widgets/home/rangliste_kachel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 6): „Auf der Startseite ein Widget mit
/// der Rangliste — Top 3, eigene Position, wöchentlich und monatlich, im
/// kleinen Quadrat oder im großen Rechteck, keine Lücken."
Map<String, dynamic> _row(int rang, String name, double km, {bool ich = false}) => {
      'rang': rang,
      'user_id': 'u$rang',
      'username': name,
      'avatar_url': null,
      'distance_km': km,
      'xp': (km * 10).round(),
      'session_count': 2,
      'is_me': ich,
    };

void main() {
  group('Rangliste.ausZeilen', () {
    test('trennt Top-N und eigene Zeile, sortiert nach Rang', () {
      final r = Rangliste.ausZeilen(RanglisteZeitraum.woche, [
        _row(7, 'ich', 12, ich: true),
        _row(2, 'b', 80),
        _row(1, 'a', 120),
        _row(3, 'c', 40),
      ]);
      expect(r.top.map((e) => e.username), ['a', 'b', 'c']);
      expect(r.ich?.rang, 7);
      expect(r.ichInTop, isFalse);
    });

    test('eigene Zeile in den Top 3 bleibt beides', () {
      final r = Rangliste.ausZeilen(RanglisteZeitraum.monat, [
        _row(1, 'a', 120),
        _row(2, 'ich', 80, ich: true),
      ]);
      expect(r.top.length, 2);
      expect(r.ichInTop, isTrue);
      expect(r.ich?.distanceKm, 80);
    });

    test('kaputte Zeilen werden uebersprungen', () {
      final r = Rangliste.ausZeilen(RanglisteZeitraum.woche, [
        {'rang': 1},
        _row(2, 'b', 5),
      ]);
      expect(r.top.length, 1);
    });
  });

  group('RanglisteKachel', () {
    Future<Rangliste?> lader(RanglisteZeitraum z) async {
      if (z == RanglisteZeitraum.woche) {
        return Rangliste.ausZeilen(z, [
          _row(1, 'mrtn', 172.4),
          _row(2, 'Vucko', 95.0, ich: true),
          _row(3, 'AK47', 28.6),
        ]);
      }
      // Monat: nur zwei Fahrer, ich auf Platz 5.
      return Rangliste.ausZeilen(z, [
        _row(1, 'mrtn', 400),
        _row(2, 'AK47', 120),
        _row(5, 'Vucko', 20, ich: true),
      ]);
    }

    testWidgets('gross: Top 3, eigene Zeile, Woche/Monat-Umschalter', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RanglisteKachel(kompakt: false, lader: lader),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rangliste'), findsOneWidget);
      expect(find.text('mrtn'), findsOneWidget);
      expect(find.text('Vucko'), findsOneWidget);
      expect(find.text('AK47'), findsOneWidget);
      expect(find.text('172 km'), findsOneWidget);
      expect(find.textContaining('Du: Platz 2'), findsOneWidget);
      // Umschalten auf Monat: Platz 3 ist frei, ich auf Platz 5.
      await tester.tap(find.byKey(const ValueKey('rangliste_monat')));
      await tester.pumpAndSettle();
      expect(find.text('Platz frei'), findsOneWidget);
      expect(find.textContaining('Du: Platz 5'), findsOneWidget);
      expect(find.text('Gefahrene Kilometer diesen Monat'), findsOneWidget);
    });

    testWidgets('klein: drei Zeilen + eigene Position auf 184 px ohne Ueberlauf', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 176,
                child: RanglisteKachel(kompakt: true, hoehe: 184, lader: lader),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'kein Overflow im Quadrat');
      expect(find.text('mrtn'), findsOneWidget);
      expect(find.textContaining('Du: Platz 2'), findsOneWidget);
      // Mini-Umschalter wechselt zu Monat.
      await tester.tap(find.byKey(const ValueKey('rangliste_mini_umschalter')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Platz frei'), findsOneWidget);
      expect(find.textContaining('Du: Platz 5'), findsOneWidget);
    });

    testWidgets('ohne Daten: „Platz frei" x3 und „noch nicht dabei"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RanglisteKachel(
              kompakt: false,
              lader: (_) async => const Rangliste(zeitraum: RanglisteZeitraum.woche, top: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Platz frei'), findsNWidgets(3));
      expect(find.textContaining('noch nicht dabei'), findsOneWidget);
    });
  });

  group('Verdrahtung', () {
    test('Dashboard kennt die Rangliste (Katalog, Standard-Layout, Builder, Einmal-Einfuegen)', () {
      final home = File('lib/presentation/pages/home_content_page.dart').readAsStringSync();
      expect(home.contains('  rangliste,\n}'), isTrue);
      expect(home.contains("title: 'Rangliste'"), isTrue);
      expect(home.contains('case _HomeWidgetId.rangliste:'), isTrue);
      expect(home.contains("key: 'rangliste',"), isTrue);
      expect(home.contains("'home_rangliste_kachel_eingefuegt_v1'"), isTrue);
    });

    test('RPC-Migration liegt im Repo (SECURITY DEFINER, Wiener Zeit, Top-N + ich)', () {
      final sql = File('supabase/migrations/20260816040000_get_rangliste.sql').readAsStringSync();
      expect(sql.contains('create or replace function public.get_rangliste('), isTrue);
      expect(sql.contains('security definer'), isTrue);
      expect(sql.contains("'Europe/Vienna'"), isTrue);
      expect(sql.contains('or is_me'), isTrue);
      expect(sql.contains('grant execute on function public.get_rangliste(text, integer) to authenticated;'), isTrue);
    });
  });
}
