import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/membership_since_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 2026-08-14 (vucko Tutorial-Umbau): 10 passive Schritte → 7 kurze Schritte
/// mit Animationen, zwei INTERAKTIVEN Pflicht-Schritten (Adresse favorisieren,
/// Routensuche starten) und einer Badge-Verleihung mit 125 XP zum Abschluss.
/// „die person muss das interaktiv machen damit sie weiterkommt" — Weiter ist
/// bei den Pflicht-Schritten gesperrt, bis die Aktion in der Attrappe passiert
/// ist. Überspringen bleibt IMMER möglich (bricht ohne Belohnung ab).
Future<void> showAppTutorialOverlay(
  BuildContext context, {
  required ValueChanged<int> onTabChange,
  ValueChanged<int>? onCommunitySectionChange,
}) async {
  if (await AppTutorialService.hasCompleted()) return;
  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return AppTutorialOverlay(
        onTabChange: onTabChange,
        onCommunitySectionChange: onCommunitySectionChange,
      );
    },
  );
}

/// Public für Widget-Tests: Datum und Belohnungspfad sind injizierbar, damit
/// Tests weder Supabase noch echte Vergaben brauchen. Produktion geht immer
/// über [showAppTutorialOverlay] (dort ohne Overrides).
class AppTutorialOverlay extends StatefulWidget {
  const AppTutorialOverlay({
    super.key,
    required this.onTabChange,
    this.onCommunitySectionChange,
    this.loadMemberSince,
    this.claimReward,
    this.initialStepIndex = 0,
  });

  final ValueChanged<int> onTabChange;
  final ValueChanged<int>? onCommunitySectionChange;

  /// Beitrittsdatum-Loader (Default: profiles.created_at via
  /// [MembershipSinceService]). Fallback in der Anzeige: heutiges Datum.
  final Future<DateTime?> Function()? loadMemberSince;

  /// Belohnungspfad beim ECHTEN Abschluss (Default: 125-XP-Vergabe mit
  /// Duplikat-Schutz + calculateAndSync für Badge/Level-Abgleich).
  final Future<void> Function()? claimReward;

  @visibleForTesting
  final int initialStepIndex;

  @override
  State<AppTutorialOverlay> createState() => _AppTutorialOverlayState();
}

class _AppTutorialOverlayState extends State<AppTutorialOverlay> {
  late int _index = widget.initialStepIndex.clamp(0, _steps.length - 1).toInt();

  /// Indizes der interaktiven Schritte, deren Pflicht-Aktion erledigt ist.
  final Set<int> _completedActions = <int>{};

  DateTime? _memberSince;
  bool _rewardTriggered = false;

  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      tab: 0,
      icon: CupertinoIcons.car_detailed,
      title: 'Willkommen bei CruiseConnect',
      body:
          'Routen entdecken, mit Freunden synchron cruisen, Momente teilen. '
          'In einer Minute kennst du alles Wichtige.',
      cta: 'Los geht’s',
      target: _TutorialTarget.none,
      kind: _StepKind.welcome,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.car_detailed,
      title: 'Cruise Mode',
      body:
          'Hier startet jede Fahrt: Stil wählen, Route suchen, losfahren. '
          'Tipp: Halte einen Punkt auf der Karte lange gedrückt, um direkt '
          'dorthin zu cruisen. Starte jetzt eine Routensuche:',
      cta: 'Cruise',
      target: _TutorialTarget.cruise,
      kind: _StepKind.routeSearch,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.person_3_fill,
      title: 'Gruppen: synchron fahren',
      body:
          'Erstell eine Gruppe und lade deine Freunde ein — ihr fahrt '
          'dieselbe Route und seht euch dabei live auf der Karte, wie ein '
          'Konvoi.',
      cta: 'Fahrten',
      target: _TutorialTarget.communityRides,
      communitySection: 1,
      kind: _StepKind.groups,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.news_solid,
      title: 'Feed',
      body:
          'Fahrten, Fotos und Routen von Leuten, denen du folgst — teile '
          'deine besten Cruises direkt nach der Fahrt.',
      cta: 'Feed',
      target: _TutorialTarget.communityFeed,
      communitySection: 0,
      kind: _StepKind.feed,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.search,
      title: 'Entdecken',
      body:
          'Neue Fahrer, Gruppen und Communities außerhalb deiner Kontakte — '
          'hier wächst dein Netzwerk.',
      cta: 'Entdecken',
      target: _TutorialTarget.communityDiscover,
      communitySection: 3,
      kind: _StepKind.discover,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.star_fill,
      title: 'Favoriten',
      body:
          'Lieblingsorte merkst du dir mit dem Stern — sie warten dann in '
          'der Suche auf dich. Tippe die Adresse an und merke sie mit dem '
          'Stern:',
      cta: 'Merken',
      target: _TutorialTarget.none,
      kind: _StepKind.favorite,
    ),
    _TutorialStep(
      tab: 0,
      icon: CupertinoIcons.checkmark_seal_fill,
      title: 'Du bist startklar!',
      body:
          'Als Dankeschön: dein erstes Badge und 125 XP. Das Tutorial '
          'findest du jederzeit in den Einstellungen.',
      cta: 'Fertig',
      target: _TutorialTarget.none,
      kind: _StepKind.completion,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTab());
    unawaited(_loadMemberSince());
  }

  Future<void> _loadMemberSince() async {
    final loader = widget.loadMemberSince ?? MembershipSinceService.load;
    try {
      final since = await loader();
      if (mounted && since != null) setState(() => _memberSince = since);
    } catch (_) {
      // Fallback bleibt: heutiges Datum beim Rendern.
    }
  }

  Future<void> _syncTab() async {
    final step = _steps[_index];
    widget.onTabChange(step.tab);
    final communitySection = step.communitySection;
    if (communitySection != null) {
      widget.onCommunitySectionChange?.call(communitySection);
    }
    await Future<void>.delayed(const Duration(milliseconds: 240));
  }

  /// Überspringen: Tutorial gilt als gesehen, aber KEINE Belohnung — die 125 XP
  /// gibt es nur für den echten Abschluss. Das Badge kommt unabhängig davon
  /// über calculateAndSync (badge_15 wird immer qualifiziert).
  Future<void> _skip() async {
    await AppTutorialService.markCompleted();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Echter Abschluss (letzter Schritt, „Fertig"): markCompleted + Belohnung.
  /// Die Vergabe läuft bewusst unawaited weiter, auch wenn das Overlay schon
  /// zu ist — der Duplikat-Schutz in claimCompletionReward verhindert, dass
  /// ein Replay oder Doppel-Tap eine zweite Vergabe auslöst.
  Future<void> _complete() async {
    await AppTutorialService.markCompleted();
    unawaited(StarterAufgabenService.instance.markiere('tutorial'));
    if (!_rewardTriggered) {
      _rewardTriggered = true;
      final claim =
          widget.claimReward ??
          () async {
            await AppTutorialService.claimCompletionReward();
            await GamificationService.calculateAndSync();
          };
      unawaited(claim());
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      unawaited(_complete());
      return;
    }
    setState(() => _index += 1);
    unawaited(_syncTab());
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index -= 1);
    unawaited(_syncTab());
  }

  void _markActionDone() {
    if (_completedActions.contains(_index)) return;
    setState(() => _completedActions.add(_index));
  }

  bool get _nextEnabled {
    final step = _steps[_index];
    if (!step.kind.requiresAction) return true;
    return _completedActions.contains(_index);
  }

  Widget? _stepExtra(_TutorialStep step, Color accent) {
    switch (step.kind) {
      case _StepKind.welcome:
        return _WelcomeAnimation(accent: accent);
      case _StepKind.routeSearch:
        return _RouteSearchActionCard(
          accent: accent,
          completed: _completedActions.contains(_index),
          onCompleted: _markActionDone,
        );
      case _StepKind.groups:
        return _GroupConvoyAnimation(accent: accent);
      case _StepKind.feed:
        return _FeedCardAnimation(accent: accent);
      case _StepKind.discover:
        return _DiscoverAnimation(accent: accent);
      case _StepKind.favorite:
        return _FavoriteActionCard(
          accent: accent,
          completed: _completedActions.contains(_index),
          onCompleted: _markActionDone,
        );
      case _StepKind.completion:
        return _CompletionCelebration(
          accent: accent,
          memberSince: _memberSince ?? DateTime.now(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final accent = AppAccentColors.accent;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(maxScaleFactor: 1.08),
    );
    final extra = _stepExtra(step, accent);

    return MediaQuery(
      data: clampedMedia,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            _TutorialHighlight(target: step.target, accent: accent),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: 14,
                    child: _Pill(
                      text: '${_index + 1}/${_steps.length}',
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 10,
                    child: TextButton(
                      onPressed: _skip,
                      child: const Text(
                        'Überspringen',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: media.padding.bottom + 112,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xF2161921),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.40),
                                blurRadius: 30,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(step.icon, color: accent),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              step.title,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            step.cta,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  step.body,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 13.6,
                                    height: 1.34,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (extra != null) ...[
                                  const SizedBox(height: 12),
                                  extra,
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 54,
                                      height: 50,
                                      child: IconButton(
                                        onPressed: _index == 0 ? null : _back,
                                        icon: Icon(
                                          CupertinoIcons.chevron_left,
                                          color: _index == 0
                                              ? Colors.white.withValues(
                                                  alpha: 0.20,
                                                )
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 50,
                                        child: FilledButton(
                                          onPressed: _nextEnabled
                                              ? _next
                                              : null,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: accent,
                                            disabledBackgroundColor: accent
                                                .withValues(alpha: 0.28),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: Text(
                                            _index == _steps.length - 1
                                                ? 'Fertig'
                                                : 'Weiter',
                                            style: TextStyle(
                                              color: _nextEnabled
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.55,
                                                    ),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
}

// ---------------------------------------------------------------------------
// Schritt-Animationen (alle ENDLICH — kein repeat, damit pumpAndSettle und
// Akku nicht leiden; der Endzustand bleibt als ruhiges Bild stehen).
// ---------------------------------------------------------------------------

class _WelcomeAnimation extends StatelessWidget {
  const _WelcomeAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutBack,
        builder: (context, t, child) {
          return Transform.scale(
            scale: 0.6 + 0.4 * t,
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          );
        },
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.16),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 22),
            ],
          ),
          child: Icon(CupertinoIcons.car_detailed, color: accent, size: 36),
        ),
      ),
    );
  }
}

class _GroupConvoyAnimation extends StatelessWidget {
  const _GroupConvoyAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Drei „Fahrer" fahren nacheinander ein — Konvoi-Gefühl in einer Zeile.
    return SizedBox(
      height: 52,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Builder(
                  builder: (context) {
                    final local = ((t - i * 0.18) / 0.6).clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(60 * (1 - local), 0),
                      child: Opacity(
                        opacity: local,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.14 + 0.06 * i),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Icon(
                              i == 0
                                  ? CupertinoIcons.car_detailed
                                  : CupertinoIcons.person_fill,
                              color: accent,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FeedCardAnimation extends StatelessWidget {
  const _FeedCardAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Eine Mini-Post-Karte schiebt sich von unten ein.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, 26 * (1 - t)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
              ),
              child: Icon(CupertinoIcons.person_fill, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 8,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(CupertinoIcons.heart_fill, color: accent, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DiscoverAnimation extends StatelessWidget {
  const _DiscoverAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutBack,
        builder: (context, t, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Builder(
                  builder: (context) {
                    final local = ((t - i * 0.22) / 0.55).clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: local,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.40),
                            ),
                          ),
                          child: Icon(
                            switch (i) {
                              0 => CupertinoIcons.person_2_fill,
                              1 => CupertinoIcons.search,
                              _ => CupertinoIcons.map_fill,
                            },
                            color: accent,
                            size: 19,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interaktiver Pflicht-Schritt (a): Adresse antippen + mit Stern merken.
// Reine Overlay-Attrappe — steuert KEINE echten Seiten.
// ---------------------------------------------------------------------------

class _FavoriteActionCard extends StatefulWidget {
  const _FavoriteActionCard({
    required this.accent,
    required this.completed,
    required this.onCompleted,
  });

  final Color accent;
  final bool completed;
  final VoidCallback onCompleted;

  @override
  State<_FavoriteActionCard> createState() => _FavoriteActionCardState();
}

class _FavoriteActionCardState extends State<_FavoriteActionCard> {
  late bool _addressPicked = widget.completed;
  late bool _starred = widget.completed;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suchfeld-Attrappe
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.search,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: 17,
                ),
                const SizedBox(width: 9),
                Text(
                  'Feldkirch',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Vorschlag → nach Tap ausgewählte Zeile mit Stern
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _addressPicked
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _addressPicked
                    ? accent.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: InkWell(
              onTap: _addressPicked
                  ? null
                  : () => setState(() => _addressPicked = true),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.location_solid,
                    color: _addressPicked
                        ? accent
                        : Colors.white.withValues(alpha: 0.55),
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Feldkirch, Vorarlberg',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_addressPicked)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _starred
                          ? null
                          : () {
                              setState(() => _starred = true);
                              widget.onCompleted();
                            },
                      icon: TweenAnimationBuilder<double>(
                        key: ValueKey(_starred),
                        tween: Tween(begin: _starred ? 0.4 : 1.0, end: 1),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutBack,
                        builder: (context, t, child) {
                          return Transform.scale(scale: t, child: child);
                        },
                        child: Icon(
                          _starred
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.star,
                          color: _starred
                              ? const Color(0xFFFFD166)
                              : Colors.white.withValues(alpha: 0.70),
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_starred) ...[
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, t, child) {
                return Transform.scale(
                  scale: t.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: child,
                );
              },
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Color(0xFF4ADE80),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Gemerkt! Findest du ab jetzt in deinen Favoriten.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interaktiver Pflicht-Schritt (b): Routensuche starten (Attrappe mit
// Stil-Chip, kurzer Lade-Animation und „Route gefunden").
// ---------------------------------------------------------------------------

enum _RouteSearchPhase { idle, loading, found }

class _RouteSearchActionCard extends StatefulWidget {
  const _RouteSearchActionCard({
    required this.accent,
    required this.completed,
    required this.onCompleted,
  });

  final Color accent;
  final bool completed;
  final VoidCallback onCompleted;

  @override
  State<_RouteSearchActionCard> createState() => _RouteSearchActionCardState();
}

class _RouteSearchActionCardState extends State<_RouteSearchActionCard> {
  late _RouteSearchPhase _phase = widget.completed
      ? _RouteSearchPhase.found
      : _RouteSearchPhase.idle;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_turn_up_right,
                          color: accent,
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Kurvenjagd',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: FilledButton(
                  onPressed: _phase == _RouteSearchPhase.idle
                      ? () => setState(() => _phase = _RouteSearchPhase.loading)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: accent.withValues(alpha: 0.25),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Route suchen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_phase == _RouteSearchPhase.loading) ...[
            const SizedBox(height: 12),
            // Endlicher Lade-Balken: läuft einmal voll und kippt dann in
            // „Route gefunden" — kein repeat, kein Timer-Leak.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              onEnd: () {
                if (!mounted) return;
                setState(() => _phase = _RouteSearchPhase.found);
                widget.onCompleted();
              },
              builder: (context, t, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: t,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Suche die kurvigste Strecke…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.60),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_phase == _RouteSearchPhase.found) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                builder: (context, t, _) {
                  return CustomPaint(painter: _MiniRoutePainter(progress: t));
                },
              ),
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, t, child) {
                return Transform.scale(
                  scale: t.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: child,
                );
              },
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Color(0xFF4ADE80),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Route gefunden — 42 km, 87 Kurven!',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zeichnet eine kleine geschwungene Route, die sich mit [progress] von links
/// nach rechts aufbaut (grün = gefunden), samt Start- und Zielpunkt.
class _MiniRoutePainter extends CustomPainter {
  const _MiniRoutePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(6, size.height * 0.78)
      ..cubicTo(
        size.width * 0.28,
        size.height * 1.05,
        size.width * 0.34,
        -size.height * 0.15,
        size.width * 0.62,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.80,
        size.height * 0.78,
        size.width * 0.88,
        size.height * 0.30,
        size.width - 8,
        size.height * 0.22,
      );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0, 1));

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4ADE80),
    );

    // Startpunkt
    canvas.drawCircle(
      Offset(6, size.height * 0.78),
      5,
      Paint()..color = Colors.white,
    );
    // Zielpunkt erst, wenn die Linie angekommen ist
    if (progress >= 0.98) {
      canvas.drawCircle(
        Offset(size.width - 8, size.height * 0.22),
        5,
        Paint()..color = const Color(0xFF4ADE80),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniRoutePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ---------------------------------------------------------------------------
// Abschluss: Badge-Verleihung mit Skalier-/Glow-Animation, „Dabei seit"-Datum
// und +125-XP-Zähler.
// ---------------------------------------------------------------------------

class _CompletionCelebration extends StatelessWidget {
  const _CompletionCelebration({
    required this.accent,
    required this.memberSince,
  });

  final Color accent;
  final DateTime memberSince;

  @override
  Widget build(BuildContext context) {
    final badge = app.Badge.getById(app.Badge.membershipBadgeId);

    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 950),
          curve: Curves.easeOutBack,
          builder: (context, t, child) {
            final clamped = t.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 0.35 + 0.65 * t,
              child: Opacity(
                opacity: clamped,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.55 * clamped),
                        blurRadius: 18 + 22 * clamped,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: const Color(
                          0xFFFFD76A,
                        ).withValues(alpha: 0.35 * clamped),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: badge?.assetPath != null
              ? Image.asset(badge!.assetPath!, fit: BoxFit.contain)
              : Center(
                  child: Text(
                    badge?.emoji ?? '\u{1F31F}',
                    style: const TextStyle(fontSize: 52),
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Text(
          badge?.name ?? 'Gründungszeit',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Text(
            'Dabei seit ${app.Badge.formatMonthYearDe(memberSince)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: AppTutorialService.completionXp),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) {
            return Text(
              '+$value XP',
              style: TextStyle(
                color: accent,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Spotlight (unverändertes Prinzip: Bottom-Nav/Community-Tabs ausleuchten)
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TutorialHighlight extends StatelessWidget {
  const _TutorialHighlight({required this.target, required this.accent});

  final _TutorialTarget target;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _TutorialSpotlightPainter(target: target, accent: accent),
        ),
      ),
    );
  }
}

class _TutorialSpotlightPainter extends CustomPainter {
  const _TutorialSpotlightPainter({required this.target, required this.accent});

  final _TutorialTarget target;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final spotlight = _spotlightFor(size);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.70);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, dim);
    if (spotlight != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlight, const Radius.circular(24)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();

    if (spotlight == null) return;
    final outer = RRect.fromRectAndRadius(
      spotlight.inflate(3),
      const Radius.circular(27),
    );
    canvas
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = accent.withValues(alpha: 0.78),
      )
      ..drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
          ..color = accent.withValues(alpha: 0.28),
      );
  }

  Rect? _spotlightFor(Size size) {
    final width = size.width;
    final height = size.height;

    Rect communityTabTarget(double xFactor, double targetWidth) {
      return Rect.fromCenter(
        center: Offset(width * xFactor, 143),
        width: targetWidth,
        height: 46,
      );
    }

    return switch (target) {
      _TutorialTarget.communityFeed => communityTabTarget(0.125, 90),
      _TutorialTarget.communityRides => communityTabTarget(0.365, 104),
      _TutorialTarget.communityDiscover => communityTabTarget(0.84, 108),
      _TutorialTarget.cruise => Rect.fromCenter(
        center: Offset(width * 0.50, height - 72),
        width: 104,
        height: 104,
      ),
      _TutorialTarget.none => null,
    };
  }

  @override
  bool shouldRepaint(covariant _TutorialSpotlightPainter oldDelegate) {
    return oldDelegate.target != target || oldDelegate.accent != accent;
  }
}

enum _StepKind {
  welcome,
  routeSearch,
  groups,
  feed,
  discover,
  favorite,
  completion;

  bool get requiresAction =>
      this == _StepKind.routeSearch || this == _StepKind.favorite;
}

class _TutorialStep {
  const _TutorialStep({
    required this.tab,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.target,
    required this.kind,
    this.communitySection,
  });

  final int tab;
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final _TutorialTarget target;
  final _StepKind kind;
  final int? communitySection;
}

enum _TutorialTarget {
  communityFeed,
  communityRides,
  communityDiscover,
  cruise,
  none,
}
