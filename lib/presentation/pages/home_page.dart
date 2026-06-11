import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:cruise_connect/data/services/push_notification_service.dart';
import 'package:cruise_connect/presentation/pages/home_content_page.dart';
import 'package:cruise_connect/presentation/widgets/top_toast.dart';
import 'package:cruise_connect/presentation/pages/community_page.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/analytics_page.dart';
import 'package:cruise_connect/presentation/pages/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isFullscreen = false;
  CommunityProvider? _communityProvider;
  // Refresh-Counter pro Tab — wird beim Tab-Wechsel erhöht,
  // damit die Zielseite ihre Daten automatisch neu lädt.
  int _refreshCounter = 0;

  // Web-only: Lazy-Loading — Tabs werden erst beim ersten Besuch erstellt.
  // Auf Native bleibt IndexedStack unverändert (schnell genug).
  final Set<int> _visitedTabs = {0}; // Tab 0 (Home) ist immer besucht

  @override
  void initState() {
    super.initState();
    CruiseModePage.isFullscreen.addListener(_onFullscreenChanged);
    CruiseModePage.pendingRoute.addListener(_onPendingRoute);
    _requestLocationPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _communityProvider = context.read<CommunityProvider>();
      _communityProvider?.startRealtime();
      // 2026-05-23 (vucko): Notification-Service starten + Toast bei
      // neuen Einträgen anzeigen.
      _setupNotificationService();
    });
    // 2026-06-05 (vucko Crash-Fix): Pre-Warm NICHT mehr sofort. Die schwere
    // Download-/Cache-IO lief gleichzeitig mit dem ersten Karten-Öffnen und war
    // der Geräte-Verstärker für den MapLibre-SIGABRT (GPU/IO-Druck genau dann,
    // wenn der Renderer die Linien-Quelle aufbaut). Erst nach kurzer Idle-Phase,
    // damit das erste Cruise-Öffnen race-frei bleibt.
    unawaited(Future<void>.delayed(const Duration(seconds: 10)).then((_) {
      if (mounted) _prewarmOfflineMapRegion();
    }));
  }

  Future<void> _prewarmOfflineMapRegion() async {
    if (kIsWeb) return;
    // 2026-06-03 (vucko): DACH automatisch offline laden (User-Wunsch) — nur
    // über WLAN, resumierbar, im Hintergrund. Sobald lokal, rendert MapLibre die
    // ganze DACH-Karte ohne Netz. Deaktivieren via MapStyleService.autoDownloadEnabled.
    // 2026-06-11 (vucko Karten-Selbstheilung): EINMALIG die lokale
    // dach.pmtiles auf Defekte pruefen (Magic-Header + Groesse vs. Server) —
    // eine fehlerhaft geladene Karte (User sieht Mapbox-Fallback/kaputte
    // Tiles) wird geloescht und automatisch neu heruntergeladen.
    await MapStyleService.instance.verifyLocalDachIntegrityOnce();
    unawaited(MapStyleService.instance.maybeAutoDownloadDach());
    // 2026-06-05 (vucko): refreshRemoteStyle entfernt — das Bundle ist die
    // Single Source of Truth (Style-Änderungen greifen sofort, besser offline).
    try {
      // 2026-06-01 (vucko): Zuerst prüfen, welche Tile-Quelle aktiv ist
      // (self-hosted CDN wenn erreichbar, sonst Mapbox-Fallback) — DANN cachen,
      // damit die Tiles im richtigen (quell-getrennten) Ordner landen.
      await OfflineMapService.instance.refreshTileSourceHealth();
      // 2026-06-11 (vucko Karten-Selbstheilung): EINMALIG alte Mapbox-Tiles
      // und korrupte Kacheln entfernen — der Pre-Warm direkt darunter laedt
      // die Karte dann automatisch frisch von unserer Quelle neu.
      await OfflineMapService.instance.runOneTimeCacheMigrationIfNeeded();
      await OfflineMapService.instance.ensureStyleCached();
      double lat = OfflineMapService.defaultHomeLat;
      double lng = OfflineMapService.defaultHomeLng;
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          lat = last.latitude;
          lng = last.longitude;
        }
      } catch (_) {
        // Standort nicht verfügbar — Default-Heimatregion bleibt.
      }
      if (!mounted) return;
      unawaited(
        OfflineMapService.instance.cacheRegionAroundPoint(
          latitude: lat,
          longitude: lng,
          regionId: 'home_prewarm',
        ),
      );
      // 2026-05-28 (vucko Task #71): Zusätzlicher Detail-Cache 25km @Zoom
      // 13-16 für hochauflösende Live-Navi-Tiles um die User-Position.
      // Läuft 3s versetzt damit die Region-Pre-Warm Mapbox-Bandbreite
      // zuerst bekommt.
      unawaited(Future<void>.delayed(const Duration(seconds: 3)).then((_) {
        if (!mounted) return;
        unawaited(
          OfflineMapService.instance.cacheDetailRegionAroundPoint(
            latitude: lat,
            longitude: lng,
          ),
        );
      }));
      // 2026-05-28 (vucko Task #64): DACH-Übersicht einmalig cachen.
      // Läuft im Hintergrund nach dem lokalen Pre-Warm. SharedPreferences-
      // Flag verhindert mehrfaches Ausführen — neuer Download nur wenn User
      // den Cache manuell aus Settings löscht oder wir hier die Version
      // erhöhen (z.B. wenn Mapbox-Style ändert).
      unawaited(_prewarmDachOverviewIfNeeded());
    } catch (e) {
      debugPrint('[HomePage] Offline-Map pre-warm failed: $e');
    }
  }

  /// 2026-05-28 (vucko Task #64): DACH-Übersicht (~30-50 MB) einmalig
  /// vorladen. Schweigend im Hintergrund — User sieht in Settings später
  /// Status + manuellen Re-Download-Button.
  ///
  /// 2026-05-28 (vucko Task #69): Auch nach erfolgreich-markiertem Cache
  /// laufen wir bei jedem App-Start eine Verify-Pass im Hintergrund —
  /// fängt Tiles die durch Connection-Resets ausfallen oder vom System
  /// gelöscht wurden.
  Future<void> _prewarmDachOverviewIfNeeded() async {
    const cacheVersionKey = 'offline_map_dach_overview_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyDone = prefs.getBool(cacheVersionKey) == true;

      if (!alreadyDone) {
        // 2s Delay damit der lokale Pre-Warm (route-relevante Tiles) nicht
        // mit den DACH-Übersichts-Downloads kollidiert.
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final report = await OfflineMapService.instance.cacheDachOverview();
        if (!report.skipped &&
            report.failedTiles < report.requestedTiles * 0.1) {
          await prefs.setBool(cacheVersionKey, true);
          debugPrint(
            '[HomePage] DACH-Überblick gecacht: '
            '${report.downloadedTiles + report.existingTiles} / '
            '${report.requestedTiles} Tiles.',
          );
        } else {
          debugPrint(
            '[HomePage] DACH-Überblick teilweise fehlgeschlagen — '
            'versuche es beim nächsten App-Start erneut.',
          );
        }
        return;
      }

      // Cache schon einmal als "fertig" markiert. Background-Verify damit
      // wir Lücken durch Connection-Resets / System-Cleanup nachträglich
      // schließen. 5s Delay damit die App-Start-UX nicht beeinträchtigt
      // wird.
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      final verify =
          await OfflineMapService.instance.verifyAndRepairDachOverview();
      if (verify.repairedNow > 0 || verify.stillMissing > 0) {
        debugPrint(
          '[HomePage] DACH-Background-Verify: '
          '${verify.repairedNow} repariert, ${verify.stillMissing} fehlen weiterhin.',
        );
      }
    } catch (e) {
      debugPrint('[HomePage] DACH-Überblick fehlgeschlagen: $e');
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      // Auf Web: Browser zeigt eigenen Dialog bei getCurrentPosition()
      // Trotzdem requestPermission aufrufen damit der Dialog sofort kommt
      if (kIsWeb) {
        await Geolocator.requestPermission();
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('[HomePage] Location permission request failed: $e');
    }
  }

  @override
  void dispose() {
    CruiseModePage.isFullscreen.removeListener(_onFullscreenChanged);
    CruiseModePage.pendingRoute.removeListener(_onPendingRoute);
    _communityProvider?.stopRealtime();
    NotificationService.instance.onNew = null;
    unawaited(NotificationService.instance.stopRealtime());
    super.dispose();
  }

  Future<void> _setupNotificationService() async {
    final svc = NotificationService.instance;
    svc.onNew = (notif) {
      if (!mounted) return;
      final (title, body) = notif.renderTexts();
      TopToast.show(
        context,
        message: '$title · $body',
        icon: _iconForType(notif.type),
        duration: const Duration(milliseconds: 3500),
      );
    };
    await svc.loadInitial();
    await svc.startRealtime();
    // 2026-05-31 (vucko): Echte Handy-Push aktivieren — Permission anfragen +
    // FCM-Device-Token in Supabase registrieren. Läuft erst hier (nach Login),
    // damit das Token dem eingeloggten User zugeordnet wird. No-op auf Web.
    unawaited(PushNotificationService.instance.initForUser());
  }

  IconData _iconForType(String type) => switch (type) {
        'follow' => Icons.person_add_alt_1,
        'like' => Icons.favorite,
        'comment' => Icons.chat_bubble_outline,
        'friend_request' => Icons.handshake_outlined,
        'group_invite' => Icons.group_add_outlined,
        'weather_recommendation' => Icons.wb_sunny_outlined,
        'trip_reminder' => Icons.route_outlined,
        _ => Icons.notifications_active_outlined,
      };

  void _onPendingRoute() {
    if (CruiseModePage.pendingRoute.value != null && mounted) {
      setState(() {
        _selectedIndex = 2;
        _refreshCounter++;
        _visitedTabs.add(2);
      });
    }
  }

  void _onFullscreenChanged() {
    final newValue = CruiseModePage.isFullscreen.value;
    if (_isFullscreen != newValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isFullscreen = newValue);
      });
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _refreshCounter++;
      _visitedTabs.add(index);
    });
  }

  /// Fullscreen-Modus darf nur greifen wenn der User tatsächlich auf der
  /// Cruise-Tab (Index 2) ist. Verhindert dass ein verwaister Notifier-Zustand
  /// (z. B. nach App-Resume aus dem Hintergrund mit aktiver Route) die
  /// Bottom-Nav auf den anderen Tabs ausblendet.
  bool get _hideChromeForFullscreen => _isFullscreen && _selectedIndex == 2;

  @override
  Widget build(BuildContext context) {
    final hideChrome = _hideChromeForFullscreen;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        top: !hideChrome,
        bottom: !hideChrome,
        left: !hideChrome,
        right: !hideChrome,
        child: kIsWeb ? _buildWebTabs() : _buildNativeTabs(),
      ),
      bottomNavigationBar: hideChrome ? null : _buildBottomNav(),
    );
  }

  /// Native: IndexedStack wie bisher — alle Tabs live, GPU-beschleunigt.
  Widget _buildNativeTabs() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        HomeContentPage(
          onTabChange: _onNavItemTapped,
          refreshKey: _selectedIndex == 0 ? _refreshCounter : 0,
        ),
        CommunityPage(refreshKey: _selectedIndex == 1 ? _refreshCounter : 0),
        // 2026-06-05 (vucko): Cruise-Tab LAZY bauen (erst bei Besuch). Die
        // MapLibre-Karte ist eine native Platform-View — wird sie im IndexedStack
        // OFFSTAGE (Tab nicht sichtbar) gebaut, initialisiert die View mit
        // 0-Größe und toScreenLocation wirft nativ (SIGABRT → App-Crash beim
        // Start). _visitedTabs.add(2) passiert beim Tab-Tap UND beim pendingRoute
        // → die Karte entsteht nur sichtbar. (Web-Tabs machen das schon so.)
        _visitedTabs.contains(2)
            ? const CruiseModePage()
            : const SizedBox.shrink(),
        AnalyticsPage(refreshKey: _selectedIndex == 3 ? _refreshCounter : 0),
        ProfilePage(refreshKey: _selectedIndex == 4 ? _refreshCounter : 0),
      ],
    );
  }

  /// Web: Lazy-Loading + TickerMode für nicht-aktive Tabs.
  /// Tabs werden erst beim ersten Besuch erstellt (spart initiale Ladezeit).
  /// Nicht-aktive Tabs werden mit TickerMode(enabled: false) pausiert,
  /// sodass Animationen keine CPU verbrauchen.
  Widget _buildWebTabs() {
    final tabs = <Widget>[
      HomeContentPage(
        onTabChange: _onNavItemTapped,
        refreshKey: _selectedIndex == 0 ? _refreshCounter : 0,
      ),
      CommunityPage(refreshKey: _selectedIndex == 1 ? _refreshCounter : 0),
      const CruiseModePage(),
      AnalyticsPage(refreshKey: _selectedIndex == 3 ? _refreshCounter : 0),
      ProfilePage(refreshKey: _selectedIndex == 4 ? _refreshCounter : 0),
    ];

    return Stack(
      children: [
        for (var i = 0; i < tabs.length; i++)
          if (_visitedTabs.contains(i))
            Offstage(
              offstage: _selectedIndex != i,
              child: TickerMode(enabled: _selectedIndex == i, child: tabs[i]),
            ),
      ],
    );
  }

  Widget _buildBottomNav() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final accent = context.watch<AppAccentProvider>().color;
    return Container(
      height: 60 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildNavItem(Icons.home_outlined, 0),
              _buildNavItem(Icons.groups_outlined, 1),
              const SizedBox(width: 80),
              _buildNavItem(Icons.show_chart, 3),
              _buildNavItem(Icons.person_outline, 4),
            ],
          ),
          Positioned(
            top: -25,
            child: GestureDetector(
              onTap: () => _onNavItemTapped(2),
              child: AnimatedScale(
                scale: _selectedIndex == 2 ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Angepasster Gradient für den exakten Figma-Look
                    gradient: AppAccentColors.primaryGradient,
                    // Der neue "Mini-Schatten" (subtiler)
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Vergrößertes Icon in der Mitte (34 statt 28)
                      const Icon(
                        Icons.directions_car_outlined,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(height: 2),
                      // Leicht vergrößerte Straßen-Linien
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform(
                            transform: Matrix4.skewX(-0.5),
                            child: Container(
                              width: 3,
                              height: 7,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(width: 3, height: 7, color: Colors.white),
                          const SizedBox(width: 4),
                          Transform(
                            transform: Matrix4.skewX(0.5),
                            child: Container(
                              width: 3,
                              height: 7,
                              color: Colors.white,
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
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    final accent = context.watch<AppAccentProvider>().color;

    return GestureDetector(
      onTap: () => _onNavItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Center(
          // 1. Weiche Skalierungs-Animation (15% größer, wenn ausgewählt)
          child: AnimatedScale(
            scale: isSelected ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves
                .easeOutCubic, // Sehr weiche, natürliche Kurve ohne extremes Bouncen
            // 2. Weiche Farbüberblendung (Fade) von Grau zu Rot
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: const Color(0xFF9E9E9E),
                end: isSelected ? accent : const Color(0xFF9E9E9E),
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, color, child) {
                return Icon(icon, size: 34, color: color);
              },
            ),
          ),
        ),
      ),
    );
  }
}
