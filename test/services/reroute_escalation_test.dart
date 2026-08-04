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

  /// 2026-08-04 (vucko „manchmal kommt während der Route auf einmal ein starkes
  /// Rerouting"): Die Analyse fand die wahrscheinlichste Ursache — und sie lag
  /// in genau diesem Zähler.
  ///
  /// Der Watchdog beendet nach 22 s den Zustand `_isRerouting` und zählt einen
  /// Fehlschlag. Die laufenden HTTP-Aufrufe kann er NICHT abbrechen, Dart-
  /// Futures lassen sich nicht abbrechen. Meldete dieser verwaiste Zyklus
  /// danach doch noch „keine Route", zählte derselbe Vorfall ein ZWEITES Mal.
  /// Und weil schon 3 s später ein neuer Versuch erlaubt ist, stapelten sich
  /// während EINER Funklochphase mehrere Zyklen: Der Fünferzähler war nach ein
  /// bis zwei Minuten schlechtem Empfang voll — statt nach fünf wirklich
  /// getrennten Ereignissen. Dann baut die App ungefragt den Heimweg, obwohl
  /// mit der Route gar nichts ist.
  ///
  /// Die Regel heißt jetzt: EIN Zyklus darf HÖCHSTENS EINEN Fehlschlag zählen.
  group('Ein Zyklus zählt höchstens einmal', () {
    /// Bildet die Generations-Prüfung aus `_registriereRerouteFehlschlag` ab.
    ({int streak, int zuletztGezaehlt}) melde({
      required int streakVorher,
      required int generation,
      required int zuletztGezaehlt,
    }) {
      if (generation == zuletztGezaehlt) {
        return (streak: streakVorher, zuletztGezaehlt: zuletztGezaehlt);
      }
      return (streak: streakVorher + 1, zuletztGezaehlt: generation);
    }

    test('der verwaiste Zyklus nach dem Watchdog zählt NICHT nochmal', () {
      // Watchdog zählt Generation 1 ...
      var r = melde(streakVorher: 0, generation: 1, zuletztGezaehlt: -1);
      expect(r.streak, 1);
      // ... und dreht danach weiter, damit der hängende Zyklus abgehakt ist.
      const generationNachWatchdog = 2;
      const abgehakt = 2;
      // Der hängende Aufruf meldet jetzt doch noch „keine Route":
      final r2 = melde(
        streakVorher: r.streak,
        generation: generationNachWatchdog,
        zuletztGezaehlt: abgehakt,
      );
      expect(
        r2.streak,
        1,
        reason: 'Sonst wäre EIN Funkloch schon zwei Fehlschläge wert',
      );
    });

    test('fünf getrennte Zyklen zählen weiterhin fünfmal', () {
      var streak = 0;
      var zuletzt = -1;
      for (var generation = 1; generation <= 5; generation++) {
        final r = melde(
          streakVorher: streak,
          generation: generation,
          zuletztGezaehlt: zuletzt,
        );
        streak = r.streak;
        zuletzt = r.zuletztGezaehlt;
      }
      expect(
        streak,
        5,
        reason: 'Der Schutz darf die Sicherheitsfunktion nicht lahmlegen',
      );
    });

    test('drei Meldungen aus demselben Zyklus bleiben ein Fehlschlag', () {
      var streak = 0;
      var zuletzt = -1;
      for (var i = 0; i < 3; i++) {
        final r = melde(
          streakVorher: streak,
          generation: 7,
          zuletztGezaehlt: zuletzt,
        );
        streak = r.streak;
        zuletzt = r.zuletztGezaehlt;
      }
      expect(streak, 1);
    });

    test('eine Funklochphase mit Ueberlappung erreicht die Fuenf nicht mehr', () {
      // Nachgestellt: drei echte Zyklen, jeder meldet zusaetzlich verspaetet.
      var streak = 0;
      var zuletzt = -1;
      for (var generation = 1; generation <= 3; generation++) {
        for (var wiederholung = 0; wiederholung < 2; wiederholung++) {
          final r = melde(
            streakVorher: streak,
            generation: generation,
            zuletztGezaehlt: zuletzt,
          );
          streak = r.streak;
          zuletzt = r.zuletztGezaehlt;
        }
      }
      expect(
        streak,
        3,
        reason: 'Frueher waeren daraus sechs geworden und der Heimweg haette '
            'gefeuert',
      );
      expect(streak < 5, isTrue);
    });
  });
}
