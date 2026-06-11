import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/domain/models/place_suggestion.dart';

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

/// Self-hosted Geocoding & Autocomplete via Supabase Edge Function `geocode`.
class GeocodingService {
  const GeocodingService();

  static const String _functionName = 'geocode';
  static final Map<String, List<PlaceSuggestion>> _suggestCache =
      <String, List<PlaceSuggestion>>{};
  static const int _suggestCacheMax = 24;

  static void _cacheSuggestions(String key, List<PlaceSuggestion> value) {
    if (value.isEmpty) return;
    _suggestCache.remove(key);
    _suggestCache[key] = value;
    if (_suggestCache.length > _suggestCacheMax) {
      _suggestCache.remove(_suggestCache.keys.first);
    }
  }

  static void _debugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Gibt Autocomplete-Vorschläge für eine Suchanfrage zurück.
  Future<List<PlaceSuggestion>> searchSuggestions(
    String query, {
    double? proximityLatitude,
    double? proximityLongitude,
    String countryCodes = 'at,de,ch',
    int limit = 7,
  }) async {
    if (query.isEmpty) return const [];
    final searchQuery = _normalizePoiSearchAlias(query);
    final cacheKey =
        '$searchQuery|$countryCodes|$limit|'
        '${proximityLatitude?.toStringAsFixed(3) ?? "n"},'
        '${proximityLongitude?.toStringAsFixed(3) ?? "n"}';
    final cached = _suggestCache[cacheKey];
    if (cached != null) return cached;

    try {
      final result = await _fetchSuggestions(
        searchQuery,
        proximityLatitude: proximityLatitude,
        proximityLongitude: proximityLongitude,
        countryCodes: countryCodes,
        limit: limit,
        timeout: const Duration(seconds: 4),
      );
      _cacheSuggestions(cacheKey, result);
      return result;
    } catch (e) {
      _debugLog('[Geocoding] Autocomplete failed: ${e.runtimeType}: $e');
      return const [];
    }
  }

  /// Reverse-Geocoding: Koordinaten → lesbarer Ortsname.
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    try {
      final data = await _invokeSelfHostedGeocoder(<String, dynamic>{
        'type': 'reverse',
        'latitude': latitude,
        'longitude': longitude,
        'language': 'de',
        'limit': 1,
      }, timeout: const Duration(seconds: 6));
      final features = _featuresFromPayload(data);
      if (features.isEmpty) return null;
      final first = _suggestionFromFeature(features.first);
      final text = first?.placeName.trim();
      return text == null || text.isEmpty ? null : text;
    } catch (e) {
      _debugLog('[Geocoding] Reverse-Geocode failed: ${e.runtimeType}: $e');
      return null;
    }
  }

  /// Geocodiert eine Adresse und gibt Koordinaten zurück.
  Future<Map<String, double>?> getCoordinatesFromAddress(
    String address, {
    double? proximityLatitude,
    double? proximityLongitude,
    bool requireUnambiguous = false,
  }) async {
    final searchAddress = _normalizePoiSearchAlias(address);
    try {
      final suggestions = await _fetchSuggestions(
        searchAddress,
        proximityLatitude: proximityLatitude,
        proximityLongitude: proximityLongitude,
        countryCodes: 'at,de,ch',
        limit: requireUnambiguous ? 3 : 1,
        timeout: const Duration(seconds: 6),
      );
      if (suggestions.isEmpty) {
        if (requireUnambiguous) {
          throw GeocodingException(
            type: GeocodingErrorType.notFound,
            userMessage: 'Adresse konnte nicht gefunden werden.',
            debugMessage:
                'No self-hosted geocoding results for queryLength=${address.length}',
          );
        }
        return null;
      }

      if (requireUnambiguous &&
          suggestions.length > 1 &&
          _looksAmbiguous(address, suggestions)) {
        throw GeocodingException(
          type: GeocodingErrorType.ambiguous,
          userMessage:
              'Bitte wähle einen eindeutigen Treffer aus der Vorschlagsliste.',
          debugMessage:
              'Ambiguous self-hosted geocoding result for queryLength=${address.length}',
        );
      }

      final first = suggestions.first;
      return {'longitude': first.longitude, 'latitude': first.latitude};
    } on GeocodingException {
      rethrow;
    } catch (e) {
      _debugLog('[Geocoding] Lookup exception: ${e.runtimeType}: $e');
      throw GeocodingException(
        type: GeocodingErrorType.unknown,
        userMessage: 'Ziel konnte aktuell nicht aufgelöst werden.',
        debugMessage:
            'Unexpected self-hosted geocoding error: ${e.runtimeType}',
      );
    }
  }

  Future<List<PlaceSuggestion>> _fetchSuggestions(
    String query, {
    double? proximityLatitude,
    double? proximityLongitude,
    required String countryCodes,
    required int limit,
    required Duration timeout,
  }) async {
    final data = await _invokeSelfHostedGeocoder(<String, dynamic>{
      'type': 'search',
      'query': query,
      'language': 'de',
      'country_codes': countryCodes,
      'limit': limit.clamp(1, 10),
      if (proximityLatitude != null &&
          proximityLongitude != null &&
          proximityLatitude.isFinite &&
          proximityLongitude.isFinite) ...{
        'proximity_latitude': proximityLatitude,
        'proximity_longitude': proximityLongitude,
      },
    }, timeout: timeout);
    final features = _featuresFromPayload(data);
    final hasProximity =
        proximityLatitude != null &&
        proximityLongitude != null &&
        proximityLatitude.isFinite &&
        proximityLongitude.isFinite;
    final suggestions = <PlaceSuggestion>[];
    for (final feature in features) {
      final suggestion = _suggestionFromFeature(
        feature,
        proximityLatitude: proximityLatitude,
        proximityLongitude: proximityLongitude,
      );
      if (suggestion == null || suggestion.placeName.trim().isEmpty) continue;
      suggestions.add(suggestion);
    }
    if (hasProximity) {
      suggestions.sort((a, b) {
        final ad = a.distanceMeters ?? double.infinity;
        final bd = b.distanceMeters ?? double.infinity;
        return ad.compareTo(bd);
      });
    }
    return suggestions;
  }

  Future<Map<String, dynamic>> _invokeSelfHostedGeocoder(
    Map<String, dynamic> body, {
    required Duration timeout,
  }) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke(_functionName, body: body)
          .timeout(timeout);
      final status = response.status;
      final data = _mapFromResponse(response.data);
      if (status >= 400) {
        throw _functionExceptionFromPayload(status, data);
      }
      return data;
    } on TimeoutException {
      throw GeocodingException(
        type: GeocodingErrorType.network,
        userMessage: 'Geocoding-Dienst antwortet nicht rechtzeitig.',
        debugMessage: 'Self-hosted geocoding timeout',
      );
    } on FunctionException catch (e) {
      throw GeocodingException(
        type: _errorTypeForStatus(e.status),
        userMessage: _userMessageForStatus(e.status),
        debugMessage: 'Self-hosted geocoding function error: ${e.status}',
        statusCode: e.status,
      );
    }
  }

  static Map<String, dynamic> _mapFromResponse(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  static GeocodingException _functionExceptionFromPayload(
    int status,
    Map<String, dynamic> data,
  ) {
    final error = data['error'] as String?;
    if (error == 'self_hosted_geocoder_not_configured') {
      return GeocodingException(
        type: GeocodingErrorType.server,
        userMessage: 'Geocoding-Dienst ist noch nicht konfiguriert.',
        debugMessage: error!,
        statusCode: status,
      );
    }
    return GeocodingException(
      type: _errorTypeForStatus(status),
      userMessage: _userMessageForStatus(status),
      debugMessage: error ?? 'self_hosted_geocoder_http_$status',
      statusCode: status,
    );
  }

  static GeocodingErrorType _errorTypeForStatus(int? status) {
    if (status == 401 || status == 403) return GeocodingErrorType.auth;
    if (status == 429) return GeocodingErrorType.rateLimit;
    if (status != null && status >= 500) return GeocodingErrorType.server;
    if (status != null && status >= 400) {
      return GeocodingErrorType.invalidRequest;
    }
    return GeocodingErrorType.unknown;
  }

  static String _userMessageForStatus(int? status) {
    if (status == 401 || status == 403) {
      return 'Geocoding-Anfrage wurde abgelehnt.';
    }
    if (status == 429) {
      return 'Zu viele Geocoding-Anfragen. Bitte kurz warten.';
    }
    if (status != null && status >= 500) {
      return 'Geocoding-Dienst ist derzeit nicht verfügbar.';
    }
    return 'Geocoding-Anfrage konnte nicht verarbeitet werden.';
  }

  static List<Map<String, dynamic>> _featuresFromPayload(
    Map<String, dynamic> data,
  ) {
    final raw = data['features'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
  }

  static PlaceSuggestion? _suggestionFromFeature(
    Map<String, dynamic> feature, {
    double? proximityLatitude,
    double? proximityLongitude,
  }) {
    final center = feature['center'];
    if (center is! List || center.length < 2) return null;
    final lng = _numToDouble(center[0]);
    final lat = _numToDouble(center[1]);
    if (lng == null || lat == null) return null;
    final placeName =
        (feature['place_name'] as String?) ??
        (feature['name'] as String?) ??
        '';
    final context = feature['context'] as String?;
    final hasProximity =
        proximityLatitude != null &&
        proximityLongitude != null &&
        proximityLatitude.isFinite &&
        proximityLongitude.isFinite;
    return PlaceSuggestion(
      placeName: placeName,
      coordinates: [lng, lat],
      context: context,
      distanceMeters: hasProximity
          ? _distanceMeters(proximityLatitude, proximityLongitude, lat, lng)
          : null,
    );
  }

  static double? _numToDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _looksAmbiguous(String query, List<PlaceSuggestion> suggestions) {
    if (suggestions.length < 2) return false;
    final normalizedQuery = _normalizeAddressText(
      _normalizePoiSearchAlias(query),
    );
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .toList();
    if (tokens.isEmpty) return false;
    final top = _normalizeAddressText(suggestions.first.placeName);
    final second = _normalizeAddressText(suggestions[1].placeName);
    final topMatches = tokens.where(top.contains).length;
    final secondMatches = tokens.where(second.contains).length;
    return secondMatches >= topMatches && top != second;
  }

  static String _normalizeAddressText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9äöüß ]'), '');

  static String _normalizePoiSearchAlias(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .replaceFirst(RegExp(r'\bmci\b', caseSensitive: false), 'McDonalds')
        .replaceFirst(
          RegExp(r'\bmc\s*donalds\b', caseSensitive: false),
          "McDonald's",
        );
  }

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
}
