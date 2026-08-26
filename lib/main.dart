import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/app_locale_provider.dart';
import 'package:cruise_connect/core/l10n_extension.dart';
import 'package:cruise_connect/l10n/app_localizations.dart';
import 'package:cruise_connect/presentation/pages/language_choice_page.dart';
import 'package:cruise_connect/application/providers/auth_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/route_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/core/legal_documents.dart';
import 'package:cruise_connect/data/services/analytics_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';
import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:cruise_connect/data/services/notification_settings_service.dart';
import 'package:cruise_connect/data/services/push_notification_service.dart';
import 'package:cruise_connect/data/services/app_speicher_wache.dart';
import 'package:cruise_connect/data/services/offline_fahrten_warteschlange.dart';
import 'package:cruise_connect/data/services/camera_settings_service.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/presentation/pages/auth_page.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/widgets/force_update_gate.dart';
import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';
import 'package:cruise_connect/presentation/pages/group_join_gate.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/utils/legal_link_launcher.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 2026-06-25 (vucko): App NUR im Hochformat — Querformat verzerrt Karte,
      // Navi-Banner und Startscreen. Greift auf iOS + Android (zusätzlich hart
      // im AndroidManifest + Info.plist verankert, falls dieser Call zu spät
      // käme). portraitDown erlaubt, damit „auf dem Kopf" kein schwarzer Rand
      // bleibt, aber kein Landscape.
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // 2026-06-15 (vucko M5 „Die App darf NIEMALS crashen"): Globale Dart-
      // Fehler-Auffangnetze. runZonedGuarded fängt nur asynchrone Zonen-Fehler;
      // diese hier fangen ZUSÄTZLICH:
      //  • Framework-Fehler (Build/Layout/Paint) → nur loggen, kein Re-Throw.
      //  • Fehler aus Futures/Plattform-Callbacks außerhalb der Zone.
      //  • Build-Fehler eines Widgets → dezentes Fallback statt rotem/grauem
      //    Vollbild; der Rest der App bleibt bedienbar.
      // (Native Crashes wie MapLibre-SIGABRT/OOM kann Dart NICHT abfangen — die
      //  werden separat an der Quelle entschärft, siehe Cruise-End-Flow.)
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        if (kDebugMode) {
          debugPrint('[GlobalError] ${details.exceptionAsString()}');
        }
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        debugPrint('[GlobalError/platform] $error');
        return true; // als behandelt markieren → kein Prozess-Abbruch
      };
      ErrorWidget.builder = (FlutterErrorDetails details) {
        if (kDebugMode) return ErrorWidget(details.exception);
        return const _SafeErrorFallback();
      };

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
      unawaited(CameraSettingsService.instance.load());
      // 2026-08-12: Gibt im Hintergrund den Bildspeicher frei, damit Android
      // die App nicht wegen Speichermangel abschiesst (auf Vuckos Samsung
      // fuenfmal als reason=3 LOW_MEMORY nachgewiesen). Muss HIER stehen und
      // nicht auf einer Seite: Der Cruise-Tab wird erst beim ersten Besuch
      // gebaut, ein Behandler dort liefe auf der Startseite nie.
      AppSpeicherWache.instance.starten();
      // 2026-08-26 (Nutzerbericht "50 % meiner Fahrten kommen nicht an"):
      // Fahrten, die im Funkloch nicht gebucht werden konnten, nachtragen.
      // Muss HIER stehen und nicht in der Fahransicht: Wer nach der Fahrt die
      // App schliesst und sie zu Hause im WLAN wieder oeffnet, landet auf der
      // Startseite - die Fahransicht wird dabei nie gebaut.
      OfflineFahrtenWarteschlange.starteNetzWache();
      MapStyleService.instance.ensureAutoDownloadScheduled(
        delay: const Duration(seconds: 10),
        reason: 'app_start',
      );

      // 2026-05-31 (vucko): Push (FCM) nur auf Android/iOS. Firebase ist hier
      // REIN der Push-Kanal (kein Parallelbackend, vgl. codex.md). Der
      // Background-Handler wird intern beim Init registriert; Token-Registrierung
      // + Permission laufen erst nach Login (HomePage).
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await PushNotificationService.instance.ensureFirebaseInitialized();

        // 2026-07-02 (vucko Monitoring): Crashlytics fängt ab hier ZUSÄTZLICH
        // zu den obigen debugPrint-Handlern jeden Flutter- und Plattform-Fehler
        // ein und schickt ihn an Firebase (Crashlytics-Dashboard) — Analytics
        // trackt Nutzerzahlen/Sitzungsdauer automatisch (siehe navigatorObservers
        // unten) + gezielte Funnel-Events (AnalyticsService).
        FlutterError.onError = (FlutterErrorDetails details) {
          FlutterError.presentError(details);
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
          if (kDebugMode) {
            debugPrint('[GlobalError] ${details.exceptionAsString()}');
          }
        };
        WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            fatal: true,
          );
          debugPrint('[GlobalError/platform] $error');
          return true;
        };
      }

      // 2026-08-23 (vucko, Sprachnachricht: „ueber die Glocke bzw. ueber den
      // Quicklink dann joinen will [...] dass ein Fehler kommt"): Der
      // Gruppen-Einstieg und der Benachrichtigungs-Router brauchen einen
      // Navigator, auch wenn sie aus einer getippten Push kommen, wo es keinen
      // BuildContext gibt. Muss VOR runApp gesetzt sein, weil eine Push die App
      // aus dem kalten Zustand starten kann.
      GruppenEinstieg.rootNavigatorSchluessel = rootNavigatorKey;

      runApp(const MyApp());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

/// 2026-06-15 (vucko M5): Dezentes Fallback statt rotem/grauem Crash-Screen,
/// wenn ein Widget beim Bauen wirft. Die App lebt weiter, der User kann
/// zurück/erneut — niemals ein toter Bildschirm.
class _SafeErrorFallback extends StatelessWidget {
  const _SafeErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1017),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.refresh_rounded, color: Color(0xFF8A93A6), size: 34),
          SizedBox(height: 12),
          Text(
            'Kurz hakte etwas. Bitte zurück und erneut versuchen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB6BDC9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
    _horcheAufAnmeldung();
  }

  /// 2026-08-23 (vucko, Sprachnachricht: „wenn er eine Gruppe erstellt hat und
  /// er einen anderen einlaedt [...] dass ein Fehler kommt"): Ein
  /// Einladungslink ist dafuer da, NEUE Leute zu holen. Genau die sind beim
  /// Antippen nicht angemeldet. Bisher war der Link damit verbrannt: main.dart
  /// merkte sich nichts, in ganz `lib/` gab es keinen gespeicherten Deep-Link.
  /// Jetzt wird er gemerkt und nach der Anmeldung genau einmal eingeloest.
  void _horcheAufAnmeldung() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (zustand) {
        final ereignis = zustand.event;
        final relevant = ereignis == AuthChangeEvent.signedIn ||
            ereignis == AuthChangeEvent.initialSession;
        if (!relevant || zustand.session == null) return;
        unawaited(_holeEinladungNach());
      },
      onError: (e) => debugPrint('[DeepLink] auth stream Fehler: $e'),
    );
  }

  Future<void> _holeEinladungNach() async {
    await _wartAufNavigator();
    await GruppenEinstieg.holeGemerktenLinkNach();
  }

  /// Kaltstart: `getInitialLink` liefert den Link, bevor der Navigator
  /// existiert. Die alten festen 400 ms waren geraten; auf einem langsamen
  /// Geraet mit Update-Tor und Rechts-Tor davor reichen sie nicht, und der
  /// Link ging still verloren. Jetzt wird gewartet, bis wirklich ein Navigator
  /// da ist.
  Future<void> _wartAufNavigator({
    Duration hoechstens = const Duration(seconds: 15),
  }) async {
    final ende = DateTime.now().add(hoechstens);
    while (rootNavigatorKey.currentState == null &&
        DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    // Kurz Luft lassen, damit Update-Tor und Rechts-Tor zuerst aufbauen.
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
    if (_isAuthDeepLink(uri)) {
      unawaited(_handleAuthDeepLinkFeedback(uri));
      return;
    }
    final legalDocument = LegalDocuments.fromLegalDeepLink(uri);
    if (legalDocument != null) {
      unawaited(launchLegalDocument(legalDocument));
      return;
    }
    // 2026-07-03 (vucko Gruppen-Share): Gruppen-Deeplink (?group=<id>).
    // 2026-08-23 (vucko, Sprachnachricht: „ueber den Quicklink dann joinen
    // will [...] dass ein Fehler kommt"): Hier stand ein stummes `return;`.
    // Lieferte `groupExists` false — was bei einer privaten Gruppe IMMER der
    // Fall war, weil die Lesepolitik keinen Zweig fuer Eingeladene kennt —,
    // passierte gar nichts: kein Bildschirm, keine Meldung, kein Hinweis. Der
    // Quicklink war fuer genau den Zweck, fuer den er gebaut wurde (jemanden
    // einladen), unbrauchbar. Jetzt derselbe Weg wie die Glocke, inklusive
    // ehrlicher Meldung in jedem Fehlerfall.
    final groupId = CruiseDeepLinks.gruppenIdAus(uri);
    if (groupId != null) {
      await _wartAufNavigator();
      await GruppenEinstieg.oeffnen(groupId);
      return;
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
            sharedGroupId: post['shared_group_id'] as String?,
            avatarUrl: profile?['avatar_url'] as String?,
          ),
        ),
      );
    }
  }

  bool _isAuthDeepLink(Uri uri) {
    return uri.fragment.contains('access_token') ||
        uri.fragment.contains('error_description') ||
        uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error') ||
        (uri.scheme == 'cruiseconnect' && uri.host == 'auth');
  }

  Future<void> _handleAuthDeepLinkFeedback(Uri uri) async {
    // 2026-06-25 (vucko): OAuth-Rückweg (Google-Browser-Flow auf Android) MUSS
    // den Code/Token aus der Callback-URL EXPLIZIT gegen eine Session tauschen.
    // Vorher verließ sich der Handler nur auf das implizite Auto-Handling von
    // supabase_flutter — das konkurriert mit unserem eigenen app_links-Listener
    // (beide hören auf uriLinkStream) und der externalApplication-Browser kann
    // die App zwischendrin verdrängen. Folge: nach dem Google-Login kam die
    // Session NIE an („Anmeldung geht nicht" auf Android). Der explizite
    // getSessionFromUrl macht den Tausch deterministisch.
    if (Supabase.instance.client.auth.currentSession == null &&
        (uri.queryParameters.containsKey('code') ||
            uri.fragment.contains('access_token'))) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (e) {
        // Wirft, wenn das SDK den Code bereits eingelöst hat (dann ist die
        // Session ohnehin gesetzt) ODER bei echtem Fehler (Code ungültig/abgelaufen).
        debugPrint('[Auth] getSessionFromUrl: $e');
      }
    } else {
      // E-Mail-Bestätigung o.ä. ohne Code in der URL → SDK kurz arbeiten lassen.
      await Future.delayed(const Duration(milliseconds: 600));
    }
    final session = Supabase.instance.client.auth.currentSession;
    final nav = rootNavigatorKey.currentState;
    final context = rootNavigatorKey.currentContext;

    if (session != null && nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LegalGatePage(child: PostAuthGate()),
        ),
        (route) => false,
      );
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anmeldung bestätigt. Willkommen!')),
        );
      }
      return;
    }

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anmeldelink empfangen. Falls du nicht eingeloggt bist, bitte erneut versuchen.',
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
    _authSub?.cancel();
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
        // 2026-08-03 (vucko Sprachumschaltung): Deutsch/English.
        ChangeNotifierProvider(create: (_) => AppLocaleProvider()..load()),
        // 2026-05-23 (vucko): Notification-Service als Provider —
        // Realtime-Subscription wird in HomePage initState gestartet.
        ChangeNotifierProvider<NotificationService>.value(
          value: NotificationService.instance,
        ),
      ],
      child: Consumer2<AppAccentProvider, AppLocaleProvider>(
        builder: (context, accentProvider, localeProvider, _) {
          final accent = accentProvider.color;
          return MaterialApp(
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            // Übersetzungen für Code ohne BuildContext (Services) bereitstellen,
            // sobald der Baum steht bzw. die Sprache wechselt.
            // 2026-08-12: Das Update-Tor liegt hier und NICHT mehr in `home`.
            //
            // Als `home` war es eine Route IM Navigator — und alles, was per
            // push/pushAndRemoveUntil dazukommt (Gruppen-Deeplink, Ruecksprung
            // nach der Anmeldung), legt sich UEBER eine Route. Die Sperre war
            // damit umgehbar. Im builder liegt sie als Deckel ueber dem
            // gesamten Navigator: Jeder push landet darunter.
            builder: (context, child) {
              L10n.update(AppLocalizations.of(context));
              return ForceUpdateGate(
                child: child ?? const SizedBox.shrink(),
              );
            },
            navigatorKey: rootNavigatorKey,
            // Trackt jeden Seitenwechsel automatisch als "screen_view"
            // (Basis für Sitzungsdauer/Screen-Nutzung in Firebase Analytics).
            navigatorObservers: kIsWeb
                ? const []
                : [AnalyticsService.instance.observer],
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
            home: const _CruiseLaunchGate(
              child: _LanguageChoiceGate(child: AuthPage()),
            ),
          );
        },
      ),
    );
  }
}

/// Zeigt beim allerersten Start die Sprachwahl, danach direkt die App.
///
/// 2026-08-03 (vucko Sprachumschaltung): Bewusst als Gate im Baum statt als
/// Navigator-Push — sobald der Nutzer bestätigt, meldet der Provider die
/// Änderung und dieser Gate baut auf [child] um. Kein Routen-Handling nötig,
/// und ein Zurück-Wisch kann die Wahl nicht überspringen.
class _LanguageChoiceGate extends StatelessWidget {
  const _LanguageChoiceGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<AppLocaleProvider>();
    // Solange die gespeicherte Wahl noch gelesen wird, nichts entscheiden —
    // sonst blitzt die Sprachwahl bei jedem Start kurz auf. Der Launch-Screen
    // liegt in dieser Zeit ohnehin darüber.
    if (!localeProvider.isLoaded) {
      return const ColoredBox(color: Color(0xFF0D141E), child: SizedBox.expand());
    }
    if (!localeProvider.hasChosen) return const LanguageChoicePage();
    return child;
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

        return Material(
          // 2026-06-25 (vucko): Splash-Overlay ist ein Stack-Geschwister von
          // AuthPage und stand UNTER keinem Material → Texte bekamen den gelben
          // Fallback-Doppelstrich („Routen werden vorbereitet" unterstrichen).
          // Transparentes Material liefert den DefaultTextStyle → sauber.
          type: MaterialType.transparency,
          child: Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.08, -0.28),
                  radius: 1.12,
                  colors: [
                    // Opak getönt statt halbtransparent → das Dashboard scheint
                    // NICHT mehr durch die Splash-Mitte (voll deckend bis Fade).
                    Color.lerp(const Color(0xFF172232), accent, 0.32)!,
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
