import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_compass/flutter_compass.dart';

import 'geo_bearing.dart';

/// Magnetometer-Kompass-Heading, geglättet für die Karten-Rotation im freien
/// Kameramodus (Google-Maps-artig: Karte dreht smooth in Blickrichtung mit).
///
/// 2026-07-22 (vucko): Bisher gab es im Projekt GAR KEINEN Kompass-Sensor —
/// nur GPS-Kurs-über-Grund, der bei Stillstand einfriert. Dieser Service ist
/// bewusst nur eine dünne, testfreundliche Hülle: expliziter [start]/[stop]-
/// Lifecycle (kein Auto-Subscribe im Konstruktor), Glättung über die bereits
/// wrap-around-sichere [GeoBearing]-Mathematik, unbrauchbare Events (null/
/// nicht-finite — auf Geräten ohne Magnetometer laut Doku möglich) werden
/// verworfen. Magnetometer im Fahrzeug ist notorisch gestört (Metall/
/// Elektronik) — der Aufrufer nutzt das Heading deshalb NUR bei niedriger
/// Geschwindigkeit und fällt beim Fahren auf das Bewegungs-Heading zurück.
class CompassHeadingService {
  CompassHeadingService({this.smoothingFactor = 0.25});

  /// EMA-Faktor pro Event (0–1, höher = reaktiver). Kompass-Events kommen
  /// hochfrequent (~10-50 Hz) — 0.25 ergibt eine ruhige, aber folgsame Nadel.
  final double smoothingFactor;

  StreamSubscription<CompassEvent>? _sub;
  double _heading = 0.0;
  bool _hasHeading = false;

  /// Nach jedem übernommenen Event aufgerufen (hochfrequent!). Der Aufrufer
  /// nutzt das, um einen pausierten Render-Ticker aufzuwecken, wenn sich das
  /// Gerät im Stand dreht — die Arbeit selbst passiert weiterhin im Ticker.
  void Function()? onUpdate;

  /// Geglättetes Kompass-Heading in Grad (0–360, Nord=0).
  double get heading => _heading;

  /// Ob seit [start] mindestens ein brauchbares Event ankam.
  bool get hasHeading => _hasHeading;

  /// Ob der Stream gerade läuft.
  bool get isRunning => _sub != null;

  void start() {
    if (kIsWeb || _sub != null) return;
    final events = FlutterCompass.events;
    if (events == null) return; // Gerät ohne Magnetometer
    _sub = events.listen(
      (event) {
        final raw = event.heading;
        if (!GeoBearing.isUsableHeading(raw)) return;
        if (_hasHeading) {
          _heading = GeoBearing.lerpAngleDeg(_heading, raw!, smoothingFactor);
          if (_heading < 0) _heading += 360.0;
        } else {
          _heading = raw!;
          _hasHeading = true;
        }
        onUpdate?.call();
      },
      onError: (Object _) {
        // Sensor-Fehler sind kein App-Fehler — Heading gilt ab jetzt einfach
        // als nicht verfügbar, der Aufrufer nutzt seine Fallback-Quelle.
        _hasHeading = false;
      },
      cancelOnError: false,
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hasHeading = false;
  }
}
