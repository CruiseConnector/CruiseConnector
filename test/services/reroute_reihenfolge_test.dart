import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (vucko, 1.2a): „Erst zurueck auf die Route, bei Fehlschlag
/// mehrfach wiederholen, erst dann direkt zum Ziel."
///
/// GEMESSENE LUECKE: In `_runRerouteCycle` stand der ZIEL-Zweig (Position ->
/// Endziel, mode Standard, routeVariant 0) VOR der Rejoin-Leiter. Damit war
/// der erste Netz-Versuch nach jedem Verfahren die Abkuerzung ans Ziel — genau
/// das gemeldete „springt direkt auf den Endpunkt". Der Rejoin, der die
/// RESTLICHE Originalroute anhaengt, kam nur zum Zug, wenn der Ziel-Zweig
/// scheiterte.
///
/// Neue Reihenfolge:
///   1. Vorab-Zweig: Ziel-Zweig NUR fuer Trips mit noch offenen Stopps
///      (sonst ginge das bewusste Ueberspringen verpasster Stopps verloren).
///   2. Rejoin-Leiter (mehrere Andockpunkte, monoton vorwaerts).
///   3. Garantierter Re-Dock.
///   4. Ziel-Zweig als LETZTER Netz-Versuch.
///   5. Lokaler Re-Anker ohne Netz.
///
/// Dieser Waechter ist ein Quelltext-Test: die Reihenfolge in einer 700 Zeilen
/// langen async-Methode laesst sich ohne echten Routing-Server nicht anders
/// festnageln. Er ist ohne den Umbau rot, weil `zielZweigVersuchen` dann gar
/// nicht existiert und der Ziel-Zweig vor der Schleife stand.
void main() {
  late String quelle;

  setUpAll(() {
    quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
  });

  test('die Rejoin-Leiter steht VOR dem Ziel-Zweig', () {
    final leiter = quelle.indexOf('while (rejoinLohntSich &&');
    final redock = quelle.indexOf(
      'if (rerouteResult == null && rejoinLohntSich && mounted && !_disposed) {',
    );
    final zielZuletzt = quelle.indexOf(
      'if (rerouteResult == null && zielZweigMoeglich && mounted && !_disposed) {',
    );
    expect(leiter, greaterThan(0), reason: 'Rejoin-Leiter nicht gefunden');
    expect(redock, greaterThan(0), reason: 'garantierter Re-Dock nicht gefunden');
    expect(zielZuletzt, greaterThan(0), reason: 'Ziel-Zweig nicht gefunden');

    expect(
      leiter,
      lessThan(redock),
      reason: 'erst die Leiter, dann der Re-Dock',
    );
    expect(
      redock,
      lessThan(zielZuletzt),
      reason:
          'der Ziel-Zweig darf erst nach allen Rueckweg-Versuchen kommen, '
          'sonst kuerzt der Reroute wieder ans Ziel ab',
    );
  });

  test('der Ziel-Zweig steht vor dem lokalen Re-Anker', () {
    final zielZuletzt = quelle.indexOf(
      'if (rerouteResult == null && zielZweigMoeglich && mounted && !_disposed) {',
    );
    final reAnker = quelle.indexOf(
      "cycleFailures.add('no_candidate');",
    );
    expect(reAnker, greaterThan(0));
    expect(zielZuletzt, greaterThan(0), reason: 'Ziel-Zweig nicht gefunden');
    expect(
      zielZuletzt,
      lessThan(reAnker),
      reason:
          'der Ziel-Zweig ist der letzte NETZ-Versuch, der lokale Re-Anker '
          'kommt danach',
    );
  });

  test('es gibt genau eine Abbruchbedingung fuer den Rueckweg', () {
    // Der Ziel-Zweig wurde am 09.06. bewusst nach vorn gezogen: wer weit weg
    // ist, will nicht mehr zurueck. Die Umkehr braucht deshalb eine
    // begruendete Schwelle, sonst kostet sie Zeit.
    expect(quelle.contains('final rejoinLohntSich ='), isTrue);
    expect(
      quelle.contains('_rejoinMaxAbweichungMeters'),
      isTrue,
      reason: 'ohne Schwelle wird auch aus 20 km Entfernung zurueckgeschickt',
    );
    expect(
      quelle.contains('abstandZumAndockpunkt < abstandZumZiel'),
      isTrue,
      reason: 'der Rueckweg darf nie weiter sein als das Ziel selbst',
    );
    // Rundkurs / Zufahrts-Abschnitt / aktiver Umweg haben keinen Ersatz —
    // fuer sie muss der Rueckweg IMMER versucht werden.
    expect(quelle.contains('!zielZweigMoeglich ||'), isTrue);
  });

  test('der Re-Dock haengt an derselben Abbruchbedingung', () {
    expect(
      quelle.contains(
        'if (rerouteResult == null && rejoinLohntSich && mounted && !_disposed) {',
      ),
      isTrue,
      reason:
          'auch der Re-Dock ist ein Rueckweg AUF die Route und darf nicht '
          'laufen, wenn der Fahrer laengst weg ist',
    );
  });
}
