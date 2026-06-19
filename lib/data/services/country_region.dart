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

  /// Möglichst nur im Land — harte Ablehnung sichtbarer Auslandsabschnitte.
  onlyHome,
}

class CountryRouteMetrics {
  const CountryRouteMetrics({
    required this.foreignPointFraction,
    required this.foreignDistanceFraction,
    required this.maxForeignSegmentMeters,
    required this.foreignDistanceMeters,
    required this.totalDistanceMeters,
    required this.countriesTouched,
  });

  final double foreignPointFraction;
  final double foreignDistanceFraction;
  final double maxForeignSegmentMeters;
  final double foreignDistanceMeters;
  final double totalDistanceMeters;
  final List<String> countriesTouched;

  double get effectiveForeignFraction =>
      math.max(foreignPointFraction, foreignDistanceFraction);

  bool get violatesOnlyHomeLimits =>
      foreignPointFraction > CountryRegion.onlyHomeMaxForeignFraction ||
      foreignDistanceFraction > CountryRegion.onlyHomeMaxForeignFraction ||
      maxForeignSegmentMeters > CountryRegion.onlyHomeMaxForeignSegmentMeters;
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

  /// Ein einzelner sichtbarer Auslandsabschnitt darf bei `onlyHome` nicht durch
  /// Sparse-Geometrie unter die Punktquote rutschen.
  static const double onlyHomeMaxForeignSegmentMeters = 500.0;

  /// Weiche Prefer-Home-Grenze für Pool/Ranking: große Auslandsschleifen raus,
  /// kleine Grenzberührungen bleiben möglich.
  static const double preferHomeMaxForeignFraction = 0.65;

  /// Klassifiziert einen Punkt grob. Reihenfolge wichtig: Grenzregionen werden
  /// vor großen Länderboxen geprüft, damit Vorarlberg nicht als CH/LI und echte
  /// CH/LI-Ausflüge nicht als AT durchrutschen.
  static String? classify(double lat, double lng) {
    if (_isLiechtensteinApprox(lat, lng)) {
      return 'LI';
    }
    // 2026-06-08 (vucko Grenz-Test): Lindau (DE) ragt als Halbinsel in den
    // Bodensee, umgeben von AT (Hörbranz/Bregenz östl. + südl.). Die flache AT-
    // Nordgrenze würde es als AT labeln → „Im Land bleiben" am falschen Land.
    // Box schließt Hörbranz (lng>9.74) + Bregenz (lat<47.52) aus.
    if (lat >= 47.52 && lat <= 47.58 && lng >= 9.63 && lng <= 9.74) {
      return 'DE';
    }
    // Vorarlberg/Rheintal zuerst: Feldkirch/Frastanz liegen in der alten
    // LI-Rechteckbox, St. Margrethen/Buchs in der alten CH-Box. Die
    // lat-abhängige Westgrenze trennt grob entlang Rhein/Liechtenstein.
    if (_isVorarlbergAustria(lat, lng)) {
      return 'AT';
    }
    // Schweiz — westlich/südlich des Rheins, inkl. Bodensee/Rheintal.
    if (lat >= 45.80 && lat <= 47.81 && lng >= 5.95 && lng <= 9.66) {
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

  static bool _isLiechtensteinApprox(double lat, double lng) {
    if (lat < 47.04 || lat > 47.28 || lng < 9.47 || lng > 9.64) {
      return false;
    }
    const polygon = <List<double>>[
      [9.485, 47.270],
      [9.545, 47.270],
      [9.585, 47.235],
      [9.626, 47.165],
      [9.615, 47.047],
      [9.490, 47.045],
      [9.485, 47.165],
    ];
    return _pointInPolygon(lat, lng, polygon);
  }

  static bool _isVorarlbergAustria(double lat, double lng) {
    if (lat < 46.82 || lat > 47.56 || lng < 9.52 || lng > 10.30) {
      return false;
    }
    if (_isLiechtensteinApprox(lat, lng)) return false;
    return lng >= _vorarlbergWestLimit(lat);
  }

  static double _vorarlbergWestLimit(double lat) {
    if (lat >= 47.50) return 9.70; // Bodensee: Bregenz/Lochau, nicht Lindau/CH
    if (lat >= 47.44) return 9.645; // Höchst/St. Margrethen Grenzstreifen
    if (lat >= 47.32) return 9.585; // Dornbirn/Götzis östlich des Rheins
    if (lat >= 47.22) return 9.565; // Feldkirch/Frastanz
    if (lat >= 47.15) return 9.600; // nördlich Bludenz, östlich LI/CH
    return 9.650;
  }

  static bool _pointInPolygon(
    double lat,
    double lng,
    List<List<double>> polygon,
  ) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i][0];
      final yi = polygon[i][1];
      final xj = polygon[j][0];
      final yj = polygon[j][1];
      final intersects =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
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
    return routeMetrics(
      coordinates: coordinates,
      homeCountryCode: homeCountryCode,
    ).foreignPointFraction;
  }

  /// Robuste Routenmetrik für Länder-Filter.
  ///
  /// Punktquoten alleine reichen bei Routing-Geometrien nicht: Ein langer
  /// Straßenabschnitt kann nur wenige Stützpunkte haben. Darum messen wir
  /// zusätzlich die distanzgewichtete Auslandslänge und den längsten
  /// zusammenhängenden Auslandsabschnitt.
  static CountryRouteMetrics routeMetrics({
    required List<List<double>> coordinates,
    required String homeCountryCode,
  }) {
    if (coordinates.isEmpty) {
      return const CountryRouteMetrics(
        foreignPointFraction: 0.0,
        foreignDistanceFraction: 0.0,
        maxForeignSegmentMeters: 0.0,
        foreignDistanceMeters: 0.0,
        totalDistanceMeters: 0.0,
        countriesTouched: <String>[],
      );
    }

    final home = homeCountryCode.toUpperCase();
    final seenCountries = <String>{};
    var foreignPoints = 0;
    var classifiedPoints = 0;
    var foreignDistanceMeters = 0.0;
    var totalDistanceMeters = 0.0;
    var activeForeignMeters = 0.0;
    var maxForeignSegmentMeters = 0.0;
    List<double>? previous;
    String? previousCountry;

    for (final c in coordinates) {
      if (c.length < 2) continue;
      final lng = c[0];
      final lat = c[1];
      final country = classify(lat, lng); // [lng, lat]
      if (country != null) {
        seenCountries.add(country);
        classifiedPoints++;
        if (country != home) foreignPoints++;
      }

      if (previous != null) {
        final prevLng = previous[0];
        final prevLat = previous[1];
        final segmentMeters = _distanceMeters(prevLat, prevLng, lat, lng);
        if (segmentMeters.isFinite && segmentMeters > 0) {
          totalDistanceMeters += segmentMeters;
          final midCountry = classify((prevLat + lat) / 2, (prevLng + lng) / 2);
          if (midCountry != null) seenCountries.add(midCountry);

          final endpointsForeign =
              previousCountry != null &&
              country != null &&
              previousCountry != home &&
              country != home;
          final midpointForeign = midCountry != null && midCountry != home;
          if (endpointsForeign || midpointForeign) {
            foreignDistanceMeters += segmentMeters;
            activeForeignMeters += segmentMeters;
            maxForeignSegmentMeters = math.max(
              maxForeignSegmentMeters,
              activeForeignMeters,
            );
          } else {
            activeForeignMeters = 0.0;
          }
        }
      }

      previous = c;
      previousCountry = country;
    }

    final orderedCountries = seenCountries.toList()
      ..sort((a, b) {
        if (a == home) return -1;
        if (b == home) return 1;
        return a.compareTo(b);
      });

    return CountryRouteMetrics(
      foreignPointFraction: classifiedPoints == 0
          ? 0.0
          : foreignPoints / classifiedPoints,
      foreignDistanceFraction: totalDistanceMeters <= 0
          ? 0.0
          : foreignDistanceMeters / totalDistanceMeters,
      maxForeignSegmentMeters: maxForeignSegmentMeters,
      foreignDistanceMeters: foreignDistanceMeters,
      totalDistanceMeters: totalDistanceMeters,
      countriesTouched: orderedCountries,
    );
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

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  /// Score-Penalty (additiv, höher = schlechter) für einen Ausland-Anteil.
  /// Bewusst weich + nach Stufe skaliert; harte Ablehnung passiert separat
  /// über `CountryRouteMetrics.violatesOnlyHomeLimits`.
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
