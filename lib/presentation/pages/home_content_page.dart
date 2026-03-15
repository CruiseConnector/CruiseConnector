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
  int userLevel = 1;
  double levelProgress = 0;
  String levelName = 'Street Rookie';
  int kmToNextLevel = 10;
  int totalRoutes = 0;
  double totalDistanceKm = 0;
  int badgeCount = 0;
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
          userLevel = result.level.level;
          levelProgress = result.level.progress;
          levelName = result.level.name;
          kmToNextLevel = result.level.kmToNextLevel;
          totalRoutes = result.totalRoutes;
          totalDistanceKm = result.totalDistanceKm;
          badgeCount = result.earnedBadgeIds.length;
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
                      style: TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      "$userName!",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFFF3B30),
                      child: const Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          "$userLevel",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
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
                border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Fortschritt",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  // Stats List & Percentage
                  _loading
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))))
                    : Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _statRow("🏎️", "${totalDistanceKm.toStringAsFixed(0)} Km gesamt"),
                              const SizedBox(height: 6),
                              _statRow("🛣️", "$totalRoutes Strecken"),
                              const SizedBox(height: 6),
                              _statRow("🏅", "$badgeCount Badges"),
                            ],
                          ),
                        ],
                      ),
                  const SizedBox(height: 12),
                  // Progress Bar with Gradient
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Level $userLevel - $levelName",
                            style: const TextStyle(
                              color: Color(0xFFA0AEC0),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            "${(levelProgress * 100).toStringAsFixed(0)}%",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 8,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: levelProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Noch $kmToNextLevel km bis Level ${userLevel + 1}",
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Heute für dich Section
            const Text(
              "Heute für dich",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            // InkWell Wrapper wie angefordert
            Material(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RouteJoinPage()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Empfohlene Route",
                              style: TextStyle(
                                color: Color(0xFFA0AEC0),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Alpine Rush",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                const Text(
                                  "4.9",
                                  style: TextStyle(
                                    color: Color(0xFFA0AEC0),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
                                const SizedBox(width: 4),
                                const Text(
                                  "23 Fahrer",
                                  style: TextStyle(
                                    color: Color(0xFFA0AEC0),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Quadratisches Map-Preview mit Radius 12
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 180, // Quadratisch
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.teal[900]!,
                                Colors.teal[700]!,
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.map,
                            color: Colors.white54,
                            size: 30,
                          ),
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
                      border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Community",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildCommunityItem("6 Fahrer in deiner Nähe", "👥"),
                        const SizedBox(height: 4),
                        _buildCommunityItem("Meetup heute 18:30", "🔥"),
                        const SizedBox(height: 4),
                        _buildCommunityItem("Vorarlberg - Dornbirn", "📍"),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity, 
                          child: GestureDetector(
                            onTap: () {
                                widget.onTabChange?.call(1);
                            },
                            child: Container(
                              height: 35.0,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "Beitreten",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
                      border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Letzte 7 Tage",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            
                            const RotatedBox(
                              quarterTurns: 3,
                              child: Text(
                                "Kilometer",
                                style: TextStyle(
                                  color: Color(0xFFA0AEC0),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 0),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildChartBar("01", 0.3),
                                  _buildChartBar("02", 0.5),
                                  _buildChartBar("03", 0.4),
                                  _buildChartBar("04", 0.6),
                                  _buildChartBar("05", 0.7),
                                  _buildChartBar("06", 0.55),
                                  _buildChartBar("07", 0.8),
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
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 11,
            ),
          ),
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
          width: 8,
          height: barHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF2D3748),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 8,
              height: barHeight * value,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        Text(
          day,
          style: const TextStyle(
            color: Color(0xFFA0AEC0),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}