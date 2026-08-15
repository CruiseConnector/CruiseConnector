import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eine Aufgabe des Starter-Pakets.
class StarterAufgabe {
  const StarterAufgabe({
    required this.id,
    required this.titel,
    required this.beschreibung,
  });

  final String id;
  final String titel;
  final String beschreibung;
}

/// Starter-Paket: Aufgaben nach dem Tutorial, Belohnung und Doppel-XP-Woche.
///
/// 2026-08-14 (vucko): „dass man bei einem neu erstellten Account nach dem
/// Onboarding wie Aufgaben hat, die man erfüllen muss, um das Starter-Paket zu
/// haben, und einen zusätzlichen Bonus von einer Woche, wo man doppelt so
/// viele XP bekommt — und der Timer wirklich nur eine Woche läuft."
///
/// ABLAUF: Fünf Aufgaben, alle ohne Fahrt erfüllbar (damit auch das
/// Durchspielen auf der Couch funktioniert). Sind alle erledigt, gibt es
/// einmalig das Startklar-Badge, und die Doppel-XP-Woche beginnt — exakt
/// sieben Tage ab diesem Moment, danach schaltet sich der Bonus von selbst
/// ab. Der Endzeitpunkt wird EINMAL gespeichert und nie neu angesetzt; ein
/// App-Neustart verlängert nichts.
///
/// Die Erfüllung wird an den echten Stellen gemeldet (Route gesucht, Favorit
/// gespeichert, Route gespeichert, Community geöffnet, Tutorial beendet) —
/// keine Selbstauskunft, keine Abfragen: nur ein Set im Gerätespeicher.
class StarterAufgabenService extends ChangeNotifier {
  StarterAufgabenService._();
  static final StarterAufgabenService instance = StarterAufgabenService._();

  static const _kErledigt = 'starter_aufgaben_erledigt_v1';
  static const _kBonusEnde = 'starter_bonus_ende_v1';
  static const _kPaketVergeben = 'starter_paket_vergeben_v1';

  static const Duration bonusDauer = Duration(days: 7);

  /// Der XP-Faktor waehrend der Bonus-Woche.
  static const int bonusFaktor = 2;

  static const List<StarterAufgabe> aufgaben = [
    StarterAufgabe(
      id: 'tutorial',
      titel: 'Tutorial abschließen',
      beschreibung: 'Die kurze Tour bis zum Ende mitmachen.',
    ),
    StarterAufgabe(
      id: 'route',
      titel: 'Eine Route suchen',
      beschreibung: 'Egal ob Rundkurs oder A nach B.',
    ),
    StarterAufgabe(
      id: 'favorit',
      titel: 'Eine Adresse merken',
      beschreibung: 'Bei der Zielsuche den Stern antippen.',
    ),
    StarterAufgabe(
      id: 'speichern',
      titel: 'Eine Route speichern',
      beschreibung: 'Eine gefundene Strecke in deine Sammlung legen.',
    ),
    StarterAufgabe(
      id: 'community',
      titel: 'Die Community öffnen',
      beschreibung: 'Schau vorbei, wer noch unterwegs ist.',
    ),
  ];

  bool _loaded = false;
  Set<String> _erledigt = {};
  DateTime? _bonusEnde;
  bool _paketVergeben = false;

  /// Feuert genau EINMAL, wenn alle Aufgaben frisch erledigt wurden — die
  /// Oberfläche zeigt dann die Badge-Verleihung und startet die Bonus-Woche.
  final ValueNotifier<bool> paketFrischVerdient = ValueNotifier<bool>(false);

  bool get isLoaded => _loaded;
  bool erledigt(String id) => _erledigt.contains(id);
  int get erledigtAnzahl =>
      aufgaben.where((a) => _erledigt.contains(a.id)).length;
  bool get alleErledigt => erledigtAnzahl >= aufgaben.length;
  bool get paketVergeben => _paketVergeben;
  DateTime? get bonusEnde => _bonusEnde;

  /// Läuft die Doppel-XP-Woche gerade?
  bool get doppelXpAktiv =>
      _bonusEnde != null && DateTime.now().isBefore(_bonusEnde!);

  Duration get bonusVerbleibend => !doppelXpAktiv
      ? Duration.zero
      : _bonusEnde!.difference(DateTime.now());

  /// Wendet den Bonus auf eine XP-Zahl an — die EINE Stelle für die Regel.
  int wendeBonusAn(int xp) => doppelXpAktiv ? xp * bonusFaktor : xp;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final roh = p.getString(_kErledigt);
      if (roh != null && roh.isNotEmpty) {
        final json = jsonDecode(roh);
        if (json is List) _erledigt = json.whereType<String>().toSet();
      }
      final ende = p.getString(_kBonusEnde);
      if (ende != null) _bonusEnde = DateTime.tryParse(ende);
      _paketVergeben = p.getBool(_kPaketVergeben) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Starter] Laden fehlgeschlagen: $e');
    }
  }

  /// Meldet eine erfüllte Aufgabe. Idempotent und billig — darf von den
  /// Andockstellen bedenkenlos bei jedem Ereignis aufgerufen werden.
  Future<void> markiere(String id) async {
    if (!aufgaben.any((a) => a.id == id)) return;
    if (_erledigt.contains(id)) return;
    await load();
    if (_erledigt.contains(id)) return;
    _erledigt.add(id);

    final geradeKomplett = alleErledigt && !_paketVergeben;
    if (geradeKomplett) {
      _paketVergeben = true;
      // Der Timer beginnt GENAU JETZT und endet nach exakt sieben Tagen.
      _bonusEnde = DateTime.now().add(bonusDauer);
    }
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kErledigt, jsonEncode(_erledigt.toList()));
      if (geradeKomplett) {
        await p.setBool(_kPaketVergeben, true);
        await p.setString(_kBonusEnde, _bonusEnde!.toIso8601String());
      }
    } catch (e) {
      debugPrint('[Starter] Speichern fehlgeschlagen: $e');
    }
    if (geradeKomplett) {
      debugPrint('[Starter] Paket komplett — Doppel-XP bis $_bonusEnde');
      paketFrischVerdient.value = true;
    }
  }

  /// Nur für Tests.
  @visibleForTesting
  void resetForTests() {
    _loaded = false;
    _erledigt = {};
    _bonusEnde = null;
    _paketVergeben = false;
    paketFrischVerdient.value = false;
  }
}
