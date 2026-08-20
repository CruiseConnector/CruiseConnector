import 'dart:math' as math;

import 'package:cruise_connect/data/services/geo_distance.dart';

/// 2026-08-20 (vucko, Aufgabe 4): „Die neue Funktion mit Unfaelle melden,
/// Baustellen und auch Stau ist leider noch nicht so funktional." Und zum
/// Stau ausdruecklich: er soll „halt irgendwie automatisch erfasst" werden.
///
/// GEMESSENE AUSGANGSLAGE, die das Verfahren bestimmt:
/// In 104 Tagen gab es 7 zeitliche Ueberlappungen zweier Fahrer und GENAU
/// EINE davon am selben Ort. Ein Schwarmverfahren wie bei Google Maps, das
/// mehrere Fahrer auf demselben Abschnitt braucht, wuerde in dieser App also
/// praktisch nie ausloesen. Diese Klasse erkennt Stau deshalb aus dem
/// Fahrprofil eines EINZELNEN Fahrers.
///
/// Reiner Rechenkern: keine Widgets, kein Plattformzugriff, keine Uhr aus dem
/// System. Alles kommt ueber [verarbeite] herein, alles geht als [StauBefund]
/// heraus. Damit ist jeder Verlauf im Test nachspielbar.
///
/// DER SCHWIERIGE TEIL SIND DIE FALSCHEN AUSLOESER. Langsam allein heisst
/// nicht Stau:
///  * Eine rote Ampel haelt an, ein Kreisverkehr bremst, eine Pause an der
///    Tankstelle steht.
///  * Kurvige Landstrassen werden langsam gefahren, gerade von den
///    Motorradfahrern dieser App, und das ist genau der Sinn der Sache.
///  * Ortsdurchfahrten sind langsam und trotzdem voellig normal.
///
/// Vier Ideen trennen das:
///  1. VERGLEICH STATT FESTWERT. Gemessen wird gegen die von GraphHopper
///     erwartete Fahrzeit des Abschnitts, nicht gegen eine feste km/h-Zahl.
///     Die Erwartung enthaelt Strassenklasse, Kurvigkeit und Ortsgebiet
///     bereits. Eine kurvige Landstrasse hat dadurch von Haus aus eine
///     niedrige Erwartung, langsames Fahren dort faellt nicht auf.
///  2. DAUER. Ein Ampelumlauf ist endlich, ein Stau nicht.
///  3. ABSTAND DER STILLSTAENDE. Im Stau kriecht man alle paar Meter erneut
///     an, in einer Ortsdurchfahrt liegen die Ampeln hunderte Meter
///     auseinander. Dieser Abstand ist das schaerfste Trennmerkmal.
///  4. LAGE ZUR ROUTE. Wer an der Tankstelle steht, steht neben der Strasse.
///     Wer im Stau steht, steht auf ihr.
class StauErkennung {
  StauErkennung();

  // ---------------------------------------------------------------------
  // Schwellen. Jede einzelne ist begruendet, keine ist geraten.
  // ---------------------------------------------------------------------

  /// Ab hier gilt das Fahrzeug als STEHEND (1,4 m/s = 5 km/h).
  /// Nicht 0, weil ein ruhendes Geraet durch GPS-Rauschen regelmaessig
  /// Scheingeschwindigkeiten bis etwa 1 m/s meldet.
  static const double stehtSchwelleMs = 1.4;

  /// Ab hier gilt das Fahrzeug wieder als ROLLEND (4,2 m/s = 15 km/h).
  /// Der Abstand zu [stehtSchwelleMs] ist bewusste Hysterese: ohne ihn
  /// wuerde ein einziger verrauschter Messwert eine ganze Anfahr-und-Steh
  /// Runde vortaeuschen und die Zaehlung verfaelschen.
  static const double rolltSchwelleMs = 4.2;

  /// Langsam heisst: hoechstens 40 % des erwarteten Tempos.
  /// Die Stauforschung (TomTom, INRIX) zieht die Grenze bei 50 bis 60 % des
  /// freien Flusses. Wir gehen mit 40 % bewusst darunter, weil hier ein
  /// EINZELNER Fahrer die ganze Beweislast traegt und eine Fehlmeldung teurer
  /// ist als eine verpasste.
  static const double relativeSchwelle = 0.4;

  /// Fallback, wenn fuer den Abschnitt keine Erwartung vorliegt:
  /// 4,2 m/s = 15 km/h. Das liegt unter dem, was in einer Tempo-30-Zone oder
  /// einer engen Ortsdurchfahrt normal ist, ohne Stau kommt man da nicht hin.
  static const double absoluteSchwelleMs = 4.2;

  /// Ab hier gilt die Fahrt wieder als frei: 70 % der Erwartung, ersatzweise
  /// 11,1 m/s = 40 km/h. Bewusst deutlich ueber [relativeSchwelle], damit ein
  /// Stau nicht bei jedem kurzen Vorwaertsrucken als beendet gilt.
  static const double freiRelativeSchwelle = 0.7;
  static const double freiAbsoluteSchwelleMs = 11.1;

  /// Mindestdauer des Verdachtsfensters fuer den Zaehfluss-Weg.
  /// Ein voller Ampelumlauf liegt in Deutschland und Oesterreich bei 60 bis
  /// 90 s, Ausreisser erreichen 120 s. Zwei Minuten schliessen damit eine
  /// einzelne Rotphase sicher aus.
  static const Duration mindestDauer = Duration(seconds: 120);

  /// Mindeststrecke im Verdachtsfenster fuer den Zaehfluss-Weg.
  /// Ein Halt an Ampel, Kreisverkehr oder Zapfsaeule legt null Meter zurueck.
  /// 150 m beweisen, dass es sich um zaehen VERKEHR handelt und nicht um
  /// einen einzelnen Halt.
  static const double mindestStreckeMeter = 150.0;

  /// So viele Stillstaende braucht der Zaehfluss-Weg.
  /// Eine Ampel erzeugt einen, ein Kreisverkehr hoechstens einen. Drei
  /// Stillstaende in einem Fenster sind kein Einzelereignis mehr.
  static const int mindestStillstaende = 3;

  /// Und so dicht muessen sie liegen: hoechstens 120 m Rollstrecke zwischen
  /// zwei Stillstaenden. Im Stau kriecht man 10 bis 100 m pro Runde, Ampeln
  /// in einer Ortsdurchfahrt stehen 200 bis 600 m auseinander. Das ist das
  /// Merkmal, das Ortsdurchfahrt und Stau zuverlaessig trennt.
  static const double maxRollstreckeMeter = 120.0;

  /// Stillstand-Weg: ab drei Minuten am Stueck ist es kein Ampelumlauf mehr.
  static const Duration stillstandVerdacht = Duration(seconds: 180);

  /// Stillstand-Weg, harte Stufe: zehn Minuten am Stueck AUF der Route.
  /// Keine Lichtsignalanlage und kein Kreisverkehr haelt so lange, und wer
  /// nachweislich auf der Fahrbahnachse steht, parkt nicht.
  static const Duration stillstandSicher = Duration(seconds: 600);

  /// Gleichmaessiger Zaehfluss ohne Stillstand (typisch Autobahn):
  /// drei Minuten und mindestens 500 m. Kuerzer waere von einer Baustelle
  /// oder einem langsamen Lastzug nicht zu unterscheiden.
  static const Duration zaehflussDauer = Duration(seconds: 180);
  static const double zaehflussStreckeMeter = 500.0;

  /// Und nur unter 30 % der Erwartung ist gleichmaessiger Zaehfluss sicher
  /// genug zum Melden. Zwischen 30 und 40 % bleibt es beim Anzeigen.
  static const double zaehflussSicherSchwelle = 0.3;

  /// Weiter als 30 m neben der Route heisst: nicht auf der Strasse.
  /// Tankstellenvorplaetze und Parkplaetze liegen 20 bis 50 m von der
  /// Fahrbahnachse entfernt, die Ortsungenauigkeit im Stadtgebiet liegt bei
  /// 10 bis 20 m. 30 m ist der Punkt, ab dem beides sauber auseinanderfaellt.
  static const double abseitsDerRouteMeter = 30.0;

  /// So lange muss jemand stehen, bevor der Routenabstand ihn als Pause
  /// entlarven darf. Vorher koennte es das Abbiegen in eine Ausfahrt sein.
  static const Duration pausePruefungAb = Duration(seconds: 60);

  /// So lange freie Fahrt beendet einen laufenden Verdacht.
  static const Duration verdachtEndeDauer = Duration(seconds: 20);

  /// So lange bzw. so weit freie Fahrt beendet einen erkannten Stau.
  /// Stauwellen sind typischerweise 300 bis 800 m lang, ein freier Kilometer
  /// ist deshalb keine Welle mehr, sondern das Ende.
  static const Duration stauEndeDauer = Duration(seconds: 60);
  static const double stauEndeStreckeMeter = 1000.0;

  /// Schlechtere Fixes fliegen raus, sie erzeugen die falschen Tempowerte.
  static const double maxGenauigkeitMeter = 50.0;

  /// Groesser als das ist keine Messluecke mehr, sondern ein Loch.
  /// Passt zur gemessenen Ursache 2: `set_live_position` lief nur alle 60 s,
  /// dazwischen weiss niemand, ob jemand gefahren oder geparkt hat.
  static const Duration maxLuecke = Duration(seconds: 60);

  /// Ueber 70 m/s (252 km/h) ist der Fix kaputt, nicht der Fahrer schnell.
  /// Gleiche Grenze wie im [DrivenTrackRecorder].
  static const double maxPlausibelMs = 70.0;

  /// Die Erwartung wird nur benutzt, wenn sie mindestens die Haelfte des
  /// Fensters abdeckt. Sonst waere ein einzelner Abschnittswert der Massstab
  /// fuer eine Viertelstunde Fahrt.
  static const double mindestErwartungsAbdeckung = 0.5;

  // ---------------------------------------------------------------------
  // Zustand
  // ---------------------------------------------------------------------

  StauPhase _phase = StauPhase.frei;
  StauSicherheit _sicherheit = StauSicherheit.keine;

  _Probe? _letzteProbe;

  DateTime? _fensterStart;
  double? _fensterStartLat;
  double? _fensterStartLng;
  double _fensterStreckeMeter = 0.0;
  Duration _fensterDauer = Duration.zero;

  /// Zeitgewichtete Summe der Erwartung, damit lange Abschnitte staerker
  /// zaehlen als kurze.
  double _erwartungSumme = 0.0;
  Duration _erwartungDauer = Duration.zero;

  bool _steht = false;
  DateTime? _stehtSeit;
  int _stillstaende = 0;
  double _rollstreckeSeitStillstand = 0.0;
  final List<double> _rollstrecken = [];

  DateTime? _schnellSeit;
  double _schnellStreckeMeter = 0.0;

  /// Dieser Stillstand ist als Pause abseits der Route abgehakt. Solange das
  /// Fahrzeug steht, wird daraus kein neuer Verdacht mehr. Ohne den Merker
  /// wuerde eine Tankpause im Sekundentakt zwischen Verdacht und Verwerfen
  /// hin und her springen.
  bool _pauseVerworfen = false;

  String _letzterGrund = '';

  StauPhase get phase => _phase;
  StauSicherheit get sicherheit => _sicherheit;

  /// Erwartetes Tempo eines Abschnitts aus den GraphHopper-Feldern.
  /// `distance` in Metern, `time` in Millisekunden. Ergebnis in m/s,
  /// null wenn die Werte unbrauchbar sind.
  static double? erwartetesTempoAusAbschnitt({
    required double streckeMeter,
    required num fahrzeitMillis,
  }) {
    if (!streckeMeter.isFinite || streckeMeter <= 0) return null;
    final millis = fahrzeitMillis.toDouble();
    if (!millis.isFinite || millis <= 0) return null;
    final tempo = streckeMeter / (millis / 1000.0);
    if (!tempo.isFinite || tempo <= 0 || tempo > maxPlausibelMs) return null;
    return tempo;
  }

  /// Setzt alles zurueck. Bei Routenwechsel, Fahrtende und nach dem Melden.
  void zuruecksetzen() {
    _phase = StauPhase.frei;
    _sicherheit = StauSicherheit.keine;
    _letzteProbe = null;
    _steht = false;
    _stehtSeit = null;
    _pauseVerworfen = false;
    _fensterLoeschen();
  }

  /// Ein GPS-Fix hinein, eine Lagebeurteilung heraus.
  ///
  /// [tempoMetersPerSecond] ist die vom Geraet gemeldete Geschwindigkeit.
  /// Fehlt sie, wird aus Weg und Zeit gerechnet.
  /// [erwartetesTempoMetersPerSecond] kommt aus der Route (siehe
  /// [erwartetesTempoAusAbschnitt]) und ist der eigentliche Massstab.
  /// [abstandZurRouteMeter] ist der Abstand zur Routenlinie und trennt die
  /// Pause vom Stau. Ist er unbekannt, bleibt der Stillstand-Weg bewusst bei
  /// „wahrscheinlich" stehen und darf nicht gemeldet werden.
  StauBefund verarbeite({
    required double latitude,
    required double longitude,
    required DateTime zeitpunkt,
    double? tempoMetersPerSecond,
    double? erwartetesTempoMetersPerSecond,
    double? genauigkeitMeter,
    double? abstandZurRouteMeter,
  }) {
    if (!_gueltigeKoordinate(latitude, longitude)) return _befund();
    if (genauigkeitMeter != null &&
        genauigkeitMeter.isFinite &&
        genauigkeitMeter > maxGenauigkeitMeter) {
      return _befund();
    }

    final vorher = _letzteProbe;
    if (vorher == null) {
      _letzteProbe = _Probe(latitude, longitude, zeitpunkt);
      return _befund();
    }

    final dt = zeitpunkt.difference(vorher.zeitpunkt);
    // Gleiche oder aeltere Zeitstempel kommen bei Sensorwechseln vor.
    if (dt <= Duration.zero) return _befund();

    if (dt > maxLuecke) {
      // Wir wissen nicht, was in dem Loch passiert ist. Ein Stau, den wir
      // nicht mehr belegen koennen, wird beendet statt weitergeraten.
      final befund =
          _phase == StauPhase.stau ? _befundBeendet('Messlücke') : null;
      zuruecksetzen();
      _letzteProbe = _Probe(latitude, longitude, zeitpunkt);
      return befund ?? _befund();
    }

    final meter = GeoDistance.haversineMeters(
      fromLat: vorher.latitude,
      fromLng: vorher.longitude,
      toLat: latitude,
      toLng: longitude,
    );
    final sekunden = dt.inMicroseconds / Duration.microsecondsPerSecond;

    var tempo = tempoMetersPerSecond;
    if (tempo == null || !tempo.isFinite || tempo < 0) {
      tempo = meter / sekunden;
    }
    if (tempo > maxPlausibelMs) {
      // Kaputter Fix. Nicht in die Bilanz, aber auch nicht als Referenz.
      return _befund();
    }

    _letzteProbe = _Probe(latitude, longitude, zeitpunkt);

    final erwartet = (erwartetesTempoMetersPerSecond != null &&
            erwartetesTempoMetersPerSecond.isFinite &&
            erwartetesTempoMetersPerSecond > 0)
        ? erwartetesTempoMetersPerSecond
        : null;

    _stillstandsZaehlung(tempo, meter, zeitpunkt);
    _freieFahrtZaehlung(tempo, meter, erwartet, zeitpunkt);

    final imFenster = _fensterStart != null;
    if (!imFenster) {
      if (!_pauseVerworfen && _istLangsam(tempo, erwartet)) {
        _fensterStarten(latitude, longitude, zeitpunkt);
      }
      return _befund();
    }

    _fensterDauer = zeitpunkt.difference(_fensterStart!);
    _fensterStreckeMeter += meter;
    if (erwartet != null) {
      _erwartungSumme += erwartet * sekunden;
      _erwartungDauer += dt;
    }

    // Pause abseits der Route: wer lange genug neben der Fahrbahn steht,
    // steht nicht im Stau. Das ist der einzige Weg, der einen laufenden
    // Verdacht aktiv verwirft statt ihn nur auslaufen zu lassen.
    if (_steht &&
        abstandZurRouteMeter != null &&
        abstandZurRouteMeter.isFinite &&
        abstandZurRouteMeter > abseitsDerRouteMeter &&
        _stehtSeit != null &&
        zeitpunkt.difference(_stehtSeit!) >= pausePruefungAb) {
      final befund = _phase == StauPhase.stau
          ? _befundBeendet('Halt abseits der Route')
          : null;
      _phase = StauPhase.frei;
      _sicherheit = StauSicherheit.keine;
      _pauseVerworfen = true;
      _fensterLoeschen();
      return befund ?? _befund();
    }

    // Freie Fahrt beendet Verdacht bzw. Stau.
    final schnellSeit = _schnellSeit;
    if (schnellSeit != null) {
      final schnellDauer = zeitpunkt.difference(schnellSeit);
      if (_phase == StauPhase.stau) {
        if (schnellDauer >= stauEndeDauer ||
            _schnellStreckeMeter >= stauEndeStreckeMeter) {
          final befund = _befundBeendet('Wieder freie Fahrt');
          _phase = StauPhase.frei;
          _sicherheit = StauSicherheit.keine;
          _fensterLoeschen();
          return befund;
        }
      } else if (schnellDauer >= verdachtEndeDauer) {
        _phase = StauPhase.frei;
        _sicherheit = StauSicherheit.keine;
        _fensterLoeschen();
        return _befund();
      }
    }

    return _bewerten(zeitpunkt, abstandZurRouteMeter);
  }

  // ---------------------------------------------------------------------
  // Bewertung
  // ---------------------------------------------------------------------

  StauBefund _bewerten(DateTime zeitpunkt, double? abstandZurRouteMeter) {
    final sekunden = _fensterDauer.inMicroseconds / Duration.microsecondsPerSecond;
    final mittleresTempo = sekunden > 0 ? _fensterStreckeMeter / sekunden : 0.0;
    final erwartung = _mittlereErwartung();
    final verhaeltnis = erwartung != null ? mittleresTempo / erwartung : null;

    final langsam = verhaeltnis != null
        ? verhaeltnis <= relativeSchwelle
        : mittleresTempo <= absoluteSchwelleMs;

    var neu = StauSicherheit.vermutet;
    var grund = 'Verdacht läuft';

    if (langsam) {
      // Weg A: Anfahren und Stehen im dichten Wechsel. Das klassische
      // Staubild und der einzige Weg, der ohne Routenwissen melden darf,
      // weil ihn weder Ampel noch Pause erzeugen kann.
      final mittlereRollstrecke = _mittlereRollstrecke();
      if (_fensterDauer >= mindestDauer &&
          _fensterStreckeMeter >= mindestStreckeMeter &&
          _stillstaende >= mindestStillstaende &&
          mittlereRollstrecke != null &&
          mittlereRollstrecke <= maxRollstreckeMeter) {
        neu = StauSicherheit.sicher;
        grund = 'Anfahren und Stehen im Abstand von '
            '${mittlereRollstrecke.round()} m';
      } else {
        // Weg B: langer Stillstand.
        final stehtSeit = _stehtSeit;
        final stillstand = (_steht && stehtSeit != null)
            ? zeitpunkt.difference(stehtSeit)
            : Duration.zero;
        final aufDerRoute = abstandZurRouteMeter != null &&
            abstandZurRouteMeter.isFinite &&
            abstandZurRouteMeter <= abseitsDerRouteMeter;
        if (stillstand >= stillstandSicher && aufDerRoute) {
          neu = StauSicherheit.sicher;
          grund = 'Stillstand auf der Route seit '
              '${stillstand.inMinutes} Minuten';
        } else if (stillstand >= stillstandVerdacht) {
          // Ohne Routenwissen bleibt es beim Anzeigen: es koennte eine
          // Pause sein, und eine falsche Staumeldung waere teurer.
          neu = StauSicherheit.wahrscheinlich;
          grund = 'Stillstand seit ${stillstand.inMinutes} Minuten';
        } else if (_stillstaende == 0 &&
            _fensterDauer >= zaehflussDauer &&
            _fensterStreckeMeter >= zaehflussStreckeMeter) {
          // Weg C: gleichmaessig zaeh, ohne je zu stehen.
          if (verhaeltnis != null && verhaeltnis <= zaehflussSicherSchwelle) {
            neu = StauSicherheit.sicher;
            grund = 'Dauerhaft '
                '${(verhaeltnis * 100).round()} % des erwarteten Tempos';
          } else {
            neu = StauSicherheit.wahrscheinlich;
            grund = 'Deutlich langsamer als erwartet';
          }
        }
      }
    }

    final vorherPhase = _phase;
    if (vorherPhase == StauPhase.stau && neu.index < _sicherheit.index) {
      // Ein belegter Stau wird nicht durch eine Stauwelle wieder
      // kleingerechnet: nach 600 m freier Fahrt zwischen zwei Stillstaenden
      // reisst der Abstandsnachweis, obwohl der Stau weitergeht. Beendet wird
      // ein Stau ausschliesslich ueber die Endregeln weiter oben.
      neu = _sicherheit;
      grund = _letzterGrund;
    }
    _sicherheit = neu;
    _letzterGrund = grund;
    _phase = (neu == StauSicherheit.wahrscheinlich || neu == StauSicherheit.sicher)
        ? StauPhase.stau
        : StauPhase.verdacht;

    return _befund(
      begonnen: vorherPhase != StauPhase.stau && _phase == StauPhase.stau,
      grund: grund,
      mittleresTempoMs: mittleresTempo,
      erwartetesTempoMs: erwartung,
      verhaeltnis: verhaeltnis,
    );
  }

  double? _mittlereErwartung() {
    if (_erwartungDauer <= Duration.zero) return null;
    final abdeckung = _fensterDauer > Duration.zero
        ? _erwartungDauer.inMicroseconds / _fensterDauer.inMicroseconds
        : 0.0;
    if (abdeckung < mindestErwartungsAbdeckung) return null;
    final sekunden = _erwartungDauer.inMicroseconds / Duration.microsecondsPerSecond;
    if (sekunden <= 0) return null;
    return _erwartungSumme / sekunden;
  }

  double? _mittlereRollstrecke() {
    if (_rollstrecken.isEmpty) return null;
    final summe = _rollstrecken.reduce((a, b) => a + b);
    return summe / _rollstrecken.length;
  }

  bool _istLangsam(double tempo, double? erwartet) {
    if (erwartet != null) return tempo <= erwartet * relativeSchwelle;
    return tempo <= absoluteSchwelleMs;
  }

  // ---------------------------------------------------------------------
  // Buchfuehrung
  // ---------------------------------------------------------------------

  void _stillstandsZaehlung(double tempo, double meter, DateTime zeitpunkt) {
    if (_steht) {
      if (tempo >= rolltSchwelleMs) {
        _steht = false;
        _stehtSeit = null;
        _pauseVerworfen = false;
        // Der in DIESEM Takt gefahrene Weg gehoert schon zum Anfahren. Ohne
        // ihn faellt der Abstand zwischen zwei Halten um eine ganze
        // Messperiode zu kurz aus, und drei Ampeln in einer Ortsdurchfahrt
        // sehen aus wie Stop-and-go.
        _rollstreckeSeitStillstand = meter;
      }
      return;
    }
    _rollstreckeSeitStillstand += meter;
    if (tempo <= stehtSchwelleMs) {
      _steht = true;
      _stehtSeit = zeitpunkt;
      _stillstaende += 1;
      // Der Weg VOR dem ersten Stillstand ist keine Rollstrecke zwischen
      // zwei Stillstaenden, er wuerde den Abstand nur verwaessern.
      if (_stillstaende > 1) {
        _rollstrecken.add(_rollstreckeSeitStillstand);
      }
      _rollstreckeSeitStillstand = 0.0;
    }
  }

  void _freieFahrtZaehlung(
    double tempo,
    double meter,
    double? erwartet,
    DateTime zeitpunkt,
  ) {
    final schwelle = erwartet != null
        ? math.max(erwartet * freiRelativeSchwelle, stehtSchwelleMs)
        : freiAbsoluteSchwelleMs;
    if (tempo >= schwelle) {
      _schnellSeit ??= zeitpunkt;
      _schnellStreckeMeter += meter;
    } else {
      _schnellSeit = null;
      _schnellStreckeMeter = 0.0;
    }
  }

  void _fensterStarten(double latitude, double longitude, DateTime zeitpunkt) {
    _fensterStart = zeitpunkt;
    _fensterStartLat = latitude;
    _fensterStartLng = longitude;
    _fensterStreckeMeter = 0.0;
    _fensterDauer = Duration.zero;
    _erwartungSumme = 0.0;
    _erwartungDauer = Duration.zero;
    _stillstaende = _steht ? 1 : 0;
    _rollstrecken.clear();
    _rollstreckeSeitStillstand = 0.0;
    _phase = StauPhase.verdacht;
    _sicherheit = StauSicherheit.vermutet;
  }

  void _fensterLoeschen() {
    _fensterStart = null;
    _fensterStartLat = null;
    _fensterStartLng = null;
    _fensterStreckeMeter = 0.0;
    _fensterDauer = Duration.zero;
    _erwartungSumme = 0.0;
    _erwartungDauer = Duration.zero;
    _stillstaende = 0;
    _rollstrecken.clear();
    _rollstreckeSeitStillstand = 0.0;
    _schnellSeit = null;
    _schnellStreckeMeter = 0.0;
    _letzterGrund = '';
  }

  StauBefund _befund({
    bool begonnen = false,
    bool beendet = false,
    String grund = '',
    double? mittleresTempoMs,
    double? erwartetesTempoMs,
    double? verhaeltnis,
  }) {
    final letzte = _letzteProbe;
    return StauBefund(
      phase: _phase,
      sicherheit: _sicherheit,
      begonnen: begonnen,
      beendet: beendet,
      dauer: _fensterDauer,
      streckeMeter: _fensterStreckeMeter,
      stillstaende: _stillstaende,
      grund: grund,
      startLatitude: _fensterStartLat,
      startLongitude: _fensterStartLng,
      aktuellLatitude: letzte?.latitude,
      aktuellLongitude: letzte?.longitude,
      mittleresTempoMs: mittleresTempoMs,
      erwartetesTempoMs: erwartetesTempoMs,
      tempoVerhaeltnis: verhaeltnis,
    );
  }

  StauBefund _befundBeendet(String grund) {
    final letzte = _letzteProbe;
    return StauBefund(
      phase: StauPhase.frei,
      sicherheit: StauSicherheit.keine,
      begonnen: false,
      beendet: true,
      dauer: _fensterDauer,
      streckeMeter: _fensterStreckeMeter,
      stillstaende: _stillstaende,
      grund: grund,
      startLatitude: _fensterStartLat,
      startLongitude: _fensterStartLng,
      aktuellLatitude: letzte?.latitude,
      aktuellLongitude: letzte?.longitude,
    );
  }

  static bool _gueltigeKoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
  }
}

/// Wo die Erkennung gerade steht.
enum StauPhase {
  /// Nichts Auffaelliges.
  frei,

  /// Langsam, aber noch nicht belegt. Nach aussen unsichtbar.
  verdacht,

  /// Stau erkannt. Wie damit umzugehen ist, sagt [StauSicherheit].
  stau,
}

/// Wie sicher sich die Erkennung ist. Die Fahransicht entscheidet daran, ob
/// sie nur etwas anzeigt oder wirklich eine Meldung absetzt.
enum StauSicherheit {
  /// Kein Anhaltspunkt.
  keine,

  /// Verdachtsfenster laeuft. Nichts anzeigen, nichts melden.
  vermutet,

  /// Belastbar genug zum Anzeigen, nicht zum automatischen Melden.
  /// Typisch: langer Stillstand ohne Beweis, dass er auf der Fahrbahn war.
  wahrscheinlich,

  /// Belegt. Darf gemeldet werden.
  sicher,
}

/// Die Lagebeurteilung zu genau einem GPS-Fix.
class StauBefund {
  const StauBefund({
    required this.phase,
    required this.sicherheit,
    required this.begonnen,
    required this.beendet,
    required this.dauer,
    required this.streckeMeter,
    required this.stillstaende,
    required this.grund,
    this.startLatitude,
    this.startLongitude,
    this.aktuellLatitude,
    this.aktuellLongitude,
    this.mittleresTempoMs,
    this.erwartetesTempoMs,
    this.tempoVerhaeltnis,
  });

  final StauPhase phase;
  final StauSicherheit sicherheit;

  /// Flanke: genau bei diesem Fix ist aus Verdacht ein Stau geworden.
  final bool begonnen;

  /// Flanke: genau bei diesem Fix ist der Stau vorbei.
  final bool beendet;

  final Duration dauer;
  final double streckeMeter;
  final int stillstaende;

  /// Kurze deutsche Begruendung, direkt anzeigbar.
  final String grund;

  /// Wo der Stau angefangen hat, also der Punkt zum Melden.
  final double? startLatitude;
  final double? startLongitude;

  /// Wo der Fahrer jetzt ist, also das bisher bekannte Stauende
  /// (`jam_end_lat` / `jam_end_lng` in `road_incidents`).
  final double? aktuellLatitude;
  final double? aktuellLongitude;

  final double? mittleresTempoMs;
  final double? erwartetesTempoMs;
  final double? tempoVerhaeltnis;

  /// Anzeigen ja, melden nein.
  bool get darfAngezeigtWerden =>
      phase == StauPhase.stau &&
      (sicherheit == StauSicherheit.wahrscheinlich ||
          sicherheit == StauSicherheit.sicher);

  /// Nur hier darf automatisch gemeldet werden.
  bool get darfGemeldetWerden =>
      phase == StauPhase.stau && sicherheit == StauSicherheit.sicher;
}

class _Probe {
  const _Probe(this.latitude, this.longitude, this.zeitpunkt);
  final double latitude;
  final double longitude;
  final DateTime zeitpunkt;
}
