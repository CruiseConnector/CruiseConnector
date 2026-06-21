import 'dart:async';

import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/presentation/widgets/app_tutorial_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpTutorial(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppTutorialService.reset();

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _TutorialHarness(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Tutorial-Highlights sitzen zentriert auf Bottom-Nav und Community-Tabs',
    (tester) async {
      await pumpTutorial(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_home_nav_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Community'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_community_nav_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Feed'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_feed_tab_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Gruppen'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_rides_tab_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_chats_tab_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Entdecken'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_discover_tab_centered.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Cruise Mode'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_cruise_nav_only.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_analytics_nav_only.png'),
      );

      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Profil'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/app_tutorial_profile_nav_only.png'),
      );
    },
  );
}

class _TutorialHarness extends StatefulWidget {
  const _TutorialHarness();

  @override
  State<_TutorialHarness> createState() => _TutorialHarnessState();
}

class _TutorialHarnessState extends State<_TutorialHarness> {
  int _tab = 0;
  int _communitySection = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      unawaited(
        showAppTutorialOverlay(
          context,
          onTabChange: (tab) => setState(() => _tab = tab),
          onCommunitySectionChange: (section) =>
              setState(() => _communitySection = section),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _FakePage(tab: _tab, section: _communitySection),
          ),
          const _FakeBottomNavigation(),
        ],
      ),
    );
  }
}

class _FakePage extends StatelessWidget {
  const _FakePage({required this.tab, required this.section});

  final int tab;
  final int section;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF05070B),
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 150),
      child: switch (tab) {
        0 => const _HomePreview(),
        1 => _CommunityPreview(section: section),
        2 => const _LargePreview(title: 'Strecken-Setup', subtitle: 'Rundkurs'),
        3 => const _LargePreview(title: 'Analytics', subtitle: 'Highway Hero'),
        _ => const _LargePreview(
          title: 'LucWqz1',
          subtitle: 'Profil bearbeiten',
        ),
      },
    );
  }
}

class _HomePreview extends StatelessWidget {
  const _HomePreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Willkommen zurück',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
        ),
        SizedBox(height: 8),
        Text(
          'LucWqz1!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 28),
        _DarkCard(title: 'Fortschritt', subtitle: '1.285 XP gesamt'),
        SizedBox(height: 16),
        _DarkCard(title: 'Heute für dich', subtitle: 'Rheintal-Sued Loop'),
      ],
    );
  }
}

class _CommunityPreview extends StatelessWidget {
  const _CommunityPreview({required this.section});

  final int section;

  @override
  Widget build(BuildContext context) {
    const labels = ['Feed', 'Fahrten', 'Chats', 'Entdecken'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Community',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == section
                            ? Colors.white
                            : const Color(0xFF8A8D96),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 34),
        _DarkCard(title: labels[section], subtitle: 'Vorschau fuer Tutorial'),
      ],
    );
  }
}

class _LargePreview extends StatelessWidget {
  const _LargePreview({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: _DarkCard(
            title: subtitle,
            subtitle: 'Nur der Button unten wird markiert',
          ),
        ),
      ],
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF2A2F3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFFAAB1C0), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _FakeBottomNavigation extends StatelessWidget {
  const _FakeBottomNavigation();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SizedBox(
        height: 118,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 92,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Icon(CupertinoIcons.house_fill, size: 34, color: Colors.grey),
                  Icon(
                    CupertinoIcons.person_2_fill,
                    size: 34,
                    color: Colors.grey,
                  ),
                  SizedBox(width: 82),
                  Icon(
                    CupertinoIcons.chart_bar_alt_fill,
                    size: 34,
                    color: Colors.grey,
                  ),
                  Icon(
                    CupertinoIcons.person_crop_circle,
                    size: 34,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 30,
              child: Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.car_detailed,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
