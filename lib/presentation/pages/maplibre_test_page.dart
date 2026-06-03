import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';

/// TEMPORÄRE Verifikationsseite (Stage A der MapLibre-Migration).
///
/// Zweck: beweisen, dass MapLibre GL Native den Mapbox-Dark-Style aus den
/// R2-PMTiles GPU-flüssig + korrekt rendert (kein vector_tile_renderer-Bug,
/// kein Stottern). Zielkoordinate = Bregenzerwald/Allgäu — genau die Stelle,
/// an der der alte Renderer das „Kontrast/Muster"-Problem zeigte.
///
/// Wird nach erfolgreicher Verifikation in cruise_mode_page integriert und
/// diese Datei wieder entfernt.
class MaplibreTestPage extends StatefulWidget {
  const MaplibreTestPage({super.key});

  @override
  State<MaplibreTestPage> createState() => _MaplibreTestPageState();
}

class _MaplibreTestPageState extends State<MaplibreTestPage> {
  String? _style;
  MapLibreMapController? _controller;
  String _status = 'lade Style…';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/map/cruise_dark.json').then((s) {
      if (mounted) setState(() => _style = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Scaffold(
      backgroundColor: const Color(0xFF0b0e13),
      body: Stack(
        children: [
          if (style != null)
            MapLibreMap(
              styleString: style,
              initialCameraPosition: const CameraPosition(
                target: LatLng(47.48, 9.92), // Bregenzerwald / Allgäu
                zoom: 11.0,
              ),
              onMapCreated: (c) => _controller = c,
              onStyleLoadedCallback: () {
                if (mounted) setState(() => _status = 'Style geladen ✓');
              },
              trackCameraPosition: true,
            )
          else
            const Center(child: CircularProgressIndicator()),
          // Debug-Statusleiste
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'MapLibre · $_status',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
