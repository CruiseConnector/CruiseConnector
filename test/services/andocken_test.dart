import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-14 (vucko, P3): „Startet man von einer anderen Position aus eine
/// vorher aufgenommene Route, verhalten sich die Andock-Punkte komisch. Die
/// Route muss ORIGINAL bleiben, und man darf NIEMALS Abkuerzungen bekommen,
/// auch nicht bei aufgenommenen Routen."
///
/// DAS REGELWERK, in einem Satz erklaerbar: Der Zubringer bringt dich zum
/// Einstieg — ab dem Einstieg faehrst du IMMER 100 Prozent der Originalroute.
///
///  * GESCHLOSSENE Runde (Endpunkte naeher als 80 m, aus der GEOMETRIE
///    bestimmt, nicht aus dem gespeicherten Flag — aufgezeichnete Tracks
///    tragen es unzuverlaessig): Einstieg am naechsten Punkt, danach die
///    VOLLE Runde rotiert. Einstieg bei km 12 heisst km 12 bis Ende plus
///    km 0 bis 12. Keine Abkuerzung, jeder Meter wird gefahren.
///
///  * OFFENE Route: Einstieg IMMER am Original-Start. Jeder Mittel-Einstieg
///    einer offenen Route WAERE die Abkuerzung — es gibt keinen sinnvollen
///    Weg, den uebersprungenen Anfang spaeter nachzuholen.
///
/// Das „komische" Verhalten hatte zwei Wurzeln: Vorschau und Fahrtstart
/// benutzten VERSCHIEDENE Regelwerke (Vorschau: naechster Vorwaertspunkt mit
/// nur 8 % Rest-Minimum — bis zu 92 % der Route konnten uebersprungen werden;
/// Fahrtstart: 6-30-%-Fortschritts-Scan), und beide durften offene geladene
/// Routen mitten drin anschneiden.
///
/// Frische Suchen bleiben unveraendert: Dort ist das Vorwaerts-Andocken
/// richtig, weil die Route von der eigenen Position aus gebaut wurde —
/// uebersprungen werden nur Meter, die man seit der Suche schon gefahren ist.
void main() {
  late String cruise;

  setUpAll(() {
    cruise = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
  });

  test('Geschlossenheit kommt aus der Geometrie, nicht aus dem Flag', () {
    expect(cruise.contains('bool _istGeometrischGeschlossen('), isTrue);
    expect(
      cruise.contains('_loopSchlussMeter = 80.0'),
      isTrue,
      reason: 'robust gegen GPS-Rauschen am Ende aufgezeichneter Tracks',
    );
  });

  test('Vorschau: geladene Routen werden nie gekuerzt', () {
    expect(cruise.contains('bool nieKuerzen = false'), isTrue);
    expect(
      cruise.contains(
        'preferredJoinIndex:\n'
        '            nieKuerzen && !_istGeometrischGeschlossen(result) ? 0 : null,',
      ),
      isTrue,
      reason: 'offene geladene Route dockt am Original-Start an',
    );
    expect(
      cruise.contains('joinNearestForward: nieKuerzen ? false : !isRoundTrip'),
      isTrue,
      reason:
          'das Vorwaerts-Andocken (8 %-Rest-Minimum) bleibt frischen Suchen '
          'vorbehalten',
    );
  });

  test('_loadSavedRoute aktiviert die Regel', () {
    expect(
      cruise.contains('nieKuerzen: true'),
      isTrue,
      reason: 'gespeicherte, gepostete und aufgezeichnete Routen laufen hier',
    );
  });

  test('Fahrtstart dockt nach denselben Regeln an wie die Vorschau', () {
    // Zwei verschiedene Regelwerke fuer denselben Vorgang waren das
    // gemeldete „komische" Verhalten.
    expect(cruise.contains('final geladen = _isExistingRouteSession;'), isTrue);
    expect(
      cruise.contains(
        'preferredJoinIndex: geladen && !geschlossen ? 0 : null,',
      ),
      isTrue,
    );
    expect(
      cruise.contains('returnToSessionOrigin: geschlossen,'),
      isTrue,
      reason: 'geschlossene Runde: volle Rotation, Ende am Original-Start',
    );
  });

  test('frische Suchen sind unveraendert', () {
    // Der 06-27-Kommentar und sein Verhalten bleiben fuer den Nicht-
    // geladen-Fall bestehen.
    expect(
      cruise.contains('!isRoundTrip'),
      isTrue,
    );
    expect(
      cruise.contains(': _isRoundTrip;'),
      isTrue,
      reason: 'ohne geladene Session gilt weiter das Flag der frischen Suche',
    );
  });
}
