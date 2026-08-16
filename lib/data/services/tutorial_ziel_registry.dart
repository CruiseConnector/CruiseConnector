import 'package:flutter/widgets.dart';

/// Registry für die echten Bildschirm-Positionen der Tutorial-Ziele.
///
/// 2026-08-15 (vucko, Screenshots 17:14): „Beim Tutorial sind die markierten
/// Bereiche wie Feed oder sonstige inakkurat positioniert — schau, dass es
/// auf jedem Handy schön positioniert ist."
///
/// WAS SCHIEFGING: Der Spotlight-Painter rechnete mit FESTEN Zahlen
/// (`Offset(width * 0.125, 143)`). Die 143 waren auf einem Gerät richtig und
/// auf jedem anderen falsch — Statusleistenhöhe, Textskalierung, Notch: Auf
/// dem Samsung sass der Ring genau eine Zeile UNTER dem Reiter.
///
/// JETZT: Die Seiten hängen `GlobalKey`s an die Reiter und den Cruise-Knopf
/// und melden sich hier. Der Painter fragt die ECHTE Position ab (Widget →
/// RenderBox → globale Koordinaten). Erst wenn ein Ziel nicht gemeldet ist
/// (z. B. Web, oder die Seite ist noch nicht gebaut), fällt er auf den alten
/// Schätzwert zurück.
class TutorialZielRegistry {
  TutorialZielRegistry._();

  static final Map<String, GlobalKey> _keys = {};

  static const communityFeed = 'community_feed';
  static const communityRides = 'community_rides';
  static const communityChats = 'community_chats';
  static const communityDiscover = 'community_discover';
  static const cruiseKnopf = 'cruise_knopf';
  static const starterKarte = 'starter_karte';
  static const cruiseModusRundkurs = 'cruise_modus_rundkurs';
  static const cruiseModusAtoB = 'cruise_modus_atob';
  static const cruiseSuchknopf = 'cruise_suchknopf';
  static const zielsuche = 'zielsuche';
  // 2026-08-16 (Testfahrt T5): Schritt-fuer-Schritt-Fuehrung im Strecken-Setup.
  static const cruiseLaenge = 'cruise_laenge';
  static const cruiseUmweg = 'cruise_umweg';
  static const cruiseAutobahn = 'cruise_autobahn';
  static const cruiseStil = 'cruise_stil';
  static const cruiseSpeichern = 'cruise_speichern';
  static const cruiseSetupHilfe = 'cruise_setup_hilfe';
  static const homeRouteSpeichern = 'home_route_speichern';

  /// Liefert den Key für ein Ziel — legt ihn beim ersten Zugriff an.
  static GlobalKey key(String ziel) =>
      _keys.putIfAbsent(ziel, () => GlobalKey(debugLabel: 'tut_$ziel'));

  /// Das globale Rechteck des Ziels, oder `null`, wenn es gerade nicht im
  /// Baum ist.
  static Rect? rect(String ziel, {double aufblasen = 6}) {
    final ctx = _keys[ziel]?.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    final origin = ro.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      ro.size.width,
      ro.size.height,
    ).inflate(aufblasen);
  }
}
