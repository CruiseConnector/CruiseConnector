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
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Wegpunkt-Planung folgt in einer separaten Ausbaustufe.',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
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
    final highwaysIncluded = !isEnabled;
    final accentColor = highwaysIncluded
        ? const Color(0xFFFF5A36)
        : const Color(0xFFFF3B30);
    final backgroundColor = highwaysIncluded
        ? accentColor.withValues(alpha: 0.12)
        : const Color(0xFF0B0E14);
    final borderColor = highwaysIncluded
        ? accentColor.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.08);
    final description = highwaysIncluded
        ? 'Autobahnen eingeschlossen'
        : 'Nur Landstraßen & Ortsstraßen';

    return Semantics(
      button: true,
      toggled: highwaysIncluded,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!isEnabled),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: highwaysIncluded ? 1.5 : 1,
              ),
              boxShadow: highwaysIncluded
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: highwaysIncluded
                        ? accentColor.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    highwaysIncluded
                        ? Icons.speed_rounded
                        : Icons.route_rounded,
                    color: highwaysIncluded ? accentColor : Colors.white60,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Autobahn-Zugang',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: highwaysIncluded
                                  ? accentColor.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              highwaysIncluded ? 'AN' : 'AUS',
                              style: TextStyle(
                                color: highwaysIncluded
                                    ? accentColor
                                    : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 54,
                  height: 32,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: highwaysIncluded
                        ? accentColor.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: highwaysIncluded
                          ? accentColor.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: highwaysIncluded
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: highwaysIncluded ? accentColor : Colors.white70,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (highwaysIncluded
                                    ? accentColor
                                    : Colors.black)
                                .withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
