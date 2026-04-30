import 'package:cruise_connect/domain/models/saved_route.dart';

abstract class RouteBookmarkRepository {
  Future<void> saveRoute(String userId, String routeId);

  Future<void> unsaveRoute(String userId, String routeId);

  Future<bool> checkIfRouteIsSaved(String userId, String routeId);

  Future<List<SavedRoute>> getSavedRoutes(String userId);
}
