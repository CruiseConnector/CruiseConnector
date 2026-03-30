import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

enum GeocodingErrorType { network, auth, rateLimit, server, invalidRequest, unknown }

class GeocodingException implements Exception {
  GeocodingException({
    required this.type,
    required this.userMessage,
    required this.debugMessage,
    this.statusCode,
  });

  final GeocodingErrorType type;
  final String userMessage;
  final String debugMessage;
  final int? statusCode;

  @override
  String toString() =>
      'GeocodingException(type: $type, status: $statusCode, debug: $debugMessage)';
}

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
      if (response.statusCode != 200) {
        throw _mapHttpError(
          statusCode: response.statusCode,
          body: response.body,
          requestUri: uri,
        );
      }

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
    } on GeocodingException {
      rethrow;
    } on SocketException catch (e) {
      throw GeocodingException(
        type: GeocodingErrorType.network,
        userMessage: 'Keine Verbindung zum Geocoding-Dienst.',
        debugMessage:
            'Geocoding network error for "$address": ${e.message} (uri: $uri)',
      );
    } on http.ClientException catch (e) {
      throw GeocodingException(
        type: GeocodingErrorType.network,
        userMessage: 'Keine Verbindung zum Geocoding-Dienst.',
        debugMessage:
            'Geocoding client error for "$address": ${e.message} (uri: $uri)',
      );
    } catch (e, stack) {
      debugPrint('GeocodingService.getCoordinatesFromAddress Fehler: $e');
      debugPrint('Stack: $stack');
      throw GeocodingException(
        type: GeocodingErrorType.unknown,
        userMessage: 'Ziel konnte aktuell nicht aufgelöst werden.',
        debugMessage:
            'Unexpected geocoding error for "$address": $e (uri: $uri)',
      );
    }
    return null;
  }

  GeocodingException _mapHttpError({
    required int statusCode,
    required String body,
    required Uri requestUri,
  }) {
    final bodyShort = body.length > 280 ? '${body.substring(0, 280)}...' : body;
    if (statusCode == 401 || statusCode == 403) {
      return GeocodingException(
        type: GeocodingErrorType.auth,
        userMessage: 'Geocoding-Anfrage wurde abgelehnt.',
        debugMessage:
            'Geocoding auth error ($statusCode) at $requestUri body=$bodyShort',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return GeocodingException(
        type: GeocodingErrorType.rateLimit,
        userMessage: 'Zu viele Geocoding-Anfragen. Bitte kurz warten.',
        debugMessage:
            'Geocoding rate limit ($statusCode) at $requestUri body=$bodyShort',
        statusCode: statusCode,
      );
    }
    if (statusCode >= 500) {
      return GeocodingException(
        type: GeocodingErrorType.server,
        userMessage: 'Geocoding-Dienst ist derzeit nicht verfügbar.',
        debugMessage:
            'Geocoding server error ($statusCode) at $requestUri body=$bodyShort',
        statusCode: statusCode,
      );
    }
    return GeocodingException(
      type: GeocodingErrorType.invalidRequest,
      userMessage: 'Adresse konnte nicht verarbeitet werden.',
      debugMessage:
          'Geocoding request invalid ($statusCode) at $requestUri body=$bodyShort',
      statusCode: statusCode,
    );
  }
}
