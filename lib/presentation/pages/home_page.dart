import 'package:flutter/material.dart';
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
  late final List<Widget> _pages;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeContentPage(onTabChange: _onNavItemTapped),
      const CommunityPage(),
      const CruiseModePage(),
      const AnalyticsPage(),
      const ProfilePage(),
    ];
    CruiseModePage.isFullscreen.addListener(_onFullscreenChanged);
    // Dark-Style für Offline-Nutzung im Hintergrund cachen
    Future.delayed(const Duration(seconds: 2), () {
      OfflineMapService.instance.ensureStyleCached();
    });
  }

  @override
  void dispose() {
    CruiseModePage.isFullscreen.removeListener(_onFullscreenChanged);
    super.dispose();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        // Im Fullscreen-Modus: SafeArea-Padding deaktivieren, aber Widget-Tree bleibt gleich
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        left: !_isFullscreen,
        right: !_isFullscreen,
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: _isFullscreen ? null : _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      padding: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF453A), Color(0xFFD32F2F)], 
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    // Der neue "Mini-Schatten" (subtiler)
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF3B30).withOpacity(0.3),
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
                      const Icon(Icons.directions_car_outlined, color: Colors.white, size: 34),
                      const SizedBox(height: 2),
                      // Leicht vergrößerte Straßen-Linien
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform(
                            transform: Matrix4.skewX(-0.5),
                            child: Container(width: 3, height: 7, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          Container(width: 3, height: 7, color: Colors.white),
                          const SizedBox(width: 4),
                          Transform(
                            transform: Matrix4.skewX(0.5),
                            child: Container(width: 3, height: 7, color: Colors.white),
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
            curve: Curves.easeOutCubic, // Sehr weiche, natürliche Kurve ohne extremes Bouncen
            
            // 2. Weiche Farbüberblendung (Fade) von Grau zu Rot
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: const Color(0xFF9E9E9E),
                end: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF9E9E9E),
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, color, child) {
                return Icon(
                  icon,
                  size: 34,
                  color: color, 
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
