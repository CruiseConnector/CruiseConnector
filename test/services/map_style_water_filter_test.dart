// Regression-Schutz für den Wasser-Spots-Fix (2026-06-05).
//
// Hintergrund: Die App hat DREI Map-Styles, die denselben Wasser-/Label-Look
// definieren müssen:
//   1) assets/map/cruise_dark.json        (MapLibre-Vektor, aktiv zur Laufzeit)
//   2) tools/carplay_raster/style.json    (CarPlay-Raster-Quelle)
//   3) lib/data/services/cruise_dark_map_style.dart (flutter_map-Fallback)
//
// Sie drifteten in der Vergangenheit auseinander (carplay/fallback hatten noch
// das alte helle Wasser #16212f OHNE Filter + „village"-Labels → „unendlich
// viele Spots"). Dieser Test erzwingt, dass ALLE drei synchron bleiben:
//   • Wasser-Filter zeigt NUR echtes Wasser (ocean/lake/river/water) und
//     schließt Fake-Wasser aus (swimming_pool/fountain/dock/basin via kind +
//     kind_detail=basin) → Bodensee/Rhein/Seen/Flüsse bleiben, Pools/Brunnen/
//     Rückhaltebecken weg.
//   • Wasserfarbe = #16273b.
//   • Orts-Labels nur city/town (kein „village").
//
// Schlägt ein Style aus, ist die Synchronität gebrochen → Fix wieder anziehen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/cruise_dark_map_style.dart';

void main() {
  const expectedWaterFilter = [
    'all',
    ['in', 'kind', 'ocean', 'lake', 'river', 'water'],
    ['!in', 'kind_detail', 'basin'],
  ];
  const expectedWaterColor = '#16273b';

  Map<String, dynamic> layerById(List<dynamic> layers, String id) =>
      layers.firstWhere((l) => (l as Map)['id'] == id) as Map<String, dynamic>;

  void verifyStyle(String label, Map<String, dynamic> style) {
    final layers = style['layers'] as List<dynamic>;

    // Wasser: nur echtes Wasser, richtige Farbe.
    final water = layerById(layers, 'water');
    expect(water['filter'], equals(expectedWaterFilter),
        reason: '$label: Wasser-Filter muss Fake-Wasser ausschließen');
    expect((water['paint'] as Map)['fill-color'], equals(expectedWaterColor),
        reason: '$label: Wasserfarbe muss $expectedWaterColor sein');

    // Labels: keine Dörfer.
    final places = layerById(layers, 'places');
    final placesFilter =
        (places['filter'] as List).map((e) => e.toString()).toList();
    expect(placesFilter.contains('village'), isFalse,
        reason: '$label: „village"-Labels müssen draußen sein');
    expect(placesFilter.contains('city') && placesFilter.contains('town'),
        isTrue,
        reason: '$label: city + town müssen beschriftet sein');
  }

  Map<String, dynamic> loadJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('cruise_dark.json — nur echtes Wasser, keine Dörfer', () {
    verifyStyle('cruise_dark.json', loadJson('assets/map/cruise_dark.json'));
  });

  test('carplay_raster/style.json — synchron zu cruise_dark', () {
    verifyStyle(
        'carplay style.json', loadJson('tools/carplay_raster/style.json'));
  });

  test('cruise_dark_map_style.dart (Fallback) — synchron zu cruise_dark', () {
    verifyStyle('cruise_dark_map_style.dart',
        Map<String, dynamic>.from(cruiseDarkMapStyle));
  });
}
