import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

/// Setup-Karte für die Routenplanung (Rundkurs / A-nach-B).
class CruiseSetupCard extends StatelessWidget {
  const CruiseSetupCard({
    super.key,
    required this.isRoundTrip,
    required this.planningType,
    required this.selectedLength,
    required this.selectedLocation,
    required this.selectedStyle,
    required this.selectedDestination,
    required this.destinationController,
    required this.onRoundTripChanged,
    required this.onPlanningTypeChanged,
    required this.onLengthChanged,
    required this.onLocationChanged,
    required this.onStyleChanged,
    required this.onDestinationSelected,
    required this.onDestinationCleared,
  });

  final bool isRoundTrip;
  final String planningType;
  final String selectedLength;
  final String selectedLocation;
  final String selectedStyle;
  final MapboxSuggestion? selectedDestination;
  final TextEditingController destinationController;
  final ValueChanged<bool> onRoundTripChanged;
  final ValueChanged<String> onPlanningTypeChanged;
  final ValueChanged<String> onLengthChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<String> onStyleChanged;
  final ValueChanged<MapboxSuggestion> onDestinationSelected;
  final VoidCallback onDestinationCleared;

  static const _geocodingService = GeocodingService();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'Strecken-Setup',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text(
            'Routen-Modus',
            style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LargeModeButton(
                  label: 'Rundkurs',
                  icon: Icons.loop,
                  isActive: isRoundTrip,
                  onTap: () => onRoundTripChanged(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LargeModeButton(
                  label: 'A nach B',
                  icon: Icons.alt_route,
                  isActive: !isRoundTrip,
                  onTap: () => onRoundTripChanged(false),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),
          AnimatedCrossFade(
            firstChild: _buildRoundTripOptions(),
            secondChild: _buildAtoBOptions(context),
            crossFadeState: isRoundTrip ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
          const Divider(color: Colors.white10, height: 32),
          if (isRoundTrip)
            _SelectionRow(
              title: 'Länge',
              options: const ['20 Km', '50 Km', '100 Km', '+100 Km'],
              selectedValue: selectedLength,
              onSelect: onLengthChanged,
            )
          else
            _buildDistanceInfoBox(),
          const Divider(color: Colors.white10, height: 32),
          _SelectionRow(
            title: 'Standort',
            options: const ['Aktueller Standort', 'Standort wählen'],
            selectedValue: selectedLocation,
            onSelect: onLocationChanged,
          ),
          const Divider(color: Colors.white10, height: 32),
          _SelectionRow(
            title: 'Stil',
            options: const ['Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'],
            selectedValue: selectedStyle,
            onSelect: onStyleChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildRoundTripOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Planungs-Typ',
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ChoiceButton(
                label: 'Zufall',
                isSelected: planningType == 'Zufall',
                onTap: () => onPlanningTypeChanged('Zufall'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceButton(
                label: 'Wegpunkte',
                isSelected: planningType == 'Wegpunkte',
                onTap: () => onPlanningTypeChanged('Wegpunkte'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAtoBOptions(BuildContext context) {
    if (selectedDestination != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zielort',
            style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFFFF3B30), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedDestination!.placeName,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      if (selectedDestination!.context != null)
                        Text(
                          selectedDestination!.context!,
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: onDestinationCleared,
                  tooltip: 'Ziel ändern',
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Zielort',
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: TypeAheadField<MapboxSuggestion>(
            controller: destinationController,
            suggestionsCallback: (pattern) async {
              if (pattern.isEmpty) return const [];
              return _geocodingService.searchSuggestions(pattern);
            },
            builder: (context, controller, focusNode) => TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: Colors.white38),
                hintText: 'Adresse suchen...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            itemBuilder: (context, suggestion) => ListTile(
              tileColor: const Color(0xFF1C1F26),
              leading: const Icon(Icons.location_on, color: Color(0xFFFF3B30)),
              title: Text(suggestion.placeName,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: suggestion.context != null
                  ? Text(suggestion.context!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12))
                  : null,
            ),
            onSelected: onDestinationSelected,
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Adresse eingeben...', style: TextStyle(color: Colors.grey)),
            ),
            loadingBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceInfoBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Länge',
          style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Distanz wird automatisch basierend auf dem Zielort berechnet.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════ PRIVATE HELPER WIDGETS ═══════════════════════════════

class _LargeModeButton extends StatelessWidget {
  const _LargeModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 100,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1C1F26) : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFFFF3B30) : Colors.white12,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 1)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? const Color(0xFFFF3B30) : Colors.white38, size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: FontWeight.bold, fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
              : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.white60,
            fontWeight: FontWeight.bold, fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelect,
  });

  final String title;
  final List<String> options;
  final String selectedValue;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
        ),
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
                      ? [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))]
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
