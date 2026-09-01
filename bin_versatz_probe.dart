import 'dart:convert';
import 'dart:io';
import 'package:cruise_connect/data/services/ueberlappung_versatz.dart';

const m = 111320.0;
void main() {
  // Vuckos Geometrie: 2 km geradeaus, 875 m Stich hinauf und zurueck, 2 km weiter
  final p = <List<double>>[];
  void strecke(double x1, double y1, double x2, double y2, {double schritt = 25}) {
    final len = ((x2 - x1).abs() + (y2 - y1).abs());
    final n = (len / schritt).round().clamp(1, 10000);
    for (var i = 0; i < n; i++) {
      p.add([9.74 + (x1 + (x2 - x1) * i / n) / (m * 0.676),
             47.41 + (y1 + (y2 - y1) * i / n) / m]);
    }
  }
  strecke(0, 0, 0, 2000);
  strecke(0, 2000, 875, 2000);
  strecke(875, 2000, 0, 2000);
  strecke(0, 2000, 0, 4000);
  final v = mitUeberlappungsVersatz(p);
  File('/tmp/versatz_daten.json').writeAsStringSync(jsonEncode({'roh': p, 'versetzt': v}));
  stdout.writeln('Punkte: ${p.length}, versetzt: ${identical(v, p) ? "nichts" : "ja"}');
}
