#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# gh-guardian (PC2 / vucko2) — App-Layer Self-Healing für den Docker-GraphHopper.
#
# GraphHopper läuft als Container `gh-eu` mit restart=unless-stopped → Crash und
# Reboot sind schon abgedeckt. Was FEHLT ist HANG-Erkennung: ein Prozess, der
# noch auf Port 8989 lauscht, aber /health nicht mehr beantwortet, wird von der
# Docker-Restart-Policy NICHT neu gestartet. Dieser Guardian schließt genau das.
#
# Läuft selbst als Container mit restart=always (überlebt Reboot + eigenen Crash),
# braucht KEIN sudo (nur docker-Group über die gemountete docker.sock).
#
# Import-Schutz: Während eines Graph-REIMPORTS ist /health minutenlang bis
# stundenlang rot (graph-cache wird neu gebaut). Damit der Guardian den Import
# nicht abwürgt, pausiert er ALLE Restarts solange die Flag-Datei
# /guard/.import_in_progress existiert (gemountet aus /home/vucko2/gh-eu).
# ─────────────────────────────────────────────────────────────────────────────
set -u

HEALTH_URL="http://127.0.0.1:8989/health"
CONTAINER="gh-eu"
PAUSE_FLAG="/guard/.import_in_progress"
INTERVAL="${GUARD_INTERVAL:-20}"     # Sekunden zwischen Checks
THRESH="${GUARD_THRESH:-3}"          # aufeinanderfolgende Fails bis Restart
WGET_TO="${GUARD_WGET_TIMEOUT:-10}"  # /health-Timeout (JVM unter Last tolerant)
BASE_GRACE="${GUARD_GRACE:-75}"      # Sekunden Ruhe nach einem Restart (Graph-Load)
FAILS=0
NO_RECOVERY=0                        # aufeinanderfolgende Restarts, die /health NICHT heilten

log(){ echo "$(date -u +%FT%TZ) [gh-guardian] $*"; }

log "start: url=$HEALTH_URL container=$CONTAINER interval=${INTERVAL}s thresh=$THRESH wget_to=${WGET_TO}s"

while true; do
  if [ -f "$PAUSE_FLAG" ]; then
    log "import-in-progress flag present → restarts PAUSED"
    FAILS=0; NO_RECOVERY=0
    sleep "$INTERVAL"
    continue
  fi

  if wget -q -T "$WGET_TO" -O /dev/null "$HEALTH_URL" 2>/dev/null; then
    if [ "$FAILS" -ne 0 ] || [ "$NO_RECOVERY" -ne 0 ]; then log "healthy again (after $FAILS fail(s), $NO_RECOVERY unhelpful restart(s))"; fi
    FAILS=0; NO_RECOVERY=0
  else
    FAILS=$((FAILS + 1))
    log "health FAIL ${FAILS}/${THRESH}"
    if [ "$FAILS" -ge "$THRESH" ]; then
      STATE=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)
      log "hang confirmed (state=$STATE) → docker restart $CONTAINER"
      docker restart "$CONTAINER" >/dev/null 2>&1 && log "restart issued OK" || log "restart FAILED (docker error)"
      FAILS=0
      # Exponentieller Backoff: falls Restarts NICHT heilen (z.B. ein nicht-geflaggter
      # Langläufer-Import), waechst die Ruhephase 75→150→300→600→1200s statt zu stormen.
      SHIFT=$NO_RECOVERY; [ "$SHIFT" -gt 4 ] && SHIFT=4
      GRACE=$((BASE_GRACE * (1 << SHIFT)))
      NO_RECOVERY=$((NO_RECOVERY + 1))
      log "grace ${GRACE}s (unhelpful-restart backoff level $SHIFT)"
      sleep "$GRACE"
    fi
  fi
  sleep "$INTERVAL"
done
