import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

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
///
/// 2026-07-27 (vucko „die Drehung ist nur ca. 200° statt 360°"): Zwei
/// Ursachen in diesem Service behoben.
///
/// ERSTENS DIE QUELLE. `CompassEvent` hat zwei Felder: `heading` (Richtung aus
/// der OBERKANTE des Geräts) und `headingForCameraMode` (Richtung aus der
/// RÜCKSEITE — also dorthin, wo man schaut, wenn man das Gerät aufrecht vor
/// sich hält). Für die Navi-Haltung ist Letzteres das fachlich richtige Feld,
/// und auf iOS wird es über die Rotationsmatrix des DeviceMotion gerechnet,
/// also ohne die Euler-Singularität, die `heading` bei aufrechtem Gerät
/// staucht.
///
/// ABER: Auf ANDROID füllt das Plugin dieses Feld überhaupt nicht. Es sendet
/// ein `double[3]` und setzt nur Index 0 (Heading) und Index 2 (Genauigkeit);
/// Index 1 bleibt der Java-Default 0.0. Wer dort auf `headingForCameraMode`
/// umstellt, bekommt konstant „Norden" und eine Karte, die sich nie dreht.
/// Deshalb wird das Feld AUSSCHLIESSLICH auf iOS genutzt. Nachgeprüft im
/// Quellcode von flutter_compass 0.8.1: `FlutterCompassPlugin.java` setzt
/// `v[0]` und `v[2]`, niemals `v[1]`; `SwiftFlutterCompassPlugin.swift`
/// rechnet den Wert dagegen vollständig aus.
///
/// ZWEITENS DIE GLÄTTUNG. Ein EMA mit festem Faktor hat bei einer laufenden
/// Drehung einen Nachlauf, der linear mit der Drehgeschwindigkeit wächst
/// (L = ω · dt · (1−α)/α). Mit dem alten α = 0,25 blieb das geglättete
/// Heading bei zügigem Drehen dauerhaft 30–50° hinter der Realität — ein
/// spürbarer Teil der fehlenden Grad. Der Faktor ist jetzt adaptiv: ruhig bei
/// kleinen Änderungen (kein Zittern durch Sensor-Rauschen), schnell bei großen
/// (die Karte bleibt an der Drehung dran).
class CompassHeadingService {
  CompassHeadingService({this.minSmoothing = 0.15, this.maxSmoothing = 0.6});

  /// Glättung bei ruhigem Gerät — klein, damit Sensor-Rauschen (typisch 1–2°)
  /// die Karte nicht zappeln lässt.
  final double minSmoothing;

  /// Glättung bei schneller Drehung — groß, damit kaum Nachlauf entsteht.
  final double maxSmoothing;

  /// Ab dieser Winkeldifferenz pro Event gilt die Drehung als „schnell" und
  /// die Glättung erreicht [maxSmoothing].
  static const double fastDeltaDeg = 25.0;

  StreamSubscription<CompassEvent>? _sub;
  double _heading = 0.0;
  bool _hasHeading = false;

  /// Nach jedem übernommenen Event aufgerufen (hochfrequent!). Der Aufrufer
  /// nutzt das, um einen pausierten Render-Ticker aufzuwecken, wenn sich das
  /// Gerät im Stand dreht — die Arbeit selbst passiert weiterhin im Ticker.
  void Function()? onUpdate;

  /// Geglättetes Heading in Grad (0–360, Nord=0).
  double get heading => _heading;

  /// Ob seit [start] mindestens ein brauchbares Event ankam.
  bool get hasHeading => _hasHeading;

  /// Ob der Stream gerade läuft.
  bool get isRunning => _sub != null;

  /// Nur iOS liefert ein echtes Rückseiten-Heading (siehe Klassen-Doku).
  static bool get prefersCameraHeading => !kIsWeb && Platform.isIOS;

  /// Rohwert für die Karten-Rotation aus einem Event.
  ///
  /// [cameraModeAvailable] bildet die Plattform ab: true = iOS (Rückseiten-
  /// Heading vorhanden), false = Android (Feld ist dort immer 0.0 und darf
  /// NICHT verwendet werden).
  static double? rawHeadingFor(
    CompassEvent event, {
    required bool cameraModeAvailable,
  }) {
    if (cameraModeAvailable) {
      final cam = event.headingForCameraMode;
      if (GeoBearing.isUsableHeading(cam)) return cam;
    }
    final head = event.heading;
    return GeoBearing.isUsableHeading(head) ? head : null;
  }

  /// Glättungsfaktor für eine gegebene Winkeldifferenz.
  double smoothingFor(double deltaDeg) {
    final d = deltaDeg.abs().clamp(0.0, fastDeltaDeg);
    return minSmoothing + (maxSmoothing - minSmoothing) * (d / fastDeltaDeg);
  }

  void start() {
    if (kIsWeb || _sub != null) return;
    final events = FlutterCompass.events;
    if (events == null) return; // Gerät ohne Magnetometer
    _sub = events.listen(
      (event) {
        final raw = rawHeadingFor(
          event,
          cameraModeAvailable: prefersCameraHeading,
        );
        if (raw == null) return;
        feed(raw);
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

  /// Einen Rohwert übernehmen (aus dem Sensor oder aus einem Test).
  void feed(double raw) {
    if (!_hasHeading) {
      _heading = _normalize(raw);
      _hasHeading = true;
      return;
    }
    final delta = GeoBearing.angleDiff(_heading, raw);
    _heading = _normalize(
      GeoBearing.lerpAngleDeg(_heading, raw, smoothingFor(delta)),
    );
  }

  /// Setzt den Startzustand ohne Sensor (Tests).
  void seed(double value) {
    _heading = _normalize(value);
    _hasHeading = true;
  }

  static double _normalize(double deg) {
    var v = deg % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }

  /// Wie viel Drehung bei einer gleichmäßigen Rampe am Ausgang ankommt und
  /// wie weit das Heading dabei maximal zurückliegt. Grundlage des
  /// Regressionstests zur 360°-Drehung.
  static ({double tracked, double maxLag}) simulateRamp({
    required CompassHeadingService service,
    required double totalDeg,
    required int steps,
  }) {
    service.seed(0);
    var tracked = 0.0;
    var maxLag = 0.0;
    var prev = 0.0;
    for (var i = 1; i <= steps; i++) {
      final raw = totalDeg * i / steps;
      service.feed(_normalize(raw));
      tracked += GeoBearing.angleDiff(prev, service.heading).abs();
      maxLag = math.max(
        maxLag,
        GeoBearing.angleDiff(service.heading, _normalize(raw)).abs(),
      );
      prev = service.heading;
    }
    return (tracked: tracked, maxLag: maxLag);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hasHeading = false;
  }
}
