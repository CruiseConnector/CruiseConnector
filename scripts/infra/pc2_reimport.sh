#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# PC2 GraphHopper-Reimport auf dach-balkan-full.osm.pbf.
# Läuft als ROOT im Host-Namespace (nsenter) — braucht Docker + mv des
# root-eigenen graph-cache.
#
# Sicher: (1) prüft die neue PBF, (2) setzt Import-Flag (gh-guardian pausiert),
# (3) sichert alten graph-cache (Rollback!), (4) stellt config.yml um
# (PROFILE UNVERÄNDERT: car + 4× motorcycle_*), (5) startet Container → Reimport.
# Wartet NICHT auf den Import-Abschluss (das wird separat überwacht).
#
# Während des Imports ist PC2-GH offline → PC1 serviert DACH, Mapbox überbrückt
# den Balkan. Das ist gewollt.
# ─────────────────────────────────────────────────────────────────────────────
set -u
GHDIR=/home/vucko2/gh-eu
NEW_PBF="$GHDIR/data/dach-balkan-full.osm.pbf"
CFG="$GHDIR/config.yml"
CACHE="$GHDIR/data/graph-cache"
TS=$(cat /proc/uptime | cut -d. -f1)   # kein date-Format-Aerger; monotone Marke
log(){ echo "[pc2-reimport] $*"; }

# 1) neue PBF muss existieren + plausibel gross sein
if [ ! -s "$NEW_PBF" ]; then log "ABBRUCH: $NEW_PBF fehlt/leer"; exit 1; fi
SZ=$(stat -c%s "$NEW_PBF"); log "neue PBF: $NEW_PBF ($((SZ/1024/1024)) MB)"
if [ "$SZ" -lt 6000000000 ]; then log "ABBRUCH: PBF <6GB — unplausibel (DACH+Balkan sollte ~9-10GB sein)"; exit 1; fi

# 2) Guardian pausieren
touch "$GHDIR/.import_in_progress"; log "import-flag gesetzt (gh-guardian pausiert)"

# 3) Container stoppen + graph-cache sichern
log "docker stop gh-eu"; docker stop gh-eu >/dev/null 2>&1 || log "stop warn"
if [ -d "$CACHE" ]; then mv "$CACHE" "${CACHE}.bak_${TS}"; log "graph-cache gesichert -> ${CACHE}.bak_${TS}"; fi

# 4) config.yml datareader.file umstellen (Backup der config zuerst)
cp "$CFG" "${CFG}.bak_${TS}"
sed -i "s#^\(\s*datareader.file:\).*#\1 /data/dach-balkan-full.osm.pbf#" "$CFG"
log "config datareader.file ->"; grep -n "datareader.file" "$CFG"
# Groesserer Graph (DACH+Balkan+GR ~9GB) → MMAP_STORE wie PC1 (speichersicher,
# kein OOM bei -Xmx12g). Zeile einfuegen falls noch nicht vorhanden.
if ! grep -q "graph.dataaccess.default_type" "$CFG"; then
  sed -i "s#^\(\s*graph.location:.*\)#\1\n  graph.dataaccess.default_type: MMAP_STORE#" "$CFG"
  log "graph.dataaccess.default_type: MMAP_STORE eingefuegt"
else
  log "graph.dataaccess bereits gesetzt: $(grep graph.dataaccess.default_type "$CFG")"
fi
log "profiles (muss unveraendert car + 4x motorcycle_* sein):"; grep -nE "name: (car|motorcycle_)" "$CFG"

# 5) Container starten -> Reimport (graph-cache fehlt => GH baut neu)
log "docker start gh-eu (Reimport startet, ~1-3h)"; docker start gh-eu >/dev/null 2>&1 && log "started" || { log "START FEHLGESCHLAGEN"; exit 1; }
log "FERTIG. Import laeuft. Ueberwachen: docker logs -f gh-eu ; danach .import_in_progress entfernen."
