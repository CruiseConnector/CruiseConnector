import 'dart:async';
import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/location_permission_helper.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Wie lange ein Schreib-/Lesezugriff auf den Geraetespeicher dauern darf.
/// Danach machen wir ohne ihn weiter — ein haengender Speicher darf niemanden
/// im Blatt festhalten.
const Duration _speicherGrenze = Duration(seconds: 3);

/// Zeigt den Hinweis „Standort für die Navigation".
///
/// 2026-08-24 (Vorfall „App haengt", iPhone 15 Pro Max): Dieses Blatt war die
/// gefaehrlichste Sackgasse der App, weil es direkt nach der Anmeldung
/// automatisch aufgeht (`home_page.dart`, `_runFirstLoginGuidance`):
///  * `isDismissible: false`, `enableDrag: false`, kein X — kein Wischen, kein
///    Tippen daneben, auf iOS auch keine Zurueck-Geste.
///  * Beide Knoepfe (auch der Ausweg) haengen an `_busy`.
///  * `_busy` wurde erst zurueckgesetzt, NACHDEM die Standort-Anfrage
///    zurueckkam — und die lief ueber zwei `Geolocator.requestPermission()`
///    ohne jede Zeitgrenze. Antwortet das System nicht (auf iOS ist genau die
///    Hochstufung auf „Immer" so ein Fall), blieb `_busy` fuer immer `true`.
/// Ergebnis: alle Knoepfe grau, kein Ausgang, direkt nach der Anmeldung.
///
/// Seitdem gilt hier hart:
///  1. Der Ausweg „Später" ist von Anfang an sichtbar und NIE gesperrt. Er
///     braucht weder Netz noch Berechtigung noch eine Antwort des Systems.
///  2. Zusaetzlich sind Wischen und Tippen daneben wieder erlaubt — drei
///     unabhaengige Auswege statt einem. (Das widerspricht Apple 5.1.1(iv)
///     nicht: die Regel verbietet, Nutzer zu einer Freigabe zu ZWINGEN.)
///  3. Kein Aufruf ins System oder in den Speicher ohne Zeitgrenze.
///  4. `_busy` wird in einem `finally` zurueckgesetzt — auch ein Fehler laesst
///     den Nutzer nicht stehen.
Future<bool> showLocationAlwaysNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await _hinweisSchonGesehen()) {
    return true;
  }
  if (!context.mounted) return false;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // 2026-08-24: bewusst wieder wegtippbar/wegwischbar. Der Hinweis bleibt
    // trotzdem verpflichtend — wer wegwischt, hat nicht zugestimmt, und beim
    // Start einer Gruppenfahrt fragt die App erneut.
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => const LocationAlwaysNoticeSheet(),
  );
  return accepted ?? false;
}

/// Liest den „schon gesehen"-Merker. Antwortet der Speicher nicht, lautet die
/// Antwort `false` — dann erscheint der Hinweis eben nochmal. Das ist die
/// harmlose Richtung; haengenbleiben ist es nicht.
Future<bool> _hinweisSchonGesehen() async {
  try {
    return await SafetyNoticeService.hasSeenLocationAlwaysNotice().timeout(
      _speicherGrenze,
    );
  } catch (fehler) {
    debugPrint('[Standort-Hinweis] Merker lesen fehlgeschlagen: $fehler');
    return false;
  }
}

/// Fragt die Standort-Freigabe an. Getrennt herausgezogen, damit Tests das
/// Verhalten bei „System antwortet nie" und „Aufruf wirft" nachstellen koennen.
typedef StandortFreigabeAnfrage = Future<geo.LocationPermission> Function();

/// Oeffnet die App-Einstellungen. `true` = die Einstellungen sind wirklich
/// aufgegangen (Test-Naht wie oben).
typedef EinstellungenOeffner = Future<bool> Function();

/// Merkt „Hinweis gesehen" im Geraetespeicher (Test-Naht wie oben).
typedef HinweisMerker = Future<void> Function();

class LocationAlwaysNoticeSheet extends StatefulWidget {
  const LocationAlwaysNoticeSheet({
    super.key,
    this.freigabeAnfragen,
    this.einstellungenOeffnen,
    this.hinweisMerken,
    this.antwortGrenze = LocationPermissionHelper.antwortGrenze,
  });

  /// Test-Naht: Standort-Freigabe anfragen. Standard ist der echte Helfer.
  final StandortFreigabeAnfrage? freigabeAnfragen;

  /// Test-Naht: App-Einstellungen oeffnen.
  final EinstellungenOeffner? einstellungenOeffnen;

  /// Test-Naht: „gesehen" merken.
  final HinweisMerker? hinweisMerken;

  /// Wie lange wir auf eine Antwort des Systems warten — gezaehlt wird NUR die
  /// Zeit, in der unsere App vorne ist (siehe [SystemAntwortWache]). Waehrend
  /// der System-Dialog offen ist, steht diese Uhr still.
  final Duration antwortGrenze;

  @override
  State<LocationAlwaysNoticeSheet> createState() =>
      _LocationAlwaysNoticeSheetState();
}

class _LocationAlwaysNoticeSheetState extends State<LocationAlwaysNoticeSheet> {
  bool _busy = false;
  // 2026-07-03 (vucko „Standort immer / direkt in Einstellungen"): Zweiter
  // Schritt — nach dem System-Dialog hat der Nutzer evtl. nur „Beim Verwenden"
  // erteilt. Dann zeigen wir hier einen klaren 1-Tap-Button, der DIREKT die
  // App-Standort-Einstellungen öffnet (wo „Immer erlauben" gesetzt wird),
  // statt ihn hart aus der App zu werfen.
  bool _needsSettingsStep = false;
  // Das System hat innerhalb der Zeitgrenze nicht geantwortet (oder der Aufruf
  // ist gescheitert). Wir sagen es ehrlich, statt weiter grau zu bleiben.
  bool _keineSystemantwort = false;
  // Verhindert ein zweites `pop` (z. B. wenn eine spaete Antwort eintrifft,
  // nachdem der Nutzer schon „Später" getippt hat).
  bool _beendet = false;

  Future<geo.LocationPermission> _freigabeAnfragen() async {
    final naht = widget.freigabeAnfragen;
    if (naht != null) return naht();
    final serviceEnabled = await LocationPermissionHelper.isServiceEnabled();
    if (!serviceEnabled) return geo.LocationPermission.denied;
    // Fragt an + stuft (so weit per Dialog möglich) auf „Immer" hoch. Die
    // Einstellungen öffnen wir bewusst NICHT automatisch — dafür gibt es
    // den klaren Folge-Button, damit der Nutzer nicht überrascht rausfliegt.
    return LocationPermissionHelper.requestAlways(openSettingsIfNeeded: false);
  }

  /// Schreibt den Merker im Hintergrund. Nie `await`en, wo der Nutzer darauf
  /// wartet: der Geraetespeicher ist ein Plattform-Kanal und kann haengen.
  void _merkenImHintergrund() {
    final merken =
        widget.hinweisMerken ??
        SafetyNoticeService.markLocationAlwaysNoticeSeen;
    unawaited(
      merken().timeout(_speicherGrenze).catchError((Object fehler) {
        debugPrint(
          '[Standort-Hinweis] Merker schreiben fehlgeschlagen: $fehler',
        );
      }),
    );
  }

  /// Der Ausgang. Muss unter allen Umstaenden funktionieren — deshalb erst
  /// schliessen, dann (nebenher) merken.
  void _schliessen(bool ergebnis) {
    if (_beendet || !mounted) return;
    _beendet = true;
    _merkenImHintergrund();
    Navigator.of(context).pop(ergebnis);
  }

  Future<void> _acceptPermission() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _keineSystemantwort = false;
    });
    _merkenImHintergrund();

    geo.LocationPermission? antwort;
    try {
      final anfrage = _freigabeAnfragen();
      _spaeteAntwortBeobachten(anfrage);
      antwort = await SystemAntwortWache.warte<geo.LocationPermission?>(
        anfrage,
        grenze: widget.antwortGrenze,
        beiZeitgrenze: null,
      );
    } catch (fehler) {
      // Der Wachhund faengt Fehler bereits ab; dieser Zweig ist die Rueckfall-
      // ebene, falls schon das Erzeugen des Futures wirft.
      debugPrint('[Standort-Hinweis] Anfrage fehlgeschlagen: $fehler');
      antwort = null;
    } finally {
      // IMMER — sonst bleibt der Nutzer im grauen Blatt sitzen.
      if (mounted && !_beendet) setState(() => _busy = false);
    }

    if (!mounted || _beendet) return;
    if (antwort == geo.LocationPermission.always) {
      _schliessen(true);
      return;
    }
    // `unableToDetermine` ist die Antwort des Helfers, wenn dessen eigene
    // Zeitgrenze zuschlug; `null` die unserer. Beides heisst dasselbe: wir
    // wissen nichts.
    final ohneAntwort =
        antwort == null || antwort == geo.LocationPermission.unableToDetermine;
    setState(() {
      // Keine Antwort => wir bleiben im ersten Schritt und sagen es. Den Nutzer
      // in den Einstellungs-Schritt zu schicken waere gelogen: wir wissen gar
      // nicht, ob er etwas erteilt hat.
      _keineSystemantwort = ohneAntwort;
      _needsSettingsStep = !ohneAntwort;
    });
  }

  /// Eine Zeitgrenze bricht den Aufruf nicht ab — kommt die Antwort spaeter
  /// doch noch und lautet „Immer", nehmen wir sie an.
  void _spaeteAntwortBeobachten(Future<geo.LocationPermission> anfrage) {
    unawaited(
      anfrage
          .then((spaet) {
            if (!mounted || _beendet) return;
            if (spaet == geo.LocationPermission.always) _schliessen(true);
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _keineSystemantwort = false;
    });
    var geoeffnet = false;
    try {
      final oeffnen = widget.einstellungenOeffnen;
      geoeffnet = await SystemAntwortWache.warte<bool>(
        oeffnen != null ? oeffnen() : LocationPermissionHelper.openSettings(),
        grenze: LocationPermissionHelper.einstellungenGrenze,
        beiZeitgrenze: false,
      );
    } catch (fehler) {
      debugPrint(
        '[Standort-Hinweis] Einstellungen oeffnen fehlgeschlagen: $fehler',
      );
    } finally {
      // IMMER — auch ein haengender Intent darf das Blatt nicht sperren.
      if (mounted && !_beendet) setState(() => _busy = false);
    }
    if (!mounted || _beendet) return;
    if (geoeffnet) {
      // Der Nutzer ist jetzt in den Einstellungen; das Blatt hat seine Arbeit
      // getan und darf sich schliessen.
      _schliessen(true);
      return;
    }
    // Die Einstellungen gingen nicht auf. Blatt offen lassen, ehrlich sein —
    // der Ausweg „Später" steht ohnehin daneben.
    setState(() => _keineSystemantwort = true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final height = (media.size.height * 0.76).clamp(520.0, 680.0).toDouble();

    return MediaQuery(
      data: clampedMedia,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SizedBox(
            height: height,
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
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _needsSettingsStep
                                          ? CupertinoIcons.gear_alt_fill
                                          : CupertinoIcons.location_fill,
                                      color: accent,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _needsSettingsStep
                                          ? 'Standort in den Einstellungen'
                                          : 'Standort für die Navigation',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _needsSettingsStep
                                          ? 'Du hast den Standort nur „Beim Verwenden" freigegeben. Für Navigation im Hintergrund und Gruppenfahrten öffnen wir dich direkt in den Einstellungen. Tippe dort auf Standort und wähle „Immer".'
                                          : 'Für aktive Navigation, Gruppenfahrten und sichere Neuberechnungen muss Cruise Connector deinen Standort auch weiter nutzen können, wenn du kurz die App wechselst oder der Bildschirm gesperrt ist.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        fontSize: 14.2,
                                        height: 1.34,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    if (_keineSystemantwort)
                                      const _HintRow(
                                        accent: Color(0xFFFF9500),
                                        icon: CupertinoIcons
                                            .exclamationmark_triangle_fill,
                                        text:
                                            'Das System hat nicht geantwortet. Versuch es nochmal oder fahr erstmal ohne die Freigabe weiter.',
                                      ),
                                    if (_needsSettingsStep) ...[
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.location_fill,
                                        text:
                                            '„Standort" antippen → „Immer" wählen.',
                                      ),
                                      _HintRow(
                                        accent: accent,
                                        icon:
                                            CupertinoIcons.checkmark_seal_fill,
                                        text:
                                            'Genauen Standort aktiviert lassen.',
                                      ),
                                    ] else ...[
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.lock_rotation,
                                        text:
                                            'Aktive Fahrt bleibt stabil im Hintergrund.',
                                      ),
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.person_2_fill,
                                        text:
                                            'Gruppenmitglieder sehen weiter deinen echten Fortschritt.',
                                      ),
                                      _HintRow(
                                        accent: accent,
                                        icon: CupertinoIcons.gear,
                                        text:
                                            'Du kannst die Freigabe jederzeit in den Einstellungen ändern.',
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _busy
                                    ? null
                                    : (_needsSettingsStep
                                          ? _openSettings
                                          : _acceptPermission),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: _busy
                                    ? const CupertinoActivityIndicator(
                                        color: Colors.white,
                                      )
                                    : Text(
                                        // Apple 5.1.1(iv): VOR der System-Anfrage
                                        // darf der Button den Nutzer NICHT zu einer
                                        // Auswahl drängen („Immer erlauben"). Neutral
                                        // „Weiter" → führt nur zur echten iOS-Anfrage.
                                        _needsSettingsStep
                                            ? 'In den Einstellungen öffnen'
                                            : (_keineSystemantwort
                                                  ? 'Nochmal versuchen'
                                                  : 'Weiter'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                              ),
                            ),
                            // 2026-08-24: Der Ausweg ist IMMER da und NIE
                            // gesperrt — auch waehrend `_busy`. Er braucht weder
                            // Netz noch Berechtigung noch eine Antwort des
                            // Systems und ist damit der garantierte Weg nach
                            // draussen. Vorher gab es ihn erst im zweiten
                            // Schritt und er hing zusaetzlich an `_busy`.
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: TextButton(
                                onPressed: () => _schliessen(true),
                                child: Text(
                                  _needsSettingsStep
                                      ? 'Später, mit „Beim Verwenden" fahren'
                                      : 'Später entscheiden',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({
    required this.accent,
    required this.icon,
    required this.text,
  });

  final Color accent;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.74),
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
