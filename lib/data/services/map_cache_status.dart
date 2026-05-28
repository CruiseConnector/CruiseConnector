import 'package:flutter/foundation.dart';

/// 2026-05-28 (vucko Task #64): Globaler Status-Tracker für den DACH-
/// Offline-Map-Cache. Wird vom [OfflineMapService] beim Download befeuert,
/// und von der Settings-Page (und ggf. später vom Home-Screen) gelauscht
/// um Status + Progress anzuzeigen.
///
/// Singleton-ChangeNotifier — bewusst kein Provider/Riverpod nötig, das
/// passt zum existierenden Pattern in PoiSettingsService /
/// NotificationSettingsService.
enum MapCacheState {
  notStarted,
  downloading,
  completed,
  failed,
}

class MapCacheStatus extends ChangeNotifier {
  MapCacheStatus._();
  static final MapCacheStatus instance = MapCacheStatus._();

  MapCacheState _state = MapCacheState.notStarted;
  int _downloadedTiles = 0;
  int _totalTiles = 0;
  int _approxSizeMb = 0;
  DateTime? _completedAt;
  String? _lastError;

  MapCacheState get state => _state;
  int get downloadedTiles => _downloadedTiles;
  int get totalTiles => _totalTiles;
  int get approxSizeMb => _approxSizeMb;
  DateTime? get completedAt => _completedAt;
  String? get lastError => _lastError;

  double get progress {
    if (_totalTiles == 0) return 0.0;
    return (_downloadedTiles / _totalTiles).clamp(0.0, 1.0);
  }

  void markStarted({required int totalTiles}) {
    _state = MapCacheState.downloading;
    _totalTiles = totalTiles;
    _downloadedTiles = 0;
    _lastError = null;
    notifyListeners();
  }

  void updateProgress({required int downloaded}) {
    if (_state != MapCacheState.downloading) return;
    _downloadedTiles = downloaded;
    notifyListeners();
  }

  void markCompleted({required int totalTiles, required int approxSizeMb}) {
    _state = MapCacheState.completed;
    _totalTiles = totalTiles;
    _downloadedTiles = totalTiles;
    _approxSizeMb = approxSizeMb;
    _completedAt = DateTime.now();
    _lastError = null;
    notifyListeners();
  }

  void markFailed({required String error}) {
    _state = MapCacheState.failed;
    _lastError = error;
    notifyListeners();
  }

  void reset() {
    _state = MapCacheState.notStarted;
    _downloadedTiles = 0;
    _totalTiles = 0;
    _approxSizeMb = 0;
    _completedAt = null;
    _lastError = null;
    notifyListeners();
  }
}
