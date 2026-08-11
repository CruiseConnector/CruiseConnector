import 'package:cruise_connect/data/services/community_neuigkeit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-11 (vucko): Hinweispunkt am Community-Symbol.
///
/// Der Punkt darf nicht nerven. Diese Tests halten die Regeln fest:
/// beim ersten Mal locken, nach dem Besuch verstummen, nicht bei jedem
/// App-Start blinken, und im Zweifel lieber schweigen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dienst = CommunityNeuigkeitService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.zuruecksetzenFuerTest();
  });

  test('beim ersten Mal leuchtet er — genau dann soll man entdecken', () async {
    await dienst.melde(gruppen: 3, vorschlaege: 5);
    expect(dienst.hatNeues.value, isTrue);
  });

  test('ohne jeden Inhalt leuchtet er nicht', () async {
    await dienst.melde(gruppen: 0, vorschlaege: 0);
    expect(
      dienst.hatNeues.value,
      isFalse,
      reason: 'ein Punkt, hinter dem nichts steckt, ist eine Luege',
    );
  });

  test('nach dem Besuch ist er aus und bleibt aus', () async {
    await dienst.melde(gruppen: 3, vorschlaege: 5);
    await dienst.alsGesehenMarkieren();
    expect(dienst.hatNeues.value, isFalse);

    // Gleiche Zahlen beim naechsten Laden: nichts Neues.
    await dienst.melde(gruppen: 3, vorschlaege: 5);
    expect(
      dienst.hatNeues.value,
      isFalse,
      reason: 'sonst wuerde er bei jedem App-Start blinken',
    );
  });

  test('weniger als zuvor loest nichts aus', () async {
    await dienst.melde(gruppen: 5, vorschlaege: 5);
    await dienst.alsGesehenMarkieren();

    await dienst.melde(gruppen: 2, vorschlaege: 1);
    expect(dienst.hatNeues.value, isFalse);
  });

  test('mehr Gruppen laesst ihn wieder leuchten', () async {
    await dienst.melde(gruppen: 3, vorschlaege: 5);
    await dienst.alsGesehenMarkieren();

    await dienst.melde(gruppen: 4, vorschlaege: 5);
    expect(dienst.hatNeues.value, isTrue);
  });

  test('mehr Vorschlaege laesst ihn wieder leuchten', () async {
    await dienst.melde(gruppen: 3, vorschlaege: 5);
    await dienst.alsGesehenMarkieren();

    await dienst.melde(gruppen: 3, vorschlaege: 9);
    expect(dienst.hatNeues.value, isTrue);
  });

  test('der gesehene Stand ueberlebt einen Neustart', () async {
    await dienst.melde(gruppen: 4, vorschlaege: 6);
    await dienst.alsGesehenMarkieren();

    // App neu gestartet: der Dienst hat nichts mehr im Kopf, die Einstellung
    // aber sehr wohl.
    dienst.zuruecksetzenFuerTest();
    await dienst.melde(gruppen: 4, vorschlaege: 6);
    expect(dienst.hatNeues.value, isFalse);
  });

  // ── Fund der adversarischen Gegenpruefung (2026-08-11) ───────────────────
  //
  // Auf dem Startbildschirm liegen ZWEI unabhaengige Kacheln. Jede laedt nur
  // ihre eigene Haelfte, meldete aber beide Zahlen — fuer die fremde beim
  // Kaltstart eine 0. Wer zuletzt fertig wurde, ueberschrieb den korrekten
  // Wert des anderen. Weil die Vorschlaege-Abfrage die langsamere ist, kam sie
  // typischerweise zuletzt und knipste den Punkt fuer neue Gruppen aus.
  //
  // Genau das ist Vuckos „die Highlights sehe ich leider nicht".
  group('Zwei Kacheln loeschen sich nicht gegenseitig aus', () {
    test('eine spaetere Teilmeldung nimmt den Punkt nicht zurueck', () async {
      SharedPreferences.setMockInitialValues({
        'community_gesehen_gruppen_v1': 8,
        'community_gesehen_vorschlaege_v1': 5,
      });
      dienst.zuruecksetzenFuerTest();

      // Die Gruppen-Kachel ist zuerst fertig: 10 > 8 → es gibt Neues.
      await dienst.melde(gruppen: 10);
      expect(dienst.hatNeues.value, isTrue);

      // Danach die langsamere Vorschlaege-Kachel: nichts Neues bei IHR.
      await dienst.melde(vorschlaege: 5);
      expect(
        dienst.hatNeues.value,
        isTrue,
        reason:
            'die zweite Kachel weiss nichts ueber Gruppen und darf den Punkt '
            'nicht ausknipsen',
      );
    });

    test('umgekehrte Reihenfolge, gleiches Ergebnis', () async {
      SharedPreferences.setMockInitialValues({
        'community_gesehen_gruppen_v1': 8,
        'community_gesehen_vorschlaege_v1': 5,
      });
      dienst.zuruecksetzenFuerTest();

      await dienst.melde(vorschlaege: 9);
      expect(dienst.hatNeues.value, isTrue);
      await dienst.melde(gruppen: 8);
      expect(dienst.hatNeues.value, isTrue);
    });

    test('ohne Neues bleibt er aus, egal in welcher Reihenfolge', () async {
      SharedPreferences.setMockInitialValues({
        'community_gesehen_gruppen_v1': 8,
        'community_gesehen_vorschlaege_v1': 5,
      });
      dienst.zuruecksetzenFuerTest();

      await dienst.melde(gruppen: 8);
      await dienst.melde(vorschlaege: 5);
      expect(dienst.hatNeues.value, isFalse);
    });

    test('ein frueher Community-Tipp schreibt keine 0 als gesehen fest',
        () async {
      SharedPreferences.setMockInitialValues({});
      dienst.zuruecksetzenFuerTest();

      // Nutzer tippt sofort auf Community, waehrend die Kacheln noch laden.
      await dienst.alsGesehenMarkieren();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('community_gesehen_gruppen_v1'),
        isNull,
        reason:
            'eine festgeschriebene 0 liesse den Punkt danach bei jedem '
            'einzelnen Vorschlag wieder leuchten',
      );
      expect(prefs.getInt('community_gesehen_vorschlaege_v1'), isNull);
    });
  });
}
