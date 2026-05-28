import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cruise_connect/data/services/route_poi_service.dart';

/// Persistente POI-Filter-Einstellungen (welche Kategorien sollen
/// auf der Map als Marker erscheinen).
///
/// Default: nur Tankstellen aktiv (häufigster Use-Case).
/// First-Run-Flag damit Tutorial nur einmal kommt.
class PoiSettingsService extends ChangeNotifier {
  PoiSettingsService._();
  static final PoiSettingsService instance = PoiSettingsService._();

  static const _keyFuel = 'poi_fuel_v1';
  static const _keyRestaurant = 'poi_restaurant_v1';
  static const _keyCafe = 'poi_cafe_v1';
  static const _keyRepair = 'poi_repair_v1';
  // 2026-05-28 (vucko Task #75): Volle PoiType-Abdeckung im Filter-Sheet.
  static const _keyFastFood = 'poi_fastfood_v1';
  static const _keyPub = 'poi_pub_v1';
  static const _keyParking = 'poi_parking_v1';
  static const _keyToilets = 'poi_toilets_v1';
  static const _keyTutorialSeen = 'poi_tutorial_seen_v1';

  bool _loaded = false;
  bool _fuel = true;       // Tankstellen Default an
  bool _restaurant = false;
  bool _cafe = false;
  bool _repair = false;
  bool _fastFood = false;
  bool _pub = false;
  bool _parking = false;
  bool _toilets = false;
  bool _tutorialSeen = false;

  bool get isLoaded => _loaded;
  bool get fuel => _fuel;
  bool get restaurant => _restaurant;
  bool get cafe => _cafe;
  bool get repair => _repair;
  bool get fastFood => _fastFood;
  bool get pub => _pub;
  bool get parking => _parking;
  bool get toilets => _toilets;
  bool get tutorialSeen => _tutorialSeen;

  /// Liefert die aktiv-getoggelten POI-Typen.
  Set<PoiType> get enabledTypes {
    final s = <PoiType>{};
    if (_fuel) s.add(PoiType.fuel);
    if (_restaurant) s.add(PoiType.restaurant);
    if (_cafe) s.add(PoiType.cafe);
    if (_repair) s.add(PoiType.motorcycleRepair);
    if (_fastFood) s.add(PoiType.fastFood);
    if (_pub) s.add(PoiType.pub);
    if (_parking) s.add(PoiType.parking);
    if (_toilets) s.add(PoiType.toilets);
    return s;
  }

  bool get anyEnabled =>
      _fuel ||
      _restaurant ||
      _cafe ||
      _repair ||
      _fastFood ||
      _pub ||
      _parking ||
      _toilets;

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _fuel = p.getBool(_keyFuel) ?? true;
    _restaurant = p.getBool(_keyRestaurant) ?? false;
    _cafe = p.getBool(_keyCafe) ?? false;
    _repair = p.getBool(_keyRepair) ?? false;
    _fastFood = p.getBool(_keyFastFood) ?? false;
    _pub = p.getBool(_keyPub) ?? false;
    _parking = p.getBool(_keyParking) ?? false;
    _toilets = p.getBool(_keyToilets) ?? false;
    _tutorialSeen = p.getBool(_keyTutorialSeen) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setFuel(bool v) => _set(_keyFuel, v, (n) => _fuel = n);
  Future<void> setRestaurant(bool v) =>
      _set(_keyRestaurant, v, (n) => _restaurant = n);
  Future<void> setCafe(bool v) => _set(_keyCafe, v, (n) => _cafe = n);
  Future<void> setRepair(bool v) =>
      _set(_keyRepair, v, (n) => _repair = n);
  Future<void> setFastFood(bool v) =>
      _set(_keyFastFood, v, (n) => _fastFood = n);
  Future<void> setPub(bool v) => _set(_keyPub, v, (n) => _pub = n);
  Future<void> setParking(bool v) =>
      _set(_keyParking, v, (n) => _parking = n);
  Future<void> setToilets(bool v) =>
      _set(_keyToilets, v, (n) => _toilets = n);

  Future<void> markTutorialSeen() async {
    if (_tutorialSeen) return;
    _tutorialSeen = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyTutorialSeen, true);
  }

  Future<void> _set(String key, bool v, void Function(bool) apply) async {
    apply(v);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
  }
}
