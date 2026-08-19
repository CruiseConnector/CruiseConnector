import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-19 (vucko, gemessen): „Gebucht 204, angezeigt +102."
///
/// Das Abschluss-Sheet und das XP-Popup zeigten die UNVERDOPPELTE Zahl:
/// `xpAwardedForResult` bekam `xpBreakdown.totalXp`, aufs Konto ging aber
/// `StarterAufgabenService.wendeBonusAn(xpBreakdown.totalXp)` — also das
/// Doppelte. Der Fortschrittsbalken lief ueber die volle Differenz, die Zahl
/// daneben ueber die halbe. Zwei Zahlen im selben Fenster, die sich
/// widersprechen; genau deshalb wirkte der Bonus wie ausgeschaltet.
///
/// Seit dem Umbau vom 19.08. steckt die Doppel-XP-Woche in der BASIS des
/// Multiplikators (2,0 statt 1,0). Eine nachtraegliche Verdopplung wuerde
/// doppelt zaehlen. Ab jetzt gilt: EINE Aufschluesselung, EINE Zahl, an jeder
/// Stelle dieselbe.
///
/// Bewusst ein Quelltext-Test: Die Vergabe haengt an Supabase, an einer echten
/// Fahrt-Session und an drei Abschluss-Pfaden. Ein Widget-Test muesste so viel
/// nachbauen, dass er am Ende die Nachbildung prueft statt der Buchung.
void main() {
  final datei = File('lib/presentation/pages/cruise_mode_page.dart');
  late String quelle;

  setUpAll(() {
    expect(datei.existsSync(), isTrue, reason: 'Cruise-Seite nicht gefunden');
    quelle = datei.readAsStringSync();
  });

  test('Keine nachtraegliche Verdopplung mehr in der Vergabe-Kette', () {
    expect(
      quelle.contains('StarterAufgabenService.instance.wendeBonusAn('),
      isFalse,
      reason:
          'Die Doppel-XP-Woche steckt seit dem 19.08. in der Basis des '
          'Multiplikators. Wer hier wieder verdoppelt, bucht doppelt und '
          'zeigt die halbe Zahl an (gemessen: gebucht 204, angezeigt +102).',
    );
  });

  test('Die gebuchte Zahl ist woertlich die angezeigte Zahl', () {
    final start = quelle.indexOf('Future<CruiseCompletionActionResult> _saveRouteAndSyncXp(');
    expect(start, greaterThan(-1), reason: '_saveRouteAndSyncXp umbenannt');
    final ende = quelle.indexOf('/// Welche Art Fahrt laeuft gerade?', start);
    expect(ende, greaterThan(start));
    final rumpf = quelle.substring(start, ende);

    expect(
      rumpf.contains('xpAwardedForResult = xpBreakdown.totalXp'),
      isTrue,
      reason: 'Die angezeigte Zahl muss aus der Aufschluesselung kommen.',
    );
    expect(
      rumpf.contains('xpAwarded: xpAwardedForResult'),
      isTrue,
      reason:
          'Gespeichert werden muss GENAU die Variable, die als xpEarned nach '
          'aussen geht — kein zweiter Ausdruck, der auseinanderlaufen kann.',
    );
    expect(
      rumpf.contains('xpEarned: xpAwardedForResult'),
      isTrue,
      reason: 'Das Sheet und das XP-Popup lesen dieselbe Variable.',
    );
  });

  test('Die Abschluss-Rechnung nimmt den eingefrorenen Zustand', () {
    final start = quelle.indexOf('RouteXpBreakdown _calculateCompletionXpBreakdown(');
    expect(start, greaterThan(-1), reason: 'Rechen-Helfer umbenannt');
    final ende = quelle.indexOf('}', quelle.indexOf('return', start));
    final rumpf = quelle.substring(start, ende);

    expect(
      rumpf.contains('streakDays: _abschlussStreakTage'),
      isTrue,
      reason:
          'Die Buchung nimmt _abschlussStreakTage (eingefroren). Nimmt die '
          'Anzeige stattdessen _xpStreakDays (live, nach dem Reset schon '
          'geleert), zeigt sie einen anderen Multiplikator als gebucht wird.',
    );
    expect(
      rumpf.contains('doppelXpAktiv: _abschlussDoppelXpAktiv'),
      isTrue,
      reason:
          'Laeuft die Bonuswoche zwischen Anzeige und Buchung ab, waeren es '
          'sonst zwei verschiedene Basiswerte (2,0 gegen 1,0).',
    );
  });

  test('Die Fahrt-Session bucht ueber denselben Rechen-Helfer', () {
    final start = quelle.indexOf('Future<void> _recordDriveSessionForCurrentRoute(');
    expect(start, greaterThan(-1), reason: 'Buchungsmethode umbenannt');
    final ende = quelle.indexOf('_driveSessionRecordedForCompletion = true;', start);
    expect(ende, greaterThan(start));
    final rumpf = quelle.substring(start, ende);

    expect(
      rumpf.contains('_calculateCompletionXpBreakdown('),
      isTrue,
      reason:
          'Eine zweite, eigene Rechnung an dieser Stelle ist genau der Weg, '
          'auf dem Anzeige und Buchung auseinanderlaufen.',
    );
    expect(
      rumpf.contains('GamificationService.calculateRouteXpBreakdown('),
      isFalse,
      reason: 'Direktaufruf umgeht den gemeinsamen Helfer.',
    );
  });
}
