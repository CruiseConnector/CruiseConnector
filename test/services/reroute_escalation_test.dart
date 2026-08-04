import 'package:flutter_test/flutter_test.dart';

/// 2026-08-04 (vucko): „Könnte man es nicht so machen, dass es einen Zähler
/// bis fünf gibt? Wenn er wirklich gar kein Rerouting findet — nicht wenn er
/// eins findet und der Fahrer es nicht nimmt, das ist etwas anderes — dann
/// soll beim sechsten Mal die Strecke so neu berechnet werden, dass man nicht
/// mehr auf die alte kommt. Einfach als wäre das eigene Zuhause die Adresse
/// und A nach B eingeschaltet, nur automatisch."
///
/// HINTERGRUND: In den Bergen sperrte eine Baustelle die Straße. Die App sagte
/// 5 bis 7 km lang „umkehren", weil sie zurück auf die alte Route wollte —
/// was unmöglich war.
///
/// Diese Tests halten die ENTSCHEIDUNGSREGEL fest. Die Routen-Erzeugung selbst
/// braucht einen echten Server und ist im Live-Benchmark abgedeckt.
void main() {
  /// Bildet die Logik aus `_registriereRerouteFehlschlag` ab.
  ({int streak, bool eskaliert}) verarbeite({
    required int streakVorher,
    required bool neuberechnungHatRouteGeliefert,
    required bool istRundkurs,
    required bool bereitsEskaliert,
    int schwelle = 5,
  }) {
    if (neuberechnungHatRouteGeliefert) {
      // Erfolg setzt die Serie zurück — egal ob der Fahrer ihr folgt.
      return (streak: 0, eskaliert: false);
    }
    final streak = streakVorher + 1;
    final eskaliert =
        streak >= schwelle && istRundkurs && !bereitsEskaliert;
    return (streak: streak, eskaliert: eskaliert);
  }

  group('Zähler zählt nur echte Fehlschläge', () {
    test('vier Fehlschläge lösen noch nichts aus', () {
      var streak = 0;
      var eskaliert = false;
      for (var i = 0; i < 4; i++) {
        final r = verarbeite(
          streakVorher: streak,
          neuberechnungHatRouteGeliefert: false,
          istRundkurs: true,
          bereitsEskaliert: false,
        );
        streak = r.streak;
        eskaliert = eskaliert || r.eskaliert;
      }
      expect(streak, 4);
      expect(
        eskaliert,
        isFalse,
        reason: 'Erst der fünfte Fehlschlag darf die Runde aufgeben',
      );
    });

    test('der fünfte Fehlschlag löst den Heimweg aus', () {
      var streak = 0;
      var eskaliert = false;
      for (var i = 0; i < 5; i++) {
        final r = verarbeite(
          streakVorher: streak,
          neuberechnungHatRouteGeliefert: false,
          istRundkurs: true,
          bereitsEskaliert: eskaliert,
        );
        streak = r.streak;
        eskaliert = eskaliert || r.eskaliert;
      }
      expect(streak, 5);
      expect(eskaliert, isTrue);
    });

    test('eine gefundene Route setzt die Serie zurück', () {
      // Das ist vuckos ausdrückliche Unterscheidung: findet die App eine Route
      // und der Fahrer folgt ihr nur nicht, darf ihm niemand die Runde nehmen.
      var streak = 0;
      for (var i = 0; i < 4; i++) {
        streak = verarbeite(
          streakVorher: streak,
          neuberechnungHatRouteGeliefert: false,
          istRundkurs: true,
          bereitsEskaliert: false,
        ).streak;
      }
      expect(streak, 4);
      final nachErfolg = verarbeite(
        streakVorher: streak,
        neuberechnungHatRouteGeliefert: true,
        istRundkurs: true,
        bereitsEskaliert: false,
      );
      expect(nachErfolg.streak, 0);
      expect(nachErfolg.eskaliert, isFalse);
    });
  });

  group('Grenzen der Eskalation', () {
    test('A nach B eskaliert nie — dort gibt es ein echtes Ziel', () {
      var streak = 0;
      var eskaliert = false;
      for (var i = 0; i < 8; i++) {
        final r = verarbeite(
          streakVorher: streak,
          neuberechnungHatRouteGeliefert: false,
          istRundkurs: false,
          bereitsEskaliert: eskaliert,
        );
        streak = r.streak;
        eskaliert = eskaliert || r.eskaliert;
      }
      expect(eskaliert, isFalse);
    });

    test('sie feuert höchstens einmal', () {
      var streak = 5;
      final zweiterVersuch = verarbeite(
        streakVorher: streak,
        neuberechnungHatRouteGeliefert: false,
        istRundkurs: true,
        bereitsEskaliert: true,
      );
      expect(
        zweiterVersuch.eskaliert,
        isFalse,
        reason: 'Sonst würde die App die Route immer wieder neu aufbauen',
      );
    });
  });
}
