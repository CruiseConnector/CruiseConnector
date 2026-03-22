import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

/// Mapbox Geocoding & Autocomplete Service
class GeocodingService {
  const GeocodingService();

  static const String _baseUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// Gibt Autocomplete-Vorschläge für eine Suchanfrage zurück.
  Future<List<MapboxSuggestion>> searchSuggestions(String query) async {
    // KEIN Zeichenlimit - sofort suchen ab 1 Zeichen
    if (query.isEmpty) return const [];

    debugPrint('GeocodingService: Suche nach "$query"');

    final uri = Uri.parse(
      '$_baseUrl/${Uri.encodeComponent(query)}.json'
      '?access_token=${AppConstants.mapboxPublicToken}'
      '&autocomplete=true&limit=5&language=de',
    );

    try {
      final response = await http.get(uri);
      debugPrint('GeocodingService: Response ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? const [];
        debugPrint('GeocodingService: ${features.length} Ergebnisse gefunden');
        
        return features
            .map(
              (f) {
                // Context ist eine Liste, nicht ein Objekt!
                String? contextText;
                if (f['context'] != null && f['context'] is List) {
                  final contextList = f['context'] as List;
                  if (contextList.isNotEmpty) {
                    contextText = contextList.map((c) => c['text'] ?? '').where((t) => t.isNotEmpty).join(', ');
                  }
                }
                
                final center = f['center'] as List?;
                if (center == null || center.length < 2) return null;
                return MapboxSuggestion(
                  placeName: (f['place_name'] as String?) ?? '',
                  coordinates: [
                    (center[0] as num).toDouble(),
                    (center[1] as num).toDouble(),
                  ],
                  context: contextText,
                );
              },
            )
            .whereType<MapboxSuggestion>()
            .toList();
      } else {
        debugPrint('GeocodingService API Fehler: ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('GeocodingService.searchSuggestions Fehler: $e');
      debugPrint('Stack: $stack');
    }
    return const [];
  }

  /// Geocodiert eine Adresse und gibt Koordinaten zurück.
  Future<Map<String, double>?> getCoordinatesFromAddress(
    String address,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/${Uri.encodeComponent(address)}.json'
      '?access_token=${AppConstants.mapboxPublicToken}&limit=1',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final center = features[0]['center'] as List?;
          if (center != null && center.length >= 2) {
            return {
              'longitude': (center[0] as num).toDouble(),
              'latitude': (center[1] as num).toDouble(),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('GeocodingService.getCoordinatesFromAddress Fehler: $e');
    }
    return null;
  }
}
