import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ergebnis der Startzeit-Auswahl.
///
/// `null` als Rueckgabe des Sheets heisst „abgebrochen, nichts aendern".
/// Ein [StartZeitWahl] mit `zeitpunkt == null` heisst dagegen ausdruecklich
/// „ohne feste Zeit" — das ist ein Unterschied, den ein einzelnes `DateTime?`
/// nicht ausdruecken koennte.
class StartZeitWahl {
  const StartZeitWahl(this.zeitpunkt);
  const StartZeitWahl.spontan() : zeitpunkt = null;

  final DateTime? zeitpunkt;
}

/// Ein einziges Blatt fuer Tag und Uhrzeit.
///
/// 2026-08-11 (vucko): „vorallem moechte ich, dass die Datum-/Uhrzeit-
/// einstellung wesentlich aesthetischer aussieht und nicht so verklemmt."
///
/// Vorher waren es ZWEI System-Dialoge nacheinander (showDatePicker, dann
/// showTimePicker) — erst ein Kalenderblatt, dann eine Zifferblatt-Uhr, beide
/// im Material-Standard. Jetzt: ein Blatt im App-Design, in dem man den Tag
/// antippt und die Uhrzeit dreht. Die haeufigen Faelle („heute Abend",
/// „morgen frueh", „Samstag") sind ein einziger Tipp.
Future<StartZeitWahl?> zeigeStartZeitSheet(
  BuildContext context, {
  DateTime? aktuell,
}) {
  return showModalBottomSheet<StartZeitWahl>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _StartZeitSheet(aktuell: aktuell),
  );
}

class _StartZeitSheet extends StatefulWidget {
  const _StartZeitSheet({this.aktuell});

  final DateTime? aktuell;

  @override
  State<_StartZeitSheet> createState() => _StartZeitSheetState();
}

class _StartZeitSheetState extends State<_StartZeitSheet> {
  static const _wochentage = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  late DateTime _tag;
  late TimeOfDay _uhrzeit;

  /// Zwingt das Uhrzeit-Rad zum Neuaufbau, wenn die Zeit von AUSSEN gesetzt
  /// wurde (Schnellwahl).
  ///
  /// CupertinoDatePicker liest `initialDateTime` nur beim ERSTEN Bauen. Ein
  /// blosses setState bewegt das Rad also nicht: Nach „Heute Abend" stuende
  /// oben 18:00, das Rad zeigte aber weiter die alte Zeit — und die erste
  /// Radberuehrung haette die Wahl wieder ueberschrieben. Ein wechselnder
  /// Schluessel baut das Rad neu und setzt es damit auf die neue Zeit.
  /// Beim Drehen selbst bleibt der Schluessel gleich, sonst kaempfte der
  /// Neuaufbau gegen den Finger.
  int _radSchluessel = 0;

  /// Der Ausgangspunkt aller Tagesberechnungen. Einmal beim Oeffnen bestimmt,
  /// damit ein Tageswechsel um Mitternacht die Liste nicht unter dem Finger
  /// verschiebt.
  late final DateTime _heute;

  @override
  void initState() {
    super.initState();
    final jetzt = DateTime.now();
    _heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
    final start = widget.aktuell;
    if (start != null) {
      _tag = DateTime(start.year, start.month, start.day);
      _uhrzeit = TimeOfDay(hour: start.hour, minute: start.minute);
    } else {
      // Ohne Vorgabe die naechste volle Stunde — praktischer als „jetzt", weil
      // eine Ausfahrt selten in derselben Minute losgeht.
      //
      // ueber den DateTime gerechnet und NICHT ueber (stunde + 1) % 24: Um
      // 23:30 haette die Modulo-Rechnung 00:00 am HEUTIGEN Tag ergeben — also
      // fast einen ganzen Tag in der Vergangenheit.
      final naechsteStunde = DateTime(
        jetzt.year,
        jetzt.month,
        jetzt.day,
        jetzt.hour + 1,
      );
      _tag = DateTime(
        naechsteStunde.year,
        naechsteStunde.month,
        naechsteStunde.day,
      );
      _uhrzeit = TimeOfDay(
        hour: naechsteStunde.hour,
        minute: naechsteStunde.minute,
      );
    }
  }

  DateTime get _ergebnis => DateTime(
    _tag.year,
    _tag.month,
    _tag.day,
    _uhrzeit.hour,
    _uhrzeit.minute,
  );

  String _tagesName(DateTime t) {
    // Ueber die Kalenderfelder vergleichen, damit die Sommerzeit nichts
    // verschiebt.
    if (t.year == _heute.year && t.month == _heute.month && t.day == _heute.day) {
      return 'Heute';
    }
    final morgen = _heute.add(const Duration(days: 1));
    if (t.year == morgen.year &&
        t.month == morgen.month &&
        t.day == morgen.day) {
      return 'Morgen';
    }
    return _wochentage[t.weekday - 1];
  }

  void _setzeTag(DateTime t) {
    HapticFeedback.selectionClick();
    setState(() => _tag = DateTime(t.year, t.month, t.day));
  }

  /// Setzt Tag und Uhrzeit — und schiebt auf die naechste Woche/den naechsten
  /// Tag, falls der Zeitpunkt schon vorbei waere.
  ///
  /// Ohne diese Verschiebung haette „Heute Abend" um 20 Uhr eine Startzeit von
  /// 18 Uhr am selben Tag ergeben, also in der Vergangenheit — und „Samstag"
  /// am Samstagnachmittag ebenso.
  void _schnellwahl(DateTime tag, TimeOfDay zeit, {int verschiebungTage = 1}) {
    HapticFeedback.selectionClick();
    var ziel = DateTime(tag.year, tag.month, tag.day, zeit.hour, zeit.minute);
    final jetzt = DateTime.now();
    if (!ziel.isAfter(jetzt)) {
      ziel = ziel.add(Duration(days: verschiebungTage));
    }
    setState(() {
      _tag = DateTime(ziel.year, ziel.month, ziel.day);
      _uhrzeit = TimeOfDay(hour: ziel.hour, minute: ziel.minute);
      // Das Rad muss der neuen Zeit folgen.
      _radSchluessel++;
    });
  }

  /// Naechster Samstag — heute zaehlt mit, wenn heute Samstag ist.
  DateTime get _naechsterSamstag {
    final abstand = (DateTime.saturday - _heute.weekday + 7) % 7;
    return _heute.add(Duration(days: abstand));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wann geht es los?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_tagesName(_tag)}, '
                          '${_tag.day.toString().padLeft(2, '0')}.'
                          '${_tag.month.toString().padLeft(2, '0')}. um '
                          '${_uhrzeit.hour.toString().padLeft(2, '0')}:'
                          '${_uhrzeit.minute.toString().padLeft(2, '0')} Uhr',
                          style: TextStyle(
                            color: accent,
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
            const SizedBox(height: 18),

            // Schnellwahl fuer die haeufigen Faelle — ein Tipp statt zwei
            // Dialoge.
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  _schnellChip(
                    'Heute Abend',
                    () => _schnellwahl(
                      _heute,
                      const TimeOfDay(hour: 18, minute: 0),
                    ),
                  ),
                  _schnellChip(
                    'Morgen früh',
                    () => _schnellwahl(
                      _heute.add(const Duration(days: 1)),
                      const TimeOfDay(hour: 9, minute: 0),
                    ),
                  ),
                  _schnellChip(
                    'Samstag',
                    () => _schnellwahl(
                      _naechsterSamstag,
                      const TimeOfDay(hour: 10, minute: 0),
                      // Ist der Samstag schon angebrochen, meint der Nutzer den
                      // naechsten — nicht morgen.
                      verschiebungTage: 7,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tagesleiste: die naechsten zwei Wochen.
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: 14,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = _heute.add(Duration(days: i));
                  final gewaehlt =
                      t.year == _tag.year &&
                      t.month == _tag.month &&
                      t.day == _tag.day;
                  return GestureDetector(
                    onTap: () => _setzeTag(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      decoration: BoxDecoration(
                        color: gewaehlt
                            ? accent.withValues(alpha: 0.18)
                            : const Color(0xFF1C1F26),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: gewaehlt ? accent : Colors.white12,
                          width: gewaehlt ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _tagesName(t),
                            style: TextStyle(
                              color: gewaehlt ? accent : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            t.day.toString(),
                            style: TextStyle(
                              color: gewaehlt ? Colors.white : Colors.white70,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Uhrzeit zum Drehen — ruhiger als ein Zifferblatt.
            SizedBox(
              height: 150,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: ValueKey(_radSchluessel),
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 5,
                  initialDateTime: DateTime(
                    2020,
                    1,
                    1,
                    _uhrzeit.hour,
                    // Auf das 5-Minuten-Raster runden, sonst lehnt der Picker
                    // den Startwert ab.
                    (_uhrzeit.minute ~/ 5) * 5,
                  ),
                  onDateTimeChanged: (d) => setState(
                    () => _uhrzeit = TimeOfDay(
                      hour: d.hour,
                      minute: d.minute,
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(StartZeitWahl(_ergebnis)),
                      child: const Text(
                        'Übernehmen',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Der Weg zurueck zu „spontan" — ohne ihn waere eine einmal
                  // gesetzte Zeit fuer immer fest.
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const StartZeitWahl.spontan()),
                    child: const Text(
                      'Ohne feste Zeit losfahren',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _schnellChip(String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
