import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget seite() => ChangeNotifierProvider(
    create: (_) => AppAccentProvider(),
    child: const MaterialApp(
      home: CreateGroupPage(disableMapTilesForTesting: true),
    ),
  );

  testWidgets('schnelles Hin und Her waehrend der Animation', (tester) async {
    await tester.pumpWidget(seite());
    await tester.pump();

    await tester.tap(find.byTooltip('Karte im Vollbild'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byTooltip('Einstellungen zeigen'));
    await tester.pump(const Duration(milliseconds: 60));

    final anzahlScrollViews = find.byType(CustomScrollView).evaluate().length;
    debugPrint('CustomScrollViews gleichzeitig: $anzahlScrollViews');

    await tester.pumpAndSettle();
    debugPrint('Exception: ${tester.takeException()}');
  });
}
