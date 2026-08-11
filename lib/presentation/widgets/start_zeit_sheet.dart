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
    _tag = start != null
        ? DateTime(start.year, start.month, start.day)
        : _heute;
    _uhrzeit = start != null
        ? TimeOfDay(hour: start.hour, minute: start.minute)
        // Ohne Vorgabe die naechste volle Stunde — praktischer als „jetzt",
        // weil eine Ausfahrt selten in derselben Minute losgeht.
        : TimeOfDay(hour: (jetzt.hour + 1) % 24, minute: 0);
  }

  DateTime get _ergebnis => DateTime(
    _tag.year,
    _tag.month,
    _tag.day,
    _uhrzeit.hour,
    _uhrzeit.minute,
  );

  String _tagesName(DateTime t) {
    final diff = t.difference(_heute).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Morgen';
    return _wochentage[t.weekday - 1];
  }

  void _setzeTag(DateTime t) {
    HapticFeedback.selectionClick();
    setState(() => _tag = DateTime(t.year, t.month, t.day));
  }

  void _schnellwahl(DateTime tag, TimeOfDay zeit) {
    HapticFeedback.selectionClick();
    setState(() {
      _tag = DateTime(tag.year, tag.month, tag.day);
      _uhrzeit = zeit;
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
