import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/country_region.dart';
import 'package:cruise_connect/data/services/geocoding_service.dart';
import 'package:cruise_connect/domain/models/place_suggestion.dart';
import 'package:cruise_connect/presentation/widgets/cruise/mode_explainer_bubble.dart';

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
    this.destinationFocusNode,
    // 2026-05-28 (vucko): "Standort wählen" — Startort per Karte/Adresse.
    this.startLocationController,
    this.startLocationFocusNode,
    this.pickedStartLabel,
    this.onPickStartOnMap,
    this.onStartLocationSelected,
    this.onStartLocationCleared,
    // 2026-05-30 (vucko): Länder-Präferenz.
    this.countryPreference = CountryPreference.any,
    this.homeCountryCode,
    this.onCountryPreferenceChanged,
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
  final PlaceSuggestion? selectedDestination;
  final TextEditingController destinationController;
  // 2026-05-28 (vucko Startup-V Issue 3A): FocusNode wird von der Page
  // durchgereicht, damit dort beim Tippen die Bottom-Actions ausgeblendet
  // werden können (Overlay-Überlagerung verhindern).
  final FocusNode? destinationFocusNode;
  // 2026-05-28 (vucko): "Standort wählen"-Verkabelung.
  final TextEditingController? startLocationController;
  final FocusNode? startLocationFocusNode;
  final String? pickedStartLabel;
  final VoidCallback? onPickStartOnMap;
  final ValueChanged<PlaceSuggestion>? onStartLocationSelected;
  final VoidCallback? onStartLocationCleared;
  final CountryPreference countryPreference;
  final String? homeCountryCode;
  final ValueChanged<CountryPreference>? onCountryPreferenceChanged;
  final ValueChanged<bool> onRoundTripChanged;
  final ValueChanged<String> onPlanningTypeChanged;
  final ValueChanged<String> onLengthChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<String> onStyleChanged;
  final ValueChanged<String> onDetourChanged;
  final ValueChanged<PlaceSuggestion> onDestinationSelected;
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
  // 2026-05-24 (vucko): welcher Modus zeigt aktuell die Erklärungs-Bubble?
  // null = keine. 'roundtrip' | 'atob' | 'zufall' | 'wegpunkte'
  String? _activeExplainer;

  void _toggleExplainer(String key) {
    setState(() {
      _activeExplainer = _activeExplainer == key ? null : key;
    });
  }

  static const Map<String, String> _modeExplanations = {
    'roundtrip':
        'Rundkurs: Du startest und endest am gleichen Punkt. Perfekt für eine Feierabendrunde — wir suchen kurvige Straßen in der gewünschten Distanz.',
    'atob':
        'A nach B: Du gibst Start und Ziel an. Wir berechnen die schönste Fahrt dorthin, optional mit Wegpunkten dazwischen.',
    'zufall':
        'Zufall: Wir wählen den Rundkurs spontan — meist mit den kurvigsten Straßen rund um deinen Standort. Schnellste Option.',
    'wegpunkte':
        'Wegpunkte: Du tippst auf der Karte deine Stopps. Trip-Modus erlaubt bis 5 Stopps — perfekt für mehrtägige Touren mit Pause/Resume.',
  };

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
    if (kDebugMode) {
      debugPrint('[RouteDebug][SetupCard] avoidHighways=$value');
    }
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
                  onTap: () {
                    // Aktiver Modus + Klick → toggle Explainer.
                    // Inaktiver Modus + Klick → wechseln + Bubble zeigen.
                    if (isRoundTrip) {
                      _toggleExplainer('roundtrip');
                    } else {
                      widget.onRoundTripChanged(true);
                      setState(() => _activeExplainer = 'roundtrip');
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LargeModeButton(
                  label: 'A nach B',
                  icon: Icons.alt_route,
                  isActive: !isRoundTrip,
                  onTap: () {
                    if (!isRoundTrip) {
                      _toggleExplainer('atob');
                    } else {
                      widget.onRoundTripChanged(false);
                      setState(() => _activeExplainer = 'atob');
                    }
                  },
                ),
              ),
            ],
          ),
          // Animated Mode-Explainer-Bubble unter den Mode-Buttons
          ModeExplainerBubble(
            text: _modeExplanations[isRoundTrip ? 'roundtrip' : 'atob'] ?? '',
            accentColor: context.watch<AppAccentProvider>().color,
            isOpen:
                _activeExplainer == 'roundtrip' || _activeExplainer == 'atob',
            onDismiss: () => setState(() => _activeExplainer = null),
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
              options: const ['25 Km', '50 Km', '75 Km', '100 Km'],
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
          if (widget.selectedLocation == 'Standort wählen') ...[
            const SizedBox(height: 14),
            _buildStartLocationPicker(),
          ],
          // 2026-05-31 (vucko): Länder-Filter NUR bei Rundkurs/Zufall — bei
          // A→B (festes Ziel) und Wegpunkten ergibt eine Land-Präferenz keinen
          // Sinn, das Ziel/die Stopps bestimmen ja schon den Verlauf.
          if (isRoundTrip && !isWaypointPlanning) ...[
            const Divider(color: Colors.white10, height: 32),
            _buildCountryPreference(),
          ],
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
                onTap: () {
                  if (widget.planningType == 'Zufall') {
                    _toggleExplainer('zufall');
                  } else {
                    widget.onPlanningTypeChanged('Zufall');
                    setState(() => _activeExplainer = 'zufall');
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceButton(
                label: 'Wegpunkte',
                isSelected: widget.planningType == 'Wegpunkte',
                onTap: () {
                  if (widget.planningType == 'Wegpunkte') {
                    _toggleExplainer('wegpunkte');
                  } else {
                    widget.onPlanningTypeChanged('Wegpunkte');
                    setState(() => _activeExplainer = 'wegpunkte');
                  }
                },
              ),
            ),
          ],
        ),
        ModeExplainerBubble(
          text:
              _modeExplanations[widget.planningType == 'Zufall'
                  ? 'zufall'
                  : 'wegpunkte'] ??
              '',
          accentColor: context.watch<AppAccentProvider>().color,
          isOpen:
              _activeExplainer == 'zufall' || _activeExplainer == 'wegpunkte',
          onDismiss: () => setState(() => _activeExplainer = null),
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
                // 2026-06-16 (vucko): SizeTransition kennt KEIN `alignment` —
                // top-Ausrichtung läuft über axisAlignment (-1.0 = oben). Das alte
                // `alignment: Alignment.topCenter` brach den Build unter Flutter
                // 3.38.5 (kernel_snapshot Compile-Fehler); axisAlignment ist
                // versionsübergreifend gültig und optisch identisch.
                axisAlignment: -1.0,
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

    // 2026-05-31 (vucko): Google-Maps-artige Zielsuche. Backend ist bereits
    // POI-first (types=poi,place,address + proximity), d.h. „McDonald's
    // Hohenems" oder „Flughafen Zürich" funktionieren ohne genaue Adresse.
    // Hier nur die Optik aufgewertet: prominente Such-Bar mit Schatten,
    // einladender Placeholder + reichere Vorschlags-Kacheln (POI-Icon im
    // Akzent-Kreis, fetter Name, Adresse + Entfernung).
    final accent = AppAccentColors.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Zielort',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Name oder Adresse',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TypeAheadField<PlaceSuggestion>(
          controller: widget.destinationController,
          focusNode: widget.destinationFocusNode,
          debounceDuration: const Duration(milliseconds: 380),
          suggestionsCallback: (pattern) async {
            if (pattern.trim().length < 2) return [];
            try {
              return await CruiseSetupCard._geocodingService.searchSuggestions(
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
          // Abgerundete, abgesetzte Vorschlagsbox (wie Google-Maps-Dropdown).
          decorationBuilder: (context, child) => Material(
            color: const Color(0xFF161A22),
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withValues(alpha: 0.5),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          offset: const Offset(0, 8),
          constraints: const BoxConstraints(maxHeight: 320),
          errorBuilder: (context, error) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Suche gerade nicht möglich. Netz prüfen und erneut versuchen.',
              style: TextStyle(color: Colors.red.shade200, fontSize: 13),
            ),
          ),
          itemBuilder: (context, suggestion) {
            final parts = suggestion.placeName.split(',');
            final primary = parts.first.trim();
            final secondary = parts.length > 1
                ? parts.sublist(1).join(',').trim()
                : (suggestion.context ?? '');
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.place_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (secondary.isNotEmpty ||
                            suggestion.distanceMeters != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (secondary.isNotEmpty) secondary,
                                if (suggestion.distanceMeters != null)
                                  _formatSuggestionDistance(
                                    suggestion.distanceMeters!,
                                  ),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          itemSeparatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.05),
            indent: 62,
          ),
          onSelected: (suggestion) {
            FocusScope.of(context).unfocus();
            widget.onDestinationSelected(suggestion);
          },
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Kein Treffer — versuch z.B. „McDonald\'s Dornbirn" '
                    'oder „Flughafen Zürich".',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          loadingBuilder: (context) => Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: accent,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Suche läuft…',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          builder: (context, controller, focusNode) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: AppInputLimits.addressMaxLength,
              inputFormatters: AppInputLimits.lengthFormatters(
                AppInputLimits.addressMaxLength,
              ),
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              onChanged: widget.onDestinationInputChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1E232C),
                prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
                hintText: 'z.B. McDonald\'s, Flughafen Zürich …',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent, width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
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

  // 2026-05-30 (vucko): Länder-Präferenz — 3 Stufen. Land wird automatisch
  // erkannt (am Startpunkt) und im Untertitel angezeigt, damit der User weiß,
  // worauf sich „im Land bleiben" bezieht (Pass/Ausweis-Thema).
  static const Map<String, String> _countryNames = {
    'AT': '🇦🇹 Österreich',
    'DE': '🇩🇪 Deutschland',
    'CH': '🇨🇭 Schweiz',
    'LI': '🇱🇮 Liechtenstein',
    'IT': '🇮🇹 Italien',
    'SI': '🇸🇮 Slowenien',
  };

  // Kurzform fürs Segment-Label „Nur <Land>".
  static const Map<String, String> _countryShortNames = {
    'AT': 'Österreich',
    'DE': 'Deutschland',
    'CH': 'Schweiz',
    'LI': 'Liechtenstein',
    'IT': 'Italien',
    'SI': 'Slowenien',
  };

  // 2026-05-31 (vucko): Länder-Filter als Toggle (2 Optionen), Design identisch
  // zum Autobahn-Zugang-Widget. AN = nur im Heimatland bleiben, AUS = egal.
  Widget _buildCountryPreference() {
    final accent = AppAccentColors.accent;
    final homeShort = widget.homeCountryCode == null
        ? 'Inland'
        : (_countryShortNames[widget.homeCountryCode!.toUpperCase()] ??
              'Inland');
    // Bool-State: AN = onlyHome, AUS = any. preferHome wird auf „an" gemappt
    // (Altwert aus Persistenz), damit nichts hängt.
    final onlyHome = widget.countryPreference != CountryPreference.any;
    final accentColor = accent;
    final backgroundColor = onlyHome
        ? accentColor.withValues(alpha: 0.12)
        : const Color(0xFF0B0E14);
    final borderColor = onlyHome
        ? accentColor.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.08);
    final description = onlyHome
        ? 'Route bleibt in $homeShort — keine Grenzübertritte.'
        : 'Grenzübertritte erlaubt — die schönste Route zählt.';

    return Semantics(
      button: true,
      toggled: onlyHome,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onCountryPreferenceChanged?.call(
            onlyHome ? CountryPreference.any : CountryPreference.onlyHome,
          ),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: onlyHome ? 1.5 : 1),
              boxShadow: onlyHome
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
                    color: onlyHome
                        ? accentColor.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    onlyHome ? Icons.shield_rounded : Icons.public_rounded,
                    color: onlyHome ? accentColor : Colors.white60,
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
                          // 2026-06-08 (vucko): Flexible + ellipsis → kein
                          // RenderFlex-Overflow (war 11px) bei schmalem Layout.
                          const Flexible(
                            child: Text(
                              'Im Land bleiben',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
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
                              color: onlyHome
                                  ? accentColor.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              onlyHome ? 'AN' : 'AUS',
                              style: TextStyle(
                                color: onlyHome ? accentColor : Colors.white70,
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
                    color: onlyHome
                        ? accentColor.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: onlyHome
                          ? accentColor.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: onlyHome
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: onlyHome ? accentColor : Colors.white70,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (onlyHome ? accentColor : Colors.black)
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

  // ignore: unused_element
  Widget _buildCountryPreferenceLegacy() {
    final accent = AppAccentColors.accent;
    final homeName = widget.homeCountryCode == null
        ? null
        : _countryNames[widget.homeCountryCode!.toUpperCase()];
    final homeShort = widget.homeCountryCode == null
        ? 'Inland'
        : (_countryShortNames[widget.homeCountryCode!.toUpperCase()] ??
              'Inland');
    final options = <(CountryPreference, IconData, String, String)>[
      (
        CountryPreference.any,
        Icons.public_rounded,
        'Überall',
        'Grenzübertritte sind erlaubt — die schönste Route zählt.',
      ),
      (
        CountryPreference.preferHome,
        Icons.home_rounded,
        'Bevorzugt',
        'Bleibt möglichst in $homeShort, kreuzt die Grenze nur wenn nötig.',
      ),
      (
        CountryPreference.onlyHome,
        Icons.shield_rounded,
        'Nur $homeShort',
        'Vermeidet Grenzübertritte — ideal ohne Ausweis/Pass dabei.',
      ),
    ];
    final activeSubtitle = options
        .firstWhere((o) => o.$1 == widget.countryPreference)
        .$4;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Titel + (auto-erkanntes Land als Chip)
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.travel_explore_rounded,
                  color: accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Land',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Wie sehr im Heimatland bleiben?',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (homeName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    homeName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 3 Segment-Optionen mit Icon + Label
          Row(
            children: [
              for (final (pref, icon, label, _) in options) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onCountryPreferenceChanged?.call(pref),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: widget.countryPreference == pref
                            ? LinearGradient(
                                colors: [
                                  accent.withValues(alpha: 0.30),
                                  accent.withValues(alpha: 0.14),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                        color: widget.countryPreference == pref
                            ? null
                            : const Color(0xFF14171F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.countryPreference == pref
                              ? accent
                              : Colors.white12,
                          width: widget.countryPreference == pref ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 19,
                            color: widget.countryPreference == pref
                                ? Colors.white
                                : Colors.white54,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.countryPreference == pref
                                  ? Colors.white
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (pref != options.last.$1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Untertitel zur aktiven Auswahl.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.countryPreference == CountryPreference.onlyHome
                      ? '$activeSubtitle In Grenzregionen (z.B. Vorarlberg) '
                            'bleiben wir so nah wie möglich am Land, falls keine '
                            'reine Inlandsroute existiert.'
                      : activeSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2026-05-28 (vucko): "Standort wählen" — Startpunkt per Karten-Tap ODER
  // Adresssuche. Zeigt, falls schon gesetzt, eine Bestätigungs-Chip-Zeile.
  Widget _buildStartLocationPicker() {
    final accent = AppAccentColors.accent;
    final picked = widget.pickedStartLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (picked != null && picked.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF34C759).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF34C759),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Start: $picked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onStartLocationCleared,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        // Karten-Tap-Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onPickStartOnMap,
            icon: Icon(Icons.touch_app_rounded, color: accent, size: 18),
            label: const Text(
              'Auf Karte tippen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              backgroundColor: const Color(0xFF0B0E14),
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'oder',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 10),
        // Adresssuche (Startort)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TypeAheadField<PlaceSuggestion>(
            controller: widget.startLocationController,
            focusNode: widget.startLocationFocusNode,
            debounceDuration: const Duration(milliseconds: 450),
            suggestionsCallback: (pattern) async {
              if (pattern.trim().length < 2) return [];
              try {
                return await CruiseSetupCard._geocodingService
                    .searchSuggestions(
                      pattern,
                      proximityLatitude: widget.proximityLatitude,
                      proximityLongitude: widget.proximityLongitude,
                    );
              } catch (e) {
                debugPrint('[CruiseSetup] Startort-Suche fehlgeschlagen: $e');
                return [];
              }
            },
            itemBuilder: (context, suggestion) => ListTile(
              tileColor: const Color(0xFF1C1F26),
              leading: const Icon(
                Icons.my_location_rounded,
                color: Color(0xFF34C759),
              ),
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
            onSelected: (suggestion) {
              FocusScope.of(context).unfocus();
              widget.onStartLocationSelected?.call(suggestion);
            },
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Mindestens 2 Zeichen eingeben.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            loadingBuilder: (context) => Padding(
              padding: const EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator(color: accent)),
            ),
            builder: (context, controller, focusNode) => TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: AppInputLimits.addressMaxLength,
              inputFormatters: AppInputLimits.lengthFormatters(
                AppInputLimits.addressMaxLength,
              ),
              style: const TextStyle(color: Colors.white),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                prefixIcon: const Icon(Icons.search, color: Colors.white60),
                hintText: 'Startort eingeben…',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: accent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
                          // 2026-06-08 (vucko): Flexible + ellipsis → kein
                          // RenderFlex-Overflow mehr, wenn Titel + Badge in
                          // schmalen Layouts knapp werden (war 22px Overflow).
                          Flexible(
                            child: Text(
                              'Autobahn-Zugang',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.96),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
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
