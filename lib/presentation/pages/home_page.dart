import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/presentation/pages/home_content_page.dart';
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
    });
    // 2026-05-22 (vucko): Pre-Warm SOFORT statt nach 2s Delay.
    // User-Beschwerde: "Mapbox-Tiles laden teilweise lange, sieht nicht
    // schön aus". Je früher der cache greift desto besser.
    _prewarmOfflineMapRegion();
  }

  Future<void> _prewarmOfflineMapRegion() async {
    if (kIsWeb) return;
    try {
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
    } catch (e) {
      debugPrint('[HomePage] Offline-Map pre-warm failed: $e');
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
    super.dispose();
  }

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
        const CruiseModePage(),
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
