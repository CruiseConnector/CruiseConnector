import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/auth_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/route_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';
import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:cruise_connect/data/services/notification_settings_service.dart';
import 'package:cruise_connect/data/services/push_notification_service.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/presentation/pages/auth_page.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (kIsWeb) {
        usePathUrlStrategy();
      }

      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
      // Voice-Setting + Notification-Settings beim Start laden
      // (persistiert via SharedPrefs).
      unawaited(VoiceSettingsService.instance.load());
      unawaited(NotificationSettingsService.instance.load());
      unawaited(PoiSettingsService.instance.load());

      // 2026-05-31 (vucko): Push (FCM) nur auf Android/iOS. Firebase ist hier
      // REIN der Push-Kanal (kein Parallelbackend, vgl. codex.md). Der
      // Background-Handler wird intern beim Init registriert; Token-Registrierung
      // + Permission laufen erst nach Login (HomePage).
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await PushNotificationService.instance.ensureFirebaseInitialized();
      }

      runApp(const MyApp());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (e) {
      debugPrint('[DeepLink] initial link Fehler: $e');
    }
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (e) => debugPrint('[DeepLink] stream Fehler: $e'),
    );
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (kDebugMode) {
      debugPrint('[DeepLink] $uri');
    }
    final postId = _postIdFromDeepLink(uri);
    if (postId != null) {
      await Future.delayed(const Duration(milliseconds: 400));
      final post = await SocialService.getPostById(postId);
      final nav = rootNavigatorKey.currentState;
      if (post == null || nav == null) return;
      final profile = post['profiles'] as Map<String, dynamic>?;
      final name = SocialService.publicDisplayName(
        profile,
        fallbackUserId: post['user_id'] as String?,
      );
      final handle = SocialService.publicHandle(
        profile,
        fallbackUserId: post['user_id'] as String?,
      );
      nav.push(
        MaterialPageRoute(
          builder: (_) => PostDetailPage(
            postId: postId,
            name: name,
            handle: handle,
            content: (post['content'] ?? '') as String,
            time: '',
            sharedRouteId: post['shared_route_id'] as String?,
            avatarUrl: profile?['avatar_url'] as String?,
          ),
        ),
      );
    }
  }

  String? _postIdFromDeepLink(Uri uri) {
    final queryPostId = uri.queryParameters['post'] ?? uri.queryParameters['p'];
    if (queryPostId != null && queryPostId.trim().isNotEmpty) {
      return queryPostId.trim();
    }

    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'post') {
      return segments[1];
    }

    if (uri.scheme == 'cruiseconnect' &&
        uri.host == 'post' &&
        segments.isNotEmpty) {
      return segments.first;
    }

    if (uri.host == CruiseDeepLinks.host &&
        segments.length >= 2 &&
        segments[0] == 'post') {
      return segments[1];
    }

    return null;
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        ChangeNotifierProvider(create: (_) => CommunityProvider()),
        ChangeNotifierProvider(create: (_) => SavedRoutesProvider()),
        ChangeNotifierProvider(create: (_) => RouteBookmarkProvider()),
        ChangeNotifierProvider(create: (_) => AppAccentProvider()..load()),
        // 2026-05-23 (vucko): Notification-Service als Provider —
        // Realtime-Subscription wird in HomePage initState gestartet.
        ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService.instance),
      ],
      child: Consumer<AppAccentProvider>(
        builder: (context, accentProvider, _) {
          final accent = accentProvider.color;
          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'Cruise Connector',
            theme: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: accent,
                brightness: Brightness.dark,
                primary: accent,
                secondary: accent,
              ),
              progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? accent
                      : Colors.grey;
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? accent.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.3);
                }),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
            ),
            home: const _CruiseLaunchGate(child: AuthPage()),
          );
        },
      ),
    );
  }
}

class _CruiseLaunchGate extends StatefulWidget {
  const _CruiseLaunchGate({required this.child});

  final Widget child;

  @override
  State<_CruiseLaunchGate> createState() => _CruiseLaunchGateState();
}

class _CruiseLaunchGateState extends State<_CruiseLaunchGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..forward();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(child: _CruiseLaunchScreen(animation: _controller)),
      ],
    );
  }
}

class _CruiseLaunchScreen extends StatelessWidget {
  const _CruiseLaunchScreen({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.sizeOf(context);
    final cardWidth = math.min(size.width * 0.78, 320.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final intro = Curves.easeOutCubic.transform(math.min(t / 0.56, 1));
        final routeProgress = Curves.easeInOutCubic.transform(
          math.min(t / 0.74, 1),
        );
        const fadeStart = 0.78;
        final opacity = t <= fadeStart
            ? 1.0
            : (1 - ((t - fadeStart) / (1 - fadeStart)))
                  .clamp(0.0, 1.0)
                  .toDouble();
        final scan = Curves.easeInOut.transform(math.min(t / 0.95, 1));

        return Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.08, -0.28),
                radius: 1.12,
                colors: [
                  accent.withValues(alpha: 0.30),
                  const Color(0xFF172232),
                  const Color(0xFF080D14),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LaunchRoutePainter(
                      progress: routeProgress,
                      accent: accent,
                      scan: scan,
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - intro)),
                    child: Transform.scale(
                      scale: 0.94 + (0.06 * intro),
                      child: Container(
                        width: cardWidth,
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF121B27,
                          ).withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Color.lerp(
                              Colors.white.withValues(alpha: 0.08),
                              accent.withValues(alpha: 0.55),
                              intro,
                            )!,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.34),
                              blurRadius: 44,
                              spreadRadius: -16,
                              offset: const Offset(0, 24),
                            ),
                            const BoxShadow(
                              color: Color(0xCC000000),
                              blurRadius: 38,
                              offset: Offset(0, 24),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: math.min(cardWidth * 0.72, 238),
                              child: Image.asset(
                                'assets/branding/cruiseconnect_logo_full.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _LaunchStatusPill(accent: accent, progress: scan),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                height: 4,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: math.max(0.08, scan),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              accent.withValues(alpha: 0.35),
                                              accent,
                                              const Color(0xFFFF3737),
                                            ],
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
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LaunchStatusPill extends StatelessWidget {
  const _LaunchStatusPill({required this.accent, required this.progress});

  final Color accent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final dotScale = 0.72 + (0.28 * Curves.easeInOut.transform(progress));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: dotScale,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.8),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Routen werden vorbereitet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchRoutePainter extends CustomPainter {
  const _LaunchRoutePainter({
    required this.progress,
    required this.accent,
    required this.scan,
  });

  final double progress;
  final Color accent;
  final double scan;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.13, size.height * 0.67)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.53,
        size.width * 0.33,
        size.height * 0.79,
        size.width * 0.47,
        size.height * 0.58,
      )
      ..cubicTo(
        size.width * 0.61,
        size.height * 0.36,
        size.width * 0.71,
        size.height * 0.57,
        size.width * 0.87,
        size.height * 0.35,
      );

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawPath(path, basePaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..color = accent.withValues(alpha: 0.42);
    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(accent, const Color(0xFFFF3636), 0.32)!;

    final visiblePath = Path();
    for (final metric in path.computeMetrics()) {
      visiblePath.addPath(
        metric.extractPath(0, metric.length * progress),
        Offset.zero,
      );
    }
    canvas
      ..drawPath(visiblePath, glowPaint)
      ..drawPath(visiblePath, routePaint);

    final pulsePosition = Offset(
      size.width * (0.13 + (0.74 * scan)),
      size.height * (0.67 - (0.32 * Curves.easeInOut.transform(scan))),
    );
    final pulsePaint = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(pulsePosition, 24 + (8 * scan), pulsePaint);
    canvas.drawCircle(
      pulsePosition,
      4.6,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
        stops: const [0.55, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _LaunchRoutePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.scan != scan;
  }
}
