import 'package:flutter/material.dart';

class CruiseModePage extends StatefulWidget {
  const CruiseModePage({super.key});

  @override
  State<CruiseModePage> createState() => _CruiseModePageState();
}

class _CruiseModePageState extends State<CruiseModePage> {
  // 1. State & Setup
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 3. Premium Header (SliverAppBar)
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                elevation: 0,
                automaticallyImplyLeading: false, // WICHTIG: Kein Zurück-Button im Root-Tab
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF004D40), // Dunkles Smaragdgrün
                          Color(0xFF0B0E14), // Navy/Schwarz
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 100,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ),
                ),
              ),
              
              // 4. Das cleane Formular (SliverToBoxAdapter)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1F26),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Strecken-Setup",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),

                            _buildSelectionRow(
                              "Länge",
                              ['20 Km', '50 Km', '100 Km', '+100 Km'],
                              _selectedLength,
                              (val) => setState(() => _selectedLength = val),
                            ),

                            const Divider(color: Colors.white10, height: 32),

                            _buildSelectionRow(
                              "Standort",
                              ['Aktueller Standort', 'Standort wählen'],
                              _selectedLocation,
                              (val) => setState(() => _selectedLocation = val),
                            ),

                            const Divider(color: Colors.white10, height: 32),

                            _buildSelectionRow(
                              "Stil",
                              ['Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'],
                              _selectedStyle,
                              (val) => setState(() => _selectedStyle = val),
                            ),
                          ],
                        ),
                      ),

                      // Platzhalter unten
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 5. Der Action-Button (Single Usage)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 140,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xFF0B0E14),
                  ],
                  stops: [0.0, 0.6],
                ),
              ),
              child: Center(
                child: Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF3B30).withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      // Generieren Logik
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Route generieren",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionRow(String title, List<String> options, String selectedValue, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected 
                    ? [BoxShadow(color: const Color(0xFFFF3B30).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))]
                    : [],
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[400],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}