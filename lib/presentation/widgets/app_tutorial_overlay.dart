import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
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
///
/// 2026-08-19 (vucko): „schau das das tutorial wirklich die ganze app
/// erklaert". GEMESSEN am 19.08. im 7-Schritt-Fluss: erklärt wurden der
/// Cruise-Knopf und drei der vier Community-Reiter. NICHT erklärt, obwohl
/// vorhanden: der Reiter „Chats" (Communities), Analytics (Reiter 3), Profil
/// (Reiter 4) samt Garage, die Startseite selbst (Schritt 1 und 7 liefen
/// dort, zeigten aber auf nichts) und alles, was NACH der Fahrt passiert
/// (Fahrt beenden, Foto, Speichern, XP). Die Einstellungen versprachen im
/// Untertitel „Home, Community, Cruise, Analytics und Profil" — zwei davon
/// kamen gar nicht vor.
///
/// JETZT: 12 Schritte, jeder Reiter der App kommt vor (0 Home, 1 Community
/// mit allen vier Unterreitern, 2 Cruise, 3 Analytics, 4 Profil). Die
/// Reihenfolge folgt den Reitern (0, 2, 1, 3, 4, 0), damit nicht bei jedem
/// Schritt hin- und hergesprungen wird.
///
/// EHRLICHKEIT der beiden Pflicht-Schritte: Sie sind Attrappen IM Overlay und
/// lösen KEINE echte Aktion aus (das Overlay liegt modal über der Seite).
/// Gemessen: nach dem Tutorial ist genau 1 von 5 Starter-Aufgaben erledigt,
/// obwohl der Nutzer glaubte, gerade zwei davon gemacht zu haben. Die Texte
/// sagen deshalb ausdrücklich, dass es Übungen sind und die Aufgabe erst in
/// der echten App abgehakt wird. Die Attrappen bleiben Attrappen.
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

  /// Der Fluss durch die ganze App. Reihenfolge nach Reitern:
  /// Home (0) → Cruise (2) → Community (1, alle vier Unterreiter) →
  /// Analytics (3) → Profil (4) → Home (0).
  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      tab: 0,
      icon: CupertinoIcons.car_detailed,
      title: 'Willkommen bei CruiseConnect',
      body:
          'Routen entdecken, mit Freunden synchron cruisen, Momente teilen. '
          'Wir gehen jetzt einmal durch die ganze App.',
      cta: 'Los geht’s',
      target: _TutorialTarget.none,
      kind: _StepKind.welcome,
    ),
    _TutorialStep(
      tab: 0,
      icon: CupertinoIcons.house_fill,
      title: 'Deine Startseite',
      body:
          'Hier landest du bei jedem Start. Oben wartet dein Starterpaket '
          'mit fünf kleinen Aufgaben, die dir eine Woche doppelte XP '
          'freischalten. Darunter zeigen die Kacheln Level, XP, Kilometer, '
          'Streak und deine Woche. Welche Kacheln du siehst, bestimmst du '
          'selbst über „Home bearbeiten".',
      cta: 'Home',
      target: _TutorialTarget.homeStarter,
      kind: _StepKind.homeStart,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.car_detailed,
      title: 'Cruise Mode',
      body:
          'Hier startet jede Fahrt: Stil wählen, Route suchen, losfahren. '
          'Tipp: Halte einen Punkt auf der Karte lange gedrückt, um direkt '
          'dorthin zu cruisen. Probier die Suche hier am Beispiel aus:',
      cta: 'Cruise',
      target: _TutorialTarget.cruise,
      kind: _StepKind.routeSearch,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.star_fill,
      title: 'Favoriten',
      body:
          'Lieblingsorte merkst du dir mit dem Stern, dann warten sie in der '
          'Zielsuche auf dich. So sieht das aus:',
      cta: 'Merken',
      target: _TutorialTarget.none,
      kind: _StepKind.favorite,
    ),
    _TutorialStep(
      tab: 2,
      icon: CupertinoIcons.flag_fill,
      title: 'Nach der Fahrt',
      body:
          'Unterwegs sagt dir das Banner oben jede Abbiegung an. Am Ende '
          'tippst du auf „Fahrt beenden": Du siehst Distanz, Dauer, Kurven '
          'und Höchstgeschwindigkeit, kannst ein Foto anhängen und die Fahrt '
          'benennen. Erst mit „Speichern" wandern Kilometer, XP und Streak in '
          'dein Profil.',
      cta: 'Vorschau',
      target: _TutorialTarget.none,
      kind: _StepKind.afterRide,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.person_3_fill,
      title: 'Gruppen & Fahrten',
      body:
          'Hinter diesem Reiter erstellst du eine Gruppe und lädst deine '
          'Freunde ein. Ihr fahrt dieselbe Route und seht euch dabei live '
          'auf der Karte wie ein Konvoi.',
      cta: 'Gruppen & Fahrten',
      target: _TutorialTarget.communityRides,
      communitySection: 1,
      kind: _StepKind.groups,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.news_solid,
      title: 'Feed',
      body:
          'Fahrten, Fotos und Routen von Leuten, denen du folgst. Deine '
          'besten Cruises teilst du direkt nach der Fahrt.',
      cta: 'Feed',
      target: _TutorialTarget.communityFeed,
      communitySection: 0,
      kind: _StepKind.feed,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.chat_bubble_2_fill,
      title: 'Chats',
      body:
          'Hier liegen deine Communities: eine eigene gründen, mit einem '
          'Code beitreten oder einer öffentlichen folgen. Jede Community hat '
          'ihren eigenen Chat für die Absprache vor der Ausfahrt.',
      cta: 'Chats',
      target: _TutorialTarget.communityChats,
      communitySection: 2,
      kind: _StepKind.chats,
    ),
    _TutorialStep(
      tab: 1,
      icon: CupertinoIcons.search,
      title: 'Entdecken',
      body:
          'Neue Fahrer, Gruppen und Communities außerhalb deiner Kontakte. '
          'Hier wächst dein Netzwerk.',
      cta: 'Entdecken',
      target: _TutorialTarget.communityDiscover,
      communitySection: 3,
      kind: _StepKind.discover,
    ),
    _TutorialStep(
      tab: 3,
      icon: CupertinoIcons.chart_bar_alt_fill,
      title: 'Analytics',
      body:
          'Dein Fortschritt in Zahlen: Level und XP, Fahrten, Distanz und '
          'Fahrzeit, deine Streak, die Meilensteine deiner Badges und die '
          'Rangliste für Woche und Monat.',
      cta: 'Analytics',
      target: _TutorialTarget.analytics,
      kind: _StepKind.analytics,
    ),
    _TutorialStep(
      tab: 4,
      icon: CupertinoIcons.person_crop_circle_fill,
      title: 'Profil & Garage',
      body:
          'Dein Profil sammelt Posts, Reposts, gespeicherte Routen und '
          'Gruppen. Über „Profil bearbeiten" öffnest du „Meine Garage" und '
          'stellst dort deine Autos mit Bild, PS und Baujahr vor.',
      cta: 'Profil',
      target: _TutorialTarget.profilGarage,
      kind: _StepKind.profile,
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
    // Die Zielseite ist jetzt gebaut und gelayoutet: einmal nachzeichnen,
    // damit der Spotlight die GEMESSENE Position bekommt und nicht die vom
    // Moment des Schrittwechsels (dort war der Reiter evtl. noch nicht da).
    if (mounted) setState(() {});
    // Und ein zweites Mal nach dem naechsten Frame — die TabBar-Animation
    // ist dann sicher fertig.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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
      case _StepKind.homeStart:
        return _HomeStartAnimation(accent: accent);
      case _StepKind.routeSearch:
        return _RouteSearchActionCard(
          accent: accent,
          completed: _completedActions.contains(_index),
          onCompleted: _markActionDone,
        );
      case _StepKind.afterRide:
        return _AfterRidePreview(accent: accent);
      case _StepKind.groups:
        return _GroupConvoyAnimation(accent: accent);
      case _StepKind.feed:
        return _FeedCardAnimation(accent: accent);
      case _StepKind.chats:
        return _ChatsAnimation(accent: accent);
      case _StepKind.discover:
        return _DiscoverAnimation(accent: accent);
      case _StepKind.analytics:
        return _AnalyticsAnimation(accent: accent);
      case _StepKind.profile:
        return _GarageAnimation(accent: accent);
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

/// 2026-08-19 (vucko: „schau das das tutorial wirklich die ganze app
/// erklaert"): Die Startseite hatte keinen eigenen Schritt. Schritt 1 und 7
/// liefen dort, zeigten aber auf nichts. Diese Skizze zeigt die zwei Dinge,
/// die dort wirklich stehen: das Starter-Paket und die Fortschritts-Kacheln.
/// Der Zähler steht bewusst auf „0 von 5" — im Overlay ist noch nichts
/// erledigt, und genau das soll die Skizze auch sagen.
class _HomeStartAnimation extends StatelessWidget {
  const _HomeStartAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.gift_fill, color: accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dein Starterpaket',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '0 von 5',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniKachel(
                accent: accent,
                icon: CupertinoIcons.bolt_fill,
                titel: 'XP & Level',
              ),
              const SizedBox(width: 8),
              _MiniKachel(
                accent: accent,
                icon: CupertinoIcons.flame_fill,
                titel: 'Streak',
              ),
              const SizedBox(width: 8),
              _MiniKachel(
                accent: accent,
                icon: CupertinoIcons.speedometer,
                titel: 'Woche',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniKachel extends StatelessWidget {
  const _MiniKachel({
    required this.accent,
    required this.icon,
    required this.titel,
  });

  final Color accent;
  final IconData icon;
  final String titel;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                titel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2026-08-19 (vucko): Was NACH der Fahrt passiert, kam im Tutorial nicht vor.
/// Bewusst eine Vorschau ohne Knöpfe: Das Overlay kann keine Fahrt starten,
/// und eine Attrappe, die so tut, wäre gelogen. Die drei Karten zeigen nur
/// die Reihenfolge, die der Nutzer später wirklich sieht.
class _AfterRidePreview extends StatelessWidget {
  const _AfterRidePreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const schritte = [
      (CupertinoIcons.stop_circle_fill, 'Fahrt\nbeenden'),
      (CupertinoIcons.camera_fill, 'Foto &\nTitel'),
      (CupertinoIcons.tray_arrow_down_fill, 'Speichern\n+ XP'),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < schritte.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Opacity(
                        opacity: ((t - i * 0.22) / 0.4).clamp(0.0, 1.0),
                        child: Icon(
                          CupertinoIcons.chevron_right,
                          color: Colors.white.withValues(alpha: 0.40),
                          size: 14,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Opacity(
                      opacity: ((t - i * 0.22) / 0.5).clamp(0.0, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(schritte[i].$1, color: accent, size: 18),
                            const SizedBox(height: 5),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                schritte[i].$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.80),
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Nur eine Vorschau. Deine erste echte Fahrt startest du gleich '
              'selbst im Cruise Mode.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 2026-08-19 (vucko): Der Reiter „Chats" war der einzige Community-Reiter
/// ohne Schritt, obwohl sein Registry-Schlüssel längst gemeldet war
/// (community_page.dart:485).
class _ChatsAnimation extends StatelessWidget {
  const _ChatsAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        Widget blase({
          required bool links,
          required double breite,
          required double verzoegerung,
        }) {
          final local = ((t - verzoegerung) / 0.5).clamp(0.0, 1.0);
          return Opacity(
            opacity: local,
            child: Transform.translate(
              offset: Offset((links ? -24 : 24) * (1 - local), 0),
              child: Align(
                alignment: links ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: breite,
                  height: 22,
                  decoration: BoxDecoration(
                    color: links
                        ? Colors.white.withValues(alpha: 0.09)
                        : accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            blase(links: true, breite: 150, verzoegerung: 0),
            const SizedBox(height: 6),
            blase(links: false, breite: 110, verzoegerung: 0.25),
            const SizedBox(height: 6),
            blase(links: true, breite: 90, verzoegerung: 0.5),
          ],
        );
      },
    );
  }
}

/// 2026-08-19 (vucko): Analytics (Reiter 3) kam im Tutorial überhaupt nicht
/// vor, obwohl die Einstellungen es im Untertitel versprachen.
class _AnalyticsAnimation extends StatelessWidget {
  const _AnalyticsAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const hoehen = [0.35, 0.55, 0.45, 0.80, 0.62, 0.95, 0.72];
    return SizedBox(
      height: 56,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 950),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < hoehen.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    width: 14,
                    height:
                        56 * hoehen[i] * ((t - i * 0.08) / 0.6).clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.35 + 0.07 * i),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 2026-08-19 (vucko): Profil (Reiter 4) und „Meine Garage" fehlten komplett.
class _GarageAnimation extends StatelessWidget {
  const _GarageAnimation({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final clamped = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.scale(scale: 0.7 + 0.3 * clamped, child: child),
        );
      },
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Icon(CupertinoIcons.person_fill, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.car_detailed, color: accent, size: 20),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Meine Garage',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.plus_circle_fill,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interaktiver Pflicht-Schritt (a): Adresse antippen + mit Stern merken.
// Reine Overlay-Attrappe, steuert KEINE echten Seiten.
//
// 2026-08-19 (vucko: „schau das das tutorial wirklich die ganze app
// erklaert"): Der Erfolgstext hiess „Gemerkt! Findest du ab jetzt in deinen
// Favoriten." Das war schlicht falsch: Es wird nichts gespeichert, und die
// Starter-Aufgabe „Eine Adresse merken" bleibt offen. Gemessen: nach dem
// Tutorial ist 1 von 5 Starter-Aufgaben erledigt (nur „tutorial"), obwohl der
// Nutzer glaubte, zwei gemacht zu haben. Die Attrappe bleibt, der Text sagt
// jetzt die Wahrheit.
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
                      'So sieht ein gemerkter Ort aus. Das war eine Übung: '
                      'Deinen ersten echten Favoriten setzt du in der '
                      'Zielsuche, dann hakt sich auch die Aufgabe im '
                      'Starterpaket ab.',
                      maxLines: 4,
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
// Stil-Chip, kurzer Lade-Animation und Beispielroute).
//
// 2026-08-19 (vucko: „schau das das tutorial wirklich die ganze app
// erklaert"): Stand vorher „Route gefunden, 42 km, 87 Kurven!" da, als wäre
// wirklich gesucht worden. Es wird nichts gesucht und nichts gespeichert; die
// Starter-Aufgabe „Eine Route suchen" bleibt offen. Text entsprechend
// entschärft, Attrappe bleibt Attrappe (das Overlay liegt modal über der
// Seite und kann die echte Suche nicht auslösen).
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
                      'Beispielroute: 42 km, 87 Kurven. Deine echte Suche '
                      'startest du gleich selbst im Cruise Mode, dann zählt '
                      'auch die Aufgabe im Starterpaket.',
                      maxLines: 4,
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

    // 2026-08-15 (vucko, Screenshots 17:14): „inakkurat positioniert". Die
    // festen Zahlen unten (143, height-72) stimmten nur auf einem Geraet.
    // Jetzt zuerst die ECHTE Position aus der Registry — der Schaetzwert
    // bleibt nur als Rueckfall, falls das Ziel noch nicht gebaut ist.
    Rect? gemessen(String ziel, {double aufblasen = 8}) =>
        TutorialZielRegistry.rect(ziel, aufblasen: aufblasen);

    return switch (target) {
      _TutorialTarget.communityFeed =>
        gemessen(TutorialZielRegistry.communityFeed) ??
            communityTabTarget(0.125, 90),
      _TutorialTarget.communityRides =>
        gemessen(TutorialZielRegistry.communityRides) ??
            communityTabTarget(0.365, 104),
      // 2026-08-19 (vucko): Der Reiter „Chats" war in der Registry gemeldet,
      // aber kein Schritt zeigte je darauf. Schätzwert: dritter von vier
      // gleich breiten Reitern.
      _TutorialTarget.communityChats =>
        gemessen(TutorialZielRegistry.communityChats) ??
            communityTabTarget(0.615, 96),
      _TutorialTarget.communityDiscover =>
        gemessen(TutorialZielRegistry.communityDiscover) ??
            communityTabTarget(0.84, 108),
      // Diese drei Ziele hängen noch an KEINEM Widget (Startseite, Analytics
      // und Profil sind fremde Dateien). Ohne Meldung bleibt der Ring aus und
      // die Seite liegt einfach abgedunkelt hinter der Karte. Sobald der Key
      // dort gesetzt wird, leuchtet der Ring ohne Änderung an dieser Stelle.
      _TutorialTarget.homeStarter => gemessen(
        TutorialZielRegistry.starterKarte,
        aufblasen: 10,
      ),
      _TutorialTarget.analytics => gemessen(
        TutorialZielRegistry.analyticsUebersicht,
        aufblasen: 10,
      ),
      _TutorialTarget.profilGarage => gemessen(
        TutorialZielRegistry.profilGarage,
        aufblasen: 10,
      ),
      _TutorialTarget.cruise =>
        gemessen(TutorialZielRegistry.cruiseKnopf, aufblasen: 12) ??
            Rect.fromCenter(
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
  homeStart,
  routeSearch,
  favorite,
  afterRide,
  groups,
  feed,
  chats,
  discover,
  analytics,
  profile,
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
  communityChats,
  communityDiscover,
  cruise,
  homeStarter,
  analytics,
  profilGarage,
  none,
}
