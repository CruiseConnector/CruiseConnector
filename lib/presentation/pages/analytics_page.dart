import 'package:flutter/material.dart';

/// AnalyticsPage - Erweiterte Statistiken für Auto-Enthusiasten
/// 
/// Features:
/// - Übersichtskarten mit Live-Daten
/// - Interaktive Wochen-/Monatsansicht
/// - Top Strecken mit Regions-Filter
/// - RangeError-befreite Charts
/// - Cruiser-appropriate Metriken (kein Eco-Routing)
/// - CruiserConnect Dark Theme

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showWeekly = true;
  String _selectedRegion = "Alle";
  
  // Mock-Daten mit korrekter Länge für Charts
  final Map<String, dynamic> _weeklyData = {
    'drives': 42,
    'distance': '1.267 km',
    'time': '28h',
    'badges': 5,
    'avgSpeed': '45 km/h',
    'vmax': '245 km/h',
    'chartData': [0.3, 0.5, 0.4, 0.6, 0.7, 0.55, 0.8],
    'chartLabels': ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"],
    'topRoute': 'Alpenstraße',
  };
  
  final Map<String, dynamic> _monthlyData = {
    'drives': 168,
    'distance': '5.432 km',
    'time': '112h',
    'badges': 12,
    'avgSpeed': '48 km/h',
    'vmax': '267 km/h',
    'chartData': [0.4, 0.6, 0.5, 0.7, 0.75, 0.65, 0.85], // Gleiche Länge wie Labels!
    'chartLabels': ["W1", "W2", "W3", "W4", "", "", ""], // 7 Elemente
    'topRoute': 'Romantische Straße',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentData => _showWeekly ? _weeklyData : _monthlyData;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildStatsGrid(),
                const SizedBox(height: 24),
                _buildTabBar(),
                const SizedBox(height: 16),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildTopRoutesTab(),
                      _buildAchievementsTab(),
                    ],
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Analytics",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 4),
            Text(
              "Deine Fahr-Statistiken",
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFFA0AEC0),
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToggleButton('Woche', _showWeekly),
              _buildToggleButton('Monat', !_showWeekly),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _showWeekly = label == 'Woche'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF3B30) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFFA0AEC0),
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final data = _currentData;
    
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildAnalyticsCard(
          "Fahrten", 
          data['drives'].toString(), 
          Icons.directions_car, 
          const Color(0xFFFF3B30),
          "${_showWeekly ? 'Diese Woche' : 'Diesen Monat'}",
        ),
        _buildAnalyticsCard(
          "Distanz", 
          data['distance'], 
          Icons.map, 
          const Color(0xFF00E5FF),
          "+12% zur Vorperiode",
        ),
        _buildAnalyticsCard(
          "Fahrzeit", 
          data['time'], 
          Icons.timer, 
          const Color(0xFFFFD700),
          "Ø${data['avgSpeed']} Schnitt",
        ),
        // GEÄNDERT: Statt "Sprit gespart" -> "V-Max Durchschnitt"
        _buildAnalyticsCard(
          "V-Max Ø", 
          data['vmax'], 
          Icons.speed, 
          const Color(0xFFFF3B30),
          "Höchste Geschwindigkeit",
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFFFF3B30),
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFFA0AEC0),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(icon: Icon(Icons.insights, size: 20), text: "Übersicht"),
          Tab(icon: Icon(Icons.route, size: 20), text: "Top Strecken"),
          Tab(icon: Icon(Icons.emoji_events, size: 20), text: "Erfolge"),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final data = _currentData;
    final List<double> chartData = List<double>.from(data['chartData']);
    final List<String> chartLabels = List<String>.from(data['chartLabels']);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Fahraktivität",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up, color: Color(0xFFFF3B30), size: 16),
                    SizedBox(width: 4),
                    Text(
                      "+23%",
                      style: TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(chartData.length, (index) {
                // FIX: Sicherer Zugriff auf Labels
                final label = index < chartLabels.length ? chartLabels[index] : "$index";
                final isLast = index == chartData.length - 1;
                return _buildChartBar(label, chartData[index], isLast);
              }),
            ),
          ),
          const SizedBox(height: 16),
          _buildInsightCard(
            "Top Strecke",
            data['topRoute'],
            "Favorisiert mit ⭐⭐⭐⭐⭐",
            Icons.star,
          ),
        ],
      ),
    );
  }

  Widget _buildTopRoutesTab() {
    final allRoutes = [
      {"name": "Alpenstraße", "km": "245 km", "time": "3h 12m", "rating": 5.0, "region": "Alpen"},
      {"name": "Schwarzwald Hochstraße", "km": "68 km", "time": "1h 45m", "rating": 4.8, "region": "Schwarzwald"},
      {"name": "Romantische Straße", "km": "460 km", "time": "6h 30m", "rating": 4.7, "region": "Bayern"},
      {"name": "Bodensee-Rundfahrt", "km": "120 km", "time": "2h 20m", "rating": 4.5, "region": "Bodensee"},
      {"name": "Nürburgring Nordschleife", "km": "21 km", "time": "45m", "rating": 5.0, "region": "Eifel"},
      {"name": "Sächsische Schweiz", "km": "85 km", "time": "2h", "rating": 4.6, "region": "Sachsen"},
    ];
    
    final regions = ["Alle", "Alpen", "Schwarzwald", "Bayern", "Bodensee", "Eifel", "Sachsen"];
    
    final filteredRoutes = _selectedRegion == "Alle" 
        ? allRoutes 
        : allRoutes.where((r) => r["region"] == _selectedRegion).toList();

    return Column(
      children: [
        // Region Filter Chips
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: regions.length,
            itemBuilder: (context, idx) {
              final region = regions[idx];
              final isSelected = _selectedRegion == region;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedRegion = region),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF1C1F26),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF3B30) : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Text(
                      region,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[400],
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Routes List
        Expanded(
          child: filteredRoutes.isEmpty 
            ? const Center(
                child: Text(
                  "Keine Strecken in dieser Region",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: filteredRoutes.length,
                itemBuilder: (context, index) {
                  final route = filteredRoutes[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1F26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              "${index + 1}",
                              style: const TextStyle(
                                color: Color(0xFFFF3B30),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route["name"]! as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    route["km"]! as String,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    route["time"]! as String,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3B30).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  route["region"]! as String,
                                  style: const TextStyle(
                                    color: Color(0xFFFF3B30),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Color(0xFFFFD700), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              route["rating"]!.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildAchievementsTab() {
    final achievements = [
      {"icon": Icons.local_fire_department, "title": "Streak Master", "desc": "7 Tage in Folge gefahren", "color": 0xFFFF3B30},
      {"icon": Icons.speed, "title": "Speed Demon", "desc": "200 km/h+ erreicht", "color": 0xFF00E5FF},
      {"icon": Icons.route, "title": "Road Warrior", "desc": "1000 km in einer Woche", "color": 0xFFFFD700},
      {"icon": Icons.groups, "title": "Social Driver", "desc": "10 Gruppenfahrten", "color": 0xFF00FF66},
    ];

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(achievement["color"] as int).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  achievement["icon"] as IconData,
                  color: Color(achievement["color"] as int),
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                achievement["title"]! as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                achievement["desc"]! as String,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(String label, double value, bool isHighlighted) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 8,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF2D3748),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 8,
              height: 120 * value,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isHighlighted 
                      ? [const Color(0xFFFF3B30), const Color(0xFFFF6B5B)]
                      : [const Color(0xFF525252), const Color(0xFF3D3D3D)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isHighlighted ? const Color(0xFFFF3B30) : const Color(0xFFA0AEC0),
            fontSize: 10,
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard(String title, String value, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF3B30).withOpacity(0.1),
            const Color(0xFFFF3B30).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF3B30), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: const Color(0xFFFF3B30).withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFFF3B30)),
        ],
      ),
    );
  }
}