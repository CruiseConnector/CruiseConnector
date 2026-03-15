import 'package:cruise_connect/presentation/pages/interactive_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/edit_profile_page.dart';
import 'package:cruise_connect/presentation/pages/settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void signUserOut() async {
    await Supabase.instance.client.auth.signOut();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final String userEmail = user?.email ?? "user@cruiseconnect.com";
    final String userName = (user?.userMetadata?['username'] as String?) ?? "Cruiser";
    final String userHandle = "@${userEmail.split('@')[0]}";

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0B0E14),
      endDrawer: _buildBurgerMenu(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF3B30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostPage()));
        },
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // A. SliverAppBar (Banner + Burger Menu)
            SliverAppBar(
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              ),
              stretch: true,
              expandedHeight: 150,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0.6, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1C1F26), Color(0xFF0B0E14)],
                        stops: [0.3, 1.0],
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.camera_alt_outlined, size: 80, color: Colors.white.withOpacity(0.05)),
                    ),
                  ),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
              ],
            ),

            // B. SliverToBoxAdapter (Profil-Infos)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar & Edit Button Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Avatar (Overlapping)
                        Transform.translate(
                          offset: const Offset(0, -40),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0B0E14), // Match Scaffold bg for border effect
                              shape: BoxShape.circle,
                            ),
                            child: const CircleAvatar(
                              radius: 40,
                              backgroundColor: Color(0xFF3A3E48),
                              child: Icon(Icons.person, size: 40, color: Colors.white),
                            ),
                          ),
                        ),
                        // Edit Profile Button
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage()));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white30, width: 1),
                              ),
                              child: const Text(
                                "Profil bearbeiten",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Infos (Pull up slightly due to transform above)
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userHandle,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined, color: Colors.grey, size: 16),
                              const SizedBox(width: 6),
                              const Text(
                                "Beigetreten April 2023",
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildFollowStat("12", "Folge ich"),
                              const SizedBox(width: 16),
                              _buildFollowStat("240", "Follower"),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // C. SliverPersistentHeader (Tabs)
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFFFF3B30),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  tabs: const [
                    Tab(text: "Posts"),
                    Tab(text: "Aktive Gruppen"),
                  ],
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Posts
            ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 40),
              children: [
                InteractivePostCard(name: userName, handle: userHandle, time: "2 Std.", content: "Endlich Level 5 erreicht! Die 'Alpine Master' Badge sieht im Profil echt gut aus. 🏔️🏎️", initialLikeCount: "24", initialCommentCount: "2"),
                InteractivePostCard(name: userName, handle: userHandle, time: "1 Tag", content: "Suche noch Leute für den Night Run am Freitag. Wer ist dabei?", initialLikeCount: "5", initialCommentCount: "8"),
                InteractivePostCard(name: userName, handle: userHandle, time: "3 Tage", content: "Mein neuer Rekord auf der Hausstrecke: 4:20 min. 🔥", initialLikeCount: "42", initialRepostCount: "3"),
              ],
            ),
            
            // Tab 2: Aktive Gruppen
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildGroupCard("Alpine Rush", "Passstraße", "87 Km • 132 Kurven", 23, "18 Uhr | P3", true),
                const SizedBox(height: 16),
                _buildGroupCard("City Loop", "Innenstadt", "45 Km • 20 Kurven", 12, "22 Uhr | Tankstelle", true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBurgerMenu() {
    return Drawer(
      backgroundColor: const Color(0xFF1C1F26),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Menü",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildMenuItem(
              Icons.settings, 
              "Einstellungen", 
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))
            ),
            _buildMenuItem(Icons.lock, "Privatsphäre"),
            _buildMenuItem(Icons.bookmark, "Gespeicherte Routen"),
            _buildMenuItem(Icons.history, "Fahrtverlauf"),
            _buildMenuItem(Icons.help_outline, "Hilfe & Support"),
            
            const Spacer(),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: signUserOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30).withOpacity(0.1),
                    foregroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFFF3B30)),
                    ),
                  ),
                  child: const Text(
                    "Ausloggen",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {
        Navigator.pop(context); // Close drawer
        if (onTap != null) {
          onTap();
        }
      },
    );
  }

  Widget _buildFollowStat(String count, String label) {
    return Row(
      children: [
        Text(
          count,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildGroupCard(String title, String routeName, String stats, int drivers, String timeLoc, bool isJoined) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: isJoined ? Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.terrain, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(routeName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(stats, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
                            const SizedBox(width: 6),
                            Text("$drivers Fahrer", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 130),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      image: const DecorationImage(
                        image: AssetImage('lib/images/car_placeholder.jpg'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF1C1F26),
                            const Color(0xFF1C1F26).withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isJoined)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                ),
                child: const Text(
                  "Dabei",
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF0B0E14), // Background color for sticky header
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}