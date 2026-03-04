import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/pages/create_post_page.dart';
import 'package:cruise_connect/presentation/pages/create_group_page.dart';
import 'package:cruise_connect/presentation/pages/group_detail_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Listener hinzufügen, um setState aufzurufen, wenn der Tab wechselt (für FAB Update)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        title: const Text("Community", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.notifications_none, color: Colors.white), onPressed: () {}),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF3B30),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "Feed"),
            Tab(text: "Meine Kontakte"),
            Tab(text: "Entdecken"),
          ],
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF3B30),
        child: Icon(_tabController.index == 1 ? Icons.group_add : Icons.add, color: Colors.white),
        onPressed: () {
          if (_tabController.index == 0) {
            // Tab 0 (Feed) -> Post erstellen
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostPage()));
          } else if (_tabController.index == 1) {
            // Tab 1: Meine Kontakte -> Gruppe erstellen
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
          } else if (_tabController.index == 2) {
            // Tab 2 (Entdecken) -> Bottom Sheet Auswahl
            _showCreateOptions(context);
          }
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Feed
          ListView(
            padding: const EdgeInsets.only(bottom: 80), // Platz für FAB
            children: [
              _buildPostItem(context, "David", "@david_racer", "2 Std.", "Hat eine neue Route 'Alpine Rush' erstellt! Die Kurven im zweiten Sektor sind der Wahnsinn. 🏎️💨"),
              const Divider(color: Colors.white10, height: 1),
              _buildPostItem(context, "Sarah", "@sarah_speed", "5 Std.", "Wer ist heute Abend beim Meetup dabei? Treffpunkt 18:00 Uhr an der Tankstelle Nord."),
              const Divider(color: Colors.white10, height: 1),
              _buildPostItem(context, "Max", "@max_power", "1 Tag", "Mein neuer Highscore auf der Nordschleife! 7:45 min. Das Setup hat sich gelohnt."),
              const Divider(color: Colors.white10, height: 1),
              _buildPostItem(context, "Lisa", "@lisa_drift", "2 Tage", "Suche noch jemanden für eine Ausfahrt am Sonntag Richtung Schwarzwald. Meldet euch!"),
            ],
          ),
          
          // Tab 2: Meine Kontakte (Gruppen)
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGroupCard("Jonny's Gruppe", "Alpine Rush", "87 Km • 132 Kurven • 1h 35min", 23, "18 Uhr | Standort A", true),
              const SizedBox(height: 16),
              _buildGroupCard("Night Riders", "City Loop", "45 Km • 20 Kurven • 50min", 12, "22 Uhr | Tankstelle Süd", true),
              const SizedBox(height: 16),
              _buildGroupCard("Weekend Warriors", "Black Forest", "120 Km • 200 Kurven • 3h", 8, "Sa 10 Uhr | Cafe Hub", false),
            ],
          ),
          
          // Tab 3: Entdecken (Mixed Content)
          ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Vorschläge für dich", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              _buildPostItem(context, "Alex", "@alex_moto", "1 Std.", "Checkt mal meine neue Lackierung ab! 🔥", showFollow: true),
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: _buildGroupCard("Porsche Club", "Autobahn Run", "200 Km • 10 Kurven • 1h 30min", 50, "So 09 Uhr | Raststätte", false),
              ),
              const Divider(color: Colors.white10, height: 1),
              _buildPostItem(context, "Nina", "@nina_speed", "3 Std.", "Hat jemand Lust auf eine spontane Runde?", showFollow: true),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: const Text('Text-Post erstellen', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_car, color: Colors.white),
                title: const Text('Neue Gruppe gründen', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostItem(BuildContext context, String name, String handle, String time, String content, {bool showFollow = false}) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (_) => PostDetailPage(name: name, handle: handle, content: content, time: time)
          )
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[800],
              child: Text(name[0], style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 12),
            
            // Content Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Name, Handle, Time
                  Row(
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 5),
                      Text(handle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(width: 5),
                      const Text("·", style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(time, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      
                      // Follow Button (Optional)
                      if (showFollow) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text("Folgen", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],

                      const Spacer(),
                      const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  // Body Text
                  Text(
                    content,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  
                  // Footer Icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AnimatedInteractionIcon(icon: Icons.chat_bubble_outline, count: "5"),
                      _AnimatedInteractionIcon(icon: Icons.repeat, count: "2"),
                      _AnimatedInteractionIcon(icon: Icons.favorite_border, activeIcon: Icons.favorite, activeColor: const Color(0xFFFF3B30), count: "24"),
                      _AnimatedInteractionIcon(icon: Icons.share_outlined, count: ""),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(String title, String routeName, String stats, int drivers, String timeLoc, bool isJoined) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailPage(
              title: title,
              stats: stats,
              initialIsJoined: isJoined,
            ),
          ),
        );
      },
      child: Container(
        // height: 140, // REMOVED: Fixed height removed to prevent overflow
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26), // Dunkles Grau/Navy
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
            IntrinsicHeight( // Ensures the row stretches to the tallest child
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Linke Seite: Infos
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0), // Clean Padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12), // Increased spacing
                          Row(
                            children: [
                              const Icon(Icons.terrain, color: Colors.white70, size: 14),
                              const SizedBox(width: 6),
                              Text(routeName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(stats, style: const TextStyle(color: Colors.grey, fontSize: 11)), // Slightly larger font
                          const SizedBox(height: 16), // Increased spacing
                          Row(
                            children: [
                              const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
                              const SizedBox(width: 6),
                              Text("$drivers Fahrer", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.flag, color: Colors.white70, size: 14),
                              const SizedBox(width: 6),
                              Text(timeLoc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Rechte Seite: Map Placeholder
                  Expanded(
                    flex: 2,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 150), // Minimum height for image
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
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
            
            // "Dabei" Badge
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
      ),
    );
  }
}

// Helper Widget für animierte Interaktionen (Like, Repost etc.)
class _AnimatedInteractionIcon extends StatefulWidget {
  final IconData icon;
  final IconData? activeIcon;
  final Color? activeColor;
  final String count;

  const _AnimatedInteractionIcon({
    required this.icon,
    required this.count,
    this.activeIcon,
    this.activeColor,
  });

  @override
  State<_AnimatedInteractionIcon> createState() => _AnimatedInteractionIconState();
}

class _AnimatedInteractionIconState extends State<_AnimatedInteractionIcon> with SingleTickerProviderStateMixin {
  bool _isActive = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _isActive = !_isActive;
    });
    _controller.forward().then((_) => _controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Icon(
              _isActive && widget.activeIcon != null ? widget.activeIcon : widget.icon,
              color: _isActive && widget.activeColor != null ? widget.activeColor : Colors.grey,
              size: 18,
            ),
          ),
          if (widget.count.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              widget.count,
              style: TextStyle(
                color: _isActive && widget.activeColor != null ? widget.activeColor : Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}