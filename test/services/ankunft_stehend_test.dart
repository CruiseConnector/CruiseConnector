import 'dart:io';

import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko): „Wenn man kurz vorm Ziel ist, beendet es die Route
/// nicht selbstaendig, auch wenn man unmittelbar 5 Meter neben dem Ziel ist.
/// Ich will einfach, wenn man ungefaehr dort ist — und nicht, wenn man nah am
/// Ziel vorbeifaehrt — dass es die Route beendet."
///
/// WAS DIE URSACHE WAR: Der Steh-Notausgang (Fahrzeug steht in Zielnaehe)
/// lockerte bisher nur den RADIUS. Die Rundkurs-Huerde „95 % der geplanten
/// Strecke gefahren" blieb bestehen — und sie haengt an einer GPS-Track-Laenge,
/// die die geplante Strassenlaenge prinzipiell nur unterschreiten kann: Bei
/// jeder GPS-Luecke wird das betroffene Stueck ganz verworfen, und gemessen
/// wird ein Sehnenzug statt der feinen Strassengeometrie. Wer bei einem
/// Rundkurs am Ziel parkte und wartete, wartete deshalb vergeblich.
///
/// WARUM NICHT DIE NAHELIEGENDE LOESUNG: Der erste Entwurf wollte statt der
/// gefahrenen Strecke die RESTSTRECKE ENTLANG DER ROUTE nehmen. Die
/// adversarische Gegenpruefung hat daran einen Ablauf gefunden, der schlimmer
/// gewesen waere als der gemeldete Fehler: Bei einem Rundkurs, der seinen
/// eigenen Startort durchquert, kann der globale Re-Snap des Map-Matchers auf
/// das Routenende springen. Reststrecke und Index-Fortschritt stammen dann
/// BEIDE aus dem Matcher und koennen sich nicht gegenseitig pruefen — die
/// Fahrt haette bei km 22 von 40 geendet, mitten auf der Strecke, mit
/// abgeschalteter Navigation.
///
/// DESHALB DIESER WEG: Die Lockerung haengt am STEHEN. Wer vorbeifaehrt, steht
/// nicht — damit ist Vuckos Unterscheidung woertlich abgebildet. Und die 80 %
/// kommen weiterhin aus dem gefahrenen Track, nicht aus dem Matcher; ein
/// fehlgesprungener Matcher kann sie nicht vortaeuschen.
void main() {
  // Die Werte, die cruise_mode_page beim Stehen bzw. Fahren einsetzt.
  const huerdeStehend = 0.80; // _roundTripFinishArmProgress
  const huerdeFahrend = 0.95; // _minProgressForAutomaticCompletion

  group('Rundkurs: am Ziel stehend', () {
    test('88 % gefahren, 5 m vom Ziel → Fahrt endet', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 5,
          drivenDistanceMeters: 88000,
          plannedDistanceMeters: 100000,
          completionRadiusMeters: 50, // Steh-Radius
          minRoundTripProgress: huerdeStehend,
        ),
        isTrue,
        reason: 'genau der gemeldete Fall',
      );
    });

    test('derselbe Fall wuerde FAHREND nicht enden', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 5,
          drivenDistanceMeters: 88000,
          plannedDistanceMeters: 100000,
          completionRadiusMeters: 15, // strenger Radius im Fahren
          minRoundTripProgress: huerdeFahrend,
        ),
        isFalse,
        reason:
            'so war es vorher, und so bleibt es fuer alle, die nicht stehen',
      );
    });
  });

  group('Vorbeifahren beendet nichts', () {
    test('mitten in der Runde am Startort vorbei → kein Abschluss', () {
      // Rundkurs 40 km, bei km 22 durch den eigenen Startort. Geometrisch am
      // Ziel, aber erst 55 % gefahren.
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 8,
          drivenDistanceMeters: 22000,
          plannedDistanceMeters: 40000,
          completionRadiusMeters: 50,
          minRoundTripProgress: huerdeStehend, // sogar die milde Huerde
        ),
        isFalse,
        reason:
            'DER wichtigste Test: Die gelockerte Huerde darf eine Fahrt nicht '
            'mitten auf der Strecke beenden. 55 % < 80 %.',
      );
    });

    test('gleich nach dem Losfahren erst recht nicht', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: true,
          distanceToFinalTargetMeters: 3,
          drivenDistanceMeters: 200,
          plannedDistanceMeters: 40000,
          completionRadiusMeters: 50,
          minRoundTripProgress: huerdeStehend,
        ),
        isFalse,
      );
    });
  });

  group('A nach B bleibt unveraendert', () {
    test('im Radius endet die Fahrt, ohne Prozentregel', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: false,
          distanceToFinalTargetMeters: 5,
          drivenDistanceMeters: 1000,
          plannedDistanceMeters: 40000,
          completionRadiusMeters: 15,
          minRoundTripProgress: huerdeStehend,
        ),
        isTrue,
      );
    });

    test('ausserhalb des Radius nicht', () {
      expect(
        shouldCompleteNavigation(
          isRoundTrip: false,
          distanceToFinalTargetMeters: 60,
          drivenDistanceMeters: 39000,
          plannedDistanceMeters: 40000,
          completionRadiusMeters: 15,
          minRoundTripProgress: huerdeStehend,
        ),
        isFalse,
      );
    });
  });

  // Die Regel lebt in cruise_mode_page, nicht in der reinen Funktion — diese
  // Wache haelt die Verdrahtung fest. Ohne sie koennte jemand die Lockerung
  // still entfernen, und alle Tests oben blieben gruen.
  group('Verdrahtung in der Fahransicht', () {
    late String quelle;
    setUpAll(() {
      quelle = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('die Prozenthuerde haengt am Stehen', () {
      expect(
        quelle.contains(
          'minRoundTripProgress: steht\n'
          '          ? _roundTripFinishArmProgress\n'
          '          : _minProgressForAutomaticCompletion,',
        ),
        isTrue,
        reason:
            'ohne diese Verzweigung gilt wieder ueberall 95 % und der '
            'gemeldete Fehler ist zurueck',
      );
    });

    test('das kurze Steh-Fenster gilt nur direkt am Ziel', () {
      expect(quelle.contains('_arrivalStandstillDurationNah'), isTrue);
      expect(
        quelle.contains(
          'final direktAmZiel = distanceToTarget <= _abschlussRadiusFuer(position);',
        ),
        isTrue,
        reason:
            'im weiten 50-m-Radius muss das laengere Fenster (15 s) gelten — '
            'sonst zaehlt eine rote Ampel kurz vor dem Ziel als Ankunft',
      );
    });

    // Die beiden Wartezeiten stehen als Konstanten in cruise_mode_page und
    // werden von ankunft_radius_test.dart nur NACHGEBAUT — eine Aenderung dort
    // bliebe sonst voellig unbemerkt. Diese Wache haelt die vereinbarten
    // Zahlen fest.
    test('die Wartezeiten sind die vereinbarten', () {
      expect(
        quelle.contains(
          '_arrivalStandstillDuration = Duration(seconds: 15)',
        ),
        isTrue,
        reason: 'vucko: „im Umkreis von 50 m 15 Sekunden"',
      );
      expect(
        quelle.contains(
          '_arrivalStandstillDurationNah = Duration(seconds: 4)',
        ),
        isTrue,
        reason:
            'vucko: „am Ziel innerhalb von 3 bis 5 Sekunden". Vier liegt '
            'bewusst ueber drei: Beim Anhalten braucht der Tempo-Wert des '
            'Empfaengers ein bis zwei Sekunden, bis er unter 1,5 m/s faellt.',
      );
    });

    test('das Stehen verlangt weiterhin echten Stillstand', () {
      expect(
        quelle.contains('tempo > _arrivalStandstillSpeedMps'),
        isTrue,
        reason: 'wer vorbeifaehrt, darf die Lockerung nie ausloesen',
      );
    });
  });
}
