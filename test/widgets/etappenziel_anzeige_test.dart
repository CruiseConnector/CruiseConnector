import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko, Aufgabe 8): „Die Fortschrittsanzeige sieht noch etwas
/// unuebersichtlich aus. Je nachdem, wie viele Kilometer noch fehlen, sagen wir
/// 120 km bis zur 2000-km-Marke, oder wie viele Gruppenfahrten noch fehlen,
/// sollte genau das als naechstes Etappenziel angezeigt werden."
/// Praezisierung: „ist fuer das Onboarding gemeint und zukuenftige Challenges,
/// wo das gleiche Format haben werden."
///
/// Vorher stand in einer Zeile „noch 1493 km" UND „1007.5 von 2500 km": zwei
/// Sichten auf dieselbe Sache, eine Nachkommastelle, die niemanden
/// interessiert, und keine Nennung der Marke.
void main() {
  app.BadgeFortschritt f(double a, double z, String e) =>
      app.BadgeFortschritt(aktuell: a, ziel: z, einheit: e, anleitung: 'x');

  group('Zahlen sind im Vorbeigehen lesbar', () {
    test('Tausenderpunkt ab vier Stellen', () {
      expect(app.zahlMitTausenderpunkt(2500), '2.500');
      expect(app.zahlMitTausenderpunkt(1007.5), '1.008');
      expect(app.zahlMitTausenderpunkt(10000), '10.000');
      expect(app.zahlMitTausenderpunkt(999), '999');
    });

    test('Nachkommastelle nur, wo sie etwas aussagt', () {
      // Unter zehn: „2,5 von 5 Std" ist sinnvoll.
      expect(app.zahlMitTausenderpunkt(2.5), '2,5');
      // Darueber gerundet: „1007.5 km" interessiert niemanden.
      expect(app.zahlMitTausenderpunkt(42.7), '43');
    });

    test('deutsches Komma, kein Punkt', () {
      expect(app.zahlMitTausenderpunkt(2.5).contains(','), isTrue);
      expect(app.zahlMitTausenderpunkt(2.5).contains('.'), isFalse);
    });
  });

  group('Das naechste Etappenziel wird benannt', () {
    test('Kilometer', () {
      expect(badgeEtappenziel(f(1007.5, 2500, 'km')), 'Ziel 2.500 km');
    });

    test('Fahrten, mit richtiger Einzahl', () {
      expect(badgeEtappenziel(f(9, 1, 'Fahrten')), 'Ziel 1 Fahrt');
    });

    test('der Restweg nennt die fehlende Menge', () {
      expect(badgeRestweg(f(1007.5, 2500, 'km')), 'noch 1.493 km');
      expect(badgeRestweg(f(880, 1000, 'km')), 'noch 120 km');
    });

    test('erreicht heisst noch 0, nie negativ', () {
      expect(badgeRestweg(f(2600, 2500, 'km')), 'noch 0 km');
    });
  });

  test('die Fortschrittszeile hat keine Doppelung mehr', () {
    // Rechts steht die fehlende Menge, unten das Ziel. Nie beides dasselbe.
    final fort = f(1007.5, 2500, 'km');
    expect(badgeRestweg(fort), 'noch 1.493 km');
    expect(badgeEtappenziel(fort), 'Ziel 2.500 km');
    expect(badgeRestweg(fort) == badgeEtappenziel(fort), isFalse);
  });

  test('keine Striche in den Nutzertexten', () {
    final texte = [
      badgeRestweg(f(1007.5, 2500, 'km')),
      badgeEtappenziel(f(1007.5, 2500, 'km')),
      f(1007.5, 2500, 'km').zahlen,
    ];
    for (final t in texte) {
      expect(t.contains('-'), isFalse, reason: 'Strich in "$t"');
      expect(t.contains('—'), isFalse, reason: 'Gedankenstrich in "$t"');
    }
  });
}
