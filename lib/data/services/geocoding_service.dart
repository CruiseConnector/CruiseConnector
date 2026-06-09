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

  // 2026-06-09 (vucko A→B-Latenz): kleiner LRU-Cache für Autocomplete. Tippt der
  // User zurück/erneut die gleiche Anfrage (sehr häufig), kommt das Ergebnis SOFORT
  // ohne Netz-Round-Trip (Google-Maps-Gefühl). Statisch, weil GeocodingService const
  // ist; geteilt über alle Felder, unkritisch (nur Vorschlags-Cache).
  static final Map<String, List<MapboxSuggestion>> _suggestCache =
      <String, List<MapboxSuggestion>>{};
  static const int _suggestCacheMax = 24;

  static void _cacheSuggestions(String key, List<MapboxSuggestion> value) {
    if (value.isEmpty) return;
    _suggestCache.remove(key);
    _suggestCache[key] = value;
    if (_suggestCache.length > _suggestCacheMax) {
      _suggestCache.remove(_suggestCache.keys.first);
    }
  }

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
    final searchQuery = _normalizePoiSearchAlias(query);
    final cacheKey = '$searchQuery|$countryCodes|$limit';
    final cached = _suggestCache[cacheKey];
    if (cached != null) return cached; // Cache-Treffer → sofort, kein Netz

    final queryParameters = <String, String>{
      'access_token': AppConstants.mapboxPublicToken,
      'autocomplete': 'true',
      'limit': limit.clamp(1, 10).toString(),
      'language': 'de',
      'country': countryCodes,
      // 2026-05-28 (vucko Startup-V Issue 4): poi ZUERST, damit bekannte
      // Marken-POIs ("McDonald's", "Flughafen Wien") vor reinen
      // Straßen-Matches ranken. language=de + proximity (unten) sorgen für
      // den nächstgelegenen, deutschsprachigen Treffer.
      'types': 'poi,place,address,locality,neighborhood',
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
      '/geocoding/v5/mapbox.places/${_sanitizeSearchPath(searchQuery)}.json',
      queryParameters,
    );
    _debugLog(
      '[Geocoding] Autocomplete request: queryLength=${query.length}, endpoint=${_sanitizeUri(uri)}',
    );

    try {
      // 2026-06-09 (vucko A→B-Latenz): HARTES Timeout. Ohne dies hing ein einzelner
      // langsamer/stehender Mapbox-Response den TypeAheadField-Spinner UNENDLICH
      // („ewig nicht geladen"). 4s → spätestens dann leere Liste statt Dauerladen.
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      _debugLog('[Geocoding] Autocomplete response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? const [];
        _debugLog('[Geocoding] Autocomplete results: count=${features.length}');

        final geocodingSuggestions = features
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
        var result = geocodingSuggestions;
        if (_shouldPreferSearchBoxPoi(query, geocodingSuggestions)) {
          final searchBox = await _searchBoxSuggestions(
            searchQuery,
            proximityLatitude: proximityLatitude,
            proximityLongitude: proximityLongitude,
            countryCodes: countryCodes,
            limit: limit,
          );
          if (searchBox.isNotEmpty) result = searchBox;
        }
        _cacheSuggestions(cacheKey, result);
        return result;
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

  Future<List<MapboxSuggestion>> _searchBoxSuggestions(
    String query, {
    double? proximityLatitude,
    double? proximityLongitude,
    required String countryCodes,
    required int limit,
  }) async {
    final sessionToken =
        'cc-${DateTime.now().microsecondsSinceEpoch}-${query.hashCode.abs()}';
    final queryParameters = <String, String>{
      'access_token': AppConstants.mapboxPublicToken,
      'q': query,
      'limit': limit.clamp(1, 6).toString(),
      'language': 'de',
      'country': countryCodes.toUpperCase(),
      'types': 'poi,address,place',
      'session_token': sessionToken,
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
    final suggestUri = Uri.https(
      'api.mapbox.com',
      '/search/searchbox/v1/suggest',
      queryParameters,
    );
    try {
      final response =
          await http.get(suggestUri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const [];
      final data = json.decode(response.body) as Map<String, dynamic>;
      final suggestions = data['suggestions'] as List? ?? const [];
      // 2026-06-09 (vucko A→B-Latenz): Die Mapbox-SearchBox liefert pro Vorschlag
      // KEINE Koordinaten — jeder braucht einen eigenen /retrieve-Call. Früher lief
      // das in einer SEQUENZIELLEN Schleife (bis zu 6× await hintereinander) → pro
      // Tastendruck bis zu 1 suggest + 6 retrieves NACHEINANDER = „unmengen an Zeit".
      // Jetzt: Top-4 PARALLEL via Future.wait → ~1 statt 4-6 Round-Trips, Reihenfolge
      // bleibt erhalten.
      final ids = <String>[];
      for (final suggestion in suggestions.take(limit.clamp(1, 4))) {
        if (suggestion is! Map<String, dynamic>) continue;
        final id = suggestion['mapbox_id'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
      final retrievedList = await Future.wait(
        ids.map(
          (id) => _retrieveSearchBoxSuggestion(
            id,
            sessionToken: sessionToken,
            proximityLatitude: proximityLatitude,
            proximityLongitude: proximityLongitude,
          ).catchError((Object _) => null),
        ),
      );
      return retrievedList.whereType<MapboxSuggestion>().toList();
    } catch (e) {
      _debugLog('[Geocoding] Search Box fallback failed: ${e.runtimeType}');
      return const [];
    }
  }

  Future<MapboxSuggestion?> _retrieveSearchBoxSuggestion(
    String mapboxId, {
    required String sessionToken,
    double? proximityLatitude,
    double? proximityLongitude,
  }) async {
    final retrieveUri = Uri.https(
      'api.mapbox.com',
      '/search/searchbox/v1/retrieve/${Uri.encodeComponent(mapboxId)}',
      {
        'access_token': AppConstants.mapboxPublicToken,
        'language': 'de',
        'session_token': sessionToken,
      },
    );
    final response =
        await http.get(retrieveUri).timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) return null;
    final data = json.decode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List? ?? const [];
    if (features.isEmpty || features.first is! Map<String, dynamic>) {
      return null;
    }
    final feature = features.first as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List?;
    if (coordinates == null || coordinates.length < 2) return null;
    final properties = feature['properties'] as Map<String, dynamic>? ?? {};
    final name = (properties['name'] as String?) ?? '';
    final place = (properties['place_formatted'] as String?) ?? '';
    final lng = (coordinates[0] as num).toDouble();
    final lat = (coordinates[1] as num).toDouble();
    return MapboxSuggestion(
      placeName: [
        if (name.isNotEmpty) name,
        if (place.isNotEmpty) place,
      ].join(', '),
      coordinates: [lng, lat],
      context: place.isEmpty ? null : place,
      distanceMeters:
          proximityLatitude != null &&
              proximityLongitude != null &&
              proximityLatitude.isFinite &&
              proximityLongitude.isFinite
          ? _distanceMeters(proximityLatitude, proximityLongitude, lat, lng)
          : null,
    );
  }

  /// 2026-05-28 (vucko): Reverse-Geocoding — Koordinaten → lesbarer Ortsname.
  /// Für die Anzeige des per Karten-Tap gewählten Startpunkts ("Start: Hard").
  /// Best-effort: gibt null zurück wenn nichts gefunden/Netzfehler.
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/'
          '${longitude.toStringAsFixed(6)},${latitude.toStringAsFixed(6)}.json',
      <String, String>{
        'access_token': AppConstants.mapboxPublicToken,
        'language': 'de',
        'limit': '1',
        'types': 'address,place,locality,neighborhood,poi',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? const [];
      if (features.isEmpty) return null;
      final first = features.first as Map<String, dynamic>;
      final text =
          (first['text'] as String?) ?? (first['place_name'] as String?);
      return (text != null && text.trim().isNotEmpty) ? text.trim() : null;
    } catch (e) {
      _debugLog('[Geocoding] Reverse-Geocode failed: ${e.runtimeType}');
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
    final queryParameters = <String, String>{
      'access_token': AppConstants.mapboxPublicToken,
      'limit': requireUnambiguous ? '3' : '1',
      'language': 'de',
      'country': 'at,de,ch',
      // 2026-05-28 (vucko Startup-V Issue 4): poi-first konsistent mit
      // searchSuggestions, damit das aufgelöste Ziel zum angezeigten
      // Vorschlag passt.
      'types': 'poi,place,address,locality,neighborhood',
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
      '/geocoding/v5/mapbox.places/${_sanitizeSearchPath(searchAddress)}.json',
      queryParameters,
    );

    try {
      // 2026-06-09 (vucko A→B-Latenz): Timeout auch hier — das ist der Geocode,
      // der beim Tippen auf „Los" läuft; ohne Timeout hängt der Routenstart.
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
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

  // 2026-06-02 (vucko): Verallgemeinert. Vorher NUR für "mcdonald" hartcodiert
  // (Test-Überbleibsel aus Startup-V Issue 4) → jede andere Marke/jeder andere
  // POI (Spar, Lidl, Bäckerei, Hotel, Restaurant, Tankstelle …) fiel durch und
  // wurde NIE über die bessere Search-Box-POI-API gesucht. Das war die Ursache,
  // dass z.B. "McDonald's Hohenems" / Geschäfte nicht gefunden wurden.
  // Jetzt: Wenn der v5-Geocoder nichts fand ODER das wichtigste Anfrage-
  // Stichwort (i.d.R. der POI-/Marken-Name = erstes Wort) im besten Treffer
  // fehlt, die Search-Box-POI-Suche bevorzugen — sie hat deutlich bessere
  // Business-/POI-Daten als der klassische v5-Geocoder.
  static bool _shouldPreferSearchBoxPoi(
    String query,
    List<MapboxSuggestion> geocodingSuggestions,
  ) {
    final normalizedQuery = _normalizeAddressText(
      _normalizePoiSearchAlias(query),
    ).trim();
    if (normalizedQuery.isEmpty) return false;
    if (geocodingSuggestions.isEmpty) return true;
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();
    if (tokens.isEmpty) return false;
    final top = _normalizeAddressText(geocodingSuggestions.first.placeName);
    // Wichtigstes Stichwort fehlt im besten v5-Treffer → POI nicht erkannt,
    // die dedizierte POI-Suche übernimmt.
    return !top.contains(tokens.first);
  }

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
