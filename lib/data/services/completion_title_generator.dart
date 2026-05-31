/// Generiert einen passenden, NICHT zufälligen Titel für eine gefahrene Route
/// — im Stil von Strava ("Sportlicher Donnerstag").
///
/// 2026-05-31 (vucko): Der Titel ergibt sich aus echten Fahrt-Daten
/// (Wochentag + Tageszeit + Fahrstil) und ist **deterministisch**: dieselbe
/// Fahrt liefert immer denselben Titel. Über verschiedene Fahrten variiert das
/// Adjektiv leicht, aber jede Variante passt zum Stil — nie unpassend
/// zusammengewürfelt. Wochentage sind im Deutschen maskulin ("der Donnerstag"),
/// daher passt die maskuline Adjektiv-Endung "-er" immer ("Sportlicher
/// Donnerstagabend").
class CompletionTitleGenerator {
  const CompletionTitleGenerator._();

  static const List<String> _weekdays = <String>[
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  /// Tageszeit-Suffix, das direkt an den Wochentag gehängt wird
  /// ("Donnerstag" + "abend" → "Donnerstagabend").
  static String _timeOfDaySuffix(int hour) {
    if (hour >= 5 && hour < 10) return 'morgen';
    if (hour >= 10 && hour < 12) return 'vormittag';
    if (hour >= 12 && hour < 14) return 'mittag';
    if (hour >= 14 && hour < 17) return 'nachmittag';
    if (hour >= 17 && hour < 22) return 'abend';
    return 'nacht';
  }

  /// Maskuline Adjektive (alle Wochentage sind maskulin → "-er") pro Stil.
  /// Mehrere passende Varianten, damit nicht jede Fahrt identisch heißt.
  static List<String> _styleAdjectives(String style) {
    switch (_normalizeStyle(style)) {
      case 'sport':
        return const ['Sportlicher', 'Flotter', 'Dynamischer'];
      case 'kurven':
        return const ['Kurviger', 'Kurvenreicher', 'Verwinkelter'];
      case 'entspannt':
        return const ['Entspannter', 'Gemütlicher', 'Ruhiger'];
      case 'entdecker':
        return const ['Verträumter', 'Neugieriger', 'Spontaner'];
      default:
        return const ['Schöner', 'Guter', 'Runder'];
    }
  }

  static String _normalizeStyle(String style) {
    final s = style.toLowerCase().trim();
    if (s.contains('sport')) return 'sport';
    if (s.contains('kurv')) return 'kurven';
    if (s.contains('abend') || s.contains('panorama') || s.contains('genuss')) {
      return 'entspannt';
    }
    if (s.contains('entdeck') ||
        s.contains('zufall') ||
        s.contains('explore')) {
      return 'entdecker';
    }
    return 'default';
  }

  /// Liefert den fertigen Titel, z. B. "Sportlicher Donnerstagabend".
  static String generate({
    required DateTime time,
    required String style,
    required double distanceKm,
    int curves = 0,
    bool isRoundTrip = true,
  }) {
    // Deterministischer Seed aus den Fahrt-Daten — gleiche Fahrt → gleicher
    // Titel, verschiedene Fahrten variieren leicht im (stilpassenden) Adjektiv.
    final seed = (time.weekday * 31 +
            time.hour * 7 +
            distanceKm.round() * 3 +
            curves +
            (isRoundTrip ? 0 : 5))
        .abs();

    final weekday = _weekdays[(time.weekday - 1).clamp(0, 6)];
    final suffix = _timeOfDaySuffix(time.hour);
    final adjectives = _styleAdjectives(style);
    final adjective = adjectives[seed % adjectives.length];

    return '$adjective $weekday$suffix';
  }
}
