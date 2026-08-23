/// Plausibilitätsgrenzen für Fahrzeugdaten in der Garage.
///
/// 2026-08-18 (Defekt 4 aus dem Produktionsbericht): Das Leistungsfeld nahm
/// bis dahin jede Zahl bis 1999 an. In der Produktivdatenbank steht seit dem
/// 17.08. ein Skoda Fabia mit 1.100 PS und 0-100 in 1,2 Sekunden; drei
/// Fahrzeuge haben eine Höchstgeschwindigkeit über 300 km/h. Solche Werte
/// verderben jede Garagen-Statistik und jeden Vergleich.
///
/// Dieselben Grenzen stehen als CHECK-Constraints auf `profile_vehicles`
/// (Migration 20260818130000_fahrzeug_plausibilitaet.sql). Client und
/// Datenbank müssen zusammenpassen — sonst scheitert ein Speichern erst am
/// Server, mit einer Fehlermeldung, die niemand versteht.
class FahrzeugGrenzen {
  const FahrzeugGrenzen._();

  /// Bugatti Chiron Super Sport: 1.600 PS. Alles darüber ist im
  /// Straßenverkehr nicht mehr plausibel, Tuning eingerechnet.
  static const int leistungMin = 1;
  static const int leistungMax = 1500;

  /// Serienrekord liegt bei rund 490 km/h. 400 deckt jedes Straßenfahrzeug ab.
  static const int topSpeedMin = 1;
  static const int topSpeedMax = 400;

  /// Schnellste Serienautos liegen bei rund 1,9 s. Unter 1,5 s ist keine
  /// Straßenzulassung mehr denkbar; über 30 s ist es kein Beschleunigungswert.
  static const double nullAufHundertMin = 1.5;
  static const double nullAufHundertMax = 30.0;

  /// Räumt eine getippte Markenschreibweise auf. Mehr nicht.
  ///
  /// 2026-08-24 (Aufgabe 2.1). Vucko wörtlich: „B-M-W ganz in Caps
  /// geschrieben und groß geschrieben soll das Gleiche sein wie B groß,
  /// M klein und W klein [...] Wichtig ist, dass das [wortident] ist,
  /// nicht ob es jetzt groß oder klein geschrieben ist."
  ///
  /// Bis heute hat diese Methode die Schreibweise GERATEN: Title-Case,
  /// plus eine Handvoll Marken aus einer Ausnahmeliste in Großbuchstaben.
  /// Raten ist an drei Stellen nachweislich falsch gewesen:
  ///   * „GasGas" wurde zu „Gasgas",
  ///   * „McLaren" wurde zu „Mclaren",
  ///   * „Mini" und „Seat" wurden zu „MINI" und „SEAT" — und damit gegen
  ///     die eigene Vorschlagsliste in vehicle_api_service.dart gedreht,
  ///     die „Mini" und „Seat" anbietet.
  ///
  /// Seit der Migration 20260824101000 entscheidet die DATENBANK, wie eine
  /// Marke heißt: `public.vehicle_brand_canonical(text)`, aufgerufen von
  /// einem Trigger auf `profile_vehicles.brand` und `profiles.car_brand`.
  /// Gemessen am 24.08. gegen die Produktivdatenbank:
  ///   bmw → BMW, gasgas → GasGas, mclaren → McLaren, mini → Mini,
  ///   seat → Seat, Vw → Volkswagen, „Zonda Tuning GmbH" → unverändert.
  /// Was die Funktion nicht kennt, lässt sie in Ruhe. Genau das kann ein
  /// Algorithmus nicht, und „Vw" zu „Volkswagen" schon gar nicht — das ist
  /// Wissen, kein Algorithmus.
  ///
  /// ENTSCHEIDUNG (Vucko schläft, keine Rückfrage möglich): der Client rät
  /// nicht mehr mit. Zwei Stellen, die dieselbe Frage unterschiedlich
  /// beantworten, laufen auseinander — dieselbe Lehre wie bei der
  /// Länder-Klassifikation, wo der Client-Wert deshalb serverseitig
  /// überschrieben wird (siehe CLAUDE.md). Hier bleibt nur das
  /// Unstrittige: Leerraum aufräumen, damit „  BMW  " und „BMW" schon vor
  /// dem Absenden gleich aussehen.
  static String normalisiereMarke(String roh) {
    return roh.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Leere Eingabe ist erlaubt — das Feld ist freiwillig.
  static String? pruefeLeistung(String? roh) {
    final t = roh?.trim() ?? '';
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return 'Bitte eine Zahl eingeben.';
    if (v < leistungMin || v > leistungMax) {
      return '$leistungMin bis $leistungMax PS';
    }
    return null;
  }

  static String? pruefeTopSpeed(String? roh) {
    final t = roh?.trim() ?? '';
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return 'Bitte eine Zahl eingeben.';
    if (v < topSpeedMin || v > topSpeedMax) {
      return '$topSpeedMin bis $topSpeedMax km/h';
    }
    return null;
  }

  static String? pruefeNullAufHundert(String? roh) {
    final t = roh?.trim() ?? '';
    if (t.isEmpty) return null;
    final v = double.tryParse(t.replaceAll(',', '.'));
    if (v == null) return 'Bitte eine Zahl eingeben.';
    if (v < nullAufHundertMin || v > nullAufHundertMax) {
      return '${nullAufHundertMin.toString().replaceAll('.', ',')} '
          'bis ${nullAufHundertMax.round()} Sekunden';
    }
    return null;
  }

  /// Erste unplausible Angabe eines Fahrzeug-Entwurfs, oder `null`.
  /// Deckt auch Fahrzeuge ab, die gerade nicht im Formular sichtbar sind.
  static String? ersterFehlerImEntwurf(Map<String, dynamic> entwurf) {
    final ps = entwurf['horsepower'];
    if (ps is num && (ps < leistungMin || ps > leistungMax)) {
      return '${entwurf['brand'] ?? 'Fahrzeug'}: $leistungMin bis '
          '$leistungMax PS';
    }
    final ts = entwurf['top_speed'];
    if (ts is num && (ts < topSpeedMin || ts > topSpeedMax)) {
      return '${entwurf['brand'] ?? 'Fahrzeug'}: $topSpeedMin bis '
          '$topSpeedMax km/h';
    }
    final s = entwurf['zero_to_hundred_seconds'];
    if (s is num && (s < nullAufHundertMin || s > nullAufHundertMax)) {
      return '${entwurf['brand'] ?? 'Fahrzeug'}: 1,5 bis 30 Sekunden '
          'auf 100';
    }
    return null;
  }
}
