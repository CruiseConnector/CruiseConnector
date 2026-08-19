import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
/// ABLAUF: Acht Aufgaben. Sind alle erledigt, gibt es einmalig das
/// Startklar-Badge, und die Doppel-XP-Woche beginnt — exakt sieben Tage ab
/// diesem Moment, danach schaltet sich der Bonus von selbst ab. Der
/// Endzeitpunkt wird EINMAL gespeichert und nie neu angesetzt; ein
/// App-Neustart verlängert nichts.
///
/// Die Erfüllung wird an den echten Stellen gemeldet (Route gesucht, Favorit
/// gespeichert, Route gespeichert, Community geöffnet, Tutorial beendet). Die
/// drei Fahr- und Social-Aufgaben werden nicht gemeldet, sondern aus dem
/// ZUSTAND abgeleitet — siehe [synchronisiereAusKennzahlen].
class StarterAufgabenService extends ChangeNotifier {
  StarterAufgabenService._();
  static final StarterAufgabenService instance = StarterAufgabenService._();

  static const _kErledigt = 'starter_aufgaben_erledigt_v1';
  static const _kBonusEnde = 'starter_bonus_ende_v1';
  static const _kPaketVergeben = 'starter_paket_vergeben_v1';

  /// Spalten auf `profiles`, in denen derselbe Zustand serverseitig liegt
  /// (Migration 20260819120000). Siehe [synchronisiereMitProfil].
  static const spalteAufgaben = 'starter_aufgaben';
  static const spalteBonusEnde = 'starter_bonus_ende';

  static const Duration bonusDauer = Duration(days: 7);

  // 2026-08-19 (vucko): Hier stand `bonusFaktor = 2`. Der Bonus ist kein
  // Faktor mehr, der am Ende auf die fertigen XP gelegt wird, sondern die
  // BASIS des Streak-Multiplikators (GamificationService.basisMitDoppelXp).
  // Siehe wendeBonusAn weiter unten.

  /// 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
  /// erste Gruppenfahrt umfasst wo man abschliessen muss und die erste runde
  /// gefahren".
  ///
  /// Die ersten fuenf sind ohne Fahrt erfuellbar (Durchspielen auf der
  /// Couch), die letzten drei verlangen echtes Tun. Sie stehen bewusst am
  /// Ende der Liste, damit der Einstieg gleich bleibt.
  ///
  /// BESTANDSSCHUTZ: Wer die alten fuenf schon abgeschlossen hatte, hat
  /// `starter_paket_vergeben_v1 = true` und damit den Bonus bereits bekommen.
  /// [markiereAlle] vergibt ihn nur, solange er NICHT vergeben ist — die drei
  /// neuen Aufgaben koennen ihn also weder zurueckziehen noch neu ausloesen.
  /// Sichtbar wird „5/8" bei diesen Nutzern nicht: die Karte zeigt waehrend
  /// der laufenden Woche den Countdown und verschwindet danach ganz.
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
    StarterAufgabe(
      id: 'runde',
      titel: 'Die erste Runde fahren',
      beschreibung: 'Eine Fahrt starten und bis zum Ziel durchziehen.',
    ),
    StarterAufgabe(
      id: 'post',
      titel: 'Den ersten Post teilen',
      beschreibung: 'Zeig der Community, wo du unterwegs warst.',
    ),
    StarterAufgabe(
      id: 'gruppenfahrt',
      titel: 'Eine Gruppenfahrt abschließen',
      beschreibung: 'Gemeinsam losfahren und bis zum Ziel ankommen.',
    ),
  ];

  static final Set<String> _gueltigeIds = aufgaben.map((a) => a.id).toSet();

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

  /// 2026-08-19 (vucko): „das startklar abzeichen hat keiner".
  ///
  /// GEMESSEN am 19.08.: `badge_16` hatte 0 von 152 Profilen — auch die beiden
  /// Nutzer nicht, deren Doppel-XP-Woche nachweislich lief, die also alle
  /// Aufgaben erledigt hatten. Ursache: Das Abzeichen wurde NUR aus dem
  /// einmaligen Ereignis [paketFrischVerdient] heraus geschrieben, und genau
  /// zu diesem Zeitpunkt verwarf die Datenbank-Whitelist noch alles ab
  /// badge_15 (repariert erst am 18.08. mit 20260818230000). Ein Ereignis, das
  /// nur einmal feuert, kann man nicht nachholen.
  ///
  /// Deshalb gibt es diesen ZUSTAND: „Das Paket steht dir zu." Die
  /// Badge-Vergabe in `GamificationService.calculateAndSync` fragt ihn bei
  /// JEDEM Sync ab und haengt das Abzeichen an, wenn es fehlt. Damit kommt es
  /// auch Wochen spaeter noch an.
  bool get paketVerdient => _paketVergeben || alleErledigt;

  /// Läuft die Doppel-XP-Woche gerade?
  bool get doppelXpAktiv =>
      _bonusEnde != null && DateTime.now().isBefore(_bonusEnde!);

  Duration get bonusVerbleibend =>
      !doppelXpAktiv ? Duration.zero : _bonusEnde!.difference(DateTime.now());
  // 2026-08-19 (vucko): Hier stand `wendeBonusAn(int xp) => doppelXpAktiv ?
  // xp * 2 : xp`. Die Methode ist ERSATZLOS ENTFERNT, nicht nur entschaerft.
  //
  // Grund: Die Doppel-XP-Woche steckt seitdem in der BASIS des
  // Streak-Multiplikators (GamificationService.basisMitDoppelXp = 2,0 statt
  // 1,0, solange die Woche laeuft). Eine Methode, die nur noch durchreicht,
  // waere eine Falle: Wer spaeter wieder eine Verdopplung hineinschreibt,
  // rechnet die Woche ein zweites Mal. Nachgerechnet an Streak 3 und 1000 XP
  // Distanz-Basis: mit beidem 1000 * 1,3 * 2 = 2600 XP, richtig sind
  // 1000 * 2,3 = 2300 XP.

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
    if (_erledigt.contains(id)) return;
    await markiereAlle([id]);
  }

  /// Meldet mehrere Aufgaben in EINEM Durchgang.
  ///
  /// 2026-08-19: Noetig, weil die drei neuen Aufgaben (Runde, Post,
  /// Gruppenfahrt) gemeinsam aus den Kennzahlen abgeleitet werden. Einzeln
  /// markiert haette jede fuer sich gespeichert, und der Abschluss haette
  /// mehrfach gepruefte Zwischenzustaende gesehen.
  Future<void> markiereAlle(Iterable<String> ids) async {
    await load();
    final neue = ids
        .where((id) => _gueltigeIds.contains(id) && !_erledigt.contains(id))
        .toSet();
    if (neue.isEmpty) return;
    _erledigt.addAll(neue);

    final geradeKomplett = alleErledigt && !_paketVergeben;
    if (geradeKomplett) {
      _paketVergeben = true;
      // Der Timer beginnt GENAU JETZT und endet nach exakt sieben Tagen.
      _bonusEnde = DateTime.now().add(bonusDauer);
    }
    notifyListeners();
    await _speichereLokal();
    if (geradeKomplett) {
      debugPrint('[Starter] Paket komplett — Doppel-XP bis $_bonusEnde');
      paketFrischVerdient.value = true;
    }
  }

  /// Leitet die drei Aufgaben ab, die man nicht „melden" kann, ohne fremde
  /// Dateien anzufassen: sie stehen ohnehin in den Kennzahlen, die
  /// `GamificationService.calculateAndSync` fuer die Badges bereits berechnet.
  ///
  /// 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
  /// erste Gruppenfahrt umfasst wo man abschliessen muss und die erste runde
  /// gefahren".
  ///
  /// Aus dem Zustand statt aus dem Ereignis — genau die Lehre aus dem
  /// verlorenen Startklar-Abzeichen: Wer die Runde schon gefahren ist, bevor
  /// es diese Aufgabe gab, bekommt sie beim naechsten Sync gutgeschrieben.
  ///
  /// [abgeschlosseneFahrten] zaehlt Fahrten mit `completed_at_end`, also
  /// wirklich zu Ende gefahrene — „die erste runde gefahren".
  /// [abgeschlosseneGruppenfahrten] zaehlt dasselbe zusaetzlich mit
  /// `group_id` — „wo man abschliessen muss", eine bloss erstellte Gruppe
  /// zaehlt ausdruecklich NICHT.
  Future<void> synchronisiereAusKennzahlen({
    required int posts,
    required int abgeschlosseneFahrten,
    required int abgeschlosseneGruppenfahrten,
  }) async {
    await markiereAlle([
      if (posts > 0) 'post',
      if (abgeschlosseneFahrten > 0) 'runde',
      if (abgeschlosseneGruppenfahrten > 0) 'gruppenfahrt',
    ]);
  }

  // ---------------------------------------------------------------------
  // Server-Abgleich (2026-08-19)
  // ---------------------------------------------------------------------

  /// 2026-08-19 (gemessen): `starter_aufgaben_erledigt_v1`,
  /// `starter_bonus_ende_v1` und `starter_paket_vergeben_v1` lagen
  /// ausschliesslich in den SharedPreferences. Folge: Ein Geraetewechsel
  /// loeschte die laufende Bonuswoche, und derselbe Account konnte auf einem
  /// zweiten Geraet eine ZWEITE Woche bekommen, weil serverseitig nichts
  /// blockte.
  ///
  /// Seit Migration 20260819120000 stehen beide Werte auch auf `profiles`
  /// (`starter_aufgaben`, `starter_bonus_ende`), und ein Trigger macht das
  /// Bonus-Ende schreib-einmalig: Ein zweites Geraet kann es nicht mehr neu
  /// setzen.
  ///
  /// Zusammenfuehrungsregel:
  ///  * erledigte Aufgaben: VEREINIGUNG, nichts geht verloren.
  ///  * Bonus-Ende: Der Server gewinnt, wenn er eines hat — das zweite Geraet
  ///    uebernimmt die laufende Woche, statt eine neue zu starten.
  ///  * Hat der Server keines und lokal ist alles erledigt, wird die Woche
  ///    jetzt gestartet und hochgeschrieben.
  Future<void> synchronisiereMitProfil() async {
    await load();

    Map<String, dynamic>? profil;
    try {
      profil = await _leseProfil();
    } catch (e) {
      debugPrint('[Starter] Profil-Abgleich (lesen) fehlgeschlagen: $e');
      return;
    }
    if (profil == null) return;

    final serverErledigt = <String>{};
    final rohAufgaben = profil[spalteAufgaben];
    if (rohAufgaben is Iterable) {
      serverErledigt.addAll(
        rohAufgaben.whereType<String>().where(_gueltigeIds.contains),
      );
    }
    final rohEnde = profil[spalteBonusEnde];
    final serverEnde = rohEnde is String
        ? DateTime.tryParse(rohEnde)?.toLocal()
        : null;

    var geaendert = false;
    final vorher = _erledigt.length;
    _erledigt.addAll(serverErledigt);
    if (_erledigt.length != vorher) geaendert = true;

    if (serverEnde != null &&
        (_bonusEnde == null || !_nahezuGleich(_bonusEnde!, serverEnde))) {
      _bonusEnde = serverEnde;
      _paketVergeben = true;
      geaendert = true;
    }

    // Alles erledigt, aber noch nie eine Woche vergeben: jetzt starten.
    var frischVergeben = false;
    if (alleErledigt && _bonusEnde == null && !_paketVergeben) {
      _paketVergeben = true;
      _bonusEnde = DateTime.now().add(bonusDauer);
      geaendert = true;
      frischVergeben = true;
    }

    if (geaendert) {
      notifyListeners();
      await _speichereLokal();
    }

    final hoch = <String, dynamic>{};
    if (!_gleicheMenge(serverErledigt, _erledigt)) {
      hoch[spalteAufgaben] = (_erledigt.toList()..sort());
    }
    // Nur schreiben, wenn der Server noch keines hat — der Trigger wuerde ein
    // vorhandenes ohnehin zurueckdrehen, aber wir fragen gar nicht erst.
    if (serverEnde == null && _bonusEnde != null) {
      hoch[spalteBonusEnde] = _bonusEnde!.toUtc().toIso8601String();
    }
    if (hoch.isNotEmpty) {
      try {
        await _schreibeProfil(hoch);
      } catch (e) {
        debugPrint('[Starter] Profil-Abgleich (schreiben) fehlgeschlagen: $e');
      }
    }

    if (frischVergeben) {
      debugPrint('[Starter] Paket komplett (Abgleich) — Bonus bis $_bonusEnde');
      paketFrischVerdient.value = true;
    }
  }

  static bool _nahezuGleich(DateTime a, DateTime b) =>
      a.difference(b).inSeconds.abs() <= 1;

  static bool _gleicheMenge(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _speichereLokal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kErledigt, jsonEncode(_erledigt.toList()));
      await p.setBool(_kPaketVergeben, _paketVergeben);
      if (_bonusEnde != null) {
        await p.setString(_kBonusEnde, _bonusEnde!.toIso8601String());
      }
    } catch (e) {
      debugPrint('[Starter] Speichern fehlgeschlagen: $e');
    }
  }

  /// Ersetzbar, damit der Test ohne Supabase auskommt.
  @visibleForTesting
  Future<Map<String, dynamic>?> Function()? profilLeserFuerTests;

  /// Ersetzbar, damit der Test ohne Supabase auskommt.
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> werte)? profilSchreiberFuerTests;

  Future<Map<String, dynamic>?> _leseProfil() async {
    final leser = profilLeserFuerTests;
    if (leser != null) return leser();
    final db = Supabase.instance.client;
    final userId = db.auth.currentUser?.id;
    if (userId == null) return null;
    final zeile = await db
        .from('profiles')
        .select('$spalteAufgaben, $spalteBonusEnde')
        .eq('id', userId)
        .maybeSingle();
    return zeile;
  }

  Future<void> _schreibeProfil(Map<String, dynamic> werte) async {
    final schreiber = profilSchreiberFuerTests;
    if (schreiber != null) return schreiber(werte);
    final db = Supabase.instance.client;
    final userId = db.auth.currentUser?.id;
    if (userId == null) return;
    await db.from('profiles').update(werte).eq('id', userId);
  }

  /// Nur für Tests.
  @visibleForTesting
  void resetForTests() {
    _loaded = false;
    _erledigt = {};
    _bonusEnde = null;
    _paketVergeben = false;
    paketFrischVerdient.value = false;
    profilLeserFuerTests = null;
    profilSchreiberFuerTests = null;
  }
}
