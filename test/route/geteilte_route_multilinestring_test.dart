import 'dart:io';

import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-25 (vucko, Feld-Meldung mit Bildschirmfoto): „Ich konnte eine
/// Community-Runde nicht fahren, die ein anderer Nutzer reingepostet hat.
/// Es kommt immer die Meldung, dass die Route nicht geladen werden kann."
///
/// URSACHE: Eine aufgezeichnete Fahrt mit GPS-Luecke (Tunnel, App im
/// Hintergrund, kurzer Empfangsverlust) wird als MultiLineString gespeichert
/// — `driven_track_recorder.dart` schreibt ab dem zweiten Segment diesen Typ.
/// `cruise_mode_page.dart` baute die Abflachung an DREI Stellen von Hand nach
/// und konnte dabei nur LineString: bei MultiLineString ist ein Element ein
/// ganzes SEGMENT, `c[0]` also selbst eine Liste. Der Cast `as num` warf einen
/// TypeError, den ein Sammel-catch in die nichtssagende Meldung verwandelte.
///
/// Gemessen an der Produktionsdatenbank am 25.08.: 51 von 252 Routen sind
/// MultiLineString, verteilt auf 15 Nutzer. Die gemeldete Route hatte drei
/// Segmente mit 939 + 228 + 2169 = 3336 Punkten. Nicht nur der Weg ueber den
/// Beitrag war betroffen, sondern jeder Einstieg: Startseite, Lesezeichen und
/// die Lieblingsrouten im Profil laufen durch dieselbe Methode.
void main() {
  // Nachbau des echten Datensatzes: drei Segmente, dazwischen kurze Luecken.
  Map<String, dynamic> mehrteilig() => {
    'type': 'MultiLineString',
    'coordinates': [
      [
        [9.713664350620151, 47.412593850766015],
        [9.713700, 47.412650],
        [9.713750, 47.412700],
      ],
      [
        [9.713800, 47.412760],
        [9.713860, 47.412820],
      ],
      [
        [9.713920, 47.412880],
        [9.713980, 47.412940],
        [9.714040, 47.413000],
        [9.714100, 47.413060],
      ],
    ],
  };

  Map<String, dynamic> einteilig() => {
    'type': 'LineString',
    'coordinates': [
      [9.713664350620151, 47.412593850766015],
      [9.713700, 47.412650],
      [9.713750, 47.412700],
    ],
  };

  group('Eine aufgezeichnete Fahrt mit Luecken bleibt fahrbar', () {
    test('MultiLineString wird zu einer durchgehenden Punktliste', () {
      final punkte = SavedRoute.flattenGeometryCoordinates(mehrteilig());
      // 3 + 2 + 4 Punkte aus den Segmenten, nicht 3 Segmente.
      expect(punkte.length, 9);
      expect(punkte.first, [9.713664350620151, 47.412593850766015]);
      // Jeder Eintrag ist ein Punkt aus zwei Zahlen, KEIN verschachteltes Feld.
      for (final p in punkte) {
        expect(p.length, 2, reason: 'ein Punkt, kein Segment');
        expect(p[0], isA<double>());
        expect(p[1], isA<double>());
      }
    });

    test('LineString funktioniert unveraendert weiter', () {
      final punkte = SavedRoute.flattenGeometryCoordinates(einteilig());
      expect(punkte.length, 3);
      expect(punkte.first, [9.713664350620151, 47.412593850766015]);
    });

    test('leere und kaputte Geometrie ergibt eine leere Liste, keinen Absturz', () {
      expect(SavedRoute.flattenGeometryCoordinates(const {}), isEmpty);
      expect(
        SavedRoute.flattenGeometryCoordinates(const {'coordinates': 'kaputt'}),
        isEmpty,
      );
      expect(
        SavedRoute.flattenGeometryCoordinates(const {
          'type': 'MultiLineString',
          'coordinates': [
            [
              ['a', 'b'],
            ],
          ],
        }),
        isEmpty,
      );
    });

    test('BELEG: der alte Nachbau waere hier gescheitert', () {
      // Genau die Zeile, die in cruise_mode_page.dart stand.
      final roh = (mehrteilig()['coordinates'] as List?) ?? [];
      expect(
        () => roh
            .whereType<List>()
            .where((c) => c.length >= 2)
            .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
            .toList(),
        throwsA(isA<TypeError>()),
        reason: 'Das war die Ursache der Meldung im Feld',
      );
    });
  });

  test('Quelltext-Waechter: nirgends mehr handgebautes Abflachen', () {
    // Das Muster stand an SECHS Stellen in vier Dateien, nicht nur an der
    // gemeldeten. Deshalb wird das ganze Projekt geprueft, nicht eine Datei.
    final treffer = <String>[];
    final muster = RegExp(
      r'\(c\[0\] as num\)\.toDouble\(\),\s*\(c\[1\] as num\)\.toDouble\(\)',
    );
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final zeilen = e.readAsLinesSync();
      for (var i = 0; i < zeilen.length; i++) {
        if (muster.hasMatch(zeilen[i])) treffer.add('${e.path}:${i + 1}');
      }
    }
    expect(
      treffer,
      isEmpty,
      reason:
          'Geometrie IMMER ueber SavedRoute.flattenGeometryCoordinates lesen, '
          'sonst scheitert jede aufgezeichnete Fahrt mit GPS-Luecke',
    );
  });

  test('Quelltext-Waechter: keine Striche als Platzhalter auf der Fahrtseite', () {
    // 2026-08-25: Bei „Hoechsttempo" stand ein Geviertstrich, weil der Wert
    // bei einer geteilten fremden Route gar nicht vorliegt. Kacheln ohne Wert
    // werden jetzt weggelassen.
    final quelle = File(
      'lib/presentation/pages/ride_detail_page.dart',
    ).readAsStringSync();
    expect(
      quelle.contains("'\u2014'"),
      isFalse,
      reason: 'Kachel weglassen statt einen Strich anzeigen',
    );
    expect(quelle.contains("'—'"), isFalse, reason: 'kein Geviertstrich');
  });
}
