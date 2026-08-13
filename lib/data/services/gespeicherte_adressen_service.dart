import 'dart:convert';

import 'package:cruise_connect/domain/models/place_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine vom Nutzer gemerkte Adresse für die Schnellsuche.
class GespeicherteAdresse {
  const GespeicherteAdresse({
    required this.label,
    required this.placeName,
    required this.latitude,
    required this.longitude,
    this.context,
  });

  /// Kurzname, den der Nutzer vergeben hat („Zuhause", „Arbeit").
  final String label;
  final String placeName;
  final double latitude;
  final double longitude;
  final String? context;

  Map<String, dynamic> toJson() => {
    'label': label,
    'place_name': placeName,
    'lat': latitude,
    'lng': longitude,
    if (context != null) 'context': context,
  };

  static GespeicherteAdresse? fromJson(dynamic json) {
    if (json is! Map) return null;
    final label = json['label'];
    final placeName = json['place_name'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (label is! String || placeName is! String || lat is! num || lng is! num) {
      return null;
    }
    return GespeicherteAdresse(
      label: label,
      placeName: placeName,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      context: json['context'] as String?,
    );
  }

  /// Als Suchvorschlag — derselbe Typ, den ein Tipp auf einen Suchtreffer
  /// liefert. Koordinaten in [longitude, latitude] (Mapbox-Format).
  PlaceSuggestion zuVorschlag() => PlaceSuggestion(
    placeName: placeName,
    coordinates: [longitude, latitude],
    context: context,
  );
}

/// Gerätelokale Favoriten-Adressen für die A-nach-B-Zielsuche.
///
/// 2026-08-14 (vucko, P4): „Beim A-nach-B-Modus will ich, dass man Adressen
/// speichern kann für Schnellsuche."
///
/// Bewusst SharedPreferences statt Datenbank: Favoriten sind persönlich und
/// gerätelokal sinnvoll — wie bei Google Maps ohne Konto. Kein Netz nötig,
/// keine RLS-Fragen, kein Sync-Konflikt.
///
/// Reihenfolge bei Änderungen: erst im Speicher ändern, dann melden, DANN auf
/// die Platte — die Oberfläche reagiert sofort (Optimistic-UI-Grundsatz, wie
/// in CameraSettingsService).
class GespeicherteAdressenService extends ChangeNotifier {
  GespeicherteAdressenService._();
  static final GespeicherteAdressenService instance =
      GespeicherteAdressenService._();

  static const _key = 'gespeicherte_adressen_v1';

  /// Mehr braucht niemand für die Schnellwahl — und die Chip-Zeile bleibt
  /// überschaubar. Beim Überlauf fliegt der älteste Eintrag.
  static const int maxEintraege = 10;

  /// Gleicher Ort = gleicher Eintrag (ersetzen statt duplizieren).
  static const double _koordinatenEpsilon = 1e-4; // ~11 m

  bool _loaded = false;
  List<GespeicherteAdresse> _eintraege = [];

  List<GespeicherteAdresse> get alle => List.unmodifiable(_eintraege);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final roh = p.getString(_key);
      if (roh == null || roh.isEmpty) return;
      final json = jsonDecode(roh);
      if (json is! List) return;
      _eintraege = json
          .map(GespeicherteAdresse.fromJson)
          .whereType<GespeicherteAdresse>()
          .toList();
      notifyListeners();
    } catch (e) {
      // Korruptes JSON: leere Liste, weiterleben — Favoriten sind nie so
      // wichtig, dass sie einen Start verhindern dürfen.
      debugPrint('[Adressen] Laden fehlgeschlagen: $e');
      _eintraege = [];
    }
  }

  bool istGespeichert(double latitude, double longitude) =>
      _indexVon(latitude, longitude) >= 0;

  int _indexVon(double latitude, double longitude) {
    for (var i = 0; i < _eintraege.length; i++) {
      final e = _eintraege[i];
      if ((e.latitude - latitude).abs() < _koordinatenEpsilon &&
          (e.longitude - longitude).abs() < _koordinatenEpsilon) {
        return i;
      }
    }
    return -1;
  }

  Future<void> speichern(GespeicherteAdresse adresse) async {
    final vorhanden = _indexVon(adresse.latitude, adresse.longitude);
    if (vorhanden >= 0) {
      _eintraege[vorhanden] = adresse;
    } else {
      _eintraege.add(adresse);
      while (_eintraege.length > maxEintraege) {
        _eintraege.removeAt(0);
      }
    }
    notifyListeners();
    await _persist();
  }

  Future<void> entfernen(GespeicherteAdresse adresse) async {
    final i = _indexVon(adresse.latitude, adresse.longitude);
    if (i < 0) return;
    _eintraege.removeAt(i);
    notifyListeners();
    await _persist();
  }

  Future<void> umbenennen(
    GespeicherteAdresse adresse,
    String neuesLabel,
  ) async {
    final i = _indexVon(adresse.latitude, adresse.longitude);
    if (i < 0 || neuesLabel.trim().isEmpty) return;
    final e = _eintraege[i];
    _eintraege[i] = GespeicherteAdresse(
      label: neuesLabel.trim(),
      placeName: e.placeName,
      latitude: e.latitude,
      longitude: e.longitude,
      context: e.context,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode(_eintraege.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[Adressen] Speichern fehlgeschlagen: $e');
    }
  }

  /// Nur für Tests.
  @visibleForTesting
  void resetForTests() {
    _loaded = false;
    _eintraege = [];
  }
}
