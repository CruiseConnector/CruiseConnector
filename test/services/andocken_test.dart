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
///  * OFFENE Route: Einstieg am naechsten Vorwaertspunkt.
///
///    2026-08-31 (Vucko: „man nicht extra zu einem Startpunkt fahren muss,
///    was halt wesentlich angenehmer waere"): Bis heute war hier der
///    Original-Start erzwungen, damit niemand abkuerzt. In der Praxis hiess
///    das: Wer eine geteilte Strecke fahren wollte, wurde erst kilometerweit
///    zum Startpunkt des Erstellers gefuehrt, oft vor dessen Haustuer. Der
///    Zwang faellt deshalb fuer SOLO-Fahrten.
///
///    Die Abkuerzung ist damit nicht zurueck: Kilometer und XP richten sich
///    nach der GEFAHRENEN Strecke, und als abgeschlossen gilt eine Route
///    weiterhin nur bei echter Ankunft. In der GRUPPE bleibt der Zwang
///    bestehen (andockRegelFuerGeteilteRoute), damit alle dieselbe Strecke
///    fahren.
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

  test('Vorschau: geschlossene Runden werden nie gekuerzt', () {
    expect(cruise.contains('bool nieKuerzen = false'), isTrue);
    expect(
      cruise.contains('preferredJoinIndex: null,'),
      isTrue,
      reason:
          'seit 31.08. kein Zwang mehr zum Original-Start — der Fahrer '
          'steigt dort ein, wo er steht',
    );
    expect(
      cruise.contains(
        'joinNearestForward: nieKuerzen\n'
        '            ? !_istGeometrischGeschlossen(result)\n'
        '            : !isRoundTrip,',
      ),
      isTrue,
      reason:
          'offene geladene Route dockt vorwaerts an, die GESCHLOSSENE Runde '
          'behaelt ihre Rotation (jeder Meter wird gefahren)',
    );
    expect(
      cruise.contains('rebaseClosedLoop: nieKuerzen'),
      isTrue,
      reason:
          'die Rotation geschlossener Runden haengt weiter an der Geometrie',
    );
  });

  test('_loadSavedRoute aktiviert die Regel — ausser bei einer Wiederaufnahme', () {
    // 2026-08-16 (Testfahrt T1/T2): Eine WIEDERAUFNAHME ist keine Abkuerzung —
    // der Anfang ist gefahren, die Reststrecke wird vorwaerts angeschlossen.
    // Fuer gespeicherte, gepostete und aufgezeichnete Routen gilt die Regel
    // unveraendert (routeSource != 'resume').
    expect(
      cruise.contains("nieKuerzen: route.routeSource != 'resume'"),
      isTrue,
      reason: 'gespeicherte, gepostete und aufgezeichnete Routen laufen hier',
    );
  });

  test('Fahrtstart dockt nach denselben Regeln an wie die Vorschau', () {
    // Zwei verschiedene Regelwerke fuer denselben Vorgang waren das
    // gemeldete „komische" Verhalten.
    // 2026-08-16 (Testfahrt T2): Eine WIEDERAUFNAHME ist keine geladene
    // Route im P3-Sinn — sie schliesst vorwaerts an (siehe
    // fahrt_weiter_nach_appwechsel_test). Fuer alle anderen geladenen Routen
    // gilt die Regel unveraendert.
    expect(
      cruise.contains('final geladen = _isExistingRouteSession && !_istWiederaufnahme;'),
      isTrue,
    );
    expect(
      cruise.contains(
        'joinNearestForward: _istWiederaufnahme || (geladen && !geschlossen),',
      ),
      isTrue,
      reason:
          'Fahrtstart dockt bei offenen geladenen Routen vorwaerts an — '
          'genau wie die Vorschau. Zwei verschiedene Regelwerke fuer '
          'denselben Vorgang waren das gemeldete komische Verhalten.',
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
