import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/driven_track_recorder.dart';

/// 2026-08-04 (vucko): „Wenn man Speichern oder Verwerfen drückt, soll die UI
/// direkt reagieren und das Backend soll sich seine Zeit nehmen."
///
/// Die Umsetzung in `cruise_mode_page.dart` friert den Fahrt-Abschluss ein
/// (`_AbschlussStand`), setzt die Oberfläche sofort zurück und speichert danach
/// im Hintergrund. Diese Reihenfolge ist nur dann ungefährlich, wenn der
/// eingefrorene Stand ein ABZUG ist und kein Verweis auf lebende Objekte.
///
/// Denn `_resetAfterCompletion()` ruft unmittelbar `_drivenTrackRecorder
/// .reset()` auf. Wäre `snapshot()` eine Sicht statt einer Kopie, fände der
/// Hintergrund einen leeren Track, `_buildAdjustedCompletionResult()` gäbe
/// `null` zurück, und der gesamte Speicherblock würde stillschweigend
/// übersprungen: Die Fahrt wäre verloren, obwohl die App längst „gespeichert"
/// gemeldet hat.
///
/// Genau diese Eigenschaft prüfen die Tests hier. Wer `snapshot()` einmal auf
/// eine billigere Sicht umbaut, bricht damit das Speichern im Hintergrund —
/// und würde es ohne diesen Test nicht merken, weil nichts abstürzt.
void main() {
  DrivenTrackRecorder mitFahrt() {
    final r = DrivenTrackRecorder();
    final start = DateTime(2026, 8, 4, 12);
    var lat = 47.4125;
    for (var i = 0; i < 40; i++) {
      lat += 0.0002; // gut 20 m je Schritt
      r.addSample(
        latitude: lat,
        longitude: 9.7414,
        timestamp: start.add(Duration(seconds: i * 2)),
        accuracyMeters: 6.0,
        speedMetersPerSecond: 11.0,
      );
    }
    return r;
  }

  group('Der eingefrorene Track überlebt den Reset', () {
    test('ein vor dem Reset gezogener Abzug behält seine Punkte', () {
      final recorder = mitFahrt();
      final eingefroren = recorder.snapshot();

      expect(eingefroren.hasDrawableTrack, isTrue);
      final punkteVorher = eingefroren.coordinates.length;
      final meterVorher = eingefroren.distanceMeters;
      expect(punkteVorher, greaterThan(2));
      expect(meterVorher, greaterThan(0));

      // Das macht `_resetAfterCompletion()` direkt nach dem Tap.
      recorder.reset();

      expect(
        eingefroren.coordinates.length,
        punkteVorher,
        reason: 'Der Abzug darf sich durch den Reset nicht verändern',
      );
      expect(eingefroren.distanceMeters, meterVorher);
      expect(
        eingefroren.hasDrawableTrack,
        isTrue,
        reason: 'Sonst würde der Hintergrund die Fahrt stillschweigend '
            'verwerfen, statt sie zu speichern',
      );
    });

    test('der Recorder selbst ist nach dem Reset erwartungsgemäß leer', () {
      final recorder = mitFahrt();
      final eingefroren = recorder.snapshot();
      recorder.reset();

      final danach = recorder.snapshot();
      expect(danach.hasDrawableTrack, isFalse);
      expect(danach.distanceMeters, 0);
      // Und trotzdem hat der Abzug noch alles — das ist der springende Punkt.
      expect(eingefroren.hasDrawableTrack, isTrue);
    });

    test('eine neue Fahrt verändert den alten Abzug nicht', () {
      final recorder = mitFahrt();
      final ersteFahrt = recorder.snapshot();
      final punkteErsteFahrt = ersteFahrt.coordinates.length;

      recorder.reset();
      final start = DateTime(2026, 8, 4, 14);
      var lat = 48.2;
      for (var i = 0; i < 15; i++) {
        lat += 0.0002;
        recorder.addSample(
          latitude: lat,
          longitude: 16.37,
          timestamp: start.add(Duration(seconds: i * 2)),
          accuracyMeters: 6.0,
          speedMetersPerSecond: 11.0,
        );
      }

      expect(
        ersteFahrt.coordinates.length,
        punkteErsteFahrt,
        reason: 'Ein noch laufender Hintergrund-Speichervorgang der ERSTEN '
            'Fahrt darf niemals die Punkte der zweiten bekommen',
      );
      expect(ersteFahrt.coordinates.first[1], closeTo(47.41, 0.1));
    });
  });

  group('Die Voraussetzung dahinter', () {
    test('snapshot() liefert eine Kopie, keine Sicht auf die Segmente', () {
      final recorder = mitFahrt();
      final a = recorder.snapshot();
      final b = recorder.snapshot();
      expect(
        identical(a.segments, b.segments),
        isFalse,
        reason: 'Zwei Abzüge müssen unabhängig sein',
      );
      expect(a.coordinates.length, b.coordinates.length);
    });
  });
}
