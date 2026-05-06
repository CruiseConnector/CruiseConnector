import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

class RouteBookmarkProvider extends ChangeNotifier {
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
      final route = await SavedRoutesService.getRouteById(routeId);
      final saved =
          route != null && await SavedRoutesService.isRouteSaved(route);
      _savedByRouteId[routeId] = saved;
      if (route != null) _markRouteState(route, saved);
      notifyListeners();
    } catch (e) {
      _checkedRouteIds.remove(routeId);
      debugPrint('[RouteBookmarkProvider] ensureChecked Fehler: $e');
    }
  }

  Future<bool?> toggle(String routeId) async {
    final userId = _userId;
    if (userId == null || _busyRouteIds.contains(routeId)) return null;

    _busyRouteIds.add(routeId);
    final route = await SavedRoutesService.getRouteById(routeId);
    if (route == null) {
      _busyRouteIds.remove(routeId);
      notifyListeners();
      return null;
    }

    final wasSaved = await SavedRoutesService.isRouteSaved(route);
    _savedByRouteId[routeId] = !wasSaved;
    _markRouteState(route, !wasSaved);
    notifyListeners();

    try {
      if (wasSaved) {
        await SavedRoutesService.unsaveRouteEverywhere(route);
      } else {
        await SavedRoutesService.saveExistingRoute(route);
      }
      _savedRoutes = await SavedRoutesService.getSavedRouteLibrary();
      _syncSavedRouteMap(_savedRoutes);
      _checkedRouteIds.add(routeId);
      return !wasSaved;
    } catch (e) {
      _savedByRouteId[routeId] = wasSaved;
      _markRouteState(route, wasSaved);
      debugPrint('[RouteBookmarkProvider] toggle Fehler: $e');
      return null;
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
      final routes = await SavedRoutesService.getSavedRouteLibrary();
      _savedRoutes = routes;
      _syncSavedRouteMap(routes);
    } catch (e) {
      debugPrint('[RouteBookmarkProvider] loadSavedRoutes Fehler: $e');
    } finally {
      _isLoadingList = false;
      notifyListeners();
    }
  }

  void _syncSavedRouteMap(List<SavedRoute> routes) {
    _savedByRouteId.clear();
    for (final route in routes) {
      _markRouteState(route, true);
      _checkedRouteIds.add(route.id);
    }
  }

  void _markRouteState(SavedRoute route, bool saved) {
    _savedByRouteId[route.id] = saved;
    final sourceRouteId = route.sourceRouteId?.trim();
    if (sourceRouteId != null && sourceRouteId.isNotEmpty) {
      _savedByRouteId[sourceRouteId] = saved;
    }
  }
}
