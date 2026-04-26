import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

enum GeocodingErrorType {
  network,
  auth,
  rateLimit,
  server,
  invalidRequest,
  notFound,
  ambiguous,
  unknown,
}

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

  static void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  static String _sanitizeUri(Uri uri) => '${uri.origin}${uri.path}';

  /// Gibt Autocomplete-Vorschläge für eine Suchanfrage zurück.
  Future<List<MapboxSuggestion>> searchSuggestions(
    String query, {
    double? proximityLatitude,
    double? proximityLongitude,
    String countryCodes = 'at,de,ch',
    int limit = 7,
  }) async {
    // KEIN Zeichenlimit - sofort suchen ab 1 Zeichen
    if (query.isEmpty) return const [];

    final queryParameters = <String, String>{
      'access_token': AppConstants.mapboxPublicToken,
      'autocomplete': 'true',
      'limit': limit.clamp(1, 10).toString(),
      'language': 'de',
      'country': countryCodes,
      'types': 'address,poi,place,locality,neighborhood',
    };
    final hasProximity =
        proximityLatitude != null &&
        proximityLongitude != null &&
        proximityLatitude.isFinite &&
        proximityLongitude.isFinite;
    if (hasProximity) {
      queryParameters['proximity'] =
          '${proximityLongitude.toStringAsFixed(5)},${proximityLatitude.toStringAsFixed(5)}';
    }
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${_sanitizeSearchPath(query)}.json',
      queryParameters,
    );
    _debugLog(
      '[Geocoding] Autocomplete request: queryLength=${query.length}, endpoint=${_sanitizeUri(uri)}',
    );

    try {
      final response = await http.get(uri);
      _debugLog('[Geocoding] Autocomplete response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? const [];
        _debugLog('[Geocoding] Autocomplete results: count=${features.length}');

        return features
            .map((f) {
              // Context ist eine Liste, nicht ein Objekt!
              String? contextText;
              if (f['context'] != null && f['context'] is List) {
                final contextList = f['context'] as List;
                if (contextList.isNotEmpty) {
                  contextText = contextList
                      .map((c) => c['text'] ?? '')
                      .where((t) => t.isNotEmpty)
                      .join(', ');
                }
              }

              final center = f['center'] as List?;
              if (center == null || center.length < 2) return null;
              final distanceMeters = hasProximity
                  ? _distanceMeters(
                      proximityLatitude,
                      proximityLongitude,
                      (center[1] as num).toDouble(),
                      (center[0] as num).toDouble(),
                    )
                  : null;
              return MapboxSuggestion(
                placeName: (f['place_name'] as String?) ?? '',
                coordinates: [
                  (center[0] as num).toDouble(),
                  (center[1] as num).toDouble(),
                ],
                context: contextText,
                distanceMeters: distanceMeters,
              );
            })
            .whereType<MapboxSuggestion>()
            .toList();
      } else {
        _debugLog(
          '[Geocoding] Autocomplete failed: status=${response.statusCode}',
        );
      }
    } catch (e) {
      _debugLog('[Geocoding] Autocomplete exception: ${e.runtimeType}: $e');
    }
    return const [];
  }

  /// Geocodiert eine Adresse und gibt Koordinaten zurück.
  Future<Map<String, double>?> getCoordinatesFromAddress(
    String address, {
    double? proximityLatitude,
    double? proximityLongitude,
    bool requireUnambiguous = false,
  }) async {
    final queryParameters = <String, String>{
      'access_token': AppConstants.mapboxPublicToken,
      'limit': requireUnambiguous ? '3' : '1',
      'language': 'de',
      'country': 'at,de,ch',
      'types': 'address,poi,place,locality,neighborhood',
    };
    if (proximityLatitude != null &&
        proximityLongitude != null &&
        proximityLatitude.isFinite &&
        proximityLongitude.isFinite) {
      queryParameters['proximity'] =
          '${proximityLongitude.toStringAsFixed(5)},${proximityLatitude.toStringAsFixed(5)}';
    }
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${_sanitizeSearchPath(address)}.json',
      queryParameters,
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw _mapHttpError(statusCode: response.statusCode, requestUri: uri);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features != null && features.isNotEmpty) {
        if (requireUnambiguous && features.length > 1) {
          final topRelevance =
              (features[0]['relevance'] as num?)?.toDouble() ?? 0.0;
          final secondRelevance =
              (features[1]['relevance'] as num?)?.toDouble() ?? 0.0;
          final topText = (features[0]['place_name'] as String?) ?? '';
          final queryNormalized = _normalizeAddressText(address);
          final topNormalized = _normalizeAddressText(topText);
          final clearlyExact =
              topRelevance >= 0.96 && topNormalized.contains(queryNormalized);
          final ambiguous =
              !clearlyExact && (topRelevance - secondRelevance).abs() < 0.12;
          if (ambiguous) {
            throw GeocodingException(
              type: GeocodingErrorType.ambiguous,
              userMessage:
                  'Bitte wähle einen eindeutigen Treffer aus der Vorschlagsliste.',
              debugMessage:
                  'Ambiguous geocoding result for queryLength=${address.length} at ${_sanitizeUri(uri)}',
            );
          }
        }
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
            'Geocoding network error: ${e.message} (endpoint: ${_sanitizeUri(uri)})',
      );
    } on http.ClientException catch (e) {
      throw GeocodingException(
        type: GeocodingErrorType.network,
        userMessage: 'Keine Verbindung zum Geocoding-Dienst.',
        debugMessage:
            'Geocoding client error: ${e.message} (endpoint: ${_sanitizeUri(uri)})',
      );
    } catch (e) {
      _debugLog('[Geocoding] Lookup exception: ${e.runtimeType}: $e');
      throw GeocodingException(
        type: GeocodingErrorType.unknown,
        userMessage: 'Ziel konnte aktuell nicht aufgelöst werden.',
        debugMessage:
            'Unexpected geocoding error: $e (endpoint: ${_sanitizeUri(uri)})',
      );
    }
    if (requireUnambiguous) {
      throw GeocodingException(
        type: GeocodingErrorType.notFound,
        userMessage: 'Adresse konnte nicht gefunden werden.',
        debugMessage:
            'No geocoding results for queryLength=${address.length} at ${_sanitizeUri(uri)}',
      );
    }
    return null;
  }

  static String _normalizeAddressText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9äöüß ]'), '');

  static String _sanitizeSearchPath(String value) =>
      value.trim().replaceAll(RegExp(r'[/#?]+'), ' ');

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) =>
      degrees * 0.017453292519943295;

  GeocodingException _mapHttpError({
    required int statusCode,
    required Uri requestUri,
  }) {
    if (statusCode == 401 || statusCode == 403) {
      return GeocodingException(
        type: GeocodingErrorType.auth,
        userMessage: 'Geocoding-Anfrage wurde abgelehnt.',
        debugMessage:
            'Geocoding auth error ($statusCode) at ${_sanitizeUri(requestUri)}',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return GeocodingException(
        type: GeocodingErrorType.rateLimit,
        userMessage: 'Zu viele Geocoding-Anfragen. Bitte kurz warten.',
        debugMessage:
            'Geocoding rate limit ($statusCode) at ${_sanitizeUri(requestUri)}',
        statusCode: statusCode,
      );
    }
    if (statusCode >= 500) {
      return GeocodingException(
        type: GeocodingErrorType.server,
        userMessage: 'Geocoding-Dienst ist derzeit nicht verfügbar.',
        debugMessage:
            'Geocoding server error ($statusCode) at ${_sanitizeUri(requestUri)}',
        statusCode: statusCode,
      );
    }
    return GeocodingException(
      type: GeocodingErrorType.invalidRequest,
      userMessage: 'Adresse konnte nicht verarbeitet werden.',
      debugMessage:
          'Geocoding request invalid ($statusCode) at ${_sanitizeUri(requestUri)}',
      statusCode: statusCode,
    );
  }
}
