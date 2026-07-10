#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# PC1 schneller Reimport OHNE LM-Prep (wie PC2 = flexibles Routing).
# Grund: LM-Landmark-Prep braucht auf dem 9GB-Balkan-Graphen ~33min/Profil ×4 =
# ~2h. PC2 laeuft ohne LM als Primaer bestens; PC1 ist nur Failover → LM unnoetig.
# Laeuft als ROOT (nsenter). gh-healthcheck.timer ist bereits gestoppt.
# ─────────────────────────────────────────────────────────────────────────────
set -u
CFG=/home/vucko1/graphhopper/config/config.yml
CACHE=/home/vucko1/graphhopper/data/graph-cache
TS=$(cat /proc/uptime | cut -d. -f1)
log(){ echo "[pc1-fast] $*"; }

log "stop graphhopper_dach (bricht LM-Prep ab)"
systemctl stop graphhopper_dach.service 2>/dev/null || true

# profiles_lm leeren: die Kopfzeile auf [] setzen + die 4 LM-Eintraege loeschen.
cp "$CFG" "${CFG}.bak_lm_${TS}"
sed -i 's/^  profiles_lm:.*/  profiles_lm: []/' "$CFG"
sed -i '/^    - profile: motorcycle_/d' "$CFG"
log "profiles_lm jetzt:"; grep -n "profiles_lm" "$CFG"
log "verbleibende '- profile:' Zeilen (sollte 0 sein):"; grep -c "^    - profile:" "$CFG" || true

# graph-cache (mit halber LM-Prep) verwerfen → sauberer No-LM-Import
if [ -d "$CACHE" ]; then mv "$CACHE" "${CACHE}.bak_lm_${TS}"; log "graph-cache -> ${CACHE}.bak_lm_${TS}"; fi

log "start graphhopper_dach (schlanker Import ~20min)"
systemctl start graphhopper_dach.service && log "gestartet" || { log "START FEHLGESCHLAGEN"; exit 1; }
log "FERTIG. Import laeuft ohne LM. NACH Verifikation: systemctl start gh-healthcheck.timer"
