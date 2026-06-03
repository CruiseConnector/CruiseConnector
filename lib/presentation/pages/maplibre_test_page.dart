import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';

/// TEMPORÄRE Verifikationsseite (Stage B der MapLibre-Migration).
///
/// Prüft im Simulator: Mapbox-Dark-Basis (GPU, clean) + Route als GL-Linie +
/// Marker als projizierte Flutter-Overlays + Tap — am Bregenzerwald, der
/// alten „Kontrast/Muster"-Problemstelle. Wird nach Verifikation in
/// cruise_mode_page integriert und entfernt.
class MaplibreTestPage extends StatefulWidget {
  const MaplibreTestPage({super.key});

  @override
  State<MaplibreTestPage> createState() => _MaplibreTestPageState();
}

class _MaplibreTestPageState extends State<MaplibreTestPage> {
  CruiseMapLibreController? _ctrl;
  String _status = 'lädt…';
  ll.LatLng? _lastTap;

  // Beispiel-Route durch den Bregenzerwald (eine kleine Schleife).
  static final _route = <ll.LatLng>[
    ll.LatLng(47.503, 9.747),
    ll.LatLng(47.495, 9.820),
    ll.LatLng(47.482, 9.892),
    ll.LatLng(47.470, 9.955),
    ll.LatLng(47.445, 9.985),
    ll.LatLng(47.430, 9.920),
    ll.LatLng(47.452, 9.860),
  ];

  @override
  Widget build(BuildContext context) {
    final markers = <CruiseMapMarker>[
      // Puck (Mitte der Koordinate)
      CruiseMapMarker(
        id: 'puck',
        position: ll.LatLng(47.482, 9.892),
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2F7BFF),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ),
      // Ziel-Pin (Spitze unten auf der Koordinate)
      CruiseMapMarker(
        id: 'dest',
        position: ll.LatLng(47.430, 9.920),
        width: 40,
        height: 48,
        alignment: Alignment.bottomCenter,
        child: const Icon(Icons.location_on, color: Color(0xFFFF3B30), size: 48),
      ),
      // Waypoint-Badge "1"
      CruiseMapMarker(
        id: 'wp1',
        position: ll.LatLng(47.495, 9.820),
        width: 30,
        height: 30,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Text('1',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
      if (_lastTap != null)
        CruiseMapMarker(
          id: 'tap',
          position: _lastTap!,
          width: 18,
          height: 18,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.amber,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0b0e13),
      body: Stack(
        children: [
          CruiseMapLibreMap(
            initialCenter: ll.LatLng(47.482, 9.892),
            initialZoom: 11.5,
            lines: [
              CruiseMapLine(
                points: _route,
                color: const Color(0xFFFF3B30).withValues(alpha: 0.30),
                width: 12,
              ),
              CruiseMapLine(
                points: _route,
                color: const Color(0xFFFF3B30),
                width: 5,
              ),
            ],
            markers: markers,
            onControllerReady: (c) {
              _ctrl = c;
              if (mounted) setState(() => _status = 'bereit ✓');
            },
            onMapClick: (p) {
              if (mounted) {
                setState(() {
                  _lastTap = p;
                  _status =
                      'Tap ${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
                });
              }
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('MapLibre · $_status',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  const Spacer(),
                  FloatingActionButton.small(
                    heroTag: 'fit',
                    onPressed: () => _ctrl?.fitBounds(_route,
                        padding: const EdgeInsets.all(60)),
                    child: const Icon(Icons.fit_screen),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
