import 'package:flutter/material.dart';

class AdvicerPage extends StatefulWidget {
  const AdvicerPage({super.key});

  @override
  State<AdvicerPage> createState() => _AdvicerPageState();
}

class _AdvicerPageState extends State<AdvicerPage> {
  // State variables for dynamic logic
  bool _isRoundTrip = true; // Default to 'Rundkurs'
  String _planningType = 'random'; // 'random' (Zufall) or 'waypoints' (Wegpunkte)
  double _selectedLength = 50.0; // Default length
  final TextEditingController _destinationController = TextEditingController();

  // Colors
  final Color _backgroundColor = const Color(0xFF0B0E14);
  final Color _cardColor = const Color(0xFF1A1F26);
  final Color _accentColor = const Color(0xFFFF4500); // Orange-Red for active state

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Strecken-Setup',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Route Mode Section (Routen-Modus)
              _buildSectionTitle('Routen-Modus'),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildRouteModeButton(
                      label: 'Rundkurs',
                      icon: Icons.loop,
                      isActive: _isRoundTrip,
                      onTap: () {
                        setState(() {
                          _isRoundTrip = true;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildRouteModeButton(
                      label: 'A nach B',
                      icon: Icons.alt_route,
                      isActive: !_isRoundTrip,
                      onTap: () {
                        setState(() {
                          _isRoundTrip = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 30),
              const Divider(color: Colors.white24, thickness: 1),
              const SizedBox(height: 30),

              // 2. Dynamic Logic Section
              AnimatedCrossFade(
                firstChild: _buildRoundTripOptions(),
                secondChild: _buildAtoBOptions(),
                crossFadeState: _isRoundTrip ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 300),
              ),

              const SizedBox(height: 30),
              const Divider(color: Colors.white24, thickness: 1),
              const SizedBox(height: 30),

              // 3. Length Section (Conditional/Optional)
              _buildLengthSection(),

              const SizedBox(height: 30),
              // Add more sections (Location, Style) as placeholders if needed
              _buildSectionTitle('Stil & Umgebung'),
              const SizedBox(height: 15),
              _buildStyleOptions(),

              const SizedBox(height: 50),
              _buildStartButton(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- Widget Builders ---

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildRouteModeButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 100, // Large for gloves
        decoration: BoxDecoration(
          color: isActive ? _cardColor : _backgroundColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isActive ? _accentColor : Colors.white24,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? _accentColor : Colors.white54,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white60,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundTripOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Planungs-Typ'),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _buildChoiceButton(
                label: 'Zufall',
                isSelected: _planningType == 'random',
                onTap: () => setState(() => _planningType = 'random'),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildChoiceButton(
                label: 'Wegpunkte',
                isSelected: _planningType == 'waypoints',
                onTap: () => setState(() => _planningType = 'waypoints'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAtoBOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Zielort'),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white54),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _destinationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Adresse oder Ort suchen...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.map, color: Colors.white),
                  onPressed: () {
                    // Open Map for selection
                  },
                  tooltip: 'Auf Karte wählen',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20), // Padding for gloves
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withOpacity(0.2) : _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _accentColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _accentColor : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildLengthSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Länge'),
            if (!_isRoundTrip)
              const Text(
                '(Auto-Berechnung)',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 15),
        if (_isRoundTrip) ...[
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: _accentColor.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              trackHeight: 4,
            ),
            child: Slider(
              value: _selectedLength,
              min: 10,
              max: 200,
              divisions: 19,
              label: '${_selectedLength.round()} km',
              onChanged: (value) {
                setState(() {
                  _selectedLength = value;
                });
              },
            ),
          ),
          Center(
            child: Text(
              '${_selectedLength.round()} km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.white54),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Distanz wird basierend auf Zielort berechnet.',
                    style: TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStyleOptions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildChip('Kurvig'),
        _buildChip('Schnell'),
        _buildChip('Offroad'),
        _buildChip('Malerisch'),
      ],
    );
  }

  Widget _buildChip(String label) {
    // This could also be stateful if selection is needed
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
      ),
    );
  }
  
  Widget _buildStartButton() {
     return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          // Action to start route calculation
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Text(
          'ADV Suchen',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}