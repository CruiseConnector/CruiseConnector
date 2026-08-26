import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 2026-08-26 (vucko, Entscheidung zu Aufgabe 2 der Sprachnachrichten):
///
/// „Nur beim Rundkurs umfahren. Beim A nach B Modus oder Trip Modus soll auch
/// bei der Meldung oben kommen: X Baustellen auf dem Weg, Umleitung nehmen
/// oder mit den Baustellen? Und wie lange der Umweg um die Baustellen kosten
/// wuerde an Zeit oder Zeit erspart normalerweise."
///
/// Der Unterschied ist bewusst: Beim Rundkurs faehrst du zum Vergnuegen, ohne
/// Ziel und ohne Zeitplan — dort wird still umfahren, eine Frage waere nur
/// laestig. Bei A nach B und im Trip willst du ankommen, und dann gehoert die
/// Entscheidung dir. Dafuer brauchst du eine Zahl, sonst ist es geraten.
///
/// Das Blatt schliesst sich NICHT von selbst. Es ist eine echte Entscheidung
/// vor der Abfahrt, kein Hinweis waehrend der Fahrt.
class UmleitungEntscheidung {
  const UmleitungEntscheidung._();

  /// Ergebnis: true = Umleitung nehmen, false = durch die Baustellen fahren.
  /// null = weggetippt, dann bleibt es bei der urspruenglichen Strecke.
  static Future<bool?> zeigen(
    BuildContext context, {
    required int anzahlMeldungen,
    required Duration dauerDirekt,
    required Duration dauerUmleitung,
    required double distanzDirektMeter,
    required double distanzUmleitungMeter,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _Blatt(
        anzahlMeldungen: anzahlMeldungen,
        dauerDirekt: dauerDirekt,
        dauerUmleitung: dauerUmleitung,
        distanzDirektMeter: distanzDirektMeter,
        distanzUmleitungMeter: distanzUmleitungMeter,
      ),
    );
  }

  /// „3 Minuten laenger", „2 Minuten schneller", „gleich lang".
  ///
  /// Oeffentlich, weil ein Test die Formulierung festhaelt. Ohne Striche, wie
  /// ueberall in Nutzertexten.
  static String zeitUnterschiedText(Duration direkt, Duration umleitung) {
    final differenzSekunden = umleitung.inSeconds - direkt.inSeconds;
    final betrag = differenzSekunden.abs();
    if (betrag < 45) return 'ungefähr gleich lang';
    final minuten = (betrag / 60).round().clamp(1, 999);
    final einheit = minuten == 1 ? 'Minute' : 'Minuten';
    return differenzSekunden > 0
        ? '$minuten $einheit länger'
        : '$minuten $einheit schneller';
  }

  /// „1,2 km mehr", „400 Meter weniger", „gleich weit".
  static String wegUnterschiedText(double direktMeter, double umleitungMeter) {
    final differenz = umleitungMeter - direktMeter;
    final betrag = differenz.abs();
    if (betrag < 100) return 'gleich weit';
    final wert = betrag < 1000
        ? '${(betrag / 10).round() * 10} Meter'
        : '${(betrag / 100).round() / 10} km';
    return differenz > 0 ? '$wert mehr' : '$wert weniger';
  }
}

class _Blatt extends StatelessWidget {
  const _Blatt({
    required this.anzahlMeldungen,
    required this.dauerDirekt,
    required this.dauerUmleitung,
    required this.distanzDirektMeter,
    required this.distanzUmleitungMeter,
  });

  final int anzahlMeldungen;
  final Duration dauerDirekt;
  final Duration dauerUmleitung;
  final double distanzDirektMeter;
  final double distanzUmleitungMeter;

  static const Color _bgDark = Color(0xFF11141B);
  static const Color _baustellenOrange = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    final zeit = UmleitungEntscheidung.zeitUnterschiedText(
      dauerDirekt,
      dauerUmleitung,
    );
    final weg = UmleitungEntscheidung.wegUnterschiedText(
      distanzDirektMeter,
      distanzUmleitungMeter,
    );
    final ueberschrift = anzahlMeldungen == 1
        ? 'Eine Baustelle auf dem Weg'
        : '$anzahlMeldungen Baustellen auf dem Weg';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _bgDark,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _baustellenOrange.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _baustellenOrange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.construction_rounded,
                        color: _baustellenOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        ueberschrift,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Die Zahl, die die Entscheidung ueberhaupt erst moeglich macht.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.alt_route_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Umleitung ist $zeit',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'und $weg',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _baustellenOrange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Umleitung nehmen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(false);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Durchfahren',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
