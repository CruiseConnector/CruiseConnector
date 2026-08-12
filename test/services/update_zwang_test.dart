import 'dart:io';

import 'package:cruise_connect/data/services/app_version_gate_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-12 (vucko): „wenn die app eine alte version hat, man benachrichtigt
/// wird und die app neuinstallieren MUSS um reinzukommen."
///
/// Für dieses Tor gab es bis heute KEINEN Test — der einzige Schutz war ein
/// Textfund auf „ForceUpdateGate(" in main.dart. Der merkt nur, wenn das Tor
/// ganz aus dem Baum fällt, nicht wenn der Versionsvergleich falsch rechnet
/// oder das Tor bei einem Netzfehler fälschlich sperrt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppVersionGateService.resetForTests);
  tearDown(AppVersionGateService.resetForTests);

  // Der Dienst fragt Platform.isAndroid/isIOS ab; im Test läuft er auf macOS
  // und kehrt deshalb früh mit „erlaubt" zurück. Die Rechenlogik lässt sich so
  // nicht durchspielen — dafür stehen unten die Quell-Wachen. Was hier
  // wirklich prüfbar ist, ist die Robustheit der Build-Nummer und dass der
  // Zustand nach außen sichtbar wird.
  test('der Zustand ist zu Beginn „erlaubt"', () {
    expect(AppVersionGateService.zustand.value.blockiert, isFalse);
  });

  test('eine Prüfung setzt den Zustand', () async {
    final r = await AppVersionGateService.pruefe();
    expect(AppVersionGateService.zustand.value.blockiert, r.blockiert);
  });

  group('Regeln, die in der Quelle stehen müssen', () {
    late String dienst;
    late String tor;
    late String seite;
    late String main;

    setUpAll(() {
      dienst = File(
        'lib/data/services/app_version_gate_service.dart',
      ).readAsStringSync();
      tor = File(
        'lib/presentation/widgets/force_update_gate.dart',
      ).readAsStringSync();
      seite = File(
        'lib/presentation/pages/update_required_page.dart',
      ).readAsStringSync();
      main = File('lib/main.dart').readAsStringSync();
    });

    // Die wichtigste Regel des ganzen Tors.
    //
    // Als `home` war die Sperre eine Route IM Navigator — und alles, was per
    // push/pushAndRemoveUntil dazukommt (Gruppen-Deeplink, Ruecksprung nach
    // der Anmeldung), legt sich UEBER eine Route. Die Sperre war umgehbar.
    test('das Tor liegt im builder, nicht in home', () {
      final builderPos = main.indexOf('builder: (context, child)');
      final torPos = main.indexOf('ForceUpdateGate(');
      final homePos = main.indexOf('home: const');
      expect(builderPos, greaterThan(0));
      expect(torPos, greaterThan(builderPos));
      expect(
        torPos,
        lessThan(homePos),
        reason:
            'liegt das Tor wieder in home, legt sich jeder push darueber und '
            'die Sperre ist umgehbar',
      );
      expect(
        main.contains('home: const ForceUpdateGate'),
        isFalse,
        reason: 'genau die alte, umgehbare Anordnung',
      );
    });

    test('die App bleibt unter dem Deckel im Baum', () {
      // Sonst waere der Navigator nicht gemountet und
      // rootNavigatorKey.currentState null — Gruppen- und Beitrags-Deeplinks
      // wuerden fuer Leute mit AKTUELLER Version still verschluckt.
      final start = tor.indexOf('Widget build(');
      final rumpf = tor.substring(start);
      final childPos = rumpf.indexOf('widget.child');
      final blockPos = rumpf.indexOf('UpdateRequiredPage(');
      expect(childPos, greaterThan(0));
      expect(
        childPos,
        lessThan(blockPos),
        reason: 'die App muss UNTER der Sperrseite liegen, nicht ersetzt sein',
      );
      expect(rumpf.contains('Stack('), isTrue);
    });

    test('fail-open bleibt: kein zwischengespeicherter Schwellwert', () {
      // Geprueft und bewusst verworfen: Ein Zahlendreher (995 statt 95) wuerde
      // sich sonst auf jedem Geraet festsetzen, das danach offline startet —
      // die Korrektur am Server erreicht genau diese Geraete nie mehr.
      expect(
        dienst.contains('lasse rein'),
        isTrue,
        reason: 'der Fehlerfall muss durchlassen',
      );
      for (final verboten in [
        'gate_min_build',
        'gecachteSchwelle',
        'cachedMinBuild',
      ]) {
        expect(
          dienst.contains(verboten),
          isFalse,
          reason:
              'ein lokal gemerkter Schwellwert kann Leute mit AKTUELLER '
              'Version dauerhaft aussperren',
        );
      }
    });

    test('eine unlesbare Build-Nummer sperrt niemanden', () {
      // Vorher: int.tryParse(...) ?? 0 — „95.1" oder „95 (release)" haette
      // JEDEN gesperrt.
      expect(dienst.contains(r"RegExp(r'\d+')"), isTrue);
      expect(
        dienst.contains('unlesbar → lasse rein'),
        isTrue,
        reason: 'ein Formatwechsel darf nicht die ganze Nutzerschaft sperren',
      );
    });

    test('waehrend der Fahrt wird nicht gesperrt', () {
      expect(
        tor.contains('CruiseModePage.isFullscreen.value'),
        isTrue,
        reason:
            'jemandem mitten auf der Autobahn die Navigation gegen eine '
            'Update-Wand zu tauschen waere der schlimmere Fehler',
      );
    });

    test('die Neupruefung ist gedrosselt', () {
      expect(tor.contains('erneutFruehestensNach'), isTrue);
      expect(
        tor.contains('letzteErfolgreichePruefung'),
        isTrue,
        reason: 'sonst eine DB-Abfrage bei jedem Vordergrundwechsel',
      );
    });

    test('der Zurueck-Knopf kommt nicht an der Sperre vorbei', () {
      expect(
        seite.contains('BackButtonListener'),
        isTrue,
        reason:
            'PopScope wirkt nur innerhalb des Navigators — der Deckel liegt '
            'darueber und wuerde den System-Zurueck nie sehen',
      );
    });

    test('der Store-Rueckfall passt zur Plattform', () {
      // Vorher hart der Play Store — auf einem iPhone der falsche Laden.
      expect(seite.contains('Platform.isIOS'), isTrue);
      expect(seite.contains('apps.apple.com'), isTrue);
      expect(seite.contains('play.google.com'), isTrue);
    });

    test('die Seite sagt, welche Version fehlt, und laesst neu pruefen', () {
      expect(seite.contains('installierterBuild'), isTrue);
      expect(seite.contains('benoetigterBuild'), isTrue);
      expect(seite.contains('Ich habe aktualisiert'), isTrue);
    });

    test('Fehler erscheinen inline, nicht per ScaffoldMessenger', () {
      // Ueber dem Navigator ist kein Messenger garantiert erreichbar — ein
      // Aufruf dort wuerde werfen statt zu melden.
      // Auf die VERWENDUNG pruefen, nicht auf das Wort — der Kommentar in der
      // Datei erklaert ja gerade, warum es hier nicht benutzt wird.
      expect(seite.contains('ScaffoldMessenger.of('), isFalse);
    });
  });
}
