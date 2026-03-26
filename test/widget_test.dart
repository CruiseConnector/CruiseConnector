// CruiseConnect – Widget Smoke Tests
//
// Diese Tests prüfen die reinen UI-Widgets ohne Supabase-Verbindung.
// Für echte Integrationstests wäre ein Supabase Mock notwendig.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/widgets/my_button.dart';
import 'package:cruise_connect/presentation/widgets/textfeld.dart';

void main() {
  group('MyButton', () {
    testWidgets('rendert korrekt und reagiert auf Tap', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyButton(onTap: () => tapped = true),
          ),
        ),
      );

      // Button ist sichtbar
      expect(find.byType(MyButton), findsOneWidget);

      // Tap funktioniert
      await tester.tap(find.byType(MyButton));
      expect(tapped, isTrue);
    });

    testWidgets('onTap null ist sicher (kein Crash)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MyButton(onTap: null),
          ),
        ),
      );
      expect(find.byType(MyButton), findsOneWidget);
      // Kein Crash erwartet beim Tap auf disabled Button
      await tester.tap(find.byType(MyButton), warnIfMissed: false);
    });
  });

  group('Textfeld', () {
    testWidgets('zeigt Hint-Text korrekt an', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Textfeld(
              controller: controller,
              hintText: 'E-Mail eingeben',
              obscureText: false,
            ),
          ),
        ),
      );

      expect(find.text('E-Mail eingeben'), findsOneWidget);
    });

    testWidgets('obscureText versteckt Eingabe', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Textfeld(
              controller: controller,
              hintText: 'Passwort',
              obscureText: true,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);
    });
  });
}
