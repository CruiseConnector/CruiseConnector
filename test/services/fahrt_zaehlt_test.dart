import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-29 (Vucko: „schau, dass du vielleicht eine Regelung machst, dass
/// man nicht so weit fahren muss").
///
/// Bis heute entschied allein ein ANTEIL, ob eine Fahrt verbucht wird:
/// 20 Prozent der geplanten Route. Das bestraft lange Routen. Wer 100 km
/// plante und 15 km fuhr, verlor alles — Kilometer, XP und den Eintrag in
/// „Meine Fahrten". Bei 200 km waren 40 km noetig.
///
/// Jetzt gilt zusaetzlich eine absolute Untergrenze, mit ODER verknuepft.
/// Die Huerde wird dadurch nie hoeher, nur bei langen Routen niedriger.
void main() {
  const grenze = GamificationService.mindestKmFuerVerbuchung;
  const anteil = GamificationService.minRouteProgressForXp;

  bool zaehlt(double gefahren, double geplant) =>
      GamificationService.fahrtZaehlt(
        gefahreneKm: gefahren,
        fortschrittAnteil: geplant > 0 ? gefahren / geplant : 0,
      );

  group('Der Grund fuer die Aenderung', () {
    test('lange Route, kurze Fahrt: zaehlt jetzt', () {
      // Der Fall aus dem Auftrag: 100 km geplant, 15 km gefahren.
      // Anteil 15 Prozent, also unter den 20 — frueher fiel die Fahrt
      // komplett durch.
      expect(15 / 100, lessThan(anteil));
      expect(zaehlt(15, 100), isTrue,
          reason: '15 gefahrene Kilometer sind eine echte Fahrt.');
    });

    test('sehr lange Route: 40 km waren noetig, jetzt reichen 3', () {
      expect(zaehlt(4, 200), isTrue);
      expect(4 / 200, lessThan(anteil));
    });
  });

  group('Die Huerde wird nie hoeher', () {
    test('kurze Route: der Anteil reicht weiterhin', () {
      // 10-km-Route, 2 km gefahren: genau 20 Prozent. Unter der absoluten
      // Grenze von 3 km, muss aber weiterhin zaehlen.
      expect(zaehlt(2, 10), isTrue,
          reason: 'sonst waere die Regel fuer kurze Routen strenger geworden');
    });

    test('genau an der Anteilsgrenze', () {
      expect(zaehlt(anteil * 25, 25), isTrue);
    });
  });

  group('Was weiterhin nicht zaehlt', () {
    test('der versehentlich gestartete Cruise', () {
      // 300 m auf einer 50-km-Route: weder Anteil noch Strecke.
      expect(zaehlt(0.3, 50), isFalse);
    });

    test('gar nicht gefahren', () {
      expect(zaehlt(0, 50), isFalse);
      expect(zaehlt(0, 0), isFalse);
    });

    test('knapp unter beiden Schwellen', () {
      // 2,9 km auf einer 50-km-Route: 5,8 Prozent, und unter 3 km.
      expect(zaehlt(grenze - 0.1, 50), isFalse);
      // Ein Meter mehr als die Grenze reicht.
      expect(zaehlt(grenze, 50), isTrue);
    });
  });

  group('Ohne geplante Route', () {
    test('beim Aufzeichnen entscheidet allein die Strecke', () {
      // Aufgezeichnete Fahrten haben keine geplante Route; der Anteil ist
      // dort 0 beziehungsweise bedeutungslos.
      expect(
        GamificationService.fahrtZaehlt(
          gefahreneKm: 5,
          fortschrittAnteil: 0,
        ),
        isTrue,
      );
      expect(
        GamificationService.fahrtZaehlt(
          gefahreneKm: 0.5,
          fortschrittAnteil: 0,
        ),
        isFalse,
      );
    });
  });

  group('Quelltext-Waechter', () {
    final quelle = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();

    test('Anzeige und Verbuchung fragen dieselbe Stelle', () {
      // Das ist der eigentliche Wert der gemeinsamen Funktion: Wenn das
      // Abschluss-Blatt XP verspricht, muss die Verbuchung sie auch geben.
      final treffer = RegExp(
        r'GamificationService\.fahrtZaehlt\(',
      ).allMatches(quelle).length;
      expect(
        treffer,
        greaterThanOrEqualTo(4),
        reason:
            'Alle vier Entscheidungsstellen (Vorschau, Speichern, Verbuchen, '
            'Hinweis) muessen ueber dieselbe Regel laufen.',
      );
    });

    test('die alte Einzelschwelle ist verschwunden', () {
      expect(
        quelle.contains('_minProgressForXpCredit'),
        isFalse,
        reason:
            'Zwei Wahrheiten ueber dieselbe Frage sind der Weg zurueck zum '
            'Widerspruch zwischen Anzeige und Verbuchung.',
      );
    });
  });
}
