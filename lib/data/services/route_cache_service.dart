import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Intelligente Routen-Queue mit 5 Plätzen.
///
/// - Beim App-Start werden Routen **sequentiell** (nicht parallel) generiert,
///   um CPU/Netzwerk nicht zu überlasten.
/// - Wenn eine Route verbraucht wird, wird der freie Platz im Hintergrund
///   automatisch nachgefüllt.
/// - Qualitätsprüfung: Nur Routen mit ≥50 Koordinatenpunkten (echte
///   Straßengeometrie) werden in die Queue aufgenommen.
class RouteCacheService {
  RouteCacheService._();
  static final RouteCacheService instance = RouteCacheService._();

  final RouteService _routeService = const RouteService();

  static const int _queueSize = 5;

  /// Die Queue: Liste von fertigen Routen.
  final List<_CachedRoute> _queue = [];

  /// Letzter bekannter Standort für die Vorberechnung.
  geo.Position? _lastPosition;

  bool _isGenerating = false;
  int _generationErrors = 0;

  /// Verschiedene Stile rotieren, damit Abwechslung entsteht.
  static const _styles = ['Kurvenjagd', 'Sport Mode', 'Entdecker', 'Abendrunde', 'Sport Mode'];
  int _styleIndex = 0;

  /// Startet die Hintergrund-Vorberechnung.
  /// Generiert Routen **nacheinander** (nicht parallel) → schont das Gerät.
  Future<void> preloadRoutes() async {
    if (_isGenerating) return;
    _isGenerating = true;
    _generationErrors = 0;

    try {
      _lastPosition = await _getCurrentPosition();
      if (_lastPosition == null) {
        debugPrint('[RouteCache] Kein GPS — Vorberechnung übersprungen');
        return;
      }

      // Sequentiell auffüllen bis die Queue voll ist
      while (_queue.length < _queueSize && _generationErrors < 3) {
        await _generateOne();
        // Kurze Pause zwischen Generierungen → CPU-Last verteilen
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('[RouteCache] Queue gefüllt: ${_queue.length}/$_queueSize Routen');
    } catch (e) {
      debugPrint('[RouteCache] Vorberechnung fehlgeschlagen: $e');
    } finally {
      _isGenerating = false;
    }
  }

  /// Holt die nächste Route aus der Queue und startet Nachfüllung.
  /// Gibt null zurück wenn keine gecachte Route verfügbar ist.
  RouteResult? getNextRoute() {
    if (_queue.isEmpty) return null;

    final cached = _queue.removeAt(0);
    debugPrint('[RouteCache] Route aus Queue genommen (${cached.result.distanceKm?.toStringAsFixed(1)} km, ${cached.style}) — ${_queue.length}/$_queueSize verbleibend');

    // Im Hintergrund nachfüllen
    _refillInBackground();

    return cached.result;
  }

  /// Gibt die Anzahl gecachter Routen zurück.
  int get availableCount => _queue.length;

  /// Cache leeren (z.B. bei Standortwechsel).
  void clearCache() {
    _queue.clear();
    _lastPosition = null;
  }

  /// Füllt einen freien Platz im Hintergrund nach.
  void _refillInBackground() {
    if (_isGenerating || _queue.length >= _queueSize) return;

    // Fire-and-forget: Generiert im Hintergrund ohne zu blockieren
    Future(() async {
      if (_isGenerating || _queue.length >= _queueSize) return;
      _isGenerating = true;
      try {
        // Position aktualisieren falls verfügbar
        _lastPosition = await _getCurrentPosition() ?? _lastPosition;
        if (_lastPosition == null) return;

        await _generateOne();
        debugPrint('[RouteCache] Queue nachgefüllt: ${_queue.length}/$_queueSize');
      } catch (e) {
        debugPrint('[RouteCache] Nachfüllung fehlgeschlagen: $e');
      } finally {
        _isGenerating = false;
      }
    });
  }

  /// Generiert eine einzelne Route und fügt sie zur Queue hinzu.
  Future<void> _generateOne() async {
    if (_lastPosition == null) return;

    final style = _styles[_styleIndex % _styles.length];
    _styleIndex++;

    try {
      final result = await _routeService.generateRoundTrip(
        startPosition: _lastPosition!,
        targetDistanceKm: 50, // Standard-Distanz für Vorberechnung
        mode: style,
        planningType: 'Zufall',
      );

      // Qualitätsprüfung: Echte Straßenroute hat hunderte Punkte
      final actualKm = result.distanceKm ?? 0;
      if (result.coordinates.length >= 50 && actualKm > 20) {
        _queue.add(_CachedRoute(result: result, style: style));
        _generationErrors = 0;
        debugPrint('[RouteCache] Route gecached: ${actualKm.toStringAsFixed(1)} km, ${result.coordinates.length} Punkte ($style)');
      } else {
        debugPrint('[RouteCache] Route verworfen: nur ${result.coordinates.length} Punkte, ${actualKm.toStringAsFixed(1)} km');
        _generationErrors++;
      }
    } catch (e) {
      debugPrint('[RouteCache] Generierung fehlgeschlagen ($style): $e');
      _generationErrors++;
    }
  }

  Future<geo.Position?> _getCurrentPosition() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) return null;
      }
      if (permission == geo.LocationPermission.deniedForever) return null;

      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class _CachedRoute {
  const _CachedRoute({required this.result, required this.style});
  final RouteResult result;
  final String style;
}
