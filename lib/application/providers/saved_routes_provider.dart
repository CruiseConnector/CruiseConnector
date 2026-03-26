import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

/// Verwaltet gespeicherte Routen mit lokalem Cache (Offline-Unterstützung).
/// Beim Start werden lokale Daten sofort angezeigt, dann im Hintergrund
/// mit Supabase synchronisiert.
class SavedRoutesProvider extends ChangeNotifier {
  List<SavedRoute> _routes = [];
  bool _isLoading = false;
  bool _isOffline = false;
  static const String _cacheKey = 'saved_routes_cache';

  List<SavedRoute> get routes => List.unmodifiable(_routes);
  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;

  /// Lädt Routen: zuerst aus lokalem Cache, dann von Supabase.
  Future<void> loadRoutes() async {
    _isLoading = true;
    notifyListeners();

    // 1. Sofort lokalen Cache anzeigen (Offline-Fallback)
    await _loadFromCache();

    // 2. Im Hintergrund mit Supabase synchronisieren
    try {
      final remote = await SavedRoutesService.getUserRoutes();
      _routes = remote;
      _isOffline = false;
      await _saveToCache(remote);
    } catch (e) {
      // Netzwerkfehler → bleibe bei gecachten Daten
      _isOffline = true;
      debugPrint('SavedRoutesProvider: Offline, nutze Cache. Fehler: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Löscht eine Route und aktualisiert den lokalen Cache.
  Future<void> deleteRoute(String routeId) async {
    try {
      await SavedRoutesService.deleteRoute(routeId);
      _routes.removeWhere((r) => r.id == routeId);
      await _saveToCache(_routes);
      notifyListeners();
    } catch (e) {
      debugPrint('SavedRoutesProvider: Fehler beim Löschen: $e');
      rethrow;
    }
  }

  // ─── Lokaler Cache (shared_preferences) ──────────────────────────────────

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final List<dynamic> jsonList = jsonDecode(cached) as List<dynamic>;
        _routes = jsonList
            .map((e) => SavedRoute.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SavedRoutesProvider: Cache-Fehler: $e');
    }
  }

  Future<void> _saveToCache(List<SavedRoute> routes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = routes.map((r) => r.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(json));
    } catch (e) {
      debugPrint('SavedRoutesProvider: Cache-Schreib-Fehler: $e');
    }
  }
}
