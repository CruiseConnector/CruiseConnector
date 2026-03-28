import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verteilt Navigations-Positionsupdates über Supabase Realtime (WebSocket).
///
/// Der Stream fällt automatisch auf lokale Direkt-Emission zurück, falls der
/// WebSocket noch nicht verbunden ist oder ausfällt.
class NavigationProgressSocketService {
  NavigationProgressSocketService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final StreamController<geo.Position> _positionController =
      StreamController<geo.Position>.broadcast();

  RealtimeChannel? _channel;
  bool _isSubscribed = false;
  geo.Position? _lastEmittedPosition;

  Stream<geo.Position> get positionStream => _positionController.stream;

  Future<void> openSession(String sessionId) async {
    await close();

    final channel = _client.channel(
      'navigation-progress:$sessionId',
      opts: const RealtimeChannelConfig(self: true, ack: false),
    );

    channel.onBroadcast(
      event: 'position',
      callback: (payload) {
        final decoded = _positionFromPayload(payload);
        if (decoded != null) _emit(decoded);
      },
    );

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _isSubscribed = true;
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        _isSubscribed = false;
        if (error != null) {
          // Kein throw: Navigation darf bei Socketfehlern weiterlaufen.
          // Fehler wird nur geloggt.
          // ignore: avoid_print
          print('[NavigationSocket] Realtime status $status: $error');
        }
      }
    });

    _channel = channel;
  }

  Future<void> publishPosition(geo.Position position) async {
    // Web: Supabase Realtime-Roundtrip (WebSocket → Server → zurück) ist zu
    // langsam für Echtzeit-Navigation (~50–500ms Latenz pro Update).
    // Auf Web direkt emittieren — kein Netzwerk-Roundtrip.
    if (kIsWeb) {
      _emit(position);
      return;
    }

    final payload = _positionToPayload(position);
    final channel = _channel;
    if (channel == null || !_isSubscribed) {
      _emit(position);
      return;
    }

    try {
      await channel.sendBroadcastMessage(event: 'position', payload: payload);
    } catch (_) {
      _emit(position);
    }
  }

  Future<void> close() async {
    _isSubscribed = false;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<void> dispose() async {
    await close();
    await _positionController.close();
  }

  Map<String, dynamic> _positionToPayload(geo.Position p) {
    return {
      'latitude': p.latitude,
      'longitude': p.longitude,
      'timestamp': p.timestamp.millisecondsSinceEpoch,
      'accuracy': p.accuracy,
      'altitude': p.altitude,
      'altitude_accuracy': p.altitudeAccuracy,
      'heading': p.heading,
      'heading_accuracy': p.headingAccuracy,
      'speed': p.speed,
      'speed_accuracy': p.speedAccuracy,
      'is_mocked': p.isMocked,
      if (p.floor != null) 'floor': p.floor,
    };
  }

  geo.Position? _positionFromPayload(Map<String, dynamic> payload) {
    try {
      final inner = payload['payload'];
      final data = inner is Map
          ? Map<String, dynamic>.from(inner)
          : Map<String, dynamic>.from(payload);
      return geo.Position.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  void _emit(geo.Position position) {
    final last = _lastEmittedPosition;
    if (last != null) {
      final distance = geo.Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        position.latitude,
        position.longitude,
      );

      // Zwischenpunkte glätten sichtbare Sprünge der Routenlinie.
      final interpolationSteps = (distance / 4.0).floor().clamp(0, 3);
      if (interpolationSteps > 0) {
        for (var i = 1; i <= interpolationSteps; i++) {
          final t = i / (interpolationSteps + 1);
          _positionController.add(_interpolatePosition(last, position, t));
        }
      }
    }

    _positionController.add(position);
    _lastEmittedPosition = position;
  }

  geo.Position _interpolatePosition(
    geo.Position from,
    geo.Position to,
    double t,
  ) {
    double lerp(double a, double b) => a + (b - a) * t;

    final ts =
        from.timestamp.millisecondsSinceEpoch +
        ((to.timestamp.millisecondsSinceEpoch -
                    from.timestamp.millisecondsSinceEpoch) *
                t)
            .round();

    return geo.Position(
      longitude: lerp(from.longitude, to.longitude),
      latitude: lerp(from.latitude, to.latitude),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      accuracy: lerp(from.accuracy, to.accuracy),
      altitude: lerp(from.altitude, to.altitude),
      altitudeAccuracy: lerp(from.altitudeAccuracy, to.altitudeAccuracy),
      heading: lerp(from.heading, to.heading),
      headingAccuracy: lerp(from.headingAccuracy, to.headingAccuracy),
      speed: lerp(from.speed, to.speed),
      speedAccuracy: lerp(from.speedAccuracy, to.speedAccuracy),
      floor: from.floor,
      isMocked: from.isMocked || to.isMocked,
    );
  }
}
