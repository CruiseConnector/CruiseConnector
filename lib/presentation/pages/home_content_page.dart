import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/presentation/pages/route_join_page.dart';

class HomeContentPage extends StatefulWidget {
  final Function(int)? onTabChange;
  const HomeContentPage({super.key, this.onTabChange});

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage> {
  int _totalRoutes = 0;
  double _totalDistanceKm = 0;
  int _userLevel = 1;
  double _levelProgress = 0;
  String _levelName = 'Street Rookie';
  int _kmToNextLevel = 100;
  int _badgeCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final result = await GamificationService.calculateAndSync();

      if (mounted) {
        setState(() {
          _totalRoutes = result.totalRoutes;
          _totalDistanceKm = result.totalDistanceKm;
          _userLevel = result.level.level;
          _levelProgress = result.level.progress;
          _levelName = result.level.name;
          _kmToNextLevel = result.level.kmToNextLevel;
          _badgeCount = result.earnedBadgeIds.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final String userName = (user?.userMetadata?['username'] as String?)
        ?? user?.email?.split('@')[0]
        ?? 'User';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Willkommen zurück",
                      style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                    ),
                    Text(
                      "$userName!",
                      style: const TextStyle(
                        color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Stack(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B30), shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 28),
                    ),
                    if (_totalRoutes > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4A90D9), shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_totalRoutes',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Fortschritt Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1F26),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: Color(0xFFFF3B30), strokeWidth: 2),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Fortschritt",
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _statRow('\u{1F3CE}\uFE0F', '${_totalDistanceKm.toStringAsFixed(0)} Km gesamt'),
                                const SizedBox(height: 6),
                                _statRow('\u{1F6E3}\uFE0F', '$_totalRoutes Strecken'),
                                const SizedBox(height: 6),
                                _statRow('\u{1F3C5}', '$_badgeCount Badges'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Level $_userLevel - $_levelName",
                              style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                            ),
                            Text(
                              "${(_levelProgress * 100).toStringAsFixed(0)}%",
                              style: const TextStyle(
                                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 8, width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _levelProgress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Noch $_kmToNextLevel km bis Level ${_userLevel + 1}",
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 10),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),

            // Heute für dich Section
            const Text(
              "Heute für dich",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Material(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const RouteJoinPage()));
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Empfohlene Route",
                              style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12, fontWeight: FontWeight.w500)),
                            SizedBox(height: 4),
                            Text("Alpine Rush",
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Row(children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              SizedBox(width: 4),
                              Text("4.9", style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                            ]),
                            SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
                              SizedBox(width: 4),
                              Text("23 Fahrer", style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                            ]),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 180, height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Colors.teal[900]!, Colors.teal[700]!],
                            ),
                          ),
                          child: const Icon(Icons.map, color: Colors.white54, size: 30),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Community + Chart Section
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    height: 180,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1F26),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Community",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        _buildCommunityItem("6 Fahrer in deiner Nähe", "\u{1F465}"),
                        const SizedBox(height: 4),
                        _buildCommunityItem("Meetup heute 18:30", "\u{1F525}"),
                        const SizedBox(height: 4),
                        _buildCommunityItem("Vorarlberg - Dornbirn", "\u{1F4CD}"),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: () => widget.onTabChange?.call(1),
                            child: Container(
                              height: 35,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                ),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              alignment: Alignment.center,
                              child: const Text("Beitreten",
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 180,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1F26),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Letzte 7 Tage",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const RotatedBox(
                              quarterTurns: 3,
                              child: Text("Kilometer",
                                style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                            ),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildChartBar("01", 0.0),
                                  _buildChartBar("02", 0.0),
                                  _buildChartBar("03", 0.0),
                                  _buildChartBar("04", 0.0),
                                  _buildChartBar("05", 0.0),
                                  _buildChartBar("06", 0.0),
                                  _buildChartBar("07", _totalDistanceKm > 0 ? 1.0 : 0.0),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String emoji, String text) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }

  Widget _buildCommunityItem(String text, String emoji) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildChartBar(String day, double value) {
    const double barHeight = 110.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 8, height: barHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF2D3748),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 8,
              height: barHeight * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        Text(day, style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
