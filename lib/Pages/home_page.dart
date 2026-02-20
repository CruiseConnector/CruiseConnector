import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cruise_connect/pages/welcome_page.dart';
import 'package:cruise_connect/Pages/route_join_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late int userLevel;
  late double levelProgress;
  late String levelName;
  late int kmToNextLevel;

  @override
  void initState() {
    super.initState();
    _initializeUserLevel();
  }

  void _initializeUserLevel() {
    final user = FirebaseAuth.instance.currentUser;
    bool isTestUser = (user?.email?.contains('david') ?? false) || 
                      (user?.email?.contains('test') ?? false);
    
    if (isTestUser) {
      userLevel = 5;
      levelProgress = 0.35;
      levelName = "Alpine Master";
      kmToNextLevel = 650;
    } else {
      userLevel = 1;
      levelProgress = 0.10;
      levelName = "Street Rookie";
      kmToNextLevel = 899;
    }
  }

  void signUserOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false, 
      );
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String userName = user?.displayName ?? user?.email?.split('@')[0] ?? "User";

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: _buildPage(_selectedIndex, userName, user),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildPage(int index, String userName, User? user) {
    switch (index) {
      case 0:
        return _buildHomePage(userName);
      case 1:
        return _buildCommunityPage();
      case 2:
        return _buildCruiseModePage();
      case 3:
        return _buildAnalyticsPage();
      case 4:
        return _buildProfilePage(user);
      default:
        return _buildHomePage(userName);
    }
  }

  Widget _buildHomePage(String userName) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
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
                      radius: 32,
                      backgroundColor: const Color(0xFFFF3B30),
                      child: const Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    Container(
                      width: 28,
                      height: 28,
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
            const SizedBox(height: 20),

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
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: const [
                            Text("🏎️", style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            Text("1.287 Km gesamt", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: const [
                            Text("🛣️", style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            Text("3 neue Strecken", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: const [
                            Text("🏅", style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            Text("5 Badges", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ]),
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
            const SizedBox(height: 16),

            // Heute für dich Section
            const Text(
              "Heute für dich",
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
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
                  // Navigation zur RouteJoinPage
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
                          width: 80, // Quadratisch
                          height: 80,
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
                    height: 190,
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
                            onTap: () => _onNavItemTapped(1),
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
                    height: 190,
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
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            
                          ),
                        ),
                        const SizedBox(height: 24),
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

  Widget _buildStatItem(String title, String emoji) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
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

  void _navigateToRouteDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RouteDetailsPage(),
      ),
    );
  }

  Widget _buildCommunityPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people,
            size: 80,
            color: Color(0xFFFF3B30),
          ),
          const SizedBox(height: 20),
          const Text(
            "Community",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Verbinde dich mit anderen CruiseConnect Nutzern",
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildCruiseModePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(60),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: const Icon(
              Icons.directions_car,
              color: Colors.white,
              size: 60,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Cruise Mode",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[900]?.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "🔧 In Arbeit - Ein anderer Entwickler arbeitet daran",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsPage() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Analytics",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAnalyticsCard("Fahrten", "42", Icons.directions_car, Colors.blue),
                _buildAnalyticsCard("Distanz", "1.267 km", Icons.map, Colors.green),
                _buildAnalyticsCard("Zeit", "28h", Icons.timer, Colors.orange),
                _buildAnalyticsCard("Badges", "5", Icons.emoji_events, Colors.purple),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Diese Woche",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildChartBar("Mo", 0.3),
                        _buildChartBar("Di", 0.5),
                        _buildChartBar("Mi", 0.4),
                        _buildChartBar("Do", 0.6),
                        _buildChartBar("Fr", 0.7),
                        _buildChartBar("Sa", 0.55),
                        _buildChartBar("So", 0.8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage(User? user) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_circle,
              size: 80,
              color: Color(0xFFFF3B30),
            ),
            const SizedBox(height: 20),
            const Text(
              "Mein Profil",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "E-Mail:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    user?.email ?? "Keine E-Mail gefunden",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Einstellungen",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Hilfe & Support",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.info, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Über CruiseConnect",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => signUserOut(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Abmelden",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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

  Widget _buildBottomNav() {
    return Container(
      height: 90,
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
            top: -30,
            child: GestureDetector(
              onTap: () => _onNavItemTapped(2),
              child: AnimatedScale(
                scale: _selectedIndex == 2 ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 68,
                  height: 68,
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

// Route Details Page
class RouteDetailsPage extends StatelessWidget {
  const RouteDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Alpine Rush",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.teal[900]!,
                      Colors.teal[700]!,
                      Colors.teal[600]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.map,
                  color: Colors.white,
                  size: 80,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Alpine Rush",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoRow("Distanz", "87 km"),
              const SizedBox(height: 12),
              _buildInfoRow("Kurven", "132"),
              const SizedBox(height: 12),
              _buildInfoRow("Dauer", "1h 36min"),
              const SizedBox(height: 12),
              _buildInfoRow("Schwierigkeit", "Mittel"),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F26),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
                ),
                child: Row(
                  children: [
                    const Text("⭐", style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "4.9",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "328 Bewertungen",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Fahrer heute unterwegs",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "23 Fahrer",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Fahrt starten",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
