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

  static const List<VehicleMake> _fallbackMakes = [
    VehicleMake(id: 0, name: 'Abarth'),
    VehicleMake(id: 0, name: 'Alfa Romeo'),
    VehicleMake(id: 0, name: 'Aston Martin'),
    VehicleMake(id: 0, name: 'Audi'),
    VehicleMake(id: 0, name: 'Bentley'),
    VehicleMake(id: 0, name: 'BMW'),
    VehicleMake(id: 0, name: 'Bugatti'),
    VehicleMake(id: 0, name: 'Chevrolet'),
    VehicleMake(id: 0, name: 'Citroen'),
    VehicleMake(id: 0, name: 'Cupra'),
    VehicleMake(id: 0, name: 'Dacia'),
    VehicleMake(id: 0, name: 'Dodge'),
    VehicleMake(id: 0, name: 'Ferrari'),
    VehicleMake(id: 0, name: 'Fiat'),
    VehicleMake(id: 0, name: 'Ford'),
    VehicleMake(id: 0, name: 'Honda'),
    VehicleMake(id: 0, name: 'Hyundai'),
    VehicleMake(id: 0, name: 'Jaguar'),
    VehicleMake(id: 0, name: 'Jeep'),
    VehicleMake(id: 0, name: 'Kia'),
    VehicleMake(id: 0, name: 'Lamborghini'),
    VehicleMake(id: 0, name: 'Land Rover'),
    VehicleMake(id: 0, name: 'Lexus'),
    VehicleMake(id: 0, name: 'Maserati'),
    VehicleMake(id: 0, name: 'Mazda'),
    VehicleMake(id: 0, name: 'McLaren'),
    VehicleMake(id: 0, name: 'Mercedes-Benz'),
    VehicleMake(id: 0, name: 'Mini'),
    VehicleMake(id: 0, name: 'Mitsubishi'),
    VehicleMake(id: 0, name: 'Nissan'),
    VehicleMake(id: 0, name: 'Opel'),
    VehicleMake(id: 0, name: 'Peugeot'),
    VehicleMake(id: 0, name: 'Porsche'),
    VehicleMake(id: 0, name: 'Renault'),
    VehicleMake(id: 0, name: 'Seat'),
    VehicleMake(id: 0, name: 'Skoda'),
    VehicleMake(id: 0, name: 'Subaru'),
    VehicleMake(id: 0, name: 'Suzuki'),
    VehicleMake(id: 0, name: 'Tesla'),
    VehicleMake(id: 0, name: 'Toyota'),
    VehicleMake(id: 0, name: 'Volkswagen'),
    VehicleMake(id: 0, name: 'Volvo'),
  ];

  static Future<List<VehicleMake>> searchMakes(String query) async {
    final needle = _normalize(query);
    if (needle.length < 2) return const [];

    try {
      final makes = await _loadMakes();
      return _filterMakes(makes, needle).take(12).toList();
    } catch (e) {
      debugPrint('[VehicleApi] Makes fallback: $e');
      return _filterMakes(_fallbackMakes, needle).take(12).toList();
    }
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
