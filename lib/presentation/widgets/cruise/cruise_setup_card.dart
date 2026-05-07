import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
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
    this.onDestinationInputChanged,
    required this.selectedDetour,
    required this.onDetourChanged,
    this.selectedAvoidHighways = false,
    this.onAvoidHighwaysChanged,
    this.proximityLatitude,
    this.proximityLongitude,
    this.roundTripWaypointCount = 0,
    this.selectedWaypointIndex,
    this.replacingWaypointIndex,
    this.waypointActionsEnabled = true,
    this.onGenerateWaypointSeed,
    this.onRemoveLastWaypoint,
    this.onDeleteSelectedWaypoint,
    this.onReplaceSelectedWaypoint,
    this.onClearWaypoints,
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
  final ValueChanged<String>? onDestinationInputChanged;
  final bool selectedAvoidHighways;
  final ValueChanged<bool>? onAvoidHighwaysChanged;
  final double? proximityLatitude;
  final double? proximityLongitude;
  final int roundTripWaypointCount;
  final int? selectedWaypointIndex;
  final int? replacingWaypointIndex;
  final bool waypointActionsEnabled;
  final VoidCallback? onGenerateWaypointSeed;
  final VoidCallback? onRemoveLastWaypoint;
  final VoidCallback? onDeleteSelectedWaypoint;
  final VoidCallback? onReplaceSelectedWaypoint;
  final VoidCallback? onClearWaypoints;

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
    debugPrint('[RouteDebug][SetupCard] avoidHighways=$value');
    widget.onAvoidHighwaysChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final isRoundTrip = widget.isRoundTrip;
    final isWaypointPlanning =
        isRoundTrip && widget.planningType == 'Wegpunkte';
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey(
                isRoundTrip ? 'round_trip_options' : 'atob_options',
              ),
              child: isRoundTrip
                  ? _buildRoundTripOptions()
                  : _buildAtoBOptions(context),
            ),
          ),
          const Divider(color: Colors.white10, height: 32),
          if (isRoundTrip && !isWaypointPlanning) ...[
            _SelectionRow(
              title: 'Länge',
              options: const ['50 Km', '75 Km', '100 Km'],
              selectedValue: widget.selectedLength,
              onSelect: widget.onLengthChanged,
            ),
            const Divider(color: Colors.white10, height: 32),
          ],
          _HighwayToggleSwitch(
            isEnabled: _avoidHighways,
            onChanged: _setAvoidHighways,
          ),
          const Divider(color: Colors.white10, height: 32),
          _SelectionRow(
            title: 'Standort',
            options: const ['Aktueller Standort', 'Standort wählen'],
            selectedValue: widget.selectedLocation,
            onSelect: widget.onLocationChanged,
          ),
          const Divider(color: Colors.white10, height: 32),
          if ((isRoundTrip && !isWaypointPlanning) ||
              (!isRoundTrip && widget.selectedDetour != 'Direkt')) ...[
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

  Widget _buildDetourSelection() {
    return _SelectionRow(
      title: 'Route',
      options: const [
        'Direkt',
        'Kleiner Umweg',
        'Mittlerer Umweg',
        'Großer Umweg',
      ],
      selectedValue: widget.selectedDetour,
      onSelect: widget.onDetourChanged,
    );
  }

  Widget _buildRoundTripOptions() {
    final isWaypointPlanning = widget.planningType == 'Wegpunkte';
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: SlideTransition(position: offsetAnimation, child: child),
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(
              isWaypointPlanning
                  ? 'waypoint_planning_hint'
                  : 'random_planning_hint',
            ),
            child: isWaypointPlanning
                ? _buildWaypointPlanningHint()
                : _buildRandomPlanningHint(),
          ),
        ),
      ],
    );
  }

  Widget _buildWaypointPlanningHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _waypointHintText(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Die Strecke ergibt sich aus deinen Stopps. Stil und Aktionen steuerst du direkt auf der Karte.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRandomPlanningHint() {
    return const Padding(
      padding: EdgeInsets.only(top: 10),
      child: Text(
        'Die App erzeugt automatisch eine geprüfte Rundkursroute.',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
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
                color: AppAccentColors.accent.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: AppAccentColors.accent,
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
          const SizedBox(height: 20),
          _buildDetourSelection(),
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
            // Debounce: Geocoding erst ~450ms nach letztem Tastendruck (weniger
            // Flattern, weniger parallele Requests).
            debounceDuration: const Duration(milliseconds: 450),
            suggestionsCallback: (pattern) async {
              // Erst ab 2 Zeichen abfragen, sonst wenig sinnvolle Treffer.
              if (pattern.trim().length < 2) return [];
              try {
                return await CruiseSetupCard._geocodingService
                    .searchSuggestions(
                      pattern,
                      proximityLatitude: widget.proximityLatitude,
                      proximityLongitude: widget.proximityLongitude,
                    );
              } catch (e, stack) {
                debugPrint('[CruiseSetup] Vorschlags-Suche fehlgeschlagen: $e');
                debugPrintStack(stackTrace: stack);
                return [];
              }
            },
            errorBuilder: (context, error) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Suche gerade nicht möglich. Netz prüfen und erneut versuchen.',
                style: TextStyle(color: Colors.red.shade200, fontSize: 13),
              ),
            ),
            itemBuilder: (context, suggestion) => ListTile(
              tileColor: const Color(0xFF1C1F26),
              leading: Icon(Icons.location_on, color: AppAccentColors.accent),
              title: Text(
                suggestion.placeName,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle:
                  suggestion.context != null ||
                      suggestion.distanceMeters != null
                  ? Text(
                      [
                        if (suggestion.context != null) suggestion.context!,
                        if (suggestion.distanceMeters != null)
                          _formatSuggestionDistance(suggestion.distanceMeters!),
                      ].join(' · '),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    )
                  : null,
            ),
            onSelected: (suggestion) {
              FocusScope.of(context).unfocus();
              widget.onDestinationSelected(suggestion);
            },
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Mindestens 2 Zeichen eingeben oder anderes Stichwort probieren.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            loadingBuilder: (context) => Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: AppAccentColors.accent),
              ),
            ),
            builder: (context, controller, focusNode) => TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white),
              onChanged: widget.onDestinationInputChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: Colors.white38),
                hintText: 'Ziel suchen...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildDetourSelection(),
      ],
    );
  }

  String _formatSuggestionDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m entfernt';
    return '${(meters / 1000).toStringAsFixed(1)} km entfernt';
  }

  String _waypointHintText() {
    if (widget.roundTripWaypointCount == 0) {
      return 'Setze bis zu 3 Stopps, die deine Rundroute wirklich anfahren soll.';
    }
    final replacing = widget.replacingWaypointIndex;
    if (replacing != null && replacing >= 0) {
      return 'Tippe auf die Karte, um Stopp ${replacing + 1} neu zu setzen.';
    }
    final selected = widget.selectedWaypointIndex;
    if (selected != null && selected >= 0) {
      return 'Stopp ${selected + 1} ausgewählt. Nutze die Karten-Aktionen rechts.';
    }
    final pluralSuffix = widget.roundTripWaypointCount == 1 ? '' : 's';
    return '${widget.roundTripWaypointCount} Stopp$pluralSuffix gesetzt. Die Route fährt diese Punkte an.';
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
            color: isActive ? AppAccentColors.accent : Colors.white12,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppAccentColors.accent.withValues(alpha: 0.3),
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
              color: isActive ? AppAccentColors.accent : Colors.white38,
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
              ? AppAccentColors.accent.withValues(alpha: 0.15)
              : const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppAccentColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppAccentColors.accent : Colors.white60,
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
    final accentColor = AppAccentColors.accent;
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
                            color:
                                (highwaysIncluded ? accentColor : Colors.black)
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
                      ? AppAccentColors.accent
                      : const Color(0xFF0B0E14),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppAccentColors.accent.withValues(
                              alpha: 0.4,
                            ),
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
