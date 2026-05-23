import 'dart:convert';
import 'package:http/http.dart' as http;

/// Wetter-Service auf Basis der OpenMeteo Free API.
/// Kein API-Key nötig, keine Rate-Limits für leichte App-Nutzung.
///
/// Liefert aktuelle Bedingungen + 6h-Forecast inkl. Regen-Wahrscheinlichkeit
/// und einer einfachen "moto-ready?"-Bewertung.
///
/// Caching: in-memory pro (lat,lng,minute) Bucket — verhindert dass dieselbe
/// Position innerhalb einer Minute mehrfach gefetcht wird.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  final Map<String, _WeatherCacheEntry> _cache = {};

  /// Liefert aktuelles Wetter + 6h-Outlook für die gegebene Position.
  /// Bei Netzwerk-Fehler wird `null` zurückgegeben — Caller zeigen dann
  /// einfach gar kein Wetter-Widget.
  Future<WeatherSnapshot?> fetchForPosition({
    required double latitude,
    required double longitude,
  }) async {
    final cacheKey = _buildCacheKey(latitude, longitude);
    final cached = _cache[cacheKey];
    if (cached != null && cached.isFresh) {
      return cached.snapshot;
    }
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,'
            'weather_code,wind_speed_10m,wind_direction_10m,precipitation',
        'hourly': 'temperature_2m,precipitation,precipitation_probability,'
            'weather_code,wind_speed_10m',
        'forecast_hours': '6',
        'timezone': 'auto',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final snap = WeatherSnapshot.fromJson(data);
      _cache[cacheKey] = _WeatherCacheEntry(snap);
      return snap;
    } catch (_) {
      return null;
    }
  }

  String _buildCacheKey(double lat, double lng) {
    final minuteBucket = DateTime.now().minute ~/ 5;
    return '${lat.toStringAsFixed(2)}|${lng.toStringAsFixed(2)}|$minuteBucket';
  }
}

class _WeatherCacheEntry {
  _WeatherCacheEntry(this.snapshot) : fetchedAt = DateTime.now();
  final WeatherSnapshot snapshot;
  final DateTime fetchedAt;

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < const Duration(minutes: 10);
}

/// Ein vollständiger Wetter-Snapshot.
class WeatherSnapshot {
  final double temperatureC;
  final double feelsLikeC;
  final int humidityPct;
  final double windKmh;
  final int weatherCode;
  final double precipitationMm;
  final List<HourlyForecast> next6Hours;

  WeatherSnapshot({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.humidityPct,
    required this.windKmh,
    required this.weatherCode,
    required this.precipitationMm,
    required this.next6Hours,
  });

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    final current = (json['current'] as Map<String, dynamic>? ?? {});
    final hourly = (json['hourly'] as Map<String, dynamic>? ?? {});
    final hourlyTimes = (hourly['time'] as List?) ?? [];
    final hourlyTemps = (hourly['temperature_2m'] as List?) ?? [];
    final hourlyPrec = (hourly['precipitation'] as List?) ?? [];
    final hourlyPrecProb =
        (hourly['precipitation_probability'] as List?) ?? [];
    final hourlyCodes = (hourly['weather_code'] as List?) ?? [];
    final hourlyWind = (hourly['wind_speed_10m'] as List?) ?? [];

    final hourly6 = <HourlyForecast>[];
    final count = [
      hourlyTimes.length,
      hourlyTemps.length,
      hourlyPrec.length,
      hourlyPrecProb.length,
      hourlyCodes.length,
      hourlyWind.length,
      6,
    ].reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < count; i++) {
      hourly6.add(HourlyForecast(
        time: DateTime.tryParse(hourlyTimes[i] as String? ?? '') ??
            DateTime.now(),
        temperatureC: ((hourlyTemps[i] ?? 0) as num).toDouble(),
        precipitationMm: ((hourlyPrec[i] ?? 0) as num).toDouble(),
        precipitationProbability: ((hourlyPrecProb[i] ?? 0) as num).toInt(),
        weatherCode: ((hourlyCodes[i] ?? 0) as num).toInt(),
        windKmh: ((hourlyWind[i] ?? 0) as num).toDouble(),
      ));
    }

    return WeatherSnapshot(
      temperatureC: ((current['temperature_2m'] ?? 0) as num).toDouble(),
      feelsLikeC: ((current['apparent_temperature'] ?? 0) as num).toDouble(),
      humidityPct: ((current['relative_humidity_2m'] ?? 0) as num).toInt(),
      windKmh: ((current['wind_speed_10m'] ?? 0) as num).toDouble(),
      weatherCode: ((current['weather_code'] ?? 0) as num).toInt(),
      precipitationMm: ((current['precipitation'] ?? 0) as num).toDouble(),
      next6Hours: hourly6,
    );
  }

  /// Höchste Regen-Wahrscheinlichkeit in den nächsten 6h (für Banner).
  int get maxPrecipitationProbabilityNext6h {
    if (next6Hours.isEmpty) return 0;
    return next6Hours
        .map((h) => h.precipitationProbability)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Erster Eintrag in den nächsten 6h mit Regen >2mm (für Warnung).
  HourlyForecast? get firstHeavyRainHour {
    for (final h in next6Hours) {
      if (h.precipitationMm > 2.0) return h;
    }
    return null;
  }

  /// Schnelle "Motorrad-tauglich"-Bewertung.
  /// `excellent` = trocken, mild, wenig Wind
  /// `good`      = trocken, OK
  /// `marginal`  = leichter Regen / starker Wind
  /// `poor`      = Sturm / Starkregen
  RidingCondition get ridingCondition {
    if (precipitationMm > 4 || windKmh > 40 || temperatureC < 0) {
      return RidingCondition.poor;
    }
    if (precipitationMm > 0.5 || windKmh > 25 || temperatureC < 5) {
      return RidingCondition.marginal;
    }
    if (precipitationMm == 0 &&
        windKmh < 15 &&
        temperatureC >= 12 &&
        temperatureC <= 28) {
      return RidingCondition.excellent;
    }
    return RidingCondition.good;
  }
}

class HourlyForecast {
  final DateTime time;
  final double temperatureC;
  final double precipitationMm;
  final int precipitationProbability;
  final int weatherCode;
  final double windKmh;

  HourlyForecast({
    required this.time,
    required this.temperatureC,
    required this.precipitationMm,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.windKmh,
  });
}

enum RidingCondition { excellent, good, marginal, poor }

/// Mapped WMO-Weather-Codes (https://open-meteo.com/en/docs#weathervariables)
/// auf passende Material-Icons + Beschreibungen.
class WeatherCodeIcon {
  WeatherCodeIcon._();

  /// Returns (icon, label, color-hint 0-3 für sunny/cloudy/rainy/stormy)
  static (int iconCodePoint, String label, int colorHint) describe(int code) {
    // Material Icons codepoints
    if (code == 0) return (0xe1ee, 'Sonnig', 0); // wb_sunny
    if (code <= 2) return (0xe1e8, 'Heiter', 0); // wb_cloudy mit Sonne
    if (code == 3) return (0xe2bd, 'Bewölkt', 1); // cloud
    if (code <= 49) return (0xe818, 'Nebel', 1); // foggy
    if (code <= 55) return (0xe179, 'Nieselregen', 2); // grain
    if (code <= 57) return (0xe798, 'Gefrierender Regen', 2);
    if (code <= 65) return (0xe798, 'Regen', 2); // beach_access
    if (code <= 67) return (0xe2cf, 'Eisregen', 3);
    if (code <= 77) return (0xe2cd, 'Schnee', 1); // ac_unit
    if (code <= 82) return (0xe798, 'Regenschauer', 2);
    if (code <= 86) return (0xe2cd, 'Schneeschauer', 1);
    if (code <= 99) return (0xe1bb, 'Gewitter', 3); // flash_on
    return (0xe2bd, 'Wetter', 1);
  }
}
