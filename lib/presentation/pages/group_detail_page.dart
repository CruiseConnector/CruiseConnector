import 'package:flutter/material.dart';

class GroupDetailPage extends StatefulWidget {
  final String title;
  final String stats;
  final bool initialIsJoined;

  const GroupDetailPage({
    super.key,
    required this.title,
    required this.stats,
    required this.initialIsJoined,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  late bool _isJoined;

  @override
  void initState() {
    super.initState();
    _isJoined = widget.initialIsJoined;
  }

  void _toggleJoin() {
    setState(() {
      _isJoined = !_isJoined;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. Premium Header mit Gradient
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF004D40), // Dunkles Smaragdgrün/Teal
                          Color(0xFF0B0E14), // Navy/Schwarz
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 100,
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Content Body
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titel & Rating
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.star, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  "4.9",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.stats,
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),

                      const SizedBox(height: 32),

                      // Stats Boxen
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatBox(Icons.straighten, "87 km", "Distanz"),
                          _buildStatBox(Icons.timer, "1h 35m", "Dauer"),
                          _buildStatBox(Icons.turn_right, "132", "Kurven"),
                        ],
                      ),

                      const SizedBox(height: 32),
                      
                      const Text(
                        "Beschreibung",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Eine anspruchsvolle Route durch die Alpenpässe. Perfekt für Sportwagen und erfahrene Fahrer. Wir treffen uns am Parkplatz P3 und fahren gemeinsam los.",
                        style: TextStyle(color: Colors.grey, height: 1.5),
                      ),
                      
                      // Platzhalter für Scrolling
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 3. Floating Action Button (Bottom)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _toggleJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isJoined ? const Color(0xFF1C1F26) : const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: _isJoined ? const BorderSide(color: Color(0xFFFF3B30), width: 1) : BorderSide.none,
                  ),
                  elevation: _isJoined ? 0 : 8,
                  shadowColor: const Color(0xFFFF3B30).withOpacity(0.5),
                ),
                child: Text(
                  _isJoined ? "Gruppe verlassen" : "Route beitreten",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isJoined ? const Color(0xFFFF3B30) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(IconData icon, String value, String label) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFFFF3B30), size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}