import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showRoutingOnboardingSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (!force && await RoutingOnboardingService.hasAccepted()) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: force,
    enableDrag: force,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => RoutingOnboardingSheet(showCloseButton: force),
  );
}

class RoutingOnboardingSheet extends StatefulWidget {
  const RoutingOnboardingSheet({super.key, this.showCloseButton = false});

  final bool showCloseButton;

  @override
  State<RoutingOnboardingSheet> createState() => _RoutingOnboardingSheetState();
}

class _RoutingOnboardingSheetState extends State<RoutingOnboardingSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _hasReachedEnd = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollGate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollGate());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollGate)
      ..dispose();
    super.dispose();
  }

  void _updateScrollGate() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final reachedEnd =
        position.maxScrollExtent <= 4 ||
        position.pixels >= position.maxScrollExtent - 8;
    if (reachedEnd != _hasReachedEnd) {
      setState(() => _hasReachedEnd = reachedEnd);
    }
  }

  Future<void> _accept() async {
    if (!_hasReachedEnd || _saving) return;
    setState(() => _saving = true);
    await RoutingOnboardingService.markAccepted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final sheetHeight = (media.size.height * 0.9)
        .clamp(560.0, 780.0)
        .toDouble();

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              media.padding.bottom == 0 ? 12 : 0,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(34),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xF2161921),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(34),
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.34)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.20),
                        blurRadius: 32,
                        offset: const Offset(0, -8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 36,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _OnboardingHeader(
                        accent: accent,
                        showCloseButton: widget.showCloseButton,
                      ),
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black,
                              Colors.black,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.035, 0.94, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _IntroHero(accent: accent),
                                const SizedBox(height: 18),
                                _InfoSection(
                                  icon: CupertinoIcons.arrow_2_circlepath,
                                  title: 'Was macht der Rundkurs-Modus?',
                                  body:
                                      'Cruise Connector schlägt dir eine Rundroute vor, die ungefähr zur gewählten Länge, deinem Stil und deiner Autobahn-Einstellung passt. Start und Ende liegen wieder in deiner Nähe. Die Strecke ist immer ein Vorschlag und kann sich durch Verkehr, Sperren oder lokale Regeln in der Realität unterscheiden.',
                                  accent: accent,
                                ),
                                _ModeGrid(accent: accent),
                                _InfoSection(
                                  icon: CupertinoIcons.map_pin_ellipse,
                                  title: 'Wegpunkte',
                                  body:
                                      'Im Wegpunkte-Modus kannst du Punkte auf der Karte setzen. Du kannst Punkte antippen, ersetzen oder per langem Druck löschen. Die angezeigte Reihenfolge zählt für die Planung. Nutze wenige, klare Punkte, damit die Route fahrbar bleibt.',
                                  accent: accent,
                                ),
                                _InfoSection(
                                  icon: CupertinoIcons.location_north_line,
                                  title: 'A nach B',
                                  body:
                                      'Bei A nach B suchst du ein Ziel und wählst, ob du direkt fahren oder einen kleinen, mittleren oder großen Umweg möchtest. Der gewählte Stil beeinflusst, ob die Strecke flüssiger, kurviger, ruhiger oder entdeckender geplant wird.',
                                  accent: accent,
                                ),
                                _InfoSection(
                                  icon: CupertinoIcons.car_detailed,
                                  title: 'Autobahn-Schalter',
                                  body:
                                      'Autobahn AN bedeutet: Autobahn ist erlaubt, aber nicht Pflicht. Eine gute Route ohne Autobahn kann trotzdem richtig sein. Autobahn AUS bedeutet: Autobahn soll vermieden werden.',
                                  accent: accent,
                                ),
                                _SafetySection(accent: accent),
                                const SizedBox(height: 12),
                                _LegalNote(accent: accent),
                                const SizedBox(height: 14),
                                Center(
                                  child: Text(
                                    'Ende der Hinweise',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.42,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _OnboardingFooter(
                        accent: accent,
                        canAccept: _hasReachedEnd && !_saving,
                        saving: _saving,
                        onAccept: _accept,
                      ),
                    ],
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

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.accent,
    required this.showCloseButton,
  });

  final Color accent;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
      child: Column(
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.38)),
                ),
                child: Icon(
                  CupertinoIcons.car_detailed,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Routing verstehen',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kurz lesen, sicher fahren.',
                      style: TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCloseButton)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntroHero extends StatelessWidget {
  const _IntroHero({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.25),
            const Color(0xFF211B18),
            const Color(0xFF141821),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: const Text(
        'Routen in Cruise Connector sind intelligente Vorschläge. Du entscheidest immer selbst, ob eine Straße, ein Manöver oder eine Situation sicher und erlaubt ist.',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 13.2,
                    height: 1.36,
                    fontWeight: FontWeight.w500,
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

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const modes = [
      (
        'Sport',
        CupertinoIcons.speedometer,
        'Flüssige Straßen, klare Linien, weniger künstliche Stiche.',
      ),
      (
        'Kurvenjagd',
        CupertinoIcons.waveform_path,
        'Mehr Kurven und Höhenwechsel, aber keine riskanten Manöver.',
      ),
      (
        'Abendrunde',
        CupertinoIcons.moon_stars,
        'Ruhiger, kompakter und entspannter für kurze Ausfahrten.',
      ),
      (
        'Entdecker',
        CupertinoIcons.compass,
        'Mehr Abwechslung und andere Sektoren statt immer derselben Richtung.',
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 340;
              final itemWidth = useTwoColumns
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final mode in modes)
                    SizedBox(
                      width: itemWidth,
                      child: _ModeCard(
                        title: mode.$1,
                        icon: mode.$2,
                        body: mode.$3,
                        accent: accent,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.icon,
    required this.body,
    required this.accent,
  });

  final String title;
  final IconData icon;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10141C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontWeight: FontWeight.w500,
              height: 1.28,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const bullets = [
      'Du bleibst als Fahrer jederzeit eigenverantwortlich.',
      'Die Route ist ein Vorschlag, keine Garantie.',
      'Beachte Verkehrsregeln, Fahrverbote, Privatstraßen und Sperren.',
      'Folge der Route nicht blind, wenn die Situation vor Ort anders ist.',
      'Blick auf die Straße, nicht dauerhaft aufs Handy.',
      'Keine Haftung für Schäden, Verstöße oder Unfälle.',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_shield, color: accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Sicherheit',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final bullet in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13.2,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
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

class _LegalNote extends StatelessWidget {
  const _LegalNote({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.doc_text, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Der finale Rechtstext muss später juristisch geprüft werden. Diese Hinweise ersetzen keine rechtliche Prüfung.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.accent,
    required this.canAccept,
    required this.saving,
    required this.onAccept,
  });

  final Color accent;
  final bool canAccept;
  final bool saving;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xF2161921),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: canAccept ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 180),
              child: const Text(
                'Bitte bis ganz nach unten scrollen.',
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: canAccept ? onAccept : null,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.10),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                ),
                child: saving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(
                        canAccept ? 'Verstanden' : 'Erst vollständig lesen',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.1,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
