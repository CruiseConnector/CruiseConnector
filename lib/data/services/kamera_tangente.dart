import 'geo_bearing.dart';
import 'geo_distance.dart';

/// Kamera-Peilung entlang der Route, herausgezogen aus der Cruise-Seite.
///
/// 2026-08-18 (Aufgabe 3.3, Vucko-Sprachnachricht 10 vom 18.08.):
/// „Bei der Gruppenfahrt hat sich die Kamera die ganze Zeit gedreht, aus
/// irgendeinem Grund."
///
/// Die Ursache war NICHT, wie zunächst vermutet, ein Wettlauf zwischen
/// Gruppen-Sync und lokalem Heading-Tracking. Nachgemessen: Kein einziger
/// Gruppen-Timer und kein Gruppen-Stream fasst die Kamera an. Der Fehler war
/// indirekt: Stand `_currentRouteIndex` nicht beim Fahrer — im Gruppenmodus
/// sprang er beim Übernehmen der Leader-Route auf 0, also auf den fernen
/// Routenanfang —, dann peilte die Tangente einen FESTEN geografischen Punkt
/// kilometerweit weg an. Wer daran vorbeifährt, dessen Karte dreht sich
/// stetig weiter, obwohl er geradeaus fährt.
///
/// Der Schutz dagegen (Fix vom 09.08., Commit 2c3f563) lebte bis heute
/// ungetestet mitten in einer 20.000-Zeilen-Datei und konnte jederzeit
/// unbemerkt zurückgedreht werden. Deshalb liegt die Rechnung jetzt hier —
/// reine Geometrie, ohne Widget, ohne Plattform, prüfbar.
class KameraTangente {
  const KameraTangente._();

  /// Über diesem Abstand zwischen Fahrer und Ankerpunkt gilt die Tangente als
  /// unglaubwürdig. 80 m liegt komfortabel über dem breitesten
  /// Off-Route-Korridor, echte Fahrten werden also nie beschnitten.
  static const double maxAnkerAbstandMeter = 80.0;

  /// Kürzer als das ist der Vorausschau-Vektor zu unzuverlässig für eine
  /// Peilung.
  static const double minVorlaufMeter = 5.0;

  /// Liefert die Fahrtrichtung entlang der Route, oder `null`, wenn die
  /// Rechnung nicht vertrauenswürdig ist. Bei `null` fällt die Kamera auf den
  /// GPS-Kurs zurück.
  ///
  /// [koordinaten] im Mapbox-Format `[longitude, latitude]`.
  /// [offRoute] true, sobald der Fahrer als abgekommen gilt.
  static double? peilung({
    required double kopfLat,
    required double kopfLng,
    required List<List<double>> koordinaten,
    required int index,
    bool offRoute = false,
    double vorausschauMeter = 30.0,
  }) {
    if (offRoute) return null;
    if (koordinaten.length < 2) return null;

    final idx = index.clamp(0, koordinaten.length - 2).toInt();

    // Der Notaus gegen die Fernpeilung: Die Tangente MUSS am Fahrer hängen.
    // Eine reine Längenprüfung des Vorausschau-Vektors reicht nicht — eine
    // Peilung auf einen kilometerweit entfernten Punkt rutscht dort glatt
    // durch, weil der Vektor ja lang genug ist.
    final ankerAbstand = GeoDistance.haversineMeters(
      fromLat: kopfLat,
      fromLng: kopfLng,
      toLat: koordinaten[idx][1],
      toLng: koordinaten[idx][0],
    );
    if (!ankerAbstand.isFinite || ankerAbstand > maxAnkerAbstandMeter) {
      return null;
    }

    var summe = 0.0;
    var vorLat = kopfLat;
    var vorLng = kopfLng;
    double? zielLat;
    double? zielLng;
    for (var i = idx + 1; i < koordinaten.length; i++) {
      final lat = koordinaten[i][1];
      final lng = koordinaten[i][0];
      final d = GeoDistance.haversineMeters(
        fromLat: vorLat,
        fromLng: vorLng,
        toLat: lat,
        toLng: lng,
      );
      if (!d.isFinite || d <= 0) {
        vorLat = lat;
        vorLng = lng;
        continue;
      }
      if (summe + d >= vorausschauMeter) {
        final f = ((vorausschauMeter - summe) / d).clamp(0.0, 1.0);
        zielLat = vorLat + (lat - vorLat) * f;
        zielLng = vorLng + (lng - vorLng) * f;
        break;
      }
      summe += d;
      vorLat = lat;
      vorLng = lng;
      zielLat = lat;
      zielLng = lng;
    }
    if (zielLat == null || zielLng == null) return null;

    final vorlauf = GeoDistance.haversineMeters(
      fromLat: kopfLat,
      fromLng: kopfLng,
      toLat: zielLat,
      toLng: zielLng,
    );
    if (vorlauf < minVorlaufMeter) return null;

    return GeoBearing.bearingDegrees(kopfLat, kopfLng, zielLat, zielLng);
  }
}
