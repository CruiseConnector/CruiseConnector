import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

/// TEMP: verifiziert, dass MapLibre PMTiles aus einer LOKALEN Datei rendert
/// (Schema `pmtiles://file://…`) — der Kern des Offline-Modus. Nutzt die kleine
/// world_z6.pmtiles (~43 MB), lädt sie lokal, zeigt den Style auf die lokale
/// Datei. Rendert die Welt → lokales PMTiles-Lesen funktioniert.
class MaplibreLocalTest extends StatefulWidget {
  const MaplibreLocalTest({super.key});

  @override
  State<MaplibreLocalTest> createState() => _MaplibreLocalTestState();
}

class _MaplibreLocalTestState extends State<MaplibreLocalTest> {
  String _status = 'lade world_z6 lokal…';
  String? _style;

  static const _url =
      'https://pub-0535dd4f86054de1820907b6f06bf17c.r2.dev/world_z6.pmtiles';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/world_z6_test.pmtiles');
      if (!await f.exists() || (await f.length()) < 1024 * 1024) {
        setState(() => _status = 'downloade world_z6…');
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(_url));
        final resp = await req.close();
        final sink = f.openWrite();
        await resp.pipe(sink);
        client.close();
      }
      final size = await f.length();
      // Lokales PMTiles-Schema:
      final localSource = 'pmtiles://${Uri.file(f.path)}';
      _style =
          '{"version":8,"glyphs":"https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf",'
          '"sources":{"protomaps":{"type":"vector","url":"$localSource"}},'
          '"layers":['
          '{"id":"bg","type":"background","paint":{"background-color":"#0b0e13"}},'
          '{"id":"earth","type":"fill","source":"protomaps","source-layer":"earth","paint":{"fill-color":"#0d1117"}},'
          '{"id":"water","type":"fill","source":"protomaps","source-layer":"water","paint":{"fill-color":"#16212f"}},'
          '{"id":"bound","type":"line","source":"protomaps","source-layer":"boundaries","paint":{"line-color":"#8c99b3","line-width":1.2}}'
          ']}';
      setState(() => _status =
          'LOKAL geladen (${(size / 1024 / 1024).toStringAsFixed(0)} MB) → rendere…');
    } catch (e) {
      setState(() => _status = 'FEHLER: $e');
    }
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
              initialCameraPosition:
                  const CameraPosition(target: LatLng(48.0, 10.0), zoom: 3.5),
              onStyleLoadedCallback: () {
                if (mounted) {
                  setState(() => _status =
                      'OFFLINE-RENDER OK ✓ (lokale PMTiles, kein Netz nötig)');
                }
              },
            ),
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black.withValues(alpha: 0.7),
              child: Text('LOKAL-TEST · $_status',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
