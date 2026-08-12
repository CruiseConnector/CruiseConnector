import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko, zweimal gemeldet, er nennt es „Frust!"):
///
///   „wenn ich die app wechsle auf eine andere app, die app komplett aufeinmal
///    crashed vom app verlauf oder die route einfach geresetted wird und ich
///    nochmal auf route bestaetigen klicken muss, wie wenn man frisch eine
///    route erstellt hat und sie fahren moechte."
///
///   „Bei appwechsel stoppt route automatisch und man muss extra wieder auf
///    route anfangen oder route beginnen klicken mitten in der strecke."
///
/// WAS DIE MESSUNG AM GERAET ERGAB. `adb shell dumpsys activity exit-info
/// com.vucko.cruiserconnect` auf seinem Samsung: fuenfmal `reason=3
/// (LOW_MEMORY)` und fuenfmal „OTHER KILLS BY SYSTEM". Die App wird also nicht
/// von einem eigenen Fehler zerrissen, sondern von Android aufgeraeumt, weil
/// sie im Hintergrund zu viel Speicher haelt. Danach ist der Prozess tot.
///
/// WARUM DANN ZWEI KLICKS. Nach dem Prozesstod kam die Fahrt ueber die
/// Home-Karte als GESPEICHERTE ROUTE zurueck, also als reine Vorschau: erst
/// „Route bestaetigen", dann „Fahrt starten". Genau das beschreibt er mit „wie
/// wenn man frisch eine Route erstellt hat".
///
/// WARUM EINE ADVERSARISCHE PRUEFUNG DIE ERSTE THEORIE VERWORFEN HAT. Der
/// erste Verdacht war das Bild-im-Bild-Fenster, das auf Android den
/// Bildschirmaufbau abreisst. Das erklaert aber nur EINEN Klick (die Route
/// bliebe bestaetigt) und wirkt auf iOS gar nicht, weil die Funktion dort ein
/// No-Op ist. Zwei Klicks entstehen nur beim echten Prozesstod.
///
/// Drei Maszahmen, drei Wachen.
void main() {
  late String quelle;

  setUpAll(() {
    quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
  });

  group('1. Speicher: damit Android die App gar nicht erst abschiesst', () {
    test('im Hintergrund wird der Bildspeicher geraeumt', () {
      expect(quelle.contains('_entlasteImHintergrund()'), isTrue);
      expect(
        quelle.contains('clearLiveImages()'),
        isTrue,
        reason:
            'der Bildspeicher ist der groesste Brocken, den man gefahrlos '
            'wegwerfen kann - Feed- und Profilbilder laedt die App beim '
            'Zurueckkommen einfach neu',
      );
    });

    test('das Entlasten haengt am Pausieren', () {
      final start = quelle.indexOf('void didChangeAppLifecycleState(');
      expect(start, greaterThan(0));
      final rumpf = quelle.substring(start, start + 1400);
      expect(
        rumpf.contains('_entlasteImHintergrund()'),
        isTrue,
        reason: 'sonst wird nie geraeumt',
      );
    });

    test('Androids Speicherdruck-Warnung wird beantwortet', () {
      // Vorher gab es dafuer gar keinen Behandler: Die letzte Warnung vor dem
      // Abschuss verpuffte.
      expect(quelle.contains('void didHaveMemoryPressure()'), isTrue);
      final start = quelle.indexOf('void didHaveMemoryPressure()');
      final rumpf = quelle.substring(start, start + 400);
      expect(rumpf.contains('_entlasteImHintergrund()'), isTrue);
      expect(
        rumpf.contains('_persistActiveRideSnapshot'),
        isTrue,
        reason:
            'wenn der Abschuss kommt, soll die Fahrt wenigstens gesichert sein',
      );
    });

    test('die laufende Fahrt wird dabei NICHT angefasst', () {
      final start = quelle.indexOf('void _entlasteImHintergrund()');
      final rumpf = quelle.substring(start, start + 900);
      for (final verboten in [
        '_stopNavigationTracking',
        '_routeLatLngs = []',
        '_fullRouteCoordinates.clear',
        '_isRouteConfirmed = false',
      ]) {
        expect(
          rumpf.contains(verboten),
          isFalse,
          reason:
              'Speicher sparen darf die Fahrt nicht beenden - das waere '
              'derselbe Fehler in gruen',
        );
      }
    });
  });

  group('2. Ein zweiter Druck auf „Fahrt starten" bleibt folgenlos', () {
    test('der Wiedereintritts-Schutz steht ganz am Anfang', () {
      final start = quelle.indexOf('Future<void> _startNavigationFlow() async');
      expect(start, greaterThan(0));
      final rumpf = quelle.substring(start, start + 4200);

      final schutz = rumpf.indexOf('fahrtLaeuftBereits');
      final zugriff = rumpf.indexOf('_prepareAccessLegForOffRouteStart()');
      expect(schutz, greaterThan(0));
      expect(zugriff, greaterThan(0));
      expect(
        schutz,
        lessThan(zugriff),
        reason:
            'ohne den Schutz DAVOR berechnet ein versehentlicher zweiter Druck '
            'eine neue Anfahrtsstrecke - aus einem Anzeigefehler wird ein '
            'echter Routen-Reset, die Linie springt sichtbar um',
      );
    });

    test('der Schutz gilt fuer Einzel- UND Gruppenfahrt', () {
      final start = quelle.indexOf('Future<void> _startNavigationFlow() async');
      final rumpf = quelle.substring(start, start + 4200);
      expect(rumpf.contains('_soloRideStarted'), isTrue);
      expect(
        rumpf.contains("widget.groupId != null"),
        isTrue,
        reason:
            '_soloRideStarted wird bei Gruppenfahrten nie gesetzt - ohne den '
            'zweiten Zweig waere die Gruppe ungeschuetzt',
      );
    });

    test('die Pause laeuft nicht ueber diesen Weg', () {
      // Sonst koennte eine pausierte Fahrt nicht mehr fortgesetzt werden.
      final aufrufe = RegExp(
        r'_startNavigationFlow\(\)',
      ).allMatches(quelle).length;
      expect(
        aufrufe,
        2,
        reason:
            'erwartet: genau die Definition und der eine Aufruf vom Knopf. '
            'Mehr Aufrufer bedeuten, dass der Schutz auch einen legitimen Weg '
            'blockieren koennte.',
      );
    });
  });

  group('3. Nach dem Abschuss reicht EIN Druck statt zwei', () {
    test('eine Wiederaufnahme wird direkt bestaetigt', () {
      expect(quelle.contains('_uebernehmeAusstehendeRoute'), isTrue);
      final start = quelle.indexOf(
        'Future<void> _uebernehmeAusstehendeRoute(',
      );
      expect(start, greaterThan(0));
      final rumpf = quelle.substring(start, start + 700);
      expect(
        rumpf.contains("route.routeSource != 'resume'"),
        isTrue,
        reason:
            'nur Wiederaufnahmen - eine frisch gewaehlte gespeicherte Route '
            'soll weiterhin als Vorschau erscheinen',
      );
      expect(rumpf.contains('_confirmRoute(preserveCurrentProgress: true)'),
          isTrue);
    });

    test('die Fahrt startet NICHT von selbst', () {
      final start = quelle.indexOf(
        'Future<void> _uebernehmeAusstehendeRoute(',
      );
      final rumpf = quelle.substring(start, start + 700);
      expect(
        rumpf.contains('_startNavigationFlow()'),
        isFalse,
        reason:
            'wer die App beendet hat, wollte vielleicht aufhoeren. Ein '
            'ungefragt weiterlaufender Trip wuerde XP, Streak und '
            'Fahrtstatistik verfaelschen - der letzte Druck bleibt beim Fahrer.',
      );
    });
  });
}
