#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# PC1 GraphHopper-Reimport (nativ/systemd, Port 8989 = graphhopper_dach) auf
# dach-balkan-full.osm.pbf. Läuft als ROOT im Host-Namespace (nsenter).
#
# KRITISCH: PC1 hat einen `gh-healthcheck.timer`, der bei /health-Fail die Unit
# neustartet. Während des mehrstündigen Imports ist /health rot → der Timer würde
# den Import ENDLOS neu starten. Deshalb wird der Timer ZUERST gestoppt und erst
# nach erfolgreicher Verifikation wieder aktiviert.
#
# PC1-Config bleibt strukturell unveraendert (curvature-EV, LM-Prep, MMAP, 4×
# motorcycle_*) — nur datareader.file wird getauscht. Kein Profil-Umbau => kein
# "Profiles do not match"-Crash-Loop.
#
# Voraussetzung: /home/vucko1/graphhopper/data/dach-balkan-full.osm.pbf liegt schon
# (per rsync von PC2 kopiert).
# ─────────────────────────────────────────────────────────────────────────────
set -u
GHDATA=/home/vucko1/graphhopper/data
CFG=/home/vucko1/graphhopper/config/config.yml
NEW_PBF="$GHDATA/dach-balkan-full.osm.pbf"
CACHE="$GHDATA/graph-cache"
TS=$(cat /proc/uptime | cut -d. -f1)
log(){ echo "[pc1-reimport] $*"; }

if [ ! -s "$NEW_PBF" ]; then log "ABBRUCH: $NEW_PBF fehlt/leer (erst von PC2 rsync'en)"; exit 1; fi
SZ=$(stat -c%s "$NEW_PBF"); log "neue PBF: $((SZ/1024/1024)) MB"
if [ "$SZ" -lt 6000000000 ]; then log "ABBRUCH: PBF <6GB unplausibel"; exit 1; fi

# 1) Healthcheck-Timer stoppen (sonst Restart-Loop waehrend Import)
systemctl stop gh-healthcheck.timer 2>/dev/null && log "gh-healthcheck.timer gestoppt" || log "timer-stop warn"

# 2) Unit stoppen
systemctl stop graphhopper_dach.service 2>/dev/null && log "graphhopper_dach gestoppt" || log "stop warn"

# 3) graph-cache sichern (Rollback moeglich)
if [ -d "$CACHE" ]; then mv "$CACHE" "${CACHE}.bak_${TS}"; log "graph-cache -> ${CACHE}.bak_${TS}"; fi

# 4) config.yml datareader.file umstellen (Backup zuerst)
cp "$CFG" "${CFG}.bak_${TS}"
sed -i "s#^\(\s*datareader.file:\).*#\1 $NEW_PBF#" "$CFG"
log "datareader.file ->"; grep -n "datareader.file" "$CFG"

# 5) Unit starten -> Reimport (~1-3h; MMAP+LM-Prep auf groesserem Graph)
systemctl start graphhopper_dach.service && log "graphhopper_dach gestartet (Reimport laeuft)" || { log "START FEHLGESCHLAGEN"; exit 1; }
log "FERTIG. Import laeuft auf 8989. NACH Verifikation: systemctl start gh-healthcheck.timer"
