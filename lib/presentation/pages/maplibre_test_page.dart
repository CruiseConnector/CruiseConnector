import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';

/// TEMP Style-Diagnose-Harness: Vollbild-MapLibre-Karte am Bregenzerwald/Rheintal
/// (User-Problemstelle) mit Zoom-Buttons, um Spots + Labels in MEHREREN
/// Zoomstufen zu prüfen. Keine Route/Marker — nur die Basiskarte.
class MaplibreTestPage extends StatefulWidget {
  const MaplibreTestPage({super.key});

  @override
  State<MaplibreTestPage> createState() => _MaplibreTestPageState();
}

class _MaplibreTestPageState extends State<MaplibreTestPage> {
  CruiseMapLibreController? _ctrl;
  // Start am Rheintal (Dornbirn/Götzis/Hohenems) — die Orte, die der User
  // benannt haben will, + die Täler mit den „Spots".
  static final _center = ll.LatLng(47.38, 9.72);
  double _zoom = 11;

  void _setZoom(double z) {
    _zoom = z.clamp(4, 18);
    _ctrl?.animateTo(
      lat: _center.latitude,
      lng: _center.longitude,
      zoom: _zoom,
      duration: const Duration(milliseconds: 250),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b0e13),
      body: Stack(
        children: [
          CruiseMapLibreMap(
            initialCenter: _center,
            initialZoom: _zoom,
            onControllerReady: (c) => _ctrl = c,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Text('z ${_zoom.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  FloatingActionButton.small(
                    heroTag: 'zin',
                    onPressed: () => _setZoom(_zoom + 1),
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'zout',
                    onPressed: () => _setZoom(_zoom - 1),
                    child: const Icon(Icons.remove),
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
