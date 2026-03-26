# CruiseConnect — Web Setup Guide

## Was wurde geändert (mapbox_maps_flutter → flutter_map)

### Warum die Migration?
`mapbox_maps_flutter` ist ein nativer Plugin und funktioniert **nicht** im Web (Flutter Web unterstützt nur Pure-Dart Packages). `flutter_map` ist komplett in Dart geschrieben und läuft identisch auf Web, iOS und Android.

### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `pubspec.yaml` | `mapbox_maps_flutter` → `flutter_map: ^7.0.2` + `latlong2: ^0.9.1` |
| `lib/main.dart` | `MapboxOptions.setAccessToken()` entfernt (Token wird jetzt in der Tile-URL übergeben) |
| `lib/data/services/offline_map_service.dart` | No-Op Stub (flutter_map cached via HTTP automatisch) |
| `lib/presentation/pages/cruise_mode_page.dart` | Vollständige Map-Logik migriert (siehe unten) |
| `web/index.html` | `mapbox-gl.js` entfernt, `viewport` meta-tag hinzugefügt |

### Was sich in cruise_mode_page.dart geändert hat

**Vorher (Mapbox SDK):**
- `MapWidget(...)` mit nativem GL-Renderer
- `MapboxMap?` Controller + `style.addSource/addLayer` für Route
- `CircleAnnotationManager` für Simulations-Puck
- `FollowPuckViewportState` für Kamera-Tracking
- `cameraForCoordinatesPadding` für Route-Übersicht
- `MapboxOptions.setAccessToken()` global in main.dart

**Nachher (flutter_map):**
- `FlutterMap(...)` mit `TileLayer` (Mapbox Raster-Tiles API)
- `List<LatLng> _routeLatLngs` + `PolylineLayer` für Route (einfaches setState!)
- `LatLng? _simulationPuckPosition` + `MarkerLayer` für Puck
- Manuelles `_mapController.move()` bei `_isCameraLocked`
- `_mapController.fitCamera(CameraFit.bounds(...))` für Übersicht
- Mapbox Token direkt in TileLayer-URL

**Kritische Koordinaten-Konvertierung:**
```
Mapbox: [longitude, latitude]  →  flutter_map: LatLng(latitude, longitude)
```
Diese Konvertierung geschieht in `_drawRoute()`:
```dart
.map((c) => LatLng(c[1], c[0]))  // c[0]=lng, c[1]=lat → LatLng(lat, lng)
```

---

## Lokal starten

### Voraussetzungen
- Flutter SDK installiert
- Mapbox-Token in `lib/config/secrets.dart` gesetzt

### Befehle

```bash
# Packages installieren (einmalig nach pubspec-Änderung)
flutter pub get

# Web im Chrome starten (am einfachsten)
make web-dev
# Entspricht: flutter run -d chrome --web-port=8080

# Web im Netzwerk (für Handy-Tests via WLAN)
make web-local
# Entspricht: flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0

# Release-Build für Vercel
make web-build
# Entspricht: flutter build web --release --web-renderer=canvaskit
```

---

## Vercel Deployment

### Vorhandene Konfiguration

`vercel.json` ist bereits korrekt konfiguriert:
```json
{
  "buildCommand": "flutter build web --release --web-renderer=canvaskit",
  "outputDirectory": "build/web",
  "framework": null,
  "rewrites": [{"source": "/(.*)", "destination": "/index.html"}]
}
```

### Schritte für Vercel-Setup

1. **Vercel Account erstellen** (falls noch nicht vorhanden): https://vercel.com

2. **Vercel CLI installieren:**
   ```bash
   npm install -g vercel
   ```

3. **Flutter-Build lokal testen:**
   ```bash
   make web-build
   # Dann: cd build/web && python3 -m http.server 8080
   ```

4. **Vercel Projekt einrichten:**
   ```bash
   cd /Users/vucko/Development/CruiserConnect
   vercel login
   vercel          # Folge dem Setup-Assistenten
   ```

5. **Wichtige Vercel-Einstellungen (im Dashboard):**
   - Build Command: `flutter build web --release --web-renderer=canvaskit`
   - Output Directory: `build/web`
   - Environment Variables: **nicht nötig** (Mapbox-Token ist in secrets.dart, nicht in Env-Vars)

6. **Flutter auf Vercel installieren:**
   Vercel hat kein Flutter vorinstalliert. Daher: Build **lokal** ausführen und `build/web/` deployen:
   ```bash
   make web-build
   vercel deploy build/web --prod
   ```
   Oder CI/CD über GitHub Actions (`.github/workflows/vercel-deploy.yml` bereits vorhanden).

### GitHub Actions (vorhanden)
Der Workflow `.github/workflows/vercel-deploy.yml` baut und deployed automatisch bei Push auf main.

---

## Vom Handy darauf zugreifen

### Option 1: Vercel URL (empfohlen)
Nach dem Deployment erhältst du eine URL wie `https://cruise-connect.vercel.app`.
Einfach auf dem Handy im Browser öffnen — funktioniert sofort.

### Option 2: Lokal via WLAN (zum Testen)
```bash
make web-local
# Startet Server auf 0.0.0.0:8080
```
Dann auf dem Handy im Browser: `http://[DEINE-MAC-IP]:8080`
Mac-IP findest du mit: `ifconfig | grep "inet " | grep -v 127`

---

## Bekannte Limitierungen

### GPS im Browser (Web)
- Browser-GPS nutzt die **Geolocation Web API** (nicht native GPS wie iOS/Android)
- Erfordert **HTTPS** — auf localhost funktioniert es trotzdem (Browser-Ausnahme)
- Genauigkeit ist schlechter als nativer GPS-Chip
- User muss GPS-Berechtigung im Browser erteilen (einmalig)
- Firefox hat manchmal Probleme mit GPS — Chrome/Safari bevorzugen

### Karten-Tiles
- flutter_map lädt Tiles via HTTP von Mapbox — braucht Internet
- Offline-Caching: Der Browser cached Tiles automatisch via HTTP-Cache
- Mapbox-Token ist im Dart-Code eingebaut → bei Web-Deployment ist er im JS-Bundle sichtbar (ist bei Web-Apps unvermeidbar, dasselbe gilt für Mapbox GL JS)

### Performance
- `canvaskit` Renderer (Standardeinstellung) ist am besten für Karten
- Erster Load kann 2-3 Sekunden dauern (WASM lädt)
- Danach: smooth wie native

### Simulation-Modus
- Simulation funktioniert auch im Web vollständig
- GPS-Simulation läuft über Timer + `_onLocationUpdate` (plattformunabhängig)

### Kein 3D-Kippwinkel (Pitch)
- flutter_map unterstützt keine 45°-Neigung wie die Mapbox Navigation-Kamera
- Die Karte bleibt in der Vogelperspektive (Pitch = 0)
- Alle anderen Features (Routing, Manöver, Simulation) funktionieren vollständig

---

## Schnell-Referenz: flutter_map vs mapbox_maps_flutter

| Feature | mapbox_maps_flutter | flutter_map |
|---------|---------------------|-------------|
| Web-Support | ❌ | ✅ |
| Karten-Style | Mapbox GL (Vektor) | Mapbox Raster-Tiles |
| Route zeichnen | `style.addLayer(LineLayer(...))` | `PolylineLayer` in Widget-Tree |
| Kamera bewegen | `flyTo(CameraOptions(...))` | `_mapController.move(LatLng, zoom)` |
| Route einpassen | `cameraForCoordinatesPadding()` | `_mapController.fitCamera(CameraFit.bounds(...))` |
| User-Position | Built-in Puck | `MarkerLayer` + `LatLng? _userPosition` |
| Setup in main.dart | `MapboxOptions.setAccessToken()` | Nichts (Token in TileLayer-URL) |
