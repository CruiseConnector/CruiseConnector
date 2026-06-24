import 'dart:ui' as ui;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/routing_onboarding_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showRoutingOnboardingSheet(
  BuildContext context, {
  bool force = false,
}) async {
  if (RoutingOnboardingService.isOpen) return;
  if (!force && await RoutingOnboardingService.hasAccepted()) return;
  if (!context.mounted) return;

  RoutingOnboardingService.acquireLock();
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: force,
      enableDrag: force,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (_) => RoutingOnboardingSheet(showCloseButton: force),
    );
  } finally {
    RoutingOnboardingService.releaseLock();
  }
}

class RoutingOnboardingSheet extends StatefulWidget {
  const RoutingOnboardingSheet({super.key, this.showCloseButton = false});

  final bool showCloseButton;

  @override
  State<RoutingOnboardingSheet> createState() => _RoutingOnboardingSheetState();
}

class _RoutingOnboardingSheetState extends State<RoutingOnboardingSheet> {
  final ScrollController _controller = ScrollController();
  bool _readToBottom = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_readToBottom || _saving) return;
    setState(() => _saving = true);
    await RoutingOnboardingService.markAccepted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool _handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (!_readToBottom && metrics.pixels >= metrics.maxScrollExtent - 24) {
      setState(() => _readToBottom = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final height = (media.size.height * 0.84).clamp(560.0, 720.0).toDouble();

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
                  top: Radius.circular(32),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF2161921),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      border: Border.all(color: accent.withValues(alpha: 0.34)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.40),
                          blurRadius: 34,
                          offset: const Offset(0, -10),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        child: Column(
                          children: [
                            _Header(
                              accent: accent,
                              showCloseButton: widget.showCloseButton,
                            ),
                            Expanded(
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
                                        icon:
                                            CupertinoIcons.shield_lefthalf_fill,
                                        title: 'Route bleibt Vorschlag',
                                        text:
                                            'Cruise Connector plant Routen. Du prüfst immer selbst, ob Straße, Manöver, Wetter und Situation sicher und erlaubt sind.',
                                        accent: accent,
                                      ),
                                      _NoticeCard(
                                        icon: CupertinoIcons.map_fill,
                                        title: 'Kartendaten können abweichen',
                                        text:
                                            'Sperren, Privatwege, Baustellen, Tempolimits und Anweisungen vor Ort haben immer Vorrang vor der App.',
                                        accent: accent,
                                      ),
                                      _NoticeCard(
                                        icon: CupertinoIcons.hand_raised_fill,
                                        title:
                                            'Nicht während der Fahrt bedienen',
                                        text:
                                            'Plane vor dem Losfahren. Während der Fahrt bleibt das Handy in der Halterung; Änderungen machst du nur sicher im Stand.',
                                        accent: accent,
                                      ),
                                      _NoticeCard(
                                        icon: CupertinoIcons.person_crop_circle,
                                        title: 'Du fährst eigenverantwortlich',
                                        text:
                                            'Fahrstil, Abstand, Tempo und Verkehrsregeln bleiben deine Entscheidung. Die App ersetzt keine Sorgfalt.',
                                        accent: accent,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Scrolle bis zum Ende. Danach erscheint dieser Cruise-Hinweis nicht mehr automatisch.',
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
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                onPressed: _readToBottom ? _accept : null,
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
                                        _readToBottom
                                            ? 'Verstanden'
                                            : 'Erst vollständig lesen',
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
  const _Header({required this.accent, required this.showCloseButton});

  final Color accent;
  final bool showCloseButton;

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
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(CupertinoIcons.car_detailed, color: accent, size: 27),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Routing verstehen',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
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
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E121A).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12.8,
                    height: 1.28,
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
