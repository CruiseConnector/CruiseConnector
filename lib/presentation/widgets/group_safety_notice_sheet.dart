import 'dart:async';
import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/safety_notice_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Kein Speicherzugriff darf den Nutzer aufhalten. Danach machen wir ohne ihn
/// weiter.
const Duration _speicherZeitgrenze = Duration(seconds: 3);

/// Zeigt den Gruppen-Sicherheitshinweis und meldet, ob er akzeptiert wurde.
///
/// 2026-08-18 (Defekt 3): Hier stand eine Kopplung ans Tutorial —
/// `if (!force && !await AppTutorialService.hasCompleted()) return false;`.
/// Sie stammt aus dem Tutorial-Umbau vom 14.08., der den Merkschlüssel auf
/// `app_tutorial_v2_completed` umgestellt hat. Für JEDEN Bestandsnutzer war
/// der neue Schlüssel leer, also lieferte die Funktion `false` — ohne das
/// Sheet zu zeigen. `_createGroup` brach daraufhin stumm ab: Knopf gedrückt,
/// nichts passiert, keine Meldung. Gemessen am 18.08.: 0 Gruppen, 0
/// Mitglieder, 0 Nachrichten in der gesamten Datenbank.
///
/// Der Hinweis darf nie davon abhängen, ob jemand ein Tutorial gesehen hat.
///
/// 2026-08-24 (eingesperrter Nutzer, iPhone 15 Pro Max): Dieses Blatt hatte
/// dieselbe Bauart wie das Blatt aus dem Vorfall — `isDismissible: force`,
/// `enableDrag: force`, das X nur bei `force`. Beim automatischen Aufruf war
/// also alles aus, und der einzige Weg nach vorne hing an einer
/// ScrollNotification. Passt der Inhalt ohne Scrollen ins Blatt, feuert die
/// nie (`ScrollPhysics.shouldAcceptUserOffset` ist bei `maxScrollExtent == 0`
/// false) — kein Ausgang, kein Weiterkommen.
///
/// Seitdem gilt hier hart:
///  * Es gibt IMMER einen Ausgang (X, Hintergrund-Tippen, Wischen,
///    Android-Zurück) — auf jedem Gerät, in jeder Schriftgröße.
///  * Schließen ohne „Verstanden" ist KEINE Zustimmung: es wird nichts
///    gespeichert, der Hinweis kommt beim nächsten Versuch wieder, und die
///    Gruppe entsteht nicht. Der Hinweis bleibt damit verpflichtend, ohne
///    einzusperren.
///  * Was vollständig sichtbar ist, gilt als vollständig gelesen — auch wenn
///    das erst nach dem Drehen oder einer Schriftänderung so ist.
///  * Kein Speicherzugriff darf hängen oder werfen. Im Zweifel zeigen wir
///    den Hinweis lieber einmal zu viel als den Nutzer festzusetzen.
///
/// BEWUSST OHNE Sperre gegen Doppelaufrufe. Das Routing-Blatt hat eine
/// (`tryAcquireLock`) — dort ist das Ergebnis egal. Hier hängt die
/// Gruppenerstellung daran: bliebe die Sperre je hängen (etwa weil das Blatt
/// mit dem Navigator abgeräumt wird, ohne dass sein Future je fällt), könnte
/// dieser Nutzer NIE wieder eine Gruppe anlegen. Zwei übereinanderliegende
/// Hinweise sind unschön — aber jeder davon hat sein eigenes X, und das ist
/// die harmlosere Seite.
Future<bool> showGroupSafetyNoticeSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await _hatBereitsZugestimmt()) return true;
  if (!context.mounted) return false;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // NIE auf `force` binden — sonst gibt es beim automatischen Aufruf
    // keinen Weg nach draußen.
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const GroupSafetyNoticeSheet(),
  );
  return accepted ?? false;
}

/// Fragt den Speicher, wirft aber nie und wartet nie ewig.
///
/// Im Fehlerfall lautet die Antwort „noch nicht zugestimmt". Das ist die
/// harmlose Richtung: der Hinweis kommt nochmal. Die andere Richtung wäre
/// ein Gruppen-Erstellen ohne Hinweis.
Future<bool> _hatBereitsZugestimmt() async {
  try {
    return await SafetyNoticeService.hasAcceptedGroupSafety().timeout(
      _speicherZeitgrenze,
    );
  } catch (error) {
    debugPrint('[GruppenHinweis] Zustimmung nicht lesbar: $error');
    return false;
  }
}

class GroupSafetyNoticeSheet extends StatefulWidget {
  const GroupSafetyNoticeSheet({super.key});

  @override
  State<GroupSafetyNoticeSheet> createState() => _GroupSafetyNoticeSheetState();
}

class _GroupSafetyNoticeSheetState extends State<GroupSafetyNoticeSheet> {
  /// Ab hier gilt der Inhalt als bis unten gelesen. Deckt auch den Fall ab,
  /// dass gar nichts zu scrollen ist (maxScrollExtent == 0).
  static const double _endToleranz = 24.0;

  /// Begrenzte Nachfass-Versuche, falls die Scroll-Position beim ersten
  /// Frame noch nicht existiert. Ohne Deckel liefe das endlos.
  static const int _maxNachfassen = 12;

  final ScrollController _controller = ScrollController();
  bool _readToBottom = false;
  bool _accepted = false;
  bool _saving = false;
  bool _pruefungGeplant = false;
  int _nachfassVersuche = 0;

  @override
  void initState() {
    super.initState();
    _pruefungPlanen();
  }

  /// Prüft NACH dem Layout, ob überhaupt etwas zu scrollen übrig ist.
  ///
  /// 2026-07-03 gab es dafür schon eine Notbremse — aber nur EINEN einzigen
  /// `addPostFrameCallback` aus `initState`. Ändert sich die Größe später
  /// (Drehen, Systemschrift, Splitscreen, Tastatur), lief sie nie wieder:
  /// wer vorher nicht gescrollt hatte, saß fest. Deshalb wird die Prüfung
  /// jetzt aus [initState], aus jedem `build` UND bei jeder Änderung der
  /// Scroll-Maße angestoßen.
  void _pruefungPlanen() {
    if (_readToBottom || _pruefungGeplant || !mounted) return;
    _pruefungGeplant = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruefungGeplant = false;
      _freigebenWennAllesSichtbar();
    });
  }

  void _freigebenWennAllesSichtbar() {
    if (!mounted || _readToBottom) return;
    if (!_controller.hasClients || !_controller.position.hasContentDimensions) {
      // Die Scroll-Position hängt beim allerersten Frame evtl. noch nicht.
      if (_nachfassVersuche++ < _maxNachfassen) _pruefungPlanen();
      return;
    }
    _freigebenWennAmEnde(_controller.position);
  }

  void _freigebenWennAmEnde(ScrollMetrics metrics) {
    if (_readToBottom) return;
    if (metrics.pixels >= metrics.maxScrollExtent - _endToleranz) {
      _alsGelesenMerken();
    }
  }

  /// Einmal gelesen bleibt gelesen — auch wenn der Inhalt durch Drehen
  /// wieder länger wird. Sonst könnte eine Drehung erneut einsperren.
  void _alsGelesenMerken() {
    if (_readToBottom) return;
    _readToBottom = true;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final imFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (imFrame) {
      // Während Layout/Build darf kein setState laufen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_readToBottom || !_accepted || _saving) return;
    setState(() => _saving = true);
    try {
      // Ohne Zeitgrenze blieb `_saving` bei einem hakenden Speicher für
      // immer stehen: Dauer-Ladekringel in einem Blatt ohne Ausgang.
      await SafetyNoticeService.markGroupSafetyAccepted().timeout(
        _speicherZeitgrenze,
      );
    } catch (error) {
      // Konnten wir es nicht merken, kommt der Hinweis eben nochmal. Das ist
      // nicht das Problem des Nutzers — er hat zugestimmt.
      debugPrint('[GruppenHinweis] Zustimmung nicht speicherbar: $error');
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  bool _handleScroll(ScrollNotification notification) {
    _freigebenWennAmEnde(notification.metrics);
    return false;
  }

  /// Feuert, wenn sich die Maße ändern, OHNE dass gescrollt wurde — z. B.
  /// beim Drehen oder wenn der Nutzer die Systemschrift ändert.
  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    _freigebenWennAmEnde(notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    // Deckel nach oben: bei sehr grosser Systemschrift wuerden Haken-Zeile
    // und Knopf sonst aus dem Blatt gedrueckt — beides sind Bedienelemente,
    // die erreichbar bleiben muessen.
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final height = (media.size.height * 0.82).clamp(560.0, 720.0).toDouble();
    final canAccept = _readToBottom && _accepted && !_saving;

    // Jeder Rebuild kann eine neue Größe bedeuten → erneut prüfen.
    _pruefungPlanen();

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
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        child: Column(
                          children: [
                            _Header(accent: accent),
                            Expanded(
                              child: NotificationListener<ScrollMetricsNotification>(
                                onNotification: _handleScrollMetrics,
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: _handleScroll,
                                  child: SingleChildScrollView(
                                    controller: _controller,
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 12),
                                        _NoticeCard(
                                          icon: CupertinoIcons.person_2_fill,
                                          title: 'Keine Veranstaltung',
                                          text:
                                              'Eine Gruppe ist nur eine gemeinsame Route in der App. Sie ist keine offizielle Veranstaltung, kein Rennen und keine Straßensperrung.',
                                          accent: accent,
                                        ),
                                        _NoticeCard(
                                          icon: CupertinoIcons.shield_fill,
                                          title: 'Jeder fährt selbst',
                                          text:
                                              'Alle Teilnehmer bleiben eigenverantwortlich. Abstand, Tempo, Verkehrsregeln und lokale Anweisungen gehen immer vor.',
                                          accent: accent,
                                        ),
                                        _NoticeCard(
                                          icon: CupertinoIcons.map_pin_ellipse,
                                          title: 'Route prüfen',
                                          text:
                                              'Wähle Treffpunkt, Uhrzeit und Route so, dass sie sicher erreichbar sind. Öffentliche Gruppen sollen klar und verantwortungsvoll beschrieben sein.',
                                          accent: accent,
                                        ),
                                        _NoticeCard(
                                          icon: CupertinoIcons
                                              .exclamationmark_triangle_fill,
                                          title: 'Keine riskanten Fahrten',
                                          text:
                                              'Plane keine gefährlichen Aktionen. Keine illegalen Manöver, kein Druck auf andere und keine Aufforderung zu Rennen.',
                                          accent: accent,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _readToBottom
                                              ? 'Setze den Haken und bestätige. Danach erscheint dieser Hinweis nicht mehr automatisch. Schließt du mit ✕, entsteht keine Gruppe und der Hinweis kommt wieder.'
                                              : 'Scrolle bis zum Ende und setze den Haken. Mit ✕ oben kommst du jederzeit heraus — dann entsteht keine Gruppe.',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.56,
                                            ),
                                            fontSize: 12.5,
                                            height: 1.3,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _CheckRow(
                              text:
                                  'Ich habe die Hinweise gelesen und erstelle keine riskante oder illegale Gruppenfahrt.',
                              accent: accent,
                              checked: _accepted,
                              enabled: _readToBottom,
                              onChanged: (value) =>
                                  setState(() => _accepted = value),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                onPressed: canAccept ? _accept : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  disabledBackgroundColor: Colors.white
                                      .withValues(alpha: 0.10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: _saving
                                    ? const CupertinoActivityIndicator(
                                        color: Colors.white,
                                      )
                                    : Text(
                                        !_readToBottom
                                            ? 'Erst bis unten scrollen'
                                            : !_accepted
                                            ? 'Häkchen setzen'
                                            : 'Verstanden',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
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

class _Header extends StatelessWidget {
  const _Header({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(CupertinoIcons.person_3_fill, color: accent, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Gruppenfahrt-Hinweis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            // Notausgang. Immer sichtbar — nie an `force` koppeln.
            IconButton(
              onPressed: () => Navigator.of(context).pop(false),
              tooltip: 'Schließen',
              icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 13.4,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.text,
    required this.accent,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final String text;
  final Color accent;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged(!checked) : null,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: checked
                  ? accent.withValues(alpha: 0.70)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(
                checked
                    ? CupertinoIcons.checkmark_square_fill
                    : CupertinoIcons.square,
                color: checked ? accent : Colors.white.withValues(alpha: 0.45),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13.0,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
