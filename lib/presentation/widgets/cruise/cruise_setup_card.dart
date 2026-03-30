import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/domain/models/mapbox_suggestion.dart';

/// Setup-Karte für die Routenplanung (Rundkurs / A-nach-B).
class CruiseSetupCard extends StatefulWidget {
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
    required this.selectedDetour,
    required this.onDetourChanged,
    this.selectedAvoidHighways = false,
    this.onAvoidHighwaysChanged,
  });

  final bool isRoundTrip;
  final String planningType;
  final String selectedLength;
  final String selectedLocation;
  final String selectedStyle;
  final String selectedDetour;
  final MapboxSuggestion? selectedDestination;
  final TextEditingController destinationController;
  final ValueChanged<bool> onRoundTripChanged;
  final ValueChanged<String> onPlanningTypeChanged;
  final ValueChanged<String> onLengthChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<String> onStyleChanged;
  final ValueChanged<String> onDetourChanged;
  final ValueChanged<MapboxSuggestion> onDestinationSelected;
  final VoidCallback onDestinationCleared;
  final bool selectedAvoidHighways;
  final ValueChanged<bool>? onAvoidHighwaysChanged;

  static const _geocodingService = GeocodingService();

  @override
  State<CruiseSetupCard> createState() => _CruiseSetupCardState();
}

class _CruiseSetupCardState extends State<CruiseSetupCard> {
  late bool _avoidHighways;

  @override
  void initState() {
    super.initState();
    _avoidHighways = widget.selectedAvoidHighways;
  }

  @override
  void didUpdateWidget(CruiseSetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAvoidHighways != widget.selectedAvoidHighways) {
      _avoidHighways = widget.selectedAvoidHighways;
    }
  }

  void _setAvoidHighways(bool value) {
    setState(() => _avoidHighways = value);
    widget.onAvoidHighwaysChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final isRoundTrip = widget.isRoundTrip;
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Routen-Modus',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LargeModeButton(
                  label: 'Rundkurs',
                  icon: Icons.loop,
                  isActive: isRoundTrip,
                  onTap: () => widget.onRoundTripChanged(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LargeModeButton(
                  label: 'A nach B',
                  icon: Icons.alt_route,
                  isActive: !isRoundTrip,
                  onTap: () => widget.onRoundTripChanged(false),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),
          AnimatedCrossFade(
            firstChild: _buildRoundTripOptions(),
            secondChild: _buildAtoBOptions(context),
            crossFadeState: isRoundTrip
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
          const Divider(color: Colors.white10, height: 32),
          if (isRoundTrip) ...[
            _SelectionRow(
              title: 'Länge',
              options: const ['50 Km', '75 Km', '100 Km', '150 Km'],
              selectedValue: widget.selectedLength,
              onSelect: widget.onLengthChanged,
            ),
            const Divider(color: Colors.white10, height: 32),
          ] else ...[
            _SelectionRow(
              title: 'Route',
              options: const [
                'Direkt',
                'Kleiner Umweg',
                'Mittlerer Umweg',
                'Großer Umweg',
              ],
              selectedValue: widget.selectedDetour,
              onSelect: widget.onDetourChanged,
            ),
            const Divider(color: Colors.white10, height: 32),
            _HighwayToggleSwitch(
              isEnabled: _avoidHighways,
              onChanged: _setAvoidHighways,
            ),
            const Divider(color: Colors.white10, height: 32),
          ],
          _SelectionRow(
            title: 'Standort',
            options: const ['Aktueller Standort', 'Standort wählen'],
            selectedValue: widget.selectedLocation,
            onSelect: widget.onLocationChanged,
          ),
          const Divider(color: Colors.white10, height: 32),
          if (isRoundTrip || widget.selectedDetour != 'Direkt') ...[
            _SelectionRow(
              title: 'Stil',
              options: const [
                'Kurvenjagd',
                'Sport Mode',
                'Abendrunde',
                'Entdecker',
              ],
              selectedValue: widget.selectedStyle,
              onSelect: widget.onStyleChanged,
            ),
          ],
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
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ChoiceButton(
                label: 'Zufall',
                isSelected: widget.planningType == 'Zufall',
                onTap: () => widget.onPlanningTypeChanged('Zufall'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceButton(
                label: 'Wegpunkte',
                isSelected: widget.planningType == 'Wegpunkte',
                onTap: () => widget.onPlanningTypeChanged('Wegpunkte'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAtoBOptions(BuildContext context) {
    if (widget.selectedDestination != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zielort',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Color(0xFFFF3B30),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.selectedDestination!.placeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.selectedDestination!.context != null)
                        Text(
                          widget.selectedDestination!.context!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: widget.onDestinationCleared,
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
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: TypeAheadField<MapboxSuggestion>(
            controller: widget.destinationController,
            suggestionsCallback: (pattern) async {
              if (pattern.isEmpty) return const [];
              return CruiseSetupCard._geocodingService.searchSuggestions(
                pattern,
              );
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
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            itemBuilder: (context, suggestion) => ListTile(
              tileColor: const Color(0xFF1C1F26),
              leading: const Icon(Icons.location_on, color: Color(0xFFFF3B30)),
              title: Text(
                suggestion.placeName,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: suggestion.context != null
                  ? Text(
                      suggestion.context!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    )
                  : null,
            ),
            onSelected: widget.onDestinationSelected,
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Adresse eingeben...',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            loadingBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
              ),
            ),
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
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFFF3B30) : Colors.white38,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _HighwayToggleSwitch extends StatelessWidget {
  const _HighwayToggleSwitch({
    required this.isEnabled,
    required this.onChanged,
  });

  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isEnabled
            ? const Color(0xFFFF3B30).withValues(alpha: 0.10)
            : const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEnabled
              ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isEnabled
                  ? const Color(0xFFFF3B30).withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.block_rounded,
              color: isEnabled ? const Color(0xFFFF3B30) : Colors.white54,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autobahn vermeiden',
                  style: TextStyle(
                    color: isEnabled ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Motorway, motorway_link und trunk werden gemieden.',
                  style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: FittedBox(
              child: Switch.adaptive(
                value: isEnabled,
                onChanged: onChanged,
                activeThumbColor: const Color(0xFFFF3B30),
                activeTrackColor: const Color(
                  0xFFFF3B30,
                ).withValues(alpha: 0.4),
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
        ],
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
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF3B30)
                      : const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFFFF3B30,
                            ).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
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
