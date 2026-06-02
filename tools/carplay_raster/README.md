# CarPlay/Android-Auto Raster-Tiles (unser Cruise-Dark-Look)

Rendert unseren `cruiseDarkMapStyle` (als `style.json`, MapLibre-kompatibel)
aus den self-hosted PMTiles zu Raster-PNG-Kacheln und lädt sie nach
`r2:cruise-tiles/raster/{z}/{x}/{y}.png`. Native (iOS MKTileOverlay /
Android Tile-Overlay) legen sie über die Headunit-Karte → unser Look im Auto.

## Nutzung
```
cd tools/carplay_raster && npm install
# bbox=minLon,minLat,maxLon,maxLat  minZ maxZ
node render.js 9.35,47.18,9.95,47.62 9 13          # Proof Vorarlberg
node render.js 5.5,45.7,17.2,55.1 6 14             # ganz DACH (großer Batch)
rclone copy tiles r2:cruise-tiles/raster --s3-no-check-bucket --transfers 16
```
Renderer braucht `--enable-unsafe-swiftshader` (in render.js gesetzt) für
headless WebGL. style.json muss synchron zu cruise_dark_map_style.dart bleiben.
