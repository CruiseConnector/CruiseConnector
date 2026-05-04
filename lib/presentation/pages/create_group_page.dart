import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../data/services/cruise_group_service.dart';
import '../../data/services/geocoding_service.dart';
import '../../data/services/route_service.dart';
import '../../domain/models/route_result.dart';
import 'group_lobby_page.dart';

/// Gruppenerstellung mit Live-Map: Startpunkt wählen (GPS / Karte / Adresse),
/// Route generieren, dann als Gruppe in Supabase speichern.
class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // ignore: prefer_const_constructors
  final _routeService = RouteService();
  final _geocodingService = const GeocodingService();
  final _mapController = MapController();

  // Form
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  double _maxPeople = 10;
  String _selectedLength = '50 Km';
  String _selectedLocation = 'Aktueller Standort'; // oder 'Karte antippen'
  String _selectedStyle = 'Sport Mode';
  String _selectedVisibility = 'Öffentlich (Für jeden)';
  DateTime? _selectedDateTime;

  // Map-State
  LatLng? _startPoint;
  List<LatLng> _routeLatLngs = [];
  RouteResult? _lastRoute;

  bool _isGenerating = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _tryLocateUser();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // ── Location helpers ──────────────────────────────────────────────────────

  Future<void> _tryLocateUser() async {
    try {
      final pos = await _getCurrentPosition();
      if (!mounted) return;
      setState(() => _startPoint = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_startPoint!, 12);
    } catch (_) {
      // Permission verweigert — User kann per Karte wählen.
    }
  }

  Future<geo.Position> _getCurrentPosition() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) throw Exception('Standort ist deaktiviert.');
    var perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      throw Exception('Standort-Berechtigung fehlt.');
    }
    return geo.Geolocator.getCurrentPosition(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _geocodeAddress() async {
    if (_addressCtrl.text.trim().isEmpty) return;
    final res = await _geocodingService.getCoordinatesFromAddress(
      _addressCtrl.text.trim(),
    );
    if (res == null) {
      _showError('Adresse nicht gefunden.');
      return;
    }
    setState(() {
      _startPoint = LatLng(res['latitude']!, res['longitude']!);
    });
    _mapController.move(_startPoint!, 12);
  }

  Future<void> _generateRoute() async {
    if (_isGenerating) return;
    if (_startPoint == null) {
      _showError('Bitte Startpunkt wählen (GPS oder Karte antippen).');
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final digits = _selectedLength.replaceAll(RegExp(r'[^0-9]'), '');
      final distance = digits.isNotEmpty ? int.parse(digits) : 50;

      final pos = geo.Position(
        latitude: _startPoint!.latitude,
        longitude: _startPoint!.longitude,
        timestamp: DateTime.now(),
        accuracy: 1,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );

      final result = await _routeService.generateRoundTrip(
        startPosition: pos,
        targetDistanceKm: distance,
        mode: _selectedStyle,
        planningType: 'Zufall',
      );

      final coords = result.coordinates
          .map((c) => LatLng(c[1], c[0])) // [lng,lat] → LatLng(lat,lng)
          .toList();

      setState(() {
        _lastRoute = result;
        _routeLatLngs = coords;
      });

      if (coords.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(coords),
            padding: const EdgeInsets.all(40),
          ),
        );
      }
    } catch (e) {
      _showError('Route-Generierung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    if (_lastRoute == null || _startPoint == null) {
      _showError('Bitte zuerst eine Route generieren.');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Bitte Gruppennamen eingeben.');
      return;
    }
    if (_selectedDateTime == null) {
      _showError('Bitte Datum & Uhrzeit wählen.');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final startDt = _selectedDateTime;

      final routeData = <String, dynamic>{
        'geoJson': _lastRoute!.geoJson,
        'coordinates': _lastRoute!.coordinates,
        'distance_meters': _lastRoute!.distanceMeters,
        'duration_seconds': _lastRoute!.durationSeconds,
        'style': _selectedStyle,
        'length_km_target':
            int.tryParse(_selectedLength.replaceAll(RegExp(r'[^0-9]'), '')) ??
            50,
      };

      final groupId = await CruiseGroupService.create(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        isPublic: _selectedVisibility == 'Öffentlich (Für jeden)',
        maxPeople: _maxPeople.round(),
        startTime: startDt,
        routeData: routeData,
        startLocation: {
          'lat': _startPoint!.latitude,
          'lng': _startPoint!.longitude,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: groupId)),
      );
    } catch (e) {
      _showError('Gruppe konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: const Color(0xFF0B0E14),
                elevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(background: _buildMap()),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_lastRoute != null) _buildRouteStats(),

                      const Text(
                        'Strecken-Setup',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSelectionRow(
                        'Länge',
                        ['20 Km', '50 Km', '100 Km', '+100 Km'],
                        _selectedLength,
                        (v) => setState(() => _selectedLength = v),
                      ),
                      const SizedBox(height: 24),
                      _buildSelectionRow(
                        'Startpunkt',
                        ['Aktueller Standort', 'Karte antippen', 'Adresse'],
                        _selectedLocation,
                        (v) async {
                          setState(() => _selectedLocation = v);
                          if (v == 'Aktueller Standort') await _tryLocateUser();
                        },
                      ),
                      if (_selectedLocation == 'Adresse') ...[
                        const SizedBox(height: 12),
                        _buildAddressField(),
                      ],
                      const SizedBox(height: 24),
                      _buildSelectionRow(
                        'Stil',
                        ['Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'],
                        _selectedStyle,
                        (v) => setState(() => _selectedStyle = v),
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'Gruppen-Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildGroupDetailsCard(),
                      const SizedBox(height: 24),
                      _buildNameField(),
                      const SizedBox(height: 20),
                      const Text(
                        'Beschreibung',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDescriptionField(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _startPoint ?? const LatLng(48.1351, 11.5820),
        initialZoom: 10,
        onTap: _selectedLocation == 'Karte antippen'
            ? (_, p) => setState(() => _startPoint = p)
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
          additionalOptions: {'accessToken': AppConstants.mapboxPublicToken},
          userAgentPackageName: 'com.cruise_connect.app',
          retinaMode: true,
        ),
        if (_routeLatLngs.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routeLatLngs,
                color: AppAccentColors.accent,
                strokeWidth: 5,
              ),
            ],
          ),
        if (_startPoint != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _startPoint!,
                width: 36,
                height: 36,
                child: Icon(
                  Icons.location_on,
                  color: AppAccentColors.accent,
                  size: 36,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRouteStats() {
    final km = ((_lastRoute!.distanceMeters ?? 0) / 1000).toStringAsFixed(1);
    final dur = _lastRoute!.durationSeconds ?? 0;
    final h = (dur / 3600).floor();
    final m = ((dur % 3600) / 60).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppAccentColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRouteStat(Icons.straighten, '$km km'),
          _buildRouteStat(Icons.timer, '${h}h ${m}m'),
          _buildRouteStat(
            Icons.route,
            '${_lastRoute!.coordinates.length} Punkte',
          ),
        ],
      ),
    );
  }

  Widget _buildRouteStat(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: AppAccentColors.accent, size: 16),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _buildAddressField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addressCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Adresse oder Ort',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _geocodeAddress(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.search, color: AppAccentColors.accent),
            onPressed: _geocodeAddress,
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _nameCtrl,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Gruppenname',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TextField(
        controller: _descCtrl,
        style: const TextStyle(color: Colors.white),
        maxLines: 5,
        decoration: InputDecoration(
          hintText: 'Beschreibe deine Gruppe...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildGroupDetailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          InkWell(
            onTap: _selectTime,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Startuhrzeit *',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedDateTime != null
                          ? _formatDateTime(_selectedDateTime!)
                          : 'Wählen',
                      style: TextStyle(
                        color: _selectedDateTime != null
                            ? Colors.white
                            : AppAccentColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            color: Colors.white10,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Max. Personen',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  '${_maxPeople.round()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppAccentColors.accent,
              inactiveTrackColor: Colors.grey[800],
              thumbColor: Colors.white,
              overlayColor: AppAccentColors.accent.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _maxPeople,
              min: 2,
              max: 50,
              divisions: 48,
              onChanged: (v) => setState(() => _maxPeople = v),
            ),
          ),
          const Divider(
            color: Colors.white10,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zugänglichkeit',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ['Nur Kontakte', 'Öffentlich (Für jeden)'].map((
                    option,
                  ) {
                    final isSelected = option == _selectedVisibility;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedVisibility = option),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppAccentColors.accent
                              : const Color(0xFF1A1D24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[400],
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
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
    );
  }

  Widget _buildSelectionRow(
    String title,
    List<String> options,
    String selectedValue,
    Function(String) onSelect,
  ) {
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

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
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
                  onPressed: _isGenerating ? null : _generateRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C1F26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Generieren',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
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
                  onPressed: (_isCreating || _lastRoute == null)
                      ? null
                      : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    disabledBackgroundColor: AppAccentColors.accent.withValues(
                      alpha: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Erstellen',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectTime() async {
    final now = DateTime.now();
    Widget theme(BuildContext ctx, Widget? child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: ColorScheme.dark(
          primary: AppAccentColors.accent,
          surface: const Color(0xFF1C1F26),
          onSurface: Colors.white,
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1C1F26)),
      ),
      child: child!,
    );

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: theme,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedDateTime != null
          ? TimeOfDay.fromDateTime(_selectedDateTime!)
          : TimeOfDay.now(),
      builder: theme,
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final d =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }
}

// Hilft beim JSON-Encoding sicherzustellen, dass JSONB-Struktur valide ist.
// (nur referenziert, falls wir die Route-Data lokal debuggen wollen)
// ignore: unused_element
String _debugEncode(Object o) => jsonEncode(o);
