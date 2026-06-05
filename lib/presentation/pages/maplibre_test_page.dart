import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';

/// TEMP Style-Diagnose-Harness: Vollbild-MapLibre-Karte am Bregenzerwald/Rheintal
/// (User-Problemstelle). AUTO-CYCLE durch mehrere (Center,Zoom)-Stufen alle paar
/// Sekunden, damit ohne UI-Taps (computer-use offline) per simctl-Screenshot
/// jede Zoomstufe geprüft werden kann. Großes Zoom-Label zum Zuordnen.
class MaplibreTestPage extends StatefulWidget {
  const MaplibreTestPage({super.key});

  @override
  State<MaplibreTestPage> createState() => _MaplibreTestPageState();
}

class _MaplibreTestPageState extends State<MaplibreTestPage> {
  CruiseMapLibreController? _ctrl;

  // Auto-Cycle-Stufen: Overview (Bodensee+Rheintal) → Rheintal → Hügel
  // (Kehlegg/Ebnit, wo der User die Spots markiert hat) → Stadt Dornbirn.
  static final _steps = <({ll.LatLng center, double zoom, String label})>[
    (center: const ll.LatLng(47.45, 9.66), zoom: 9, label: 'z9 Bodensee+Rheintal (Overview)'),
    (center: const ll.LatLng(47.38, 9.72), zoom: 11, label: 'z11 Dornbirn/Götzis'),
    (center: const ll.LatLng(47.39, 9.80), zoom: 13, label: 'z13 Kehlegg/Ebnit (Hügel)'),
    (center: const ll.LatLng(47.413, 9.742), zoom: 15, label: 'z15 Dornbirn Stadt'),
  ];

  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Erst nach Controller-Ready cyclen (siehe onControllerReady).
  }

  void _startCycle() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      _idx = (_idx + 1) % _steps.length;
      _applyStep();
    });
  }

  void _applyStep() {
    final s = _steps[_idx];
    _ctrl?.animateTo(
      lat: s.center.latitude,
      lng: s.center.longitude,
      zoom: s.zoom,
      duration: const Duration(milliseconds: 500),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _steps[_idx];
    return Scaffold(
      backgroundColor: const Color(0xFF0b0e13),
      body: Stack(
        children: [
          CruiseMapLibreMap(
            initialCenter: _steps.first.center,
            initialZoom: _steps.first.zoom,
            onControllerReady: (c) {
              _ctrl = c;
              _startCycle();
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Text(
                    s.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
