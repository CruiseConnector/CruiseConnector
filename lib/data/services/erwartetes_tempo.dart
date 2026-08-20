import 'package:cruise_connect/domain/models/route_result.dart';

/// 2026-08-20 (Vucko, Aufgabe 4): „Die neue Funktion mit Unfaelle melden,
/// Baustellen und auch Stau ist leider noch nicht so funktional."
///
/// [StauErkennung] misst nicht gegen eine feste km/h-Zahl, sondern gegen das
/// ERWARTETE Tempo des Abschnitts. Diese Datei liefert diese Erwartung aus dem
/// einzigen Abschnittswissen, das die App heute schon in der Hand hat: den
/// Tempolimits aus `RouteResult.speedLimits`.
///
/// WARUM NICHT EINFACH DAS TEMPOLIMIT NEHMEN. Das Limit ist eine Obergrenze,
/// kein Erwartungswert. Auf einer kurvigen Landstrasse mit Limit 100 faehrt
/// hier niemand 100, und genau diese Strassen sind der Kern der App. Wer das
/// Limit als Erwartung nimmt, erklaert gemuetliches Kurvenfahren zum Stau.
/// Zwei Sicherungen dagegen:
///
///  1. UNTERHALB VON 80 km/h GIBT ES GAR KEINE ERWARTUNG. In Ortsgebieten,
///     Tempo-30-Zonen und auf engen Nebenstrassen ist die Streuung zwischen
///     Limit und tatsaechlichem Tempo am groessten, und dort ist das Limit als
///     Massstab wertlos. [StauErkennung] faellt dann auf ihre absolute
///     Schwelle von 15 km/h zurueck — konservativ, aber nie falsch.
///  2. OBERHALB DAVON MIT ABSCHLAG. Autobahn und Schnellstrasse sind darauf
///     ausgelegt, mit dem Limit gefahren zu werden; realistisch bleiben davon
///     durch Verkehr, Auffahrten und Baustellen etwa 85 Prozent uebrig. Das
///     ist auch das Verhaeltnis, mit dem GraphHopper seine Fahrzeiten fuer das
///     car-Profil rechnet.
///
/// Rein und ohne Zustand, damit jeder Fall im Test nachrechenbar ist.

/// Ab diesem Limit ist das Tempolimit ein brauchbarer Massstab.
const int mindestTempolimitFuerErwartungKmh = 80;

/// Realitaetsabschlag auf das Limit. Siehe Punkt 2 oben.
const double tempolimitRealitaetsFaktor = 0.85;

/// Das Tempolimit an einem Routenpunkt, oder null wenn kein Abschnitt passt.
/// Die Abschnitte kommen aus der Routenberechnung und ueberlappen sich nicht;
/// gesucht wird der erste, der den Index einschliesst.
int? tempolimitAnRoutenIndex(
  List<SpeedLimitSegment> abschnitte,
  int routenIndex,
) {
  if (routenIndex < 0) return null;
  for (final abschnitt in abschnitte) {
    if (routenIndex >= abschnitt.startIndex && routenIndex <= abschnitt.endIndex) {
      final limit = abschnitt.speedKmh;
      // 0 oder Unsinn kommt aus unvollstaendigen OSM-Daten vor.
      if (limit <= 0 || limit > 300) return null;
      return limit;
    }
  }
  return null;
}

/// Erwartetes freies Tempo in m/s, oder null wenn kein belastbarer Massstab
/// vorliegt. null heisst ausdruecklich „keine Erwartung" und ist ein gueltiges
/// Ergebnis, kein Fehler.
double? erwartetesTempoMsAusTempolimit(int? tempolimitKmh) {
  final limit = tempolimitKmh;
  if (limit == null) return null;
  if (limit < mindestTempolimitFuerErwartungKmh) return null;
  if (limit > 300) return null;
  return limit * tempolimitRealitaetsFaktor / 3.6;
}

/// Bequemer Zusammenzug der beiden Schritte fuer die Fahransicht.
double? erwartetesTempoMsAnRoutenIndex(
  List<SpeedLimitSegment> abschnitte,
  int routenIndex,
) {
  return erwartetesTempoMsAusTempolimit(
    tempolimitAnRoutenIndex(abschnitte, routenIndex),
  );
}
