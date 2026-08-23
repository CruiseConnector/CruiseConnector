import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VehicleMake {
  const VehicleMake({required this.id, required this.name});

  final int id;
  final String name;
}

class VehicleModel {
  const VehicleModel({required this.id, required this.name});

  final int id;
  final String name;
}

class VehicleApiService {
  VehicleApiService._();

  static const _baseUrl = 'vpic.nhtsa.dot.gov';
  static final http.Client _client = http.Client();
  static List<VehicleMake>? _cachedMakes;
  static final Map<String, List<VehicleModel>> _modelCache = {};

  /// Die gepflegte Markenliste. DIE Quelle der Schreibweise im Client.
  ///
  /// 2026-08-24 (Aufgabe 2.1). Vucko wörtlich: „B-M-W ganz in Caps
  /// geschrieben und groß geschrieben soll das Gleiche sein wie B groß,
  /// M klein und W klein [...] Wichtig ist, dass das [wortident] ist."
  ///
  /// Warum diese Liste jetzt VOR der NHTSA-Abfrage kommt und nicht mehr
  /// nur ihr Rückfall ist: die NHTSA ist eine US-Behördendatenbank. Sie
  /// liefert 12.340 Einträge, ALLE in Großbuchstaben, dazu Firmennamen wie
  /// „102 IRONWORKS, INC." und „MINI BIG TRUCKS". Škoda und Seat fehlen
  /// dort ganz. Genau daher stammen die Zeilen „AUDI" und „VOLKSWAGEN" in
  /// der Produktivdatenbank (gemessen am 24.08.: 36 Schreibweisen für 77
  /// Fahrzeuge). Eine Vorschlagsliste, die falsche Schreibweisen anbietet,
  /// ist selbst eine Ursache des Problems.
  ///
  /// Die Schreibweisen hier sind zeichengleich mit der kanonischen Spalte
  /// von `public.vehicle_brand_alias` (Migration 20260824101000). Wer hier
  /// etwas ändert, muss die Tabelle mitziehen, sonst schreibt der Server
  /// etwas anderes, als der Nutzer angetippt hat. Der Test
  /// `test/domain/marken_liste_test.dart` vergleicht beide Dateien.
  ///
  /// 2026-08-24 ergänzt um Motorräder und Kleinkrafträder: die Garage
  /// kennt `vehicle_type` = motorcycle, die Liste kannte bis heute keine
  /// einzige Motorradmarke. Beta (8 Personen), Rieju (5) und Aprilia (3)
  /// gehören zu den zehn häufigsten Marken der Nutzerschaft.
  static const List<VehicleMake> kuratierteMarken = [
    VehicleMake(id: 0, name: 'Abarth'),
    VehicleMake(id: 0, name: 'Acura'),
    VehicleMake(id: 0, name: 'Alfa Romeo'),
    VehicleMake(id: 0, name: 'Alpine'),
    VehicleMake(id: 0, name: 'Aprilia'),
    VehicleMake(id: 0, name: 'Aston Martin'),
    VehicleMake(id: 0, name: 'Audi'),
    VehicleMake(id: 0, name: 'Benelli'),
    VehicleMake(id: 0, name: 'Bentley'),
    VehicleMake(id: 0, name: 'Beta'),
    VehicleMake(id: 0, name: 'BMW'),
    VehicleMake(id: 0, name: 'Bugatti'),
    VehicleMake(id: 0, name: 'Buick'),
    VehicleMake(id: 0, name: 'BYD'),
    VehicleMake(id: 0, name: 'Cadillac'),
    VehicleMake(id: 0, name: 'Cagiva'),
    VehicleMake(id: 0, name: 'CFMoto'),
    VehicleMake(id: 0, name: 'Chevrolet'),
    VehicleMake(id: 0, name: 'Chrysler'),
    VehicleMake(id: 0, name: 'Citroen'),
    VehicleMake(id: 0, name: 'Cupra'),
    VehicleMake(id: 0, name: 'Dacia'),
    VehicleMake(id: 0, name: 'Daihatsu'),
    VehicleMake(id: 0, name: 'Derbi'),
    VehicleMake(id: 0, name: 'Dodge'),
    VehicleMake(id: 0, name: 'DS'),
    VehicleMake(id: 0, name: 'Ducati'),
    VehicleMake(id: 0, name: 'Fantic'),
    VehicleMake(id: 0, name: 'Ferrari'),
    VehicleMake(id: 0, name: 'Fiat'),
    VehicleMake(id: 0, name: 'Ford'),
    VehicleMake(id: 0, name: 'GasGas'),
    VehicleMake(id: 0, name: 'Genesis'),
    VehicleMake(id: 0, name: 'GMC'),
    VehicleMake(id: 0, name: 'Harley-Davidson'),
    VehicleMake(id: 0, name: 'Honda'),
    VehicleMake(id: 0, name: 'Husaberg'),
    VehicleMake(id: 0, name: 'Husqvarna'),
    VehicleMake(id: 0, name: 'Hyundai'),
    VehicleMake(id: 0, name: 'Indian'),
    VehicleMake(id: 0, name: 'Infiniti'),
    VehicleMake(id: 0, name: 'Isuzu'),
    VehicleMake(id: 0, name: 'Jaguar'),
    VehicleMake(id: 0, name: 'Jeep'),
    VehicleMake(id: 0, name: 'Kawasaki'),
    VehicleMake(id: 0, name: 'Keeway'),
    VehicleMake(id: 0, name: 'Kia'),
    VehicleMake(id: 0, name: 'Kreidler'),
    VehicleMake(id: 0, name: 'KTM'),
    VehicleMake(id: 0, name: 'Kymco'),
    VehicleMake(id: 0, name: 'Lada'),
    VehicleMake(id: 0, name: 'Lamborghini'),
    VehicleMake(id: 0, name: 'Lancia'),
    VehicleMake(id: 0, name: 'Land Rover'),
    VehicleMake(id: 0, name: 'Lexus'),
    VehicleMake(id: 0, name: 'Lincoln'),
    VehicleMake(id: 0, name: 'Malaguti'),
    VehicleMake(id: 0, name: 'Maserati'),
    VehicleMake(id: 0, name: 'Mazda'),
    VehicleMake(id: 0, name: 'McLaren'),
    VehicleMake(id: 0, name: 'Mercedes-Benz'),
    VehicleMake(id: 0, name: 'MG'),
    VehicleMake(id: 0, name: 'Mini'),
    VehicleMake(id: 0, name: 'Mitsubishi'),
    VehicleMake(id: 0, name: 'Moto Guzzi'),
    VehicleMake(id: 0, name: 'MV Agusta'),
    VehicleMake(id: 0, name: 'NIO'),
    VehicleMake(id: 0, name: 'Nissan'),
    VehicleMake(id: 0, name: 'Opel'),
    VehicleMake(id: 0, name: 'Peugeot'),
    VehicleMake(id: 0, name: 'Piaggio'),
    VehicleMake(id: 0, name: 'Polestar'),
    VehicleMake(id: 0, name: 'Porsche'),
    VehicleMake(id: 0, name: 'Puch'),
    VehicleMake(id: 0, name: 'Puma'),
    VehicleMake(id: 0, name: 'RAM'),
    VehicleMake(id: 0, name: 'Renault'),
    VehicleMake(id: 0, name: 'Rieju'),
    VehicleMake(id: 0, name: 'Rover'),
    VehicleMake(id: 0, name: 'Royal Enfield'),
    VehicleMake(id: 0, name: 'Saab'),
    VehicleMake(id: 0, name: 'Seat'),
    VehicleMake(id: 0, name: 'Sherco'),
    VehicleMake(id: 0, name: 'Simson'),
    VehicleMake(id: 0, name: 'Skoda'),
    VehicleMake(id: 0, name: 'Smart'),
    VehicleMake(id: 0, name: 'SsangYong'),
    VehicleMake(id: 0, name: 'Subaru'),
    VehicleMake(id: 0, name: 'Suzuki'),
    VehicleMake(id: 0, name: 'SWM'),
    VehicleMake(id: 0, name: 'SYM'),
    VehicleMake(id: 0, name: 'Tesla'),
    VehicleMake(id: 0, name: 'TM Racing'),
    VehicleMake(id: 0, name: 'Toyota'),
    VehicleMake(id: 0, name: 'Triumph'),
    VehicleMake(id: 0, name: 'Vespa'),
    VehicleMake(id: 0, name: 'Voge'),
    VehicleMake(id: 0, name: 'Volkswagen'),
    VehicleMake(id: 0, name: 'Volvo'),
    VehicleMake(id: 0, name: 'Xpeng'),
    VehicleMake(id: 0, name: 'Yamaha'),
    VehicleMake(id: 0, name: 'Zero'),
    VehicleMake(id: 0, name: 'Zontes'),
    VehicleMake(id: 0, name: 'Zündapp'),
  ];

  /// Firmenmüll aus der NHTSA erkennen: „102 IRONWORKS, INC.",
  /// „MINI BIG TRUCKS", „AB VOLVO PENTA". Solche Zeilen sind keine Marken,
  /// die ein Cruiser fährt, und sie stehen in der Trefferliste vor der
  /// echten Marke, weil sie mit demselben Wort anfangen.
  static final RegExp _firmenmuell = RegExp(
    r'(,|\b(inc|llc|ltd|corp|corporation|company|co|gmbh|ag|kg|sa|srl|'
    r'nv|bv|plc|group|holdings?|industries|manufacturing|trailers?|'
    r'trucks?|coach|bus|marine|equipment)\b)',
    caseSensitive: false,
  );

  /// Die Treffer aus der gepflegten Liste allein, ohne Netz.
  ///
  /// Eigene Methode, damit die Reihenfolge prüfbar ist: der Test
  /// `test/domain/marken_liste_test.dart` fragt sie direkt und braucht dafür
  /// weder HTTP noch eine Zeitüberschreitung.
  static List<VehicleMake> gepflegteTreffer(String query) {
    final needle = _normalize(query);
    if (needle.length < 2) return const [];
    return _filterMakes(kuratierteMarken, needle).take(12).toList();
  }

  static Future<List<VehicleMake>> searchMakes(String query) async {
    final needle = _normalize(query);
    if (needle.length < 2) return const [];

    // 1) Immer zuerst die gepflegte Liste. Sie ist offline da, sofort da
    //    und in der richtigen Schreibweise.
    final treffer = gepflegteTreffer(query);
    if (treffer.length >= 12) return treffer;

    // 2) Erst danach die NHTSA, und nur zum Auffüllen: Nischenmarken, die
    //    die gepflegte Liste nicht kennt. Was die gepflegte Liste kennt,
    //    wird NIE durch die Großbuchstaben-Fassung der Behörde ersetzt.
    final bekannt = {
      for (final make in kuratierteMarken) _normalize(make.name),
    };
    try {
      final makes = await _loadMakes();
      for (final make in _filterMakes(makes, needle)) {
        if (bekannt.contains(_normalize(make.name))) continue;
        if (_firmenmuell.hasMatch(make.name)) continue;
        treffer.add(make);
        if (treffer.length >= 12) break;
      }
    } catch (e) {
      debugPrint('[VehicleApi] NHTSA nicht erreichbar, nur gepflegte Liste: $e');
    }
    return treffer.take(12).toList();
  }

  static Future<List<VehicleModel>> searchModels({
    required String make,
    required String query,
    int? year,
  }) async {
    final cleanedMake = make.trim();
    final needle = _normalize(query);
    if (cleanedMake.length < 2 || needle.isEmpty) return const [];

    try {
      final models = await _loadModelsForMake(cleanedMake, year: year);
      return models
          .where((model) => _normalize(model.name).contains(needle))
          .take(12)
          .toList();
    } catch (e) {
      debugPrint('[VehicleApi] Models failed: $e');
      return const [];
    }
  }

  static Future<List<VehicleMake>> _loadMakes() async {
    final cached = _cachedMakes;
    if (cached != null) return cached;

    final uri = Uri.https(_baseUrl, '/api/vehicles/GetAllMakes', {
      'format': 'json',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('GetAllMakes HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['Results'] as List? ?? const [];
    final seen = <String>{};
    final makes = <VehicleMake>[];

    for (final row in results) {
      if (row is! Map) continue;
      final name = (row['Make_Name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final normalized = _normalize(name);
      if (!seen.add(normalized)) continue;
      makes.add(
        VehicleMake(id: (row['Make_ID'] as num?)?.toInt() ?? 0, name: name),
      );
    }

    makes.sort((a, b) => a.name.compareTo(b.name));
    _cachedMakes = makes;
    return makes;
  }

  static Future<List<VehicleModel>> _loadModelsForMake(
    String make, {
    int? year,
  }) async {
    final cacheKey = '${_normalize(make)}:${year ?? 'all'}';
    final cached = _modelCache[cacheKey];
    if (cached != null) return cached;

    final Uri uri;
    if (year != null && year > 1995) {
      uri = Uri.https(
        _baseUrl,
        '/api/vehicles/GetModelsForMakeYear/make/$make/modelyear/$year',
        {'format': 'json'},
      );
    } else {
      uri = Uri.https(_baseUrl, '/api/vehicles/GetModelsForMake/$make', {
        'format': 'json',
      });
    }

    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Models HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['Results'] as List? ?? const [];
    final seen = <String>{};
    final models = <VehicleModel>[];

    for (final row in results) {
      if (row is! Map) continue;
      final name = (row['Model_Name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final normalized = _normalize(name);
      if (!seen.add(normalized)) continue;
      models.add(
        VehicleModel(id: (row['Model_ID'] as num?)?.toInt() ?? 0, name: name),
      );
    }

    models.sort((a, b) => a.name.compareTo(b.name));
    _modelCache[cacheKey] = models;
    return models;
  }

  static Iterable<VehicleMake> _filterMakes(
    List<VehicleMake> makes,
    String needle,
  ) {
    return makes.where((make) {
      final name = _normalize(make.name);
      return name.startsWith(needle) || name.contains(' $needle');
    });
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
