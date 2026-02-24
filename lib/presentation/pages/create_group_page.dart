import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  double _maxPeople = 10;
  final TextEditingController _descController = TextEditingController();
  
  // State-Variablen für die Auswahl
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort';
  String _selectedStyle = 'Sport Mode';
  String _selectedVisibility = 'Öffentlich (Für jeden)';
  
  // Neue State-Variablen für Interaktivität
  TimeOfDay? _selectedTime;
  bool _isRouteGenerated = false;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. Premium Header (SliverAppBar)
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                elevation: 0,
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
                          Color(0xFF004D40), // Dunkles Smaragdgrün
                          Color(0xFF0B0E14), // Navy/Schwarz
                        ],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 100,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ),
                ),
              ),
              
              // 2. Pro-Level Formularbereich
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- DYNAMISCHE ROUTENDATEN (Nach Generierung) ---
                      if (_isRouteGenerated)
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "Alpine Rush Route",
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildRouteStat(Icons.straighten, "87 km"),
                                  _buildRouteStat(Icons.timer, "1h 35m"),
                                  _buildRouteStat(Icons.turn_right, "132 Kurven"),
                                ],
                              ),
                            ],
                          ),
                        ),

                      // --- SEKTION 1: STRECKEN-SETUP ---
                      const Text(
                        "Strecken-Setup",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),

                      _buildSelectionRow(
                        "Länge",
                        ['20 Km', '50 Km', '100 Km', '+100 Km'],
                        _selectedLength,
                        (val) => setState(() => _selectedLength = val),
                      ),
                      const SizedBox(height: 24),

                      _buildSelectionRow(
                        "Standort",
                        ['Aktueller Standort', 'Standort wählen'],
                        _selectedLocation,
                        (val) => setState(() => _selectedLocation = val),
                      ),
                      const SizedBox(height: 24),

                      _buildSelectionRow(
                        "Stil",
                        ['Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'],
                        _selectedStyle,
                        (val) => setState(() => _selectedStyle = val),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // --- SEKTION 2: GRUPPEN-DETAILS (iOS Style Block) ---
                      const Text(
                        "Gruppen-Details",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),

                      // Container für Slider & Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1F26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            // Startuhrzeit Picker
                            InkWell(
                              onTap: () => _selectTime(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    const Text("Startuhrzeit", style: TextStyle(color: Colors.white, fontSize: 16)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0B0E14),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _selectedTime != null ? _selectedTime!.format(context) : "Wählen",
                                        style: TextStyle(
                                          color: _selectedTime != null ? Colors.white : const Color(0xFFFF3B30),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 1, indent: 20, endIndent: 20),

                            // Slider Part
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Max. Personen", style: TextStyle(color: Colors.white, fontSize: 16)),
                                  Text("${_maxPeople.round()}", style: const TextStyle(color: Colors.grey, fontSize: 16)),
                                ],
                              ),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFFF3B30),
                                inactiveTrackColor: Colors.grey[800],
                                thumbColor: Colors.white,
                                overlayColor: const Color(0xFFFF3B30).withOpacity(0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: _maxPeople,
                                min: 2,
                                max: 50,
                                divisions: 48,
                                onChanged: (value) => setState(() => _maxPeople = value),
                              ),
                            ),
                            
                            const Divider(color: Colors.white10, height: 1, indent: 20, endIndent: 20),
                            
                            // Visibility Selection Part
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Zugänglichkeit", style: TextStyle(color: Colors.white, fontSize: 16)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: ['Nur Kontakte', 'Öffentlich (Für jeden)'].map((option) {
                                      final isSelected = option == _selectedVisibility;
                                      return GestureDetector(
                                        onTap: () => setState(() => _selectedVisibility = option),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF1A1D24),
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
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Beschreibung Textfeld
                      const Text(
                        "Beschreibung",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1F26),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: TextField(
                          controller: _descController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: "Beschreibe deine Gruppe...",
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),

                      // Platzhalter für Scrolling über Buttons
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 3. Schwebende Bottom-Buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.transparent,
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isGenerating ? null : () async {
                          setState(() => _isGenerating = true);
                          // Simuliere Ladezeit
                          await Future.delayed(const Duration(seconds: 1));
                          setState(() {
                            _isGenerating = false;
                            _isRouteGenerated = true;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1F26),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isGenerating 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text("Generieren", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: const Color(0xFFFF3B30).withOpacity(0.5),
                        ),
                        child: const Text("Erstellen", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ),
                ],
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

  Widget _buildRouteStat(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF3B30), size: 16),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFF3B30),
              surface: Color(0xFF1C1F26),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1C1F26),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }
}