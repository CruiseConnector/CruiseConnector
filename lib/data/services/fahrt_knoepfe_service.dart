import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-09-02 (Vucko, Sprachnachricht):
///   "ich [moechte] die buttons rechts waehrend der fahrt minimieren ...
///    es sollen maximal 4 buttons da sein im moment ist das zu viel bzw. in
///    den einstellungen kann man alle hinzufuegen falls man eins nicht
///    braucht oder eins anders haben moechte aber maximal das man 4 anzeigen
///    kann von der position passt es"
///
/// WAS VORHER WAR
///
/// Die rechte Spalte baute ihre Knoepfe fest verdrahtet auf. Waehrend einer
/// bestaetigten Fahrt standen dort bis zu SECHS: Route-Uebersicht,
/// POI-Filter, Sprachansage, Meldungen ein und aus, Kamera zentrieren und
/// Melden. Die Spalte war deshalb schon einmal so hoch, dass sie ins
/// Manoever-Banner ragte; der Notbehelf war ein Scrollbereich mit
/// `reverse: true`, der oben abschnitt. Eine Leiste, die man wegscrollen
/// muss, um an einen Knopf zu kommen, ist waehrend der Fahrt unbrauchbar.
///
/// WAS JETZT GILT
///
/// Der Fahrer waehlt HOECHSTENS VIER. Die Auswahl liegt hier, nicht in der
/// Fahransicht: dieselbe Liste wird von der Fahransicht gezeichnet und von
/// den Einstellungen bearbeitet, und zwei Kopien derselben Liste laufen
/// frueher oder spaeter auseinander.
///
/// Die Voreinstellung sind genau die vier, die Vucko in derselben Nachricht
/// als behaltenswert genannt hat: Lautstaerke, Melden, Zentrieren und der
/// POI-Filter. Die beiden, die er streichen wollte (Meldungen ein und aus,
/// ganze Karte sehen), sind weiterhin WAEHLBAR, aber nicht mehr voreingestellt.
/// Der Meldungs-Schalter ist zusaetzlich in die POI-Liste gewandert, so wie
/// er es vorgeschlagen hat, und ist damit auch ohne eigenen Knopf erreichbar.
enum FahrKnopf {
  /// POI-Filter. Enthaelt seit dem 02.09. auch den Schalter fuer Meldungen.
  poi('poi'),

  /// Sprachansage aus, nur Wichtiges, alles. Langer Druck oeffnet die
  /// Lautstaerke.
  stimme('stimme'),

  /// Kamera an die eigene Position binden oder frei bewegen.
  zentrieren('zentrieren'),

  /// Unfall, Baustelle oder Stau melden. Nur waehrend einer bestaetigten
  /// Fahrt sichtbar.
  melden('melden'),

  /// Die ganze Strecke auf einmal sehen. Nur mit Route sichtbar.
  uebersicht('uebersicht'),

  /// Fremde Meldungen ein und aus. Liegt seit dem 02.09. auch in der
  /// POI-Liste.
  meldungen('meldungen');

  const FahrKnopf(this.kennung);

  /// Was in den Einstellungen gespeichert wird. Bewusst eine eigene, kurze
  /// Zeichenkette und nicht `name`: eine Umbenennung im Code darf die
  /// gespeicherte Auswahl der Nutzer nicht zerstoeren.
  final String kennung;

  static FahrKnopf? ausKennung(String k) {
    for (final e in FahrKnopf.values) {
      if (e.kennung == k) return e;
    }
    return null;
  }
}

/// Was zu einem Knopf in den Einstellungen steht.
class FahrKnopfInfo {
  const FahrKnopfInfo({
    required this.knopf,
    required this.name,
    required this.beschreibung,
    required this.symbol,
    this.brauchtRoute = false,
  });

  final FahrKnopf knopf;
  final String name;
  final String beschreibung;
  final IconData symbol;

  /// Knoepfe, die ohne Route nichts tun koennen. Sie bleiben waehlbar, sind
  /// aber vor dem Start der Fahrt nicht zu sehen. Das ist Absicht und kein
  /// Fehler: ein Melde-Knopf ohne Fahrt haette nichts zu melden.
  final bool brauchtRoute;
}

class FahrtKnoepfeService extends ChangeNotifier {
  FahrtKnoepfeService._();
  static final FahrtKnoepfeService instance = FahrtKnoepfeService._();

  static const _keyAuswahl = 'fahrt_knoepfe_auswahl_v1';
  static const _keyEingeklappt = 'fahrt_knoepfe_eingeklappt_v1';

  /// Vuckos Vorgabe vom 02.09., woertlich: hoechstens vier.
  static const int hoechstens = 4;

  /// Genau die vier, die er behalten wollte.
  static const List<FahrKnopf> voreinstellung = [
    FahrKnopf.poi,
    FahrKnopf.stimme,
    FahrKnopf.zentrieren,
    FahrKnopf.melden,
  ];

  static const List<FahrKnopfInfo> alle = [
    FahrKnopfInfo(
      knopf: FahrKnopf.poi,
      name: 'Punkte auf der Karte',
      beschreibung:
          'Tankstellen, Essen, Werkstatt und mehr ein oder aus. Hier liegt '
          'auch der Schalter für fremde Meldungen.',
      symbol: Icons.tune_rounded,
    ),
    FahrKnopfInfo(
      knopf: FahrKnopf.stimme,
      name: 'Sprachansage',
      beschreibung:
          'Aus, nur das Wichtige oder alles. Länger drücken öffnet die '
          'Lautstärke.',
      symbol: Icons.volume_up_rounded,
    ),
    FahrKnopfInfo(
      knopf: FahrKnopf.zentrieren,
      name: 'Karte zentrieren',
      beschreibung:
          'Die Karte folgt dir wieder, nachdem du sie verschoben hast.',
      symbol: Icons.explore,
    ),
    FahrKnopfInfo(
      knopf: FahrKnopf.melden,
      name: 'Melden',
      beschreibung: 'Unfall, Baustelle oder Stau für andere melden.',
      symbol: Icons.add_rounded,
      brauchtRoute: true,
    ),
    FahrKnopfInfo(
      knopf: FahrKnopf.uebersicht,
      name: 'Ganze Strecke sehen',
      beschreibung: 'Zoomt einmal auf die komplette Route heraus.',
      symbol: Icons.map_outlined,
      brauchtRoute: true,
    ),
    FahrKnopfInfo(
      knopf: FahrKnopf.meldungen,
      name: 'Fremde Meldungen',
      beschreibung:
          'Baustellen und Unfälle anderer ein oder aus. Steht auch in der '
          'Liste der Punkte auf der Karte.',
      symbol: Icons.warning_amber_rounded,
    ),
  ];

  static FahrKnopfInfo infoZu(FahrKnopf k) =>
      alle.firstWhere((i) => i.knopf == k);

  List<FahrKnopf> _auswahl = List<FahrKnopf>.from(voreinstellung);
  bool _eingeklappt = false;
  bool _geladen = false;

  /// Die gewaehlten Knoepfe, von oben nach unten.
  List<FahrKnopf> get auswahl => List<FahrKnopf>.unmodifiable(_auswahl);

  /// Ob die Spalte gerade zusammengeklappt ist.
  bool get eingeklappt => _eingeklappt;

  bool get geladen => _geladen;

  bool istGewaehlt(FahrKnopf k) => _auswahl.contains(k);

  bool get istVoll => _auswahl.length >= hoechstens;

  Future<void> laden() async {
    if (_geladen) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final roh = prefs.getStringList(_keyAuswahl);
      if (roh != null) {
        final gelesen = <FahrKnopf>[];
        for (final k in roh) {
          final e = FahrKnopf.ausKennung(k);
          // Unbekannte Kennungen still ueberspringen. Sie entstehen, wenn
          // jemand eine aeltere App-Fassung benutzt hat, in der es einen
          // Knopf gab, den es heute nicht mehr gibt.
          if (e != null && !gelesen.contains(e)) gelesen.add(e);
        }
        // Eine LEERE Liste ist eine gueltige Entscheidung: dann ist die
        // Spalte weg und nur der Griff zum Ausklappen bleibt.
        _auswahl = gelesen.take(hoechstens).toList();
      }
      _eingeklappt = prefs.getBool(_keyEingeklappt) ?? false;
    } catch (_) {
      // Ohne gespeicherte Einstellung gilt die Voreinstellung. Ein Fehler
      // beim Lesen darf die Fahransicht nicht aufhalten.
    }
    _geladen = true;
    notifyListeners();
  }

  Future<void> _sichern() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _keyAuswahl,
        _auswahl.map((e) => e.kennung).toList(),
      );
      await prefs.setBool(_keyEingeklappt, _eingeklappt);
    } catch (_) {}
  }

  /// Schaltet einen Knopf hinzu oder weg.
  ///
  /// Gibt `false` zurueck, wenn schon vier gewaehlt sind und ein fuenfter
  /// dazukommen soll. Die Oberflaeche sagt dann, dass zuerst einer weg muss;
  /// still den aeltesten hinauszuwerfen waere eine Ueberraschung.
  Future<bool> umschalten(FahrKnopf k) async {
    if (_auswahl.contains(k)) {
      _auswahl.remove(k);
    } else {
      if (_auswahl.length >= hoechstens) return false;
      _auswahl.add(k);
    }
    notifyListeners();
    await _sichern();
    return true;
  }

  /// Verschiebt einen Knopf in der Reihenfolge. [nach] wird auf den gueltigen
  /// Bereich beschnitten, damit ein Ziehen ueber den Rand nichts zerstoert.
  Future<void> verschieben(int von, int nach) async {
    if (von < 0 || von >= _auswahl.length) return;
    final ziel = nach.clamp(0, _auswahl.length - 1);
    if (ziel == von) return;
    final e = _auswahl.removeAt(von);
    _auswahl.insert(ziel, e);
    notifyListeners();
    await _sichern();
  }

  Future<void> aufVoreinstellung() async {
    _auswahl = List<FahrKnopf>.from(voreinstellung);
    notifyListeners();
    await _sichern();
  }

  Future<void> setzeEingeklappt(bool wert) async {
    if (_eingeklappt == wert) return;
    _eingeklappt = wert;
    notifyListeners();
    await _sichern();
  }

  Future<void> einklappenUmschalten() => setzeEingeklappt(!_eingeklappt);

  /// Nur fuer Tests: setzt den Dienst auf den Auslieferungszustand zurueck.
  @visibleForTesting
  void zuruecksetzenFuerTest() {
    _auswahl = List<FahrKnopf>.from(voreinstellung);
    _eingeklappt = false;
    _geladen = false;
  }
}
