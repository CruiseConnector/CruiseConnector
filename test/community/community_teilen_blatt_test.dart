import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/pages/community_teilen_blatt.dart';

/// 2026-08-31 (Auftrag Vucko: „entweder dass man die community als Post teilt
/// [...] und auch, dass man die community auch auf anderen Seiten verlinken
/// kann").
///
/// Das Blatt darf NICHTS selbst ausfuehren. Es sagt nur, was der Nutzer
/// gewaehlt hat, und der Aufrufer macht es. Grund: beide Wege oeffnen wieder
/// etwas, und dann ist das Blatt schon weg. Genau dieses Muster wird hier
/// festgehalten, damit es niemand aus Versehen wieder umdreht.
void main() {
  const community = <String, dynamic>{
    'id': '1f5c2b7e-4a3d-4c6b-9e21-8d0f7a6b5c34',
    'name': 'Vorarlberg Cruiser',
    'description': 'Treffen jeden Freitag.',
    'is_public': true,
  };

  Future<CommunityTeilenWahl?> zeigeUndTippe(
    WidgetTester tester,
    String knopfText,
  ) async {
    CommunityTeilenWahl? wahl;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  wahl = await CommunityTeilenBlatt.zeigen(
                    context,
                    community: community,
                    einladungsCode: 'CCC-ABC234',
                  );
                },
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(knopfText));
    await tester.pumpAndSettle();
    return wahl;
  }

  testWidgets('Das Blatt zeigt Name und fertigen Link', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityTeilenBlatt(
            community: community,
            einladungsCode: 'CCC-ABC234',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vorarlberg Cruiser'), findsOneWidget);
    expect(
      find.text('https://cruiseconnector.at/c/CCC-ABC234'),
      findsOneWidget,
    );
    expect(find.text('Link teilen'), findsOneWidget);
    expect(find.text('Als Beitrag teilen'), findsOneWidget);
  });

  testWidgets('Link teilen gibt die Wahl zurueck und fuehrt nichts aus', (
    tester,
  ) async {
    final wahl = await zeigeUndTippe(tester, 'Link teilen');
    expect(wahl, CommunityTeilenWahl.link);
    // Das Blatt ist zu. Haette es selbst etwas geoeffnet, staende es noch da.
    expect(find.text('Als Beitrag teilen'), findsNothing);
  });

  testWidgets('Als Beitrag teilen gibt die andere Wahl zurueck', (
    tester,
  ) async {
    final wahl = await zeigeUndTippe(tester, 'Als Beitrag teilen');
    expect(wahl, CommunityTeilenWahl.beitrag);
  });

  testWidgets('Wegwischen ohne Wahl liefert nichts', (tester) async {
    CommunityTeilenWahl? wahl;
    var fertig = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  wahl = await CommunityTeilenBlatt.zeigen(
                    context,
                    community: community,
                    einladungsCode: 'CCC-ABC234',
                  );
                  fertig = true;
                },
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    // Tippen neben das Blatt schliesst es.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(fertig, isTrue);
    expect(wahl, isNull);
  });

  testWidgets('Der Schreibkasten steht mit dem Vorschlag drin offen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunityBeitragBlatt(
            vorschlag: communityBeitragText(
              name: 'Vorarlberg Cruiser',
              linkUrl: 'https://cruiseconnector.at/c/CCC-ABC234',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final feld = tester.widget<TextField>(find.byType(TextField));
    expect(feld.controller!.text, contains('Vorarlberg Cruiser'));
    expect(
      feld.controller!.text,
      contains('https://cruiseconnector.at/c/CCC-ABC234'),
    );
    // Der Vorschlag ist ein Vorschlag. Wer will, schreibt ihn um.
    expect(feld.readOnly, isFalse);
    expect(find.text('Beitrag veröffentlichen'), findsOneWidget);
  });
}
