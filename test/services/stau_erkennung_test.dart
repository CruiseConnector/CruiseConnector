import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/stau_erkennung.dart';

/// 2026-08-20 (vucko, Aufgabe 4): „halt irgendwie automatisch erfasst".
///
/// Diese Tests spielen typische Verlaeufe als GPS-Folge nach. Der wichtigste
/// Teil sind NICHT die Staufaelle, sondern die falschen Ausloeser: Ampel,
/// Ortsdurchfahrt, Kurvenstrasse, Tankstellenpause. Ohne die Schwellen aus
/// [StauErkennung] wuerde jeder dieser Faelle als Stau durchgehen.
void main() {
  group('freie Fahrt und normale Langsamfahrt', () {
    test('Autobahn mit Richtgeschwindigkeit loest nie aus', () {
      final f = _Fahrt(erwartetMs: 36.1);
      f.fahre(tempoMs: 36.1, dauer: const Duration(minutes: 10));

      expect(f.letzter.phase, StauPhase.frei);
      expect(f.letzter.sicherheit, StauSicherheit.keine);
      expect(f.sahBeginn, isFalse);
    });

    test('kurvige Landstrasse mit einer langsamen Kehre loest nie aus', () {
      // Erwartung 60 km/h, gefahren 45 km/h, in der Kehre 20 km/h.
      final f = _Fahrt(erwartetMs: 16.7);
      f.fahre(tempoMs: 12.5, dauer: const Duration(minutes: 3));
      f.fahre(tempoMs: 5.6, dauer: const Duration(seconds: 30));
      f.fahre(tempoMs: 12.5, dauer: const Duration(minutes: 3));

      expect(f.sahBeginn, isFalse);
      expect(f.letzter.phase, StauPhase.frei);
    });

    test('gleichmaessige Ortsdurchfahrt mit 36 km/h loest nie aus', () {
      // Erwartung 50 km/h. 36 km/h sind 72 % davon, also normal.
      final f = _Fahrt(erwartetMs: 13.9);
      f.fahre(tempoMs: 10.0, dauer: const Duration(minutes: 6));

      expect(f.sahBeginn, isFalse);
      expect(f.letzter.phase, StauPhase.frei);
    });

    test('gemuetliche 20 km/h ohne Erwartungswert loesen nicht aus', () {
      // Ohne Routenwissen greift die absolute Schwelle von 15 km/h.
      final f = _Fahrt(erwartetMs: null);
      f.fahre(tempoMs: 5.6, dauer: const Duration(minutes: 8));

      expect(f.sahBeginn, isFalse);
      expect(f.letzter.phase, StauPhase.frei);
    });
  });

  group('Halte, die kein Stau sind', () {
    test('eine rote Ampel mit 75 s Rotphase loest nicht aus', () {
      final f = _Fahrt(erwartetMs: 13.9);
      f.fahre(tempoMs: 11.1, dauer: const Duration(minutes: 1));
      f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 75));
      f.fahre(tempoMs: 11.1, dauer: const Duration(minutes: 1));

      expect(f.sahBeginn, isFalse);
      expect(f.letzter.phase, StauPhase.frei);
      expect(f.hoechsteSicherheit, StauSicherheit.vermutet);
    });

    test('drei dichte Ampeln in der Ortsdurchfahrt loesen nicht aus', () {
      // Der Fall, der ohne das Abstandskriterium durchginge: drei
      // Stillstaende, ueber zwei Minuten, klar unter dem erwarteten Tempo.
      // Getrennt wird er allein dadurch, dass zwischen den Halten 166 m
      // liegen und nicht die 120 m eines Staus.
      final f = _Fahrt(erwartetMs: 13.9);
      f.fahre(tempoMs: 11.1, dauer: const Duration(seconds: 30));
      for (var i = 0; i < 3; i++) {
        f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 45));
        f.fahre(tempoMs: 11.1, dauer: const Duration(seconds: 15));
      }

      expect(f.sahBeginn, isFalse);
      expect(f.letzter.darfAngezeigtWerden, isFalse);
    });

    test('Pause an der Tankstelle wird durch den Routenabstand verworfen', () {
      final f = _Fahrt(erwartetMs: 22.2);
      f.fahre(tempoMs: 22.2, dauer: const Duration(minutes: 1), abstand: 4.0);
      // 45 m neben der Routenlinie: das ist der Vorplatz, nicht die Fahrbahn.
      f.fahre(tempoMs: 0.0, dauer: const Duration(minutes: 12), abstand: 45.0);

      expect(f.sahBeginn, isFalse);
      expect(f.jeAngezeigt, isFalse);
      expect(f.letzter.phase, StauPhase.frei);
    });

    test('gleiche Pause ohne Routenwissen darf angezeigt, nie gemeldet werden',
        () {
      final f = _Fahrt(erwartetMs: 22.2);
      f.fahre(tempoMs: 22.2, dauer: const Duration(minutes: 1));
      f.fahre(tempoMs: 0.0, dauer: const Duration(minutes: 12));

      expect(f.jeGemeldet, isFalse);
      expect(f.hoechsteSicherheit, StauSicherheit.wahrscheinlich);
      expect(f.letzter.darfAngezeigtWerden, isTrue);
    });
  });

  group('echter Stau', () {
    test('Stop-and-go mit dichten Halten wird sicher erkannt', () {
      final f = _stopAndGo();

      expect(f.sahBeginn, isTrue);
      expect(f.letzter.sicherheit, StauSicherheit.sicher);
      expect(f.letzter.darfGemeldetWerden, isTrue);
      expect(f.letzter.grund, contains('Anfahren und Stehen'));
      expect(f.letzter.startLatitude, isNotNull);
      expect(f.letzter.stillstaende, greaterThanOrEqualTo(3));
    });

    test('Stop-and-go wird auch ohne Erwartungswert erkannt', () {
      final f = _stopAndGo(erwartetMs: null);

      expect(f.letzter.darfGemeldetWerden, isTrue);
    });

    test('langer Stillstand auf der Route: erst anzeigen, dann melden', () {
      final f = _Fahrt(erwartetMs: 22.2);
      f.fahre(tempoMs: 22.2, dauer: const Duration(minutes: 1), abstand: 3.0);

      f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 200), abstand: 3.0);
      expect(f.letzter.sicherheit, StauSicherheit.wahrscheinlich,
          reason: 'drei Minuten Stillstand reichen zum Anzeigen');
      expect(f.letzter.darfGemeldetWerden, isFalse);

      f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 450), abstand: 3.0);
      expect(f.letzter.sicherheit, StauSicherheit.sicher,
          reason: 'zehn Minuten auf der Fahrbahnachse sind keine Ampel');
      expect(f.letzter.grund, contains('Stillstand auf der Route'));
    });

    test('gleichmaessiger Zaehfluss auf der Autobahn wird erkannt', () {
      // 130 km/h erwartet, gefahren 18 km/h ohne je zu stehen.
      final f = _Fahrt(erwartetMs: 36.1);
      f.fahre(tempoMs: 5.0, dauer: const Duration(minutes: 4));

      expect(f.letzter.darfGemeldetWerden, isTrue);
      expect(f.letzter.tempoVerhaeltnis, lessThan(0.3));
    });
  });

  group('Ende des Staus', () {
    test('eine Minute freie Fahrt beendet den Stau', () {
      final f = _stopAndGo();
      f.fahre(tempoMs: 22.2, dauer: const Duration(seconds: 70));

      expect(f.sahEnde, isTrue);
      expect(f.letzter.phase, StauPhase.frei);
      expect(f.letzter.sicherheit, StauSicherheit.keine);
    });

    test('eine Stauwelle von 30 s beendet den Stau nicht', () {
      final f = _stopAndGo();
      f.fahre(tempoMs: 20.0, dauer: const Duration(seconds: 30));
      f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 60));

      expect(f.sahEnde, isFalse);
      expect(f.letzter.phase, StauPhase.stau);
    });

    test('eine Messluecke beendet den Stau, statt ihn weiterzuraten', () {
      final f = _stopAndGo();
      f.sprung(const Duration(seconds: 90), tempoMs: 0.0);

      expect(f.sahEnde, isTrue);
      expect(f.letzter.grund, contains('Messlücke'));
      expect(f.letzter.phase, StauPhase.frei);
    });

    test('eine Messluecke verwirft auch einen laufenden Verdacht', () {
      final f = _Fahrt(erwartetMs: 13.9);
      f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 100));
      expect(f.letzter.phase, StauPhase.verdacht);

      f.sprung(const Duration(seconds: 120), tempoMs: 0.0);
      expect(f.letzter.phase, StauPhase.frei);
      expect(f.letzter.dauer, Duration.zero);
    });
  });

  group('Randfaelle', () {
    test('schlechte GPS-Fixes werden ignoriert', () {
      final f = _Fahrt(erwartetMs: 22.2);
      f.fahre(
        tempoMs: 0.0,
        dauer: const Duration(minutes: 5),
        genauigkeit: 120.0,
      );

      expect(f.letzter.phase, StauPhase.frei);
    });

    test('erwartetes Tempo wird aus Strecke und Fahrzeit gerechnet', () {
      expect(
        StauErkennung.erwartetesTempoAusAbschnitt(
          streckeMeter: 1000,
          fahrzeitMillis: 60000,
        ),
        closeTo(16.67, 0.01),
      );
      expect(
        StauErkennung.erwartetesTempoAusAbschnitt(
          streckeMeter: 0,
          fahrzeitMillis: 60000,
        ),
        isNull,
      );
      expect(
        StauErkennung.erwartetesTempoAusAbschnitt(
          streckeMeter: 1000,
          fahrzeitMillis: 0,
        ),
        isNull,
      );
    });

    test('zuruecksetzen loescht den erkannten Stau', () {
      final f = _stopAndGo();
      expect(f.letzter.phase, StauPhase.stau);

      f.erkennung.zuruecksetzen();
      expect(f.erkennung.phase, StauPhase.frei);
      expect(f.erkennung.sicherheit, StauSicherheit.keine);
    });
  });
}

/// Vier Runden Anfahren und Stehen: 60 s stehen, dann 100 m kriechen.
_Fahrt _stopAndGo({double? erwartetMs = 22.2}) {
  final f = _Fahrt(erwartetMs: erwartetMs);
  for (var i = 0; i < 4; i++) {
    f.fahre(tempoMs: 0.0, dauer: const Duration(seconds: 60), abstand: 5.0);
    f.fahre(tempoMs: 5.0, dauer: const Duration(seconds: 20), abstand: 5.0);
  }
  return f;
}

/// Kleiner Fahrsimulator: schiebt die Position entlang eines Meridians und
/// fuettert [StauErkennung] im 5-Sekunden-Takt, so wie es die Fahransicht tut.
class _Fahrt {
  _Fahrt({required this.erwartetMs});

  final double? erwartetMs;
  final StauErkennung erkennung = StauErkennung();
  final List<StauBefund> befunde = [];

  DateTime _zeit = DateTime.utc(2026, 8, 20, 10);
  double _lat = 47.5;
  final double _lng = 9.74;

  static const double _meterProGrad = 111320.0;
  static const Duration _takt = Duration(seconds: 5);

  StauBefund get letzter => befunde.last;

  bool get sahBeginn => befunde.any((b) => b.begonnen);
  bool get sahEnde => befunde.any((b) => b.beendet);
  bool get jeGemeldet => befunde.any((b) => b.darfGemeldetWerden);
  bool get jeAngezeigt => befunde.any((b) => b.darfAngezeigtWerden);

  StauSicherheit get hoechsteSicherheit {
    var hoechste = StauSicherheit.keine;
    for (final b in befunde) {
      if (b.sicherheit.index > hoechste.index) hoechste = b.sicherheit;
    }
    return hoechste;
  }

  void fahre({
    required double tempoMs,
    required Duration dauer,
    double? abstand,
    double? genauigkeit,
  }) {
    final schritte = dauer.inMilliseconds ~/ _takt.inMilliseconds;
    for (var i = 0; i < schritte; i++) {
      _zeit = _zeit.add(_takt);
      _lat += (tempoMs * _takt.inSeconds) / _meterProGrad;
      _melde(abstand: abstand, genauigkeit: genauigkeit, tempoMs: tempoMs);
    }
  }

  /// Ein einzelner Fix nach einer Messluecke.
  void sprung(Duration luecke, {required double tempoMs}) {
    _zeit = _zeit.add(luecke);
    _lat += (tempoMs * luecke.inSeconds) / _meterProGrad;
    _melde(tempoMs: tempoMs);
  }

  void _melde({
    required double tempoMs,
    double? abstand,
    double? genauigkeit,
  }) {
    befunde.add(
      erkennung.verarbeite(
        latitude: _lat,
        longitude: _lng,
        zeitpunkt: _zeit,
        tempoMetersPerSecond: tempoMs,
        erwartetesTempoMetersPerSecond: erwartetMs,
        genauigkeitMeter: genauigkeit,
        abstandZurRouteMeter: abstand,
      ),
    );
  }
}
