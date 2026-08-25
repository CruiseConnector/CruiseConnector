import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
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
/// ABLAUF: Zwölf Aufgaben, von denen [aufgabenFuerBoost] genügen. Ist die
/// Schwelle erreicht, fällt die GANZE Belohnung auf einmal — an genau einer
/// Bedingung, nämlich [paketVerdient]:
///
///   * das Abzeichen „Startklar" (`Badge.starterBadgeId`, badge_16),
///   * 1000 XP (`GamificationService.starterPaketBonusXp`),
///   * und sieben Tage doppelte XP.
///
/// 2026-08-25 (vucko wörtlich): „man soll sehen man bekommt ein badge 1000 XP
/// + noch einen 2 fach boost der 7 Tage lang aktiv ist". Eine Belohnung für
/// eine Sache. Die 1000 XP fehlten bis heute komplett — gemessen war
/// `profiles.total_xp` bei allen 202 Profilen auf die Einheit genau die Summe
/// der gefahrenen XP.
///
/// Die Doppel-XP-Woche läuft exakt sieben Tage ab diesem Moment, danach
/// schaltet sich der Bonus von selbst ab. Der Endzeitpunkt wird EINMAL
/// gespeichert und nie neu angesetzt; ein App-Neustart verlängert nichts.
///
/// Das Abzeichen für ALLE zwölf (`Badge.alleAufgabenBadgeId`, badge_58) ist
/// KEIN Teil dieser Belohnung: kein XP, keine Bonuswoche. Es ist ein reines
/// Sammler-Abzeichen und gibt den letzten vier Aufgaben ein Ziel. Warum die
/// Belohnung nicht bei zwölf hängt, steht bei [aufgabenFuerBoost].
///
/// Die Erfüllung wird an den echten Stellen gemeldet (Route gesucht, Favorit
/// gespeichert, Community geöffnet, Tutorial beendet). Alles, was einen
/// Server-Beleg hat, wird NICHT gemeldet, sondern aus dem ZUSTAND abgeleitet —
/// siehe [synchronisiereAusKennzahlen]. Seit 24.08. gehört „Eine Route
/// speichern" dazu: gemeldet wurde sie vorher, bevor die Zeile überhaupt
/// geschrieben war.
class StarterAufgabenService extends ChangeNotifier {
  StarterAufgabenService._();
  static final StarterAufgabenService instance = StarterAufgabenService._();

  static const _kErledigt = 'starter_aufgaben_erledigt_v1';
  static const _kBonusEnde = 'starter_bonus_ende_v1';
  static const _kPaketVergeben = 'starter_paket_vergeben_v1';

  /// 2026-08-25 (vucko): „jeder soll die aufgaben alle nochmal machen".
  ///
  /// Zahl hochzaehlen loest die Ruecksetzung GENAU EIN MAL aus, danach nie
  /// wieder. Dasselbe Muster wie [AppTutorialService.ruecksetzGeneration].
  ///
  /// WARUM KEINE MIGRATION: Gemessen am 25.08. haben 200 von 202 Profilen
  /// eine LEERE `starter_aufgaben` — dort gibt es nichts zurueckzusetzen.
  /// Ein UPDATE auf der Datenbank waere fuer fast alle wirkungslos gewesen
  /// und haette trotzdem so ausgesehen, als taete es etwas.
  static const int ruecksetzGeneration = 1;
  static const String _kRuecksetzGeneration =
      'starter_aufgaben_ruecksetz_generation';

  /// Die einzigen vier Aufgaben, die eine Ruecksetzung ueberhaupt UEBERLEBT.
  ///
  /// Die anderen acht leiten sich aus dem Serverzustand ab (Kilometer,
  /// Abzeichen, Fahrzeug, Post, Hashtag, gefahrene Runde, Gruppenfahrt,
  /// gespeicherte Route). Sie zu loeschen waere ein Flackern ohne Wirkung:
  /// `synchronisiereAusKennzahlen` setzt sie beim naechsten Atemzug wieder.
  /// Schlimmer noch, es waere unehrlich — wer 500 km gefahren ist, HAT
  /// „Die ersten 50 Kilometer fahren" erledigt.
  static const Set<String> _ruecksetzbareAufgaben = {
    'tutorial',
    'route',
    'favorit',
    'community',
  };

  /// Spalten auf `profiles`, in denen derselbe Zustand serverseitig liegt
  /// (Migration 20260819120000). Siehe [synchronisiereMitProfil].
  static const spalteAufgaben = 'starter_aufgaben';
  static const spalteBonusEnde = 'starter_bonus_ende';

  static const Duration bonusDauer = Duration(days: 7);

  // 2026-08-19 (vucko): Hier stand `bonusFaktor = 2`. Der Bonus ist kein
  // Faktor mehr, der am Ende auf die fertigen XP gelegt wird, sondern die
  // BASIS des Streak-Multiplikators (GamificationService.basisMitDoppelXp).
  // Siehe wendeBonusAn weiter unten.

  /// 2026-08-24 (Aufgabe 4.5): Wie viele Abzeichen die Aufgabe „die ersten
  /// drei Abzeichen sammeln" verlangt.
  ///
  /// VUCKOS ENTSCHEIDUNG vom 24.08.: DREI. Er hat am 23.08. zweimal
  /// Verschiedenes gesagt — Aufnahme 5, [01:43]: „die ersten drei Badges
  /// sammeln", Aufnahme 6, [00:03] eine Minute spaeter: „vielleicht kann es
  /// auch beim Onboarding sein, dass man eher die ersten fuenf Badges sammeln
  /// muss". Heute hat er DREI entschieden. Deshalb steht die Zahl hier als
  /// benannte Konstante und nicht mitten im Code: eine Zeile, und es sind
  /// fuenf.
  ///
  /// GEMESSEN am 24.08.: 16 von 183 Profilen haben drei oder mehr Abzeichen.
  /// Das Gruendungsabzeichen badge_15 hat seit der Migration jeder, es fehlen
  /// also zwei echte. „Erste Fahrt" (badge_02) und „Erster Routenpost"
  /// (badge_05) sind genau die zwei, die aus den anderen Starter-Aufgaben
  /// ohnehin herausfallen.
  static const int abzeichenFuerAufgabe = 3;

  /// 2026-08-24 (Aufgabe 4.5, vucko woertlich): „die ersten 50 Kilometer
  /// fahren".
  ///
  /// Die vorhandene Aufgabe „runde" zaehlt EINE Fahrt, egal wie kurz. Diese
  /// hier verlangt Strecke. GEMESSEN am 24.08.: 9 von 183 Profilen haben 50
  /// Kilometer oder mehr — deshalb ist sie bewusst NICHT Pflicht fuer den
  /// Boost, siehe [aufgabenFuerBoost].
  static const int kilometerFuerAufgabe = 50;

  /// 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
  /// erste Gruppenfahrt umfasst wo man abschliessen muss und die erste runde
  /// gefahren".
  ///
  /// 2026-08-24 (Aufgabe 4.5, vucko woertlich): „ich moechte bei dem
  /// Onboarding, dass man auch als Aufgaben hat, wie: erste Gruppenfahrt
  /// erstellen, ersten Post erstellen, Auto in die Garage hinzufuegen [...]
  /// und such ja auch noch Aufgaben, wie beispielsweise die ersten drei
  /// Badges sammeln oder halt die ersten 50 Kilometer fahren".
  ///
  /// Zwoelf Aufgaben (seit 24.08. ist „Einen Hashtag benutzen" dabei). Die
  /// ersten sechs sind ohne Fahrt erfuellbar (Durchspielen auf der Couch), die
  /// letzten sechs verlangen echtes Tun. Sie stehen bewusst am Ende, damit der
  /// Einstieg gleich bleibt.
  ///
  /// DIE WICHTIGSTE AENDERUNG STEHT BEI 'gruppenfahrt'. Sie hiess
  /// „Eine Gruppenfahrt abschliessen". GEMESSEN am 24.08. in der
  /// Produktivdatenbank: NULL Fahrten mit `group_id` in der ganzen Geschichte
  /// der App, und nur 15 von 183 Nutzern haben ueberhaupt je eine Fahrt
  /// beendet. Solange das Pflicht war, war der Boost fuer JEDEN unerreichbar —
  /// gemessen hatte niemand ein `starter_bonus_ende`. Vucko sagt am 23.08.
  /// ausdruecklich „erste Gruppenfahrt ERSTELLEN", nicht abschliessen.
  ///
  /// BESTANDSSCHUTZ: Wer den Bonus schon hat, hat `_paketVergeben = true`
  /// (lokal oder vom Server). [markiereAlle] vergibt ihn nur, solange er NICHT
  /// vergeben ist — die neuen Aufgaben koennen ihn also weder zurueckziehen
  /// noch ein zweites Mal ausloesen.
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
    // 2026-08-24 (vucko): „Auto in die Garage hinzufuegen".
    StarterAufgabe(
      id: 'garage',
      titel: 'Dein Auto in die Garage stellen',
      beschreibung: 'Marke, Modell und Leistung im Profil eintragen.',
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
    // 2026-08-24 (Aufgabe 4, vucko woertlich): „man muss die sachen wie ersten
    // post oder benutze einen hashtag wenn das noch nicht als aufgabe drinnen
    // ist auch wirklich absolvieren".
    //
    // Sie stand NICHT drin. Es gibt sie jetzt, und sie ist echt gedeckt: die
    // Ablage `post_hashtags` (Migration 20260824102000) wird ausschliesslich
    // vom Trigger `post_hashtags_trg` aus dem Beitragstext gefuellt, nie vom
    // Client. Es reicht also nicht, ein Hashtag-Feld zu oeffnen — die Raute
    // muss in einem veroeffentlichten Beitrag stehen.
    //
    // Sie steht direkt hinter „post", weil sie einen Beitrag voraussetzt.
    StarterAufgabe(
      id: 'hashtag',
      titel: 'Einen Hashtag benutzen',
      beschreibung: 'Schreib ein #Thema in deinen Beitrag, dann finden dich '
          'andere darüber.',
    ),
    // 2026-08-24 (vucko): „erste Gruppenfahrt erstellen". Vorher hiess die
    // Zeile „Eine Gruppenfahrt abschliessen" — daran ist der Boost fuer alle
    // 183 Nutzer gescheitert, siehe der Kommentar ueber dieser Liste.
    StarterAufgabe(
      id: 'gruppenfahrt',
      titel: 'Eine Gruppenfahrt erstellen',
      beschreibung: 'Leg eine Gruppe an, damit andere mitfahren können.',
    ),
    // 2026-08-24 (vucko): „die ersten drei Badges sammeln".
    StarterAufgabe(
      id: 'abzeichen',
      titel: 'Die ersten $abzeichenFuerAufgabe Abzeichen sammeln',
      beschreibung: 'Deine Sammlung findest du in der Auswertung.',
    ),
    // 2026-08-24 (vucko): „die ersten 50 Kilometer fahren".
    StarterAufgabe(
      id: 'km50',
      titel: 'Die ersten $kilometerFuerAufgabe Kilometer fahren',
      beschreibung: 'Zusammengezählt über alle deine Fahrten.',
    ),
  ];

  /// 2026-08-24 (Aufgabe 4.5): Wie viele der elf Aufgaben der Boost verlangt.
  ///
  /// ENTSCHEIDUNG (Vucko schlaeft, keine Rueckfrage moeglich): ACHT von ELF.
  ///
  /// Vuckos Zweck ist woertlich Bindung: „so bringen wir Leute dazu, dass sie
  /// auch wirklich zuverlaessig fahren." Elf von elf waere das Gegenteil. Der
  /// Beweis liegt in den Zahlen vom 24.08.: die alte Liste verlangte ALLE
  /// acht, die achte war „Gruppenfahrt abschliessen", davon gab es null in
  /// der ganzen App — Ergebnis: 0 von 183 Nutzern haben den Boost je bekommen.
  /// Genau diese Falle darf sich nicht wiederholen, und zwei der drei neuen
  /// Aufgaben sind ebenfalls duenn besetzt (50 km: 9 von 183; drei Abzeichen:
  /// 16 von 183).
  ///
  /// Acht ist so gewaehlt, dass ein Weg dorthin OHNE die drei duennen Aufgaben
  /// existiert: Tutorial, Route, Adresse, Speichern, Community, Garage sind
  /// sechs ohne jede Fahrt; „erste Runde" und „erster Post" machen acht. Also
  /// eine echte Fahrt und ein echter Post, und der Boost laeuft — sieben Tage
  /// lang, in denen sich Fahren doppelt lohnt. Die drei uebrigen bleiben als
  /// Ziel stehen, statt als Sperre zu wirken.
  ///
  /// Die Zahl ist eine Zeile. Wer sie auf 12 stellt, verlangt wieder alles.
  ///
  /// 2026-08-24, ZWEITE ENTSCHEIDUNG (Aufgabe 4): Mit der zwoelften Aufgabe
  /// („Einen Hashtag benutzen") WANDERT DIE SCHWELLE NICHT MIT. Sie bleibt
  /// bei acht.
  ///
  /// Begruendung: Acht ist kein Anteil, sondern ein Preis — so viel Einsatz
  /// kostet der Boost. Waere die Schwelle ein Anteil, muesste sie bei zwoelf
  /// Aufgaben auf neun steigen, und der einzige Weg dorthin fuehrte ueber
  /// „post" UND „hashtag", also ueber denselben Beitrag zweimal. Der Preis
  /// stiege, ohne dass jemand mehr von der App gesehen haette.
  ///
  /// Dazu die Zahl, die hier alles entscheidet: 0 von 183 Nutzern haben den
  /// Boost je bekommen, weil die Schwelle unerreichbar war. Zwei Tage spaeter
  /// die Schwelle wieder anzuheben, waere derselbe Fehler mit einer anderen
  /// Zahl. Die Hashtag-Aufgabe kommt als ZIEL dazu, nicht als Sperre — genau
  /// wie die 50 Kilometer und die drei Abzeichen.
  ///
  /// 2026-08-25, DRITTE ENTSCHEIDUNG: Acht bleibt, und ab heute faellt hier
  /// die GANZE Belohnung — Abzeichen, 1000 XP und Bonuswoche gemeinsam.
  ///
  /// Geprueft wurde ausdruecklich, ob stattdessen zwoelf die eine Schwelle
  /// werden soll (Vucko: „jeder soll die aufgaben alle nochmal machen").
  /// GEMESSEN am 25.08. ueber alle 202 Profile, gezaehlt nur die acht
  /// serverseitig ableitbaren Aufgaben:
  ///
  ///   ein Beitrag             9      eine gespeicherte Route   19
  ///   ein Hashtag             0      drei Abzeichen             6
  ///   eine beendete Fahrt    18      fuenfzig Kilometer         9
  ///   eine Gruppenfahrt       1      ein Auto in der Garage    66
  ///   ---------------------------------------------------------------
  ///   alle acht zusammen      0
  ///
  /// Null. Und „ein Hashtag" hat in der ganzen Geschichte der App NIEMAND
  /// benutzt. Eine Belohnung bei zwoelf waere heute fuer keinen einzigen
  /// Nutzer erreichbar — dieselbe Falle wie am 24.08., nur mit einer anderen
  /// Zahl. Sie wird nicht wiederholt.
  ///
  /// Die letzten vier Aufgaben bleiben trotzdem stehen und behalten ein Ziel:
  /// das Sammler-Abzeichen `Badge.alleAufgabenBadgeId` bei zwoelf. Es traegt
  /// aber keine XP und keine Bonuswoche.
  static const int aufgabenFuerBoost = 8;

  static final Set<String> _gueltigeIds = aufgaben.map((a) => a.id).toSet();

  bool _loaded = false;
  Set<String> _erledigt = {};
  DateTime? _bonusEnde;
  bool _paketVergeben = false;

  /// Feuert genau EINMAL, wenn alle Aufgaben frisch erledigt wurden — die
  /// Oberfläche zeigt dann die Badge-Verleihung und startet die Bonus-Woche.
  final ValueNotifier<bool> paketFrischVerdient = ValueNotifier<bool>(false);

  /// Feuert genau EINMAL, wenn die ZWOELFTE Aufgabe faellt.
  ///
  /// 2026-08-25: Getrennt von [paketFrischVerdient], weil die beiden seit
  /// heute verschiedene Schwellen haben (acht gegen zwoelf). Ein einziger
  /// Melder haette bedeutet, dass entweder die Bonuswoche zu spaet startet
  /// oder badge_58 zu frueh faellt.
  final ValueNotifier<bool> alleAufgabenFrischErledigt =
      ValueNotifier<bool>(false);

  bool get isLoaded => _loaded;
  bool erledigt(String id) => _erledigt.contains(id);
  int get erledigtAnzahl =>
      aufgaben.where((a) => _erledigt.contains(a.id)).length;

  /// 2026-08-24: Hiess bis heute `alleErledigt` und meinte „alle acht". Der
  /// Name log ab dem Moment, in dem der Boost nicht mehr ALLE Aufgaben
  /// verlangt (siehe [aufgabenFuerBoost]). Umbenannt statt umgedeutet, damit
  /// niemand die Schwelle uebersieht.
  bool get boostErreicht => erledigtAnzahl >= aufgabenFuerBoost;

  /// 2026-08-25 (vucko woertlich): „alle funktionen einmal durchgetestet haben
  /// die es in der app gibt".
  ///
  /// Das ist die ZWEITE, haertere Schwelle: ALLE zwoelf Aufgaben. Sie ist
  /// bewusst etwas anderes als [boostErreicht] (acht von zwoelf):
  ///
  ///   * [boostErreicht] = ACHT  → badge_16 „Startklar" + Doppel-XP-Woche.
  ///     Das ist der PREIS fuer die Belohnung und muss erreichbar bleiben.
  ///   * [alleAufgabenErledigt] = ZWOELF → badge_58 und das Ende der Karte.
  ///     Das ist woertlich „jede Funktion einmal benutzt".
  ///
  /// Bis 25.08. hing badge_58 an der EINEN Aufgabe „tutorial", also an der
  /// Fuehrung mit den Leuchtkreisen allein. Gemessen: genau ein Profil von 199
  /// traegt es, und dieses Profil hatte zehn von zwoelf Aufgaben offen stehen.
  /// Vucko hat es fuer die Tour bekommen und nicht fuer die Liste — genau das
  /// meint sein „es soll passend sein dafuer".
  bool get alleAufgabenErledigt => erledigtAnzahl >= aufgaben.length;

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
  ///
  /// 2026-08-25: An DIESER Bedingung haengt die vollstaendige Belohnung —
  /// badge_16 „Startklar", 1000 XP (`GamificationService.starterPaketBonusXp`)
  /// und die Doppel-XP-Woche. Wer hier etwas aufteilt, hat wieder zwei
  /// Belohnungen fuer dieselbe Sache.
  bool get paketVerdient => _paketVergeben || boostErreicht;

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

  /// 2026-08-24 (Aufgabe 4.1): Der Ladevorgang wird EINMAL gestartet, und jeder
  /// weitere Aufrufer wartet auf DENSELBEN Vorgang.
  ///
  /// Vorher stand hier `if (_loaded) return; _loaded = true;` und danach erst
  /// das `await`. Ein Dart-`async`-Rumpf laeuft bis zum ersten `await`
  /// synchron — `_loaded` war also schon `true`, waehrend die Werte noch gar
  /// nicht gelesen waren. Genau so ruft es die Startseite auf
  /// (`starter_paket_karte.dart`, initState):
  ///
  ///     unawaited(StarterAufgabenService.instance.load());
  ///     unawaited(StarterAufgabenService.instance.synchronisiereMitProfil());
  ///
  /// Der zweite Aufruf machte `await load()` und bekam sofort die Kontrolle
  /// zurueck, obwohl der erste noch lief. Er holte das Server-Ende, setzte
  /// `_bonusEnde` und `_paketVergeben` — und danach ueberschrieb der immer
  /// noch laufende erste Aufruf beides mit den lokalen Werten
  /// (`_erledigt = ...`, `_paketVergeben = p.getBool(...) ?? false`). Der
  /// LOKALE Zustand gewann also gegen den Server.
  ///
  /// Warum das ab heute wehtut: Die Migration vom 24.08. hat allen 183
  /// Profilen `starter_bonus_ende = jetzt + 7 Tage` gegeben (gemessen
  /// nachher: 183 von 183). Verliert der Server dieses Rennen, sieht der
  /// Nutzer statt seiner Bonuswoche weiter die Aufgabenliste.
  Future<void>? _ladeVorgang;

  Future<void> load() => _ladeVorgang ??= _ladeWirklich();

  /// Nur fuer den Test: bremst das Lesen aus dem Geraetespeicher aus, damit
  /// der Wettlauf mit [synchronisiereMitProfil] reproduzierbar wird. In der
  /// App ist der Wert immer null und die Zeile kostet nichts.
  @visibleForTesting
  Future<void> Function()? ladeBremseFuerTests;

  /// Nimmt die vier Ereignis-Aufgaben GENAU EIN MAL zurueck, siehe
  /// [ruecksetzGeneration]. Gibt true zurueck, wenn dabei etwas entfernt
  /// wurde — der Aufrufer muss dann speichern und hochladen.
  ///
  /// `_paketVergeben` und `_bonusEnde` bleiben ABSICHTLICH unangetastet: Wer
  /// die Bonuswoche schon hat, soll sie behalten. Wuerde man sie mit
  /// zuruecknehmen, liefe hier ein Countdown fuer eine zweite Woche, die der
  /// Waechter `trg_guard_starter_bonus_ende` serverseitig gar nicht vergibt —
  /// die Anzeige waere gelogen.
  /// Die Abzeichen bleiben ohnehin, `profiles.badges` ist append-only.
  Future<bool> _stelleEinmaligeRuecksetzungSicher() async {
    try {
      final p = await SharedPreferences.getInstance();
      final schluessel = NutzerPrefsSchluessel.fuer(_kRuecksetzGeneration);
      final schonGelaufen = p.getInt(schluessel) ?? 0;
      if (schonGelaufen >= ruecksetzGeneration) return false;

      final vorher = _erledigt.length;
      _erledigt.removeAll(_ruecksetzbareAufgaben);
      await p.setInt(schluessel, ruecksetzGeneration);

      final entfernt = vorher - _erledigt.length;
      if (entfernt > 0) {
        debugPrint('[Starter] Einmalige Ruecksetzung: $entfernt Aufgaben.');
        return true;
      }
      return false;
    } catch (e) {
      // Kein Speicher, kein Drama: dann laeuft die Ruecksetzung beim
      // naechsten Start. Sie darf den Abgleich auf keinen Fall abbrechen.
      debugPrint('[Starter] Ruecksetzung fehlgeschlagen: $e');
      return false;
    }
  }

  Future<void> _ladeWirklich() async {
    final bremse = ladeBremseFuerTests;
    if (bremse != null) await bremse();
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
    } catch (e) {
      debugPrint('[Starter] Laden fehlgeschlagen: $e');
    }
    _loaded = true;
    notifyListeners();
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
    // 2026-08-25: VOR dem Hinzufuegen merken, sonst waere „gerade jetzt alle
    // zwoelf" nicht von „waren vorher schon alle zwoelf" zu unterscheiden.
    final vorherAlle = alleAufgabenErledigt;
    _erledigt.addAll(neue);

    final geradeKomplett = boostErreicht && !_paketVergeben;
    if (geradeKomplett) {
      _paketVergeben = true;
      // Der Timer beginnt GENAU JETZT und endet nach exakt sieben Tagen.
      _bonusEnde = DateTime.now().add(bonusDauer);
    }
    notifyListeners();
    await _speichereLokal();
    if (geradeKomplett) {
      debugPrint('[Starter] Boost erreicht — Doppel-XP bis $_bonusEnde');
      paketFrischVerdient.value = true;
    }
    _meldeAbschlussWennKomplett(vorherAlle);
  }

  /// 2026-08-25: Meldet den Abschluss ALLER zwoelf Aufgaben — einmal.
  ///
  /// [vorherAlle] ist der Stand VOR der Aenderung. Ohne ihn wuerde jede
  /// weitere Meldung nach dem zwoelften Haken erneut feuern, und die Karte
  /// zeigte die Abzeichen-Verleihung bei jedem Sync wieder.
  void _meldeAbschlussWennKomplett(bool vorherAlle) {
    if (vorherAlle || !alleAufgabenErledigt) return;
    debugPrint('[Starter] Alle ${aufgaben.length} Aufgaben erledigt');
    alleAufgabenFrischErledigt.value = true;
  }

  /// Leitet die Aufgaben ab, die man nicht „melden" kann, ohne fremde Dateien
  /// anzufassen: sie stehen ohnehin in den Kennzahlen, die
  /// `GamificationService.calculateAndSync` fuer die Badges bereits berechnet.
  ///
  /// 2026-08-19 (vucko): „auch noch weitere sachen wie der erste post, die
  /// erste Gruppenfahrt umfasst wo man abschliessen muss und die erste runde
  /// gefahren".
  ///
  /// 2026-08-24 (vucko): „erste Gruppenfahrt erstellen, ersten Post erstellen,
  /// Auto in die Garage hinzufuegen [...] die ersten drei Badges sammeln oder
  /// halt die ersten 50 Kilometer fahren".
  ///
  /// Aus dem ZUSTAND statt aus dem EREIGNIS — die Lehre aus dem verlorenen
  /// Startklar-Abzeichen: Wer die Runde schon gefahren ist, bevor es die
  /// Aufgabe gab, bekommt sie beim naechsten Sync gutgeschrieben.
  ///
  /// [abgeschlosseneFahrten] zaehlt Fahrten mit `completed_at_end`, also
  /// wirklich zu Ende gefahrene — „die erste runde gefahren".
  ///
  /// [erstellteGruppen] zaehlt `groups.created_by = ich`. GEMESSEN am 24.08.:
  /// null Fahrten mit `group_id` in der ganzen Geschichte der App. Die alte
  /// Bedingung „abgeschlossene Gruppenfahrt" war deshalb fuer jeden Nutzer
  /// unerfuellbar und hat den Boost fuer alle 183 blockiert.
  /// [abgeschlosseneGruppenfahrten] zaehlt weiterhin mit und erfuellt die
  /// Aufgabe ebenfalls: Wer eine Gruppenfahrt zu Ende gefahren ist, soll sie
  /// nicht deshalb offen sehen, weil die Gruppe jemand anderes angelegt hat.
  ///
  /// [fahrzeuge] sind Zeilen in `profile_vehicles` — „Auto in die Garage
  /// hinzufuegen".
  ///
  /// [abzeichen] ist die Anzahl der bereits erfuellten Abzeichen OHNE das
  /// Startklar-Abzeichen selbst. Das ist Absicht und kein Versehen: badge_16
  /// ist die BELOHNUNG dieser Liste. Zaehlte es mit, haenge die Aufgabe „drei
  /// Abzeichen" an ihrem eigenen Ergebnis.
  ///
  /// [gesamtKm] sind die aufaddierten Kilometer aller Fahrten.
  ///
  /// [hashtagBenutzt] kommt aus `post_hashtags` (Migration 20260824102000).
  /// Diese Ablage fuellt AUSSCHLIESSLICH der Trigger `post_hashtags_trg` aus
  /// dem Beitragstext — der Client darf dort nicht schreiben. Damit ist die
  /// Aufgabe nicht vortaeuschbar: die Raute muss in einem veroeffentlichten
  /// Beitrag stehen.
  ///
  /// [gespeicherteRouten] zaehlt `routes` und `route_bookmarks` des Nutzers.
  /// 2026-08-24 (Aufgabe 4, Pruefung der bestehenden Aufgaben): „speichern"
  /// war die einzige Aufgabe, die sich VOR der Tat abhaken liess — die
  /// Meldung stand in `SavedRoutesService.saveRoute` noch vor der
  /// Anmelde-Pruefung und vor dem INSERT. Ein fehlgeschlagenes Speichern
  /// (kein Netz, RLS-Fehler) hakte sie trotzdem ab. Die Meldung sitzt jetzt
  /// hinter dem erfolgreichen INSERT, und dieser Zustandsabgleich ist die
  /// zweite Sicherung: Wer auf einem anderen Geraet gespeichert hat, bekommt
  /// den Haken hier nachgetragen.
  Future<void> synchronisiereAusKennzahlen({
    required int posts,
    required int abgeschlosseneFahrten,
    required int abgeschlosseneGruppenfahrten,
    int erstellteGruppen = 0,
    int fahrzeuge = 0,
    int abzeichen = 0,
    double gesamtKm = 0,
    bool hashtagBenutzt = false,
    int gespeicherteRouten = 0,
  }) async {
    await markiereAlle([
      if (posts > 0) 'post',
      if (hashtagBenutzt) 'hashtag',
      if (abgeschlosseneFahrten > 0) 'runde',
      if (erstellteGruppen > 0 || abgeschlosseneGruppenfahrten > 0)
        'gruppenfahrt',
      if (fahrzeuge > 0) 'garage',
      if (gespeicherteRouten > 0) 'speichern',
      if (abzeichen >= abzeichenFuerAufgabe) 'abzeichen',
      if (gesamtKm >= kilometerFuerAufgabe) 'km50',
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
    // 2026-08-25: Auch die Vereinigung mit dem Server kann die zwoelfte
    // Aufgabe bringen (Geraetewechsel). Sonst kaeme badge_58 auf dem neuen
    // Handy nie an.
    final vorherAlle = alleAufgabenErledigt;
    _erledigt.addAll(serverErledigt);
    if (_erledigt.length != vorher) geaendert = true;

    // 2026-08-25 (vucko): „jeder soll die aufgaben alle nochmal machen".
    //
    // MUSS HIER STEHEN, nach der Vereinigung und vor dem Hochladen. Weiter
    // oben waere sie wirkungslos: `addAll(serverErledigt)` holt die Haken
    // eine Zeile spaeter zurueck. Weiter unten kaeme sie zu spaet fuers
    // Hochladen, und der Server behielte den alten Stand.
    // Danach schreibt der vorhandene `hoch[spalteAufgaben]`-Zweig den
    // bereinigten Stand von selbst hoch — der Client korrigiert den Server,
    // genau beim ersten Start dieses Builds.
    if (await _stelleEinmaligeRuecksetzungSicher()) geaendert = true;

    if (serverEnde != null) {
      // 2026-08-24 (Aufgabe 4.1): Die zweite Bedingung („nur wenn das lokale
      // Ende fehlt oder abweicht") stand frueher aussen herum. Stimmten beide
      // Enden ueberein, blieb `_paketVergeben` auf `false` — und damit galt
      // das Startklar-Abzeichen als nicht verdient, obwohl der Server die
      // Bonuswoche laengst kannte. Der Server hat eine laufende Woche, also
      // ist das Paket vergeben. Punkt.
      if (!_paketVergeben) {
        _paketVergeben = true;
        geaendert = true;
      }
      if (_bonusEnde == null || !_nahezuGleich(_bonusEnde!, serverEnde)) {
        _bonusEnde = serverEnde;
        geaendert = true;
      }
    }

    // Alles erledigt, aber noch nie eine Woche vergeben: jetzt starten.
    var frischVergeben = false;
    if (boostErreicht && _bonusEnde == null && !_paketVergeben) {
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
      debugPrint('[Starter] Boost erreicht (Abgleich) — Bonus bis $_bonusEnde');
      paketFrischVerdient.value = true;
    }
    _meldeAbschlussWennKomplett(vorherAlle);
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
    _ladeVorgang = null;
    _erledigt = {};
    _bonusEnde = null;
    _paketVergeben = false;
    paketFrischVerdient.value = false;
    alleAufgabenFrischErledigt.value = false;
    profilLeserFuerTests = null;
    profilSchreiberFuerTests = null;
    ladeBremseFuerTests = null;
  }
}
