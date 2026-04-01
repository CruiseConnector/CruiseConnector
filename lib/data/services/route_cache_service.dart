import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Intelligente Routen-Queue mit kontrollierter Vorberechnung.
///
/// - KEINE parallelen Requests mehr — alles sequentiell
/// - Maximal 3 Routen in der Queue (reduziert von 5)
/// - Nachfüllung nur wenn keine aktive User-Generierung läuft
/// - Position-Drift-Detection: Cache invalidieren bei >1km Bewegung
class RouteCacheService {
  RouteCacheService._();
  static final RouteCacheService instance = RouteCacheService._();

  final RouteService _routeService = RouteService();

  static const int _queueSize = 3; // Reduziert von 5 → weniger Serverlast

  /// Die Queue: Liste von fertigen Routen.
  final List<_CachedRoute> _queue = [];

  /// Letzter bekannter Standort für die Vorberechnung.
  geo.Position? _lastPosition;

  bool _isGenerating = false;
  int _generationErrors = 0;
  
  /// Flag: User-initiierte Generierung hat Vorrang
  static bool userGenerationActive = false;

  /// Verschiedene Stile rotieren, damit Abwechslung entsteht.
  static const _styles = ['Kurvenjagd', 'Sport Mode', 'Entdecker'];
  int _styleIndex = 0;

  /// Startet die Hintergrund-Vorberechnung.
  /// Generiert Routen **nacheinander** (nicht parallel) → schont das Gerät.
  Future<void> preloadRoutes() async {
    // Nicht starten wenn User gerade selbst generiert
    if (userGenerationActive) {
      debugPrint('[RouteCache] ⏳ User-Generierung aktiv — Preload pausiert');
      return;
    }
    if (_isGenerating) return;
    _isGenerating = true;
    _generationErrors = 0;

    try {
      final newPosition = await _getCurrentPosition();
      if (newPosition == null) {
        debugPrint('[RouteCache] Kein GPS — Vorberechnung übersprungen');
        return;
      }
      
      // Position-Drift prüfen: Cache invalidieren bei >1km Bewegung
      if (_lastPosition != null) {
        final drift = geo.Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          newPosition.latitude,
          newPosition.longitude,
        );
        if (drift > 1000) {
          debugPrint('[RouteCache] 🔄 Position-Drift ${(drift / 1000).toStringAsFixed(1)}km — Cache invalidiert');
          _queue.clear();
        }
      }
      _lastPosition = newPosition;

      // SEQUENTIELL auffüllen: Eine Route nach der anderen
      while (_queue.length < _queueSize && _generationErrors < 2) {
        // Vor jeder Generierung prüfen ob User aktiv wurde
        if (userGenerationActive) {
          debugPrint('[RouteCache] ⏳ User-Generierung gestartet — Preload pausiert');
          break;
        }
        
        await _generateOne();
        
        // Kurze Pause zwischen Generierungen → CPU-Last verteilen
        if (_queue.length < _queueSize) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
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

    // Im Hintergrund nachfüllen (nur wenn kein User-Request aktiv)
    if (!userGenerationActive) {
      _refillInBackground();
    }

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
    // Nicht nachfüllen wenn User gerade selbst generiert
    if (userGenerationActive) return;
    if (_isGenerating || _queue.length >= _queueSize) return;
    // Flag sofort setzen um Race Condition zu verhindern
    _isGenerating = true;

    // Fire-and-forget: Generiert im Hintergrund ohne zu blockieren
    Future(() async {
      // Nochmal prüfen
      if (userGenerationActive || _queue.length >= _queueSize) {
        _isGenerating = false;
        return;
      }
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
    // Nicht generieren wenn User aktiv
    if (userGenerationActive) return;

    final style = _styles[_styleIndex % _styles.length];
    _styleIndex++;
    
    // Diversitäts-Index für Hintergrund-Generierung nutzen
    RouteService.incrementDiversityIndex();

    try {
      final result = await _routeService.generateRoundTrip(
        startPosition: _lastPosition!,
        targetDistanceKm: 50, // Standard-Distanz für Vorberechnung
        mode: style,
        planningType: 'Zufall',
      );

      // Qualitätsprüfung: Echte Straßenroute hat hunderte Punkte
      // UND Distanz muss im 50km-Band liegen (±40% Toleranz für Cache)
      final actualKm = result.distanceKm ?? 0;
      final hasGoodGeometry = result.coordinates.length >= 50;
      final hasGoodDistance = actualKm >= 25 && actualKm <= 80; // 50km ±30km
      if (hasGoodGeometry && hasGoodDistance) {
        _queue.add(_CachedRoute(result: result, style: style));
        _generationErrors = 0;
        debugPrint('[RouteCache] Route gecached: ${actualKm.toStringAsFixed(1)} km, ${result.coordinates.length} Punkte ($style)');
      } else {
        debugPrint('[RouteCache] Route verworfen: ${result.coordinates.length} Punkte, ${actualKm.toStringAsFixed(1)} km (brauche ≥50 Punkte, 25-80 km)');
        _generationErrors++;
      }
    } catch (e) {
      debugPrint('[RouteCache] Generierung fehlgeschlagen ($style): $e');
      _generationErrors++;
    }
  }

  Future<geo.Position?> _getCurrentPosition() async {
    try {
      // Auf Web: checkPermission/isLocationServiceEnabled werden unterstützt,
      // aber wir überspringen den Service-Check da Browser keinen "GPS aus"-Status hat
      if (!kIsWeb) {
        final serviceEnabled =
            await geo.Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return null;
      }

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
    } catch (e) {
      debugPrint('[RouteCache] GPS-Position fehlgeschlagen: $e');
      return null;
    }
  }
}

class _CachedRoute {
  const _CachedRoute({required this.result, required this.style});
  final RouteResult result;
  final String style;
}
