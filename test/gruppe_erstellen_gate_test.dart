import 'dart:io';

import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-18 (Defekt 3 aus dem Produktionsbericht):
/// „Gruppe erstellen ist seit dem 14.08. tot." Gemessen: 0 Gruppen,
/// 0 Mitglieder, 0 Nachrichten in der gesamten Produktivdatenbank.
///
/// Ursache: `showGroupSafetyNoticeSheet` prüfte, ob das Tutorial abgeschlossen
/// war. Der Tutorial-Umbau vom 14.08. hat den Merkschlüssel auf
/// `app_tutorial_v2_completed` umgestellt — für jeden Bestandsnutzer leer.
/// Also lieferte die Funktion `false`, ohne das Sheet überhaupt zu zeigen,
/// und `_createGroup` brach mit einem stummen `return` ab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Ohne abgeschlossenes Tutorial erscheint der Hinweis trotzdem',
    (tester) async {
      // Bewusst NICHTS gesetzt: kein Tutorial, keine Zustimmung — genau der
      // Zustand jedes Bestandsnutzers seit dem 14.08.
      SharedPreferences.setMockInitialValues(<String, Object>{});

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      unawaitedShow(ctx);
      await tester.pumpAndSettle();

      expect(
        find.byType(GroupSafetyNoticeSheet),
        findsOneWidget,
        reason:
            'Der Sicherheitshinweis muss erscheinen. Erscheint er nicht, '
            'passiert beim Tippen auf „Gruppe erstellen" gar nichts.',
      );
    },
  );

  test('Die Tutorial-Kopplung ist aus dem Quelltext verschwunden', () {
    final quelle = File(
      'lib/presentation/widgets/group_safety_notice_sheet.dart',
    ).readAsStringSync();
    // Nur der Kommentar darf den alten Aufruf noch erwähnen, kein Code.
    final codeZeilen = quelle
        .split('\n')
        .where((z) => !z.trimLeft().startsWith('///'))
        .join('\n');
    expect(
      codeZeilen.contains('AppTutorialService'),
      isFalse,
      reason: 'Der Hinweis darf nicht davon abhängen, ob jemand das '
          'Tutorial gesehen hat.',
    );
  });

  test('Kein stummer Abbruch mehr in _createGroup', () {
    final quelle = File(
      'lib/presentation/pages/create_group_page.dart',
    ).readAsStringSync();
    expect(
      quelle.contains('if (!acceptedSafety) {\n      _showError('),
      isTrue,
      reason: 'Jeder Ausstieg aus _createGroup muss sagen, warum.',
    );
  });

  test('Der Reiter heisst jetzt „Gruppen & Fahrten"', () {
    final quelle = File(
      'lib/presentation/pages/community_page.dart',
    ).readAsStringSync();
    expect(quelle.contains(r"'Gruppen &\nFahrten'"), isTrue);
  });
}

void unawaitedShow(BuildContext ctx) {
  showGroupSafetyNoticeSheet(ctx);
}
