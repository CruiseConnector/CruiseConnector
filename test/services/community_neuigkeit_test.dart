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
}
