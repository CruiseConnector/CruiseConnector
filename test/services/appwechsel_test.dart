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
      // 2026-08-16 (Testfahrt T1/T2): Definition, der Aufruf vom Knopf und
      // der automatische Weiterstart nach einer Wiederaufnahme
      // (_uebernehmeAusstehendeRoute, hinter _darfAutomatischWeiterfahren).
      expect(
        aufrufe,
        3,
        reason:
            'erwartet: Definition, Knopf, Auto-Weiterfahrt nach Wiederaufnahme. '
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
      final rumpf = quelle.substring(start, start + 3200);
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

    test('die Fahrt startet von selbst — aber nur nahe an der Route', () {
      // 2026-08-16 (Testfahrt T1/T2, vucko): „Route soll beim Zurueckwechseln
      // automatisch fortgesetzt werden, ohne manuellen Klick." Der Tipp auf
      // „Fahrt fortsetzen" ist die Absicht; der Waechter verlangt ≤ 500 m
      // Abstand zur Route, sonst bleibt die Vorschau mit „Fahrt starten".
      final start = quelle.indexOf(
        'Future<void> _uebernehmeAusstehendeRoute(',
      );
      final rumpf = quelle.substring(start, start + 4500);
      expect(
        rumpf.contains('if (_darfAutomatischWeiterfahren(route)) {'),
        isTrue,
      );
      expect(
        rumpf.contains('await _startNavigationFlow();'),
        isTrue,
        reason:
            'Vucko (Testfahrt 15.08.): kein zweiter Klick nach dem '
            'Fortsetzen — die Fahrt laeuft an der Position weiter.',
      );
    });
  });

  group('4. Die Wache haengt am App-Kern, nicht an einer Seite', () {
    late String wache;
    late String main;

    setUpAll(() {
      wache = File(
        'lib/data/services/app_speicher_wache.dart',
      ).readAsStringSync();
      main = File('lib/main.dart').readAsStringSync();
    });

    // DER FUND, DER EINE ANNAHME WIDERLEGT HAT. Der erste Anlauf haengte die
    // Entlastung an didChangeAppLifecycleState der FAHRANSICHT. Die Messung
    // danach zeigte: nichts passierte, der Verbrauch stieg im Hintergrund
    // sogar von 319 auf 365 MB. Der Grund steht in home_page.dart — der
    // Cruise-Tab wird BEWUSST erst beim ersten Besuch gebaut (die
    // MapLibre-Ansicht darf nicht unsichtbar entstehen, sonst stuerzt sie
    // nativ ab). Wer auf der Startseite ist, hat die Fahransicht gar nicht im
    // Baum, und der Behandler lief nie.
    test('sie wird beim App-Start angemeldet', () {
      expect(main.contains('AppSpeicherWache.instance.starten()'), isTrue);
    });

    test('sie haengt am Binding, nicht an einem Widget', () {
      expect(wache.contains('with WidgetsBindingObserver'), isTrue);
      expect(
        wache.contains('WidgetsBinding.instance.addObserver(this)'),
        isTrue,
      );
    });

    test('Androids Speicherdruck wird beantwortet', () {
      expect(wache.contains('void didHaveMemoryPressure()'), isTrue);
    });

    test('der Bildspeicher ist gedeckelt', () {
      // Flutter erlaubt sonst 100 MB. Bei einer App, die nachweislich wegen
      // Speichermangel abgeschossen wird, ist das zu grosszuegig.
      expect(wache.contains('maximumSizeBytes'), isTrue);
      expect(wache.contains('48 * 1024 * 1024'), isTrue);
    });
  });

  group('5. Die Karte wird im Hintergrund still gelegt', () {
    test('aber NIEMALS waehrend einer Fahrt', () {
      final start = quelle.indexOf('void didChangeAppLifecycleState(');
      final rumpf = quelle.substring(start, start + 2200);
      expect(
        rumpf.contains('if (!_isRouteConfirmed && !_recordingActive)'),
        isTrue,
        reason:
            'waehrend Fahrt oder Aufzeichnung haengen Kamera, Puck und Linie '
            'an der aktiven Karte',
      );
    });

    test('und beim Zurueckkommen wieder aktiviert', () {
      expect(
        quelle.contains('_mlController?.active = mounted && !_disposed;'),
        isTrue,
        reason: 'ohne Gegenstueck bliebe die Karte tot',
      );
    });
  });
}
