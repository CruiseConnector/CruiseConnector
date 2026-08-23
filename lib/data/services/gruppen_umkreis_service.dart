import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-24 — Aufgabe 3.1 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 4 [00:11]: „bei der Gruppenfahrt, dass man einstellen kann,
/// in welchem Umkreis man Gruppen machen will. Also wenn Gruppen im Umkreis
/// von 50 Kilometer sind, sollen die angezeigt werden — oder alle."
///
/// Akzeptanzkriterium 3 lautet: „Die Einstellung überlebt einen
/// App-Neustart." Genau daran ist der bestehende Filter gescheitert. Gemessen
/// am 24.08.2026: `_groupRadiusEnabled` und `_groupRadiusKm` waren reine
/// Felder des `_CommunityPageState` in
/// `lib/presentation/pages/community_page.dart` (Zeilen 93 bis 95). Sie
/// überlebten nicht einmal einen Reiterwechsel mit Neuaufbau der Seite, von
/// einem App-Neustart ganz zu schweigen.
///
/// Die Ablage folgt bewusst [PoiSettingsService]
/// (`lib/data/services/poi_settings_service.dart`): ein ChangeNotifier als
/// Einzelstück, versionierte Schlüssel mit `_v1`, ein `_loaded`-Flag, damit
/// die Oberfläche nicht mit dem Vorgabewert aufblitzt und dann umspringt.
///
/// Was hier NICHT liegt: der Standort des Nutzers. Der ist flüchtig und wird
/// bei jedem Öffnen frisch geholt. Gespeichert wird nur, WAS der Nutzer
/// eingestellt hat, nie WO er zuletzt war.
class GruppenUmkreisService extends ChangeNotifier {
  GruppenUmkreisService._();

  static final GruppenUmkreisService instance = GruppenUmkreisService._();

  static const String _keyAktiv = 'gruppen_umkreis_aktiv_v1';
  static const String _keyRadiusKm = 'gruppen_umkreis_km_v1';

  /// Die Stufen des Reglers. 10 bis 100 km in 5er-Schritten — so war der
  /// Regler schon gebaut, und Vuckos genannte 50 km liegen darin.
  static const double minRadiusKm = 10;
  static const double maxRadiusKm = 100;
  static const double schrittKm = 5;

  /// Vorgabe, solange niemand etwas eingestellt hat: Filter AUS.
  ///
  /// Bewusst aus und nicht an. Wer die App zum ersten Mal öffnet, hat oft
  /// noch keine Standortfreigabe erteilt. Ein von Haus aus aktiver Filter
  /// würde dann nichts ausblenden (so ist der Filter gebaut), aber sobald die
  /// Freigabe kommt, verschwänden Gruppen, ohne dass der Nutzer je etwas
  /// eingestellt hätte.
  static const bool vorgabeAktiv = false;

  /// Vorgabe-Radius. 100 km entspricht dem bisherigen Startwert des Reglers.
  static const double vorgabeRadiusKm = 100;

  bool _loaded = false;
  bool _aktiv = vorgabeAktiv;
  double _radiusKm = vorgabeRadiusKm;

  bool get istGeladen => _loaded;

  /// true = nur Gruppen im eingestellten Umkreis. false = „alle".
  bool get aktiv => _aktiv;

  double get radiusKm => _radiusKm;

  /// Der Wert, den die RPC `gruppen_in_der_naehe` erwartet.
  ///
  /// ACHTUNG: `p_radius_m` ist in METERN, der Regler zeigt Kilometer. Wer das
  /// verwechselt, filtert auf 50 Meter statt auf 50 Kilometer und der Nutzer
  /// sieht gar nichts mehr.
  ///
  /// `null` heißt für die RPC ausdrücklich „Radius alle": kein Filter, aber
  /// weiter nach Entfernung sortiert.
  double? get radiusMeterFuerAbfrage => _aktiv ? _radiusKm * 1000.0 : null;

  /// Hält einen Wert in den Stufen des Reglers.
  ///
  /// Ein gespeicherter Wert aus einer älteren Fassung (oder ein von Hand
  /// verbogener Eintrag in den Einstellungen) darf den Regler nicht aus dem
  /// Bereich werfen — Flutters Slider wirft dann eine Zusicherung.
  static double begrenze(double km) {
    if (km.isNaN) return vorgabeRadiusKm;
    final gerundet = (km / schrittKm).round() * schrittKm;
    if (gerundet < minRadiusKm) return minRadiusKm;
    if (gerundet > maxRadiusKm) return maxRadiusKm;
    return gerundet.toDouble();
  }

  Future<void> laden() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _aktiv = p.getBool(_keyAktiv) ?? vorgabeAktiv;
    _radiusKm = begrenze(p.getDouble(_keyRadiusKm) ?? vorgabeRadiusKm);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setzeAktiv(bool wert) async {
    if (_aktiv == wert && _loaded) return;
    _aktiv = wert;
    _loaded = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyAktiv, wert);
  }

  Future<void> setzeRadiusKm(double km) async {
    final wert = begrenze(km);
    if (_radiusKm == wert && _loaded) return;
    _radiusKm = wert;
    _loaded = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_keyRadiusKm, wert);
  }

  /// Nur für Tests: setzt den Dienst auf den Auslieferungszustand zurück.
  @visibleForTesting
  void zuruecksetzenFuerTest() {
    _loaded = false;
    _aktiv = vorgabeAktiv;
    _radiusKm = vorgabeRadiusKm;
  }
}
