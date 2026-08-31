import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/routen_kappung.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hinweis, der VOR dem Teilen einer Strecke erscheint (2026-08-31).
///
/// Vucko woertlich: „das ist halt dann ein Pop-up. Kommt bevor jetzt jemand
/// eine Strecke teilt, dass man sich keine Gedanken machen muss, dass die
/// Strecke dann spaeter andockt."
///
/// Seit dem 28.08. (Fehler 7 und 8) schuetzt die App den Wohnort: die Skizze
/// im Beitrag zeigt weder Karte noch Ortsnamen und kappt beide Enden, und wer
/// eine fremde Strecke NACHFAEHRT, bekommt vorn und hinten je einen Kilometer
/// abgeschnitten. Nur wusste das niemand. Dieses Blatt sagt es einmal, bevor
/// jemand zum ersten Mal teilt.
///
/// REGELN, die hier hart gelten:
///  * Es gibt IMMER einen Ausgang: Abbrechen, Hintergrund tippen, wischen,
///    Android-Zurueck. Kein Knopf haengt an einer ScrollNotification — genau
///    dieses Muster hat am 24.08. einen Nutzer eingesperrt (siehe
///    test/widgets/kein_blatt_ohne_ausweg_test.dart).
///  * Abbrechen speichert NICHTS. Der Hinweis kommt beim naechsten Versuch
///    wieder, geteilt wird nicht.
///  * Die Zahlen im Text kommen aus [anzeigeKappungMeter] und
///    [fremdfahrtKappungMeter], NICHT aus der Hand getippt. Aendert jemand
///    die Kappung, aendert sich der Text mit — sonst steht hier irgendwann
///    ein Versprechen, das die App nicht mehr haelt.
///  * Kein Speicherzugriff darf den Nutzer aufhalten. Haengt oder wirft er,
///    zeigen wir das Blatt lieber einmal zu viel.
enum RouteTeilenZiel {
  /// Die Strecke wandert als Beitrag in den Feed. Hier greifen beide
  /// Schutzstufen: Anzeige ohne Karte und gekappte Fremdfahrt.
  beitrag,

  /// Die Strecke wird als Bild aus dem Composer weitergegeben. Das passiert
  /// auf dem Geraet, an der App vorbei — und das Format „Karte" zeigt dort
  /// sehr wohl die echte Karte. Deshalb ein EIGENER, ehrlicher Text.
  bild,
}

/// Kein Speicherzugriff darf den Nutzer aufhalten. Danach machen wir ohne ihn
/// weiter (und zeigen den Hinweis lieber nochmal).
const Duration _speicherZeitgrenze = Duration(seconds: 3);

/// Basis der Merker. Kontogebunden ueber [NutzerPrefsSchluessel.fuer]: auf
/// einem Handy mit zwei Konten soll das zweite Konto den Hinweis auch sehen.
@visibleForTesting
const String merkerBasisBeitrag = 'route_teilen_hinweis_beitrag_v1';

@visibleForTesting
const String merkerBasisBild = 'route_teilen_hinweis_bild_v1';

String _merkerBasis(RouteTeilenZiel ziel) =>
    ziel == RouteTeilenZiel.beitrag ? merkerBasisBeitrag : merkerBasisBild;

/// Zeigt den Hinweis und meldet, ob weitergeteilt werden darf.
///
/// Liefert `true`, wenn der Nutzer bestaetigt hat ODER den Hinweis fuer
/// dieses Ziel schon einmal gesehen hat. Liefert `false`, wenn er abbricht
/// oder das Blatt wegwischt — dann passiert beim Aufrufer NICHTS.
///
/// [force] zeigt das Blatt auch dann, wenn es schon gesehen wurde. Das ist
/// das „danach nur noch auf Wunsch" aus dem Auftrag.
Future<bool> zeigeRouteTeilenHinweis(
  BuildContext context, {
  required RouteTeilenZiel ziel,
  bool force = false,
}) async {
  if (!force && await _schonGesehen(ziel)) return true;
  if (!context.mounted) return false;

  final bestaetigt = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // NIE auf `force` binden. Am 24.08. sass ein Nutzer in einem Blatt fest,
    // dessen Ausgaenge genau so verdrahtet waren.
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => RouteTeilenHinweisSheet(ziel: ziel),
  );
  return bestaetigt ?? false;
}

/// Fragt den Speicher, wirft aber nie und wartet nie ewig.
///
/// Im Fehlerfall lautet die Antwort „noch nicht gesehen". Das ist die
/// harmlose Richtung: der Hinweis kommt einmal zu oft. Die andere Richtung
/// waere ein Teilen ohne Hinweis, und genau darum geht es hier.
Future<bool> _schonGesehen(RouteTeilenZiel ziel) async {
  try {
    return await _leseMerker(ziel).timeout(_speicherZeitgrenze);
  } catch (error) {
    debugPrint('[TeilenHinweis] Merker nicht lesbar: $error');
    return false;
  }
}

Future<bool> _leseMerker(RouteTeilenZiel ziel) async {
  final prefs = await SharedPreferences.getInstance();
  final basis = _merkerBasis(ziel);
  return prefs.getBool(NutzerPrefsSchluessel.fuer(basis)) ?? false;
}

Future<void> _merkeGesehen(RouteTeilenZiel ziel) async {
  try {
    final prefs = await SharedPreferences.getInstance().timeout(
      _speicherZeitgrenze,
    );
    final basis = _merkerBasis(ziel);
    await prefs.setBool(NutzerPrefsSchluessel.fuer(basis), true);
  } catch (error) {
    // Nicht schlimm: der Hinweis erscheint dann beim naechsten Mal nochmal.
    // Ein fehlgeschlagener Schreibvorgang darf das Teilen NICHT verhindern.
    debugPrint('[TeilenHinweis] Merker nicht speicherbar: $error');
  }
}

/// „300 Meter" aus [anzeigeKappungMeter], nicht aus der Hand getippt.
@visibleForTesting
String anzeigeKappungText() => '${anzeigeKappungMeter.round()} Meter';

/// „1 km" aus [fremdfahrtKappungMeter], nicht aus der Hand getippt.
@visibleForTesting
String fremdfahrtKappungText() {
  const km = fremdfahrtKappungMeter / 1000.0;
  // Glatte Kilometer ohne Nachkommastelle: „1 km", nicht „1.0 km".
  return km == km.roundToDouble()
      ? '${km.round()} km'
      : '${km.toStringAsFixed(1)} km';
}

/// Die drei bis vier Zeilen, die im Blatt stehen. Ausgelagert, damit ein Test
/// sie pruefen kann, ohne das ganze Blatt zu bauen.
@visibleForTesting
List<String> hinweisZeilen(RouteTeilenZiel ziel) {
  switch (ziel) {
    case RouteTeilenZiel.beitrag:
      return [
        'Dein Beitrag zeigt keine Karte und keine Ortsnamen, nur den '
            'nachgezeichneten Verlauf der Strecke.',
        'Anfang und Ende dieser Linie werden um je ${anzeigeKappungText()} '
            'gekappt.',
        'Wer die Strecke nachfährt, startet ${fremdfahrtKappungText()} '
            'später und hört ${fremdfahrtKappungText()} früher auf.',
        'Deine eigene Ansicht bleibt vollständig. Nur Fremde sehen die '
            'gekürzte Fassung.',
      ];
    case RouteTeilenZiel.bild:
      return [
        'Das Bild entsteht auf deinem Gerät. In der App wird davon nichts '
            'veröffentlicht.',
        'Story, Quadrat und Sticker zeigen nur den Verlauf, ohne Karte und '
            'ohne Ortsnamen.',
        'Das Format Karte legt die echte Straßenkarte darunter. Darauf sind '
            'Start und Ziel zu erkennen.',
        'Sieh dir das Bild an, bevor du es weitergibst.',
      ];
  }
}

@visibleForTesting
String hinweisTitel(RouteTeilenZiel ziel) => switch (ziel) {
  RouteTeilenZiel.beitrag => 'Was beim Teilen geschützt wird',
  RouteTeilenZiel.bild => 'Bevor du das Bild weitergibst',
};

@visibleForTesting
String hinweisKnopf(RouteTeilenZiel ziel) => switch (ziel) {
  RouteTeilenZiel.beitrag => 'Teilen',
  // Hier wird noch nichts geteilt: es oeffnet sich der Composer, in dem
  // der Nutzer Format und Hintergrund waehlt. „Teilen" waere gelogen.
  RouteTeilenZiel.bild => 'Weiter',
};

class RouteTeilenHinweisSheet extends StatefulWidget {
  const RouteTeilenHinweisSheet({super.key, required this.ziel});

  final RouteTeilenZiel ziel;

  @override
  State<RouteTeilenHinweisSheet> createState() =>
      _RouteTeilenHinweisSheetState();
}

class _RouteTeilenHinweisSheetState extends State<RouteTeilenHinweisSheet> {
  bool _bestaetigt = false;

  Future<void> _weiter() async {
    if (_bestaetigt) return;
    setState(() => _bestaetigt = true);
    await _merkeGesehen(widget.ziel);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _abbrechen() {
    // Bewusst OHNE Merker: wer abbricht, hat nicht zugestimmt und soll den
    // Hinweis beim naechsten Versuch wieder sehen.
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final zeilen = hinweisZeilen(widget.ziel);

    // Waagrecht mittig, senkrecht NUR so hoch wie noetig.
    //
    // 2026-08-31: Hier stand zuerst ein `Align(bottomCenter)` wie im Blatt
    // map_download_preference_sheet. Align dehnt sich aber ueber die volle
    // Hoehe, die `isScrollControlled` hergibt — das unsichtbare Blatt lag
    // damit ueber dem ganzen Bildschirm und schluckte den Tipp auf den
    // abgedunkelten Hintergrund. Auf iOS gibt es keine Zurueck-Geste; der
    // einzige Ausgang waere der Knopf gewesen. Eine Row ist waagrecht breit,
    // aber senkrecht so hoch wie ihr Kind, und laesst den Hintergrund frei.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              // Kein fester Wert: bei grosser Systemschrift wachsen die
              // Zeilen, dann scrollt der Text statt abgeschnitten zu werden.
              maxHeight: media.size.height * 0.86,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                media.padding.bottom == 0 ? 12 : 0,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF2161921),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      border: Border.all(color: accent.withValues(alpha: 0.32)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                          child: Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  CupertinoIcons.lock_shield_fill,
                                  color: accent,
                                  size: 34,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  hinweisTitel(widget.ziel),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                for (var i = 0; i < zeilen.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 11),
                                  _HinweisZeile(
                                    text: zeilen[i],
                                    accent: accent,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Text(
                                  'Diesen Hinweis siehst du nur beim ersten Mal.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.42),
                                    fontSize: 12.4,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: TextButton(
                                      onPressed: _abbrechen,
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.07),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Abbrechen',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: FilledButton(
                                      // NIE `null`: dieser Knopf ist der Weg nach
                                      // vorn und muss im ersten Bild bedienbar
                                      // sein, egal wie gross die Schrift ist.
                                      onPressed: _weiter,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        hinweisKnopf(widget.ziel),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HinweisZeile extends StatelessWidget {
  const _HinweisZeile({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: accent.withValues(alpha: 0.85),
            size: 17,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 14.4,
              height: 1.36,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
