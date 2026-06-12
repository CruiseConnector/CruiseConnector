import 'dart:math' as math;

/// 2026-05-30 (vucko): Länder-Präferenz für die Routenplanung.
///
/// `preferHome` bleibt eine weiche Präferenz. `onlyHome` ist bewusst hart:
/// eine grenzüberschreitende Route darf dann nicht als Erfolg angezeigt werden.
/// Die harte Stufe ist trotzdem explosionssicher, weil sie nur Kandidaten
/// verwirft und keine unbegrenzten Zusatz-Requests startet.
enum CountryPreference {
  /// Egal — Land wird nicht bewertet.
  any,

  /// Eher im Land bleiben — moderater Penalty für Ausland-Anteil.
  preferHome,

  /// Möglichst nur im Land — starker Penalty, aber immer noch kein Reject.
  onlyHome,
}

extension CountryPreferenceLabel on CountryPreference {
  String get storageValue => switch (this) {
    CountryPreference.any => 'any',
    CountryPreference.preferHome => 'prefer_home',
    CountryPreference.onlyHome => 'only_home',
  };

  static CountryPreference fromStorage(String? value) => switch (value) {
    'prefer_home' => CountryPreference.preferHome,
    'only_home' => CountryPreference.onlyHome,
    _ => CountryPreference.any,
  };
}

/// Grobe Länder-Klassifikation per Lat/Lng-Boxen für die DACH-Region und
/// direkte Nachbarn. Bewusst heuristisch (kein Polygon-Asset): Für eine
/// SOFT-Präferenz reicht das, und es bleibt konsistent mit der serverseitigen
/// `isForeignPoint`-Logik in process-route-search-sessions.
///
/// ISO-3166-1 alpha-2 Codes. `null` = unbekannt/außerhalb der Boxen.
class CountryRegion {
  const CountryRegion._();

  /// Einheitliche Toleranz für grobes Box-Rauschen an gezackten Grenzen.
  /// Echte Grenzübertritte lagen in den Vorarlberg-/Bodensee-Tests klar
  /// darüber; 10% verhindert falsche Rejects durch einzelne falsch klassifizierte
  /// Punkte, blockt aber sichtbare Auslands-Schleifen.
  static const double onlyHomeMaxForeignFraction = 0.10;

  /// Weiche Prefer-Home-Grenze für Pool/Ranking: große Auslandsschleifen raus,
  /// kleine Grenzberührungen bleiben möglich.
  static const double preferHomeMaxForeignFraction = 0.65;

  /// Klassifiziert einen Punkt grob. Reihenfolge wichtig: die kleinen Länder
  /// (LI) vor den großen, weil sie sonst von AT/CH verschluckt würden.
  static String? classify(double lat, double lng) {
    // Liechtenstein — winziges Kästchen zwischen CH und AT (Rheintal-Süd).
    if (lat >= 47.05 && lat <= 47.27 && lng >= 9.47 && lng <= 9.64) {
      return 'LI';
    }
    // 2026-06-08 (vucko Grenz-Test): Lindau (DE) ragt als Halbinsel in den
    // Bodensee, umgeben von AT (Hörbranz/Bregenz östl. + südl.). Die flache AT-
    // Nordgrenze würde es als AT labeln → „Im Land bleiben" am falschen Land.
    // Box schließt Hörbranz (lng>9.74) + Bregenz (lat<47.52) aus.
    if (lat >= 47.52 && lat <= 47.58 && lng >= 9.63 && lng <= 9.74) {
      return 'DE';
    }
    // Schweiz — westlich/südlich des Rheins, grob.
    if (lat >= 45.80 && lat <= 47.81 && lng >= 5.95 && lng <= 9.55) {
      // Ostgrenze CH läuft im Rheintal ~lng 9.55; AT beginnt östlich davon.
      return 'CH';
    }
    // Italien (Südtirol/Norditalien) — südlich der Alpen.
    if (lat < 46.85 && lng >= 6.6 && lng <= 13.9) {
      return 'IT';
    }
    // Slowenien.
    if (lat >= 45.4 && lat <= 46.9 && lng >= 13.4 && lng <= 16.6) {
      return 'SI';
    }
    // Österreich vs. Deutschland: Die Grenze ist gezackt und kann mit einer
    // simplen Box nicht sauber getrennt werden. Approximation über eine
    // längen-abhängige Nordgrenze von AT:
    //   - West (lng < 13, Vorarlberg/Tirol/Salzburg): AT endet ~lat 47.7,
    //     darüber ist Bayern (DE) — z.B. München 48.14 = DE.
    //   - Ost (lng >= 13, Ober-/Niederösterreich): AT reicht bis ~lat 48.8.
    if (lng >= 9.53 && lng <= 17.16 && lat >= 46.37) {
      if (lat <= _austriaNorthLimit(lng)) return 'AT';
    }
    // Deutschland — nördlich/westlich von AT (Bayern + BW + nördlicher).
    if (lat >= 47.27 && lat <= 55.06 && lng >= 5.87 && lng <= 15.04) {
      return 'DE';
    }
    return null;
  }

  /// 2026-06-08 (vucko DACH-Test): Die AT/DE-Grenze ist im Alpenraum stark
  /// gezackt — eine flache Nordgrenze (vorher 47.70 für lng<13) labelte deutsche
  /// Alpenorte SÜDLICH davon fälschlich als AT (z.B. Garmisch 47.49, Mittenwald
  /// 47.44) → „Im Land bleiben" zielte aufs falsche Land. Stückweise lineare
  /// Näherung der echten Grenze (geprüft an Reutte/Füssen/Garmisch/Scharnitz/
  /// Kufstein/Kiefersfelden/Salzburg/Freilassing).
  static double _austriaNorthLimit(double lng) {
    if (lng < 10.9) return 47.55; // Außerfern (Reutte AT reicht nach Norden)
    if (lng < 11.6) return 47.42; // Garmisch/Mittenwald (DE buchtet nach Süden)
    if (lng < 12.6) return 47.60; // Inntal/Kufstein
    if (lng < 13.4) return 47.82; // Salzburg
    return 48.80; // Ost-Österreich (OÖ/NÖ reichen weit hoch)
  }

  /// Anteil der Routenpunkte, die NICHT im Heimatland liegen (0..1).
  /// Punkte mit unbekanntem Land (null) zählen als „neutral" (nicht foreign),
  /// damit grobe Box-Lücken nicht fälschlich als Ausland gewertet werden.
  static double foreignFraction({
    required List<List<double>> coordinates,
    required String homeCountryCode,
  }) {
    if (coordinates.isEmpty) return 0.0;
    final home = homeCountryCode.toUpperCase();
    var foreign = 0;
    var classified = 0;
    for (final c in coordinates) {
      if (c.length < 2) continue;
      final country = classify(c[1], c[0]); // [lng, lat]
      if (country == null) continue;
      classified++;
      if (country != home) foreign++;
    }
    if (classified == 0) return 0.0;
    return foreign / classified;
  }

  /// Die Liste der vom Heimatland abweichenden Länder entlang der Route
  /// (für Anzeige „Durchquert: AT · CH"). Heimatland steht zuerst.
  static List<String> countriesTouched({
    required List<List<double>> coordinates,
    String? homeCountryCode,
  }) {
    final seen = <String>{};
    for (final c in coordinates) {
      if (c.length < 2) continue;
      final country = classify(c[1], c[0]);
      if (country != null) seen.add(country);
    }
    final ordered = seen.toList();
    if (homeCountryCode != null) {
      final home = homeCountryCode.toUpperCase();
      ordered.sort((a, b) {
        if (a == home) return -1;
        if (b == home) return 1;
        return a.compareTo(b);
      });
    } else {
      ordered.sort();
    }
    return ordered;
  }

  /// Score-Penalty (additiv, höher = schlechter) für einen Ausland-Anteil.
  /// Bewusst weich + nach Stufe skaliert. NIE so hoch, dass eine Route
  /// dadurch komplett unbrauchbar/abgelehnt wird — das Acceptance-Gate bleibt
  /// davon unberührt.
  static double scorePenalty({
    required double foreignFraction,
    required CountryPreference preference,
  }) {
    if (preference == CountryPreference.any || foreignFraction <= 0) {
      return 0.0;
    }
    final clamped = foreignFraction.clamp(0.0, 1.0);
    // 2026-05-31 (vucko): onlyHome muss eine heimische Alternative IMMER
    // gewinnen lassen — daher dominanter Penalty (≈300), aber bewusst UNTER der
    // destinationReached-Reject-Schwelle (500), damit in Grenzregionen wie
    // Vorarlberg keine harte Ablehnung/Explosion entsteht (Soft-Garantie).
    // preferHome bleibt moderat.
    final maxPenalty = switch (preference) {
      CountryPreference.preferHome => 90.0,
      CountryPreference.onlyHome => 300.0,
      CountryPreference.any => 0.0,
    };
    // Quadratische Kurve: kleine Grenzberührungen kaum bestraft, große
    // Ausland-Schleifen deutlich.
    return maxPenalty * math.pow(clamped, 1.5).toDouble();
  }
}
