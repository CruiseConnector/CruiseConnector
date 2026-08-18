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

  /// Marken, die üblicherweise komplett groß geschrieben werden. Ohne diese
  /// Liste würde die Vereinheitlichung aus „BMW" ein „Bmw" machen.
  static const Set<String> _grossgeschrieben = {
    'BMW', 'VW', 'KTM', 'SEAT', 'AMG', 'MINI', 'MG', 'DS', 'GMC', 'RAM',
    'SRT', 'TVR', 'FSO', 'ZAZ', 'UAZ', 'BYD', 'NIO', 'RUF', 'ABT', 'MV',
  };

  /// Vereinheitlicht die Markenschreibweise, damit `audi`, `Audi` und
  /// ` AUDI ` nicht als drei Marken gezählt werden.
  static String normalisiereMarke(String roh) {
    final geputzt = roh.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (geputzt.isEmpty) return '';
    return geputzt
        .split(' ')
        .map((wort) {
          final gross = wort.toUpperCase();
          if (_grossgeschrieben.contains(gross)) return gross;
          // Bindestrich-Namen: „mercedes-benz" → „Mercedes-Benz".
          return wort
              .split('-')
              .map(
                (teil) => teil.isEmpty
                    ? teil
                    : teil[0].toUpperCase() + teil.substring(1).toLowerCase(),
              )
              .join('-');
        })
        .join(' ');
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
