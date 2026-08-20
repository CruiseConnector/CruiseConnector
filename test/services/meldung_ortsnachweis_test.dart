import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/road_incident_service.dart';
import 'package:cruise_connect/domain/models/road_incident.dart';

/// 2026-08-20, Vucko: „Ich habe es gemeldet, und dann bin ich spaeter wieder
/// diese Strasse gefahren, wo eine Baustelle ist, und mir wurde nichts
/// angezeigt von meiner vorherigen Meldung."
///
/// GEMESSEN: Es war kein Synchronisationsfehler. Alle sechs Meldungen standen
/// in der Datenbank, sie waren nur abgelaufen. Drei davon lebten genau 15
/// Minuten, weil der Ortsnachweis nie zustande kam.
///
/// Diese Datei prueft die zwei Stellen, an denen das behoben wurde und die
/// ohne Datenbank pruefbar sind.
void main() {
  group('Ortsnachweis blockiert das Melden nicht', () {
    test('ein haengender Server kostet hoechstens den Deckel', () async {
      // Ohne Deckel haette dieser Aufruf nie zurueckgegeben und der Fahrer
      // haette nie melden koennen. Genau deshalb steht er drin.
      final uhr = Stopwatch()..start();
      final ok = await ortsnachweisMitDeckel(
        () => Future<void>.delayed(const Duration(seconds: 30)),
        const Duration(milliseconds: 120),
      );
      uhr.stop();

      expect(ok, isFalse, reason: 'ohne Nachweis wird trotzdem gemeldet');
      expect(uhr.elapsedMilliseconds, lessThan(2000),
          reason: 'der Deckel muss greifen, nicht die 30 Sekunden');
    });

    test('ein Fehler wird geschluckt, nicht weitergeworfen', () async {
      // Eine Ausnahme hier duerfte niemals das Melden abbrechen.
      final ok = await ortsnachweisMitDeckel(
        () => Future<void>.error(StateError('kein Netz')),
        const Duration(seconds: 2),
      );
      expect(ok, isFalse);
    });

    test('der Normalfall meldet den Nachweis als angekommen', () async {
      final ok = await ortsnachweisMitDeckel(
        () async {},
        const Duration(seconds: 2),
      );
      expect(ok, isTrue);
    });
  });

  group('abgelaufene Meldungen verschwinden auch waehrend der Fahrt', () {
    test('was abgelaufen ist, faellt raus', () {
      final jetzt = DateTime.utc(2026, 8, 20, 15, 0);
      final liste = [
        _meldung('lebt', expiresAt: jetzt.add(const Duration(days: 13))),
        _meldung('abgelaufen', expiresAt: jetzt.subtract(const Duration(minutes: 1))),
        _meldung('stillgelegt',
            expiresAt: jetzt.add(const Duration(hours: 2)), active: false),
      ];

      final gueltig = nurGueltigeMeldungen(liste, jetzt: jetzt);
      expect(gueltig.map((i) => i.id), ['lebt']);
    });

    test('eine Fahrt ueber den Ablaufzeitpunkt hinweg raeumt auf', () {
      // Vuckos Fall in klein: Fahrtbeginn 13:30, die Meldung laeuft um 14:00
      // ab, die Fahrt geht bis 16:00. Vorher blieb sie zweieinhalb Stunden zu
      // lang auf der Karte, weil die geladene Liste nie erneut geprueft wurde.
      final ablauf = DateTime.utc(2026, 8, 20, 14, 0);
      final liste = [_meldung('baustelle', expiresAt: ablauf)];

      expect(
        nurGueltigeMeldungen(liste, jetzt: DateTime.utc(2026, 8, 20, 13, 30)),
        hasLength(1),
      );
      expect(
        nurGueltigeMeldungen(liste, jetzt: DateTime.utc(2026, 8, 20, 16, 0)),
        isEmpty,
      );
    });

    test('eine leere Liste bleibt leer und wirft nicht', () {
      expect(nurGueltigeMeldungen(const <RoadIncident>[]), isEmpty);
    });
  });
}

RoadIncident _meldung(
  String id, {
  required DateTime expiresAt,
  bool active = true,
}) {
  return RoadIncident(
    id: id,
    type: RoadIncidentType.baustelle,
    latitude: 47.5,
    longitude: 9.75,
    createdAt: expiresAt.subtract(const Duration(days: 14)),
    expiresAt: expiresAt,
    confirmedCount: 1,
    dismissedCount: 0,
    active: active,
  );
}
