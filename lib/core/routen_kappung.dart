import 'package:cruise_connect/core/kurven_zaehler.dart';

/// Kappung je Ende, wenn ein FREMDER Nutzer die Route FAEHRT (Fehler 8:
/// „Start- und Endpunkt 1 km weiter als der urspruengliche Startpunkt").
const double fremdfahrtKappungMeter = 1000.0;

/// Kappung je Ende fuer die reine ANZEIGE einer fremden Route (Skizze im
/// Beitrag, Detailansicht ohne Karte). Kuerzer als beim Fahren, damit die
/// Form der Strecke erkennbar bleibt; die Adresse verraet auch das nicht.
const double anzeigeKappungMeter = 300.0;

/// Bleiben nach der Kappung weniger Streckenmeter als das uebrig, liefert
/// [kappeEndstuecke] eine LEERE Liste. Der Aufrufer behandelt das als
/// "nicht fahrbar fuer Fremde": Bei so kurzen Strecken IST die ganze Linie
/// die Adresse, ein Reststueck wuerde sie trotzdem verraten.
const double mindestRestMeter = 2000.0;

/// Laenge einer flachen [longitude, latitude]-Linie in Kilometern.
double linienLaengeKm(List<List<double>> punkte) {
  var meter = 0.0;
  for (var i = 1; i < punkte.length; i++) {
    meter += KurvenZaehler.distanzMeter(punkte[i - 1], punkte[i]);
  }
  return meter / 1000.0;
}

/// (2026-08-28, Teilen ohne Karte / Fehler 7 und 8):
///
/// Kappt die Endstuecke einer Routenlinie, bevor sie irgendwo fuer FREMDE
/// Nutzer gezeichnet wird. Start und Ziel einer geteilten Route liegen meist
/// in der Naehe des Zuhauses; ohne Kappung liest jeder die Adresse aus der
/// Linie ab (derselbe Vorfall wie bei den grossen Lauf-Apps, die dafuer
/// Schutzzonen einfuehrten).
///
/// Die Signatur ist zwischen den beteiligten Agenten abgestimmt:
/// `kappeEndstuecke(List<List<double>>, double, double)`. Sowohl die
/// Anzeige (Skizze im Beitrag, Detailansicht) als auch das Fahren
/// (`SavedRoute.fuerFremdfahrt`) rufen NUR diese eine Funktion.
///
/// Verhalten:
///  * [punkte] ist die flache [longitude, latitude]-Liste (Mapbox-Format),
///    z. B. aus `SavedRoute.flattenGeometryCoordinates`.
///  * Vom Anfang werden [startMeter], vom Ende [endMeter] Streckenmeter
///    entfernt; die Schnittpunkte werden linear interpoliert, damit die
///    Kappung exakt sitzt und nicht an der Punktdichte haengt.
///  * Bleiben nach der Kappung weniger als [mindestRestMeter] Streckenmeter
///    uebrig, kommt eine LEERE Liste zurueck: Bei so kurzen Strecken IST die
///    ganze Linie die Adresse, ein Reststueck wuerde sie trotzdem verraten.
///  * Beim Rundkurs (Start nahe Ende) oeffnen die beiden Kappungen die
///    Schleife genau um die Wohngegend. Das ist gewollt.
///  * Weniger als zwei Punkte ergeben ebenfalls eine leere Liste, nie eine
///    Ausnahme.
List<List<double>> kappeEndstuecke(
  List<List<double>> punkte,
  double startMeter,
  double endMeter,
) {
  if (punkte.length < 2) return const [];
  final start = startMeter < 0 ? 0.0 : startMeter;
  final ende = endMeter < 0 ? 0.0 : endMeter;

  // Kumulierte Streckenmeter je Punkt.
  final kumuliert = List<double>.filled(punkte.length, 0);
  for (var i = 1; i < punkte.length; i++) {
    kumuliert[i] =
        kumuliert[i - 1] + KurvenZaehler.distanzMeter(punkte[i - 1], punkte[i]);
  }
  final gesamt = kumuliert.last;
  if (gesamt - start - ende < mindestRestMeter) return const [];
  if (start == 0 && ende == 0) return punkte;

  final von = start;
  final bis = gesamt - ende;

  List<double> interpoliere(int segEnde, double zielMeter) {
    final a = punkte[segEnde - 1];
    final b = punkte[segEnde];
    final segLaenge = kumuliert[segEnde] - kumuliert[segEnde - 1];
    if (segLaenge <= 0) return [b[0], b[1]];
    final t = ((zielMeter - kumuliert[segEnde - 1]) / segLaenge).clamp(0.0, 1.0);
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  }

  final ergebnis = <List<double>>[];
  for (var i = 1; i < punkte.length; i++) {
    if (kumuliert[i] <= von) continue;
    if (ergebnis.isEmpty) ergebnis.add(interpoliere(i, von));
    if (kumuliert[i] >= bis) {
      ergebnis.add(interpoliere(i, bis));
      break;
    }
    ergebnis.add([punkte[i][0], punkte[i][1]]);
  }
  return ergebnis.length >= 2 ? ergebnis : const [];
}
