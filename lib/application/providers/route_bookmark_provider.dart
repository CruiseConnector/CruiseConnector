import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/repositories/supabase_route_bookmark_repository.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/repositories/route_bookmark_repository.dart';

class RouteBookmarkProvider extends ChangeNotifier {
  RouteBookmarkProvider({RouteBookmarkRepository? repository})
    : _repository = repository ?? SupabaseRouteBookmarkRepository();

  final RouteBookmarkRepository _repository;

  final Map<String, bool> _savedByRouteId = {};
  final Set<String> _checkedRouteIds = {};
  final Set<String> _busyRouteIds = {};
  List<SavedRoute> _savedRoutes = [];
  bool _isLoadingList = false;

  List<SavedRoute> get savedRoutes => List.unmodifiable(_savedRoutes);
  bool get isLoadingList => _isLoadingList;

  bool isSaved(String routeId) => _savedByRouteId[routeId] ?? false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> ensureChecked(String routeId) async {
    final userId = _userId;
    if (userId == null || _checkedRouteIds.contains(routeId)) return;

    _checkedRouteIds.add(routeId);
    try {
      _savedByRouteId[routeId] = await _repository.checkIfRouteIsSaved(
        userId,
        routeId,
      );
      notifyListeners();
    } catch (e) {
      _checkedRouteIds.remove(routeId);
      debugPrint('[RouteBookmarkProvider] ensureChecked Fehler: $e');
    }
  }

  Future<void> toggle(String routeId) async {
    final userId = _userId;
    if (userId == null || _busyRouteIds.contains(routeId)) return;

    _busyRouteIds.add(routeId);
    final wasSaved = _savedByRouteId[routeId] ?? false;
    _savedByRouteId[routeId] = !wasSaved;
    notifyListeners();

    try {
      if (wasSaved) {
        await _repository.unsaveRoute(userId, routeId);
        _savedRoutes = _savedRoutes
            .where((route) => route.id != routeId)
            .toList();
      } else {
        await _repository.saveRoute(userId, routeId);
      }
      _checkedRouteIds.add(routeId);
    } catch (e) {
      _savedByRouteId[routeId] = wasSaved;
      debugPrint('[RouteBookmarkProvider] toggle Fehler: $e');
    } finally {
      _busyRouteIds.remove(routeId);
      notifyListeners();
    }
  }

  Future<void> loadSavedRoutes() async {
    final userId = _userId;
    if (userId == null) {
      _savedRoutes = [];
      notifyListeners();
      return;
    }

    _isLoadingList = true;
    notifyListeners();

    try {
      final routes = await _repository.getSavedRoutes(userId);
      _savedRoutes = routes;
      for (final route in routes) {
        _savedByRouteId[route.id] = true;
        _checkedRouteIds.add(route.id);
      }
    } catch (e) {
      debugPrint('[RouteBookmarkProvider] loadSavedRoutes Fehler: $e');
    } finally {
      _isLoadingList = false;
      notifyListeners();
    }
  }
}
