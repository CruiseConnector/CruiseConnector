#!/usr/bin/env bash
# DACH Improvement-Scout — analysiert alle 30min was verbessert werden kann.
#
# Schreibt strukturierte Vorschläge nach logs/improvement-suggestions.log.
# Jede Zeile = 1 Vorschlag mit Severity-Tag:
#   [INFO]    minor improvement opportunity
#   [WARN]    UX-relevant — sollte priorisiert werden
#   [CRIT]    user-impact / data-quality — sofort prüfen
#
# Datenquellen (file-basiert, keine DB-Auth nötig):
#   - logs/dach-heartbeat-*.log  Smoke-Route Trend
#   - logs/heartbeat-loop.log    Loop-Health
#   - lib/                       TODO/FIXME-Counts, Datei-Größe
#   - rotierende Feature-Idee + UX-Vorschlag-Pools

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG="$ROOT/logs/improvement-suggestions.log"
TS=$(date +"%Y-%m-%dT%H:%M:%S")
TODAY=$(date +"%Y-%m-%d")

mkdir -p "$ROOT/logs"

emit() {
  echo "[$TS] [$1] [$2] $3" >> "$LOG"
}

echo "──────── scout-run $TS ────────" >> "$LOG"

# ── 1. GH-Health: smoke-route degraded/fail Counter ─────────────────────────
HB_LOG="$ROOT/logs/dach-heartbeat-$TODAY.log"
if [[ -f "$HB_LOG" ]]; then
  FAILS=$(grep -c "STATE=fail" "$HB_LOG" 2>/dev/null || true)
  FAILS=${FAILS:-0}
  DEGRADED=$(grep -c "STATE=degraded" "$HB_LOG" 2>/dev/null || true)
  DEGRADED=${DEGRADED:-0}
  if [[ "$FAILS" -gt 3 ]]; then
    emit "CRIT" "GH_HEALTH" "$FAILS fail-states heute — GH stabilisieren / Logs prüfen"
  elif [[ "$DEGRADED" -gt 5 ]]; then
    emit "WARN" "GH_HEALTH" "$DEGRADED degraded-states heute — Quality-Gate evtl. zu streng"
  fi
fi

# ── 2. Smoke-Route Distanz-Drift ────────────────────────────────────────────
# Wenn die smoke route plötzlich andere km/turn-counts liefert, deutet das
# auf eine Routing-Regression hin.
if [[ -f "$HB_LOG" ]]; then
  LAST_KM=$(grep -o "km=[0-9.]*" "$HB_LOG" | tail -1 | cut -d= -f2)
  EXPECT_KM=49.48
  if [[ -n "$LAST_KM" ]]; then
    DIFF=$(awk "BEGIN{print ($LAST_KM - $EXPECT_KM)}")
    DIFF_ABS=$(awk "BEGIN{print ($LAST_KM > $EXPECT_KM ? $LAST_KM - $EXPECT_KM : $EXPECT_KM - $LAST_KM)}")
    OVER=$(awk "BEGIN{print ($DIFF_ABS > 2.0 ? 1 : 0)}")
    if [[ "$OVER" == "1" ]]; then
      emit "WARN" "ROUTE_DRIFT" "Smoke-Route km=$LAST_KM weicht ${DIFF}km von Baseline 49.48 ab"
    fi
  fi
fi

# ── 3. TODO/FIXME/HACK in Code — Tech-Debt Indikator ────────────────────────
TODO_COUNT=$(grep -rE "TODO|FIXME|HACK" "$ROOT/lib/" --include="*.dart" 2>/dev/null | wc -l | xargs)
TODO_COUNT=${TODO_COUNT:-0}
if [[ "$TODO_COUNT" -gt 80 ]]; then
  emit "WARN" "TECH_DEBT" "$TODO_COUNT TODO/FIXME/HACK Marker — Refactor-Sprint überlegen"
elif [[ "$TODO_COUNT" -gt 50 ]]; then
  emit "INFO" "TECH_DEBT" "$TODO_COUNT TODO/FIXME/HACK Marker in lib/"
fi

# ── 4. Große Dart-Dateien (Single-File Bloat) ───────────────────────────────
BLOAT=$(find "$ROOT/lib" -name "*.dart" -type f 2>/dev/null | \
  xargs wc -l 2>/dev/null | awk '$1 > 1800 && $2 != "total" {print $2":"$1}' | head -3)
if [[ -n "$BLOAT" ]]; then
  while IFS=: read -r file lines; do
    if [[ -n "$file" && -n "$lines" ]]; then
      base=$(basename "$file")
      emit "INFO" "FILE_BLOAT" "$base hat $lines Zeilen — Split-Refactor verbessert Testbarkeit"
    fi
  done <<< "$BLOAT"
fi

# ── 5. Rotation: Feature-Ideen Pool (deterministisch pro 30min-Slot) ────────
HOUR=$(date +"%H")
MIN=$(date +"%M")
ROTATION=$(( (10#$HOUR * 2 + (10#$MIN >= 30 ? 1 : 0)) % 10 ))
case $ROTATION in
  0) emit "INFO" "FEATURE" "Idee: Wetter-Integration vor Route-Start (OpenMeteo gratis, regen-warnung)" ;;
  1) emit "INFO" "FEATURE" "Idee: Tankstellen-POIs entlang Route via Overpass-API (amenity=fuel)" ;;
  2) emit "INFO" "FEATURE" "Idee: Elevation-Profile-Graph in Route-Preview (Mapbox liefert ascent_meters)" ;;
  3) emit "INFO" "FEATURE" "Idee: Voice-Navigation TTS für Manöver-Banner (flutter_tts package)" ;;
  4) emit "INFO" "FEATURE" "Idee: Route-Sharing Deep-Link (cruiseconnect://route/<id>)" ;;
  5) emit "INFO" "FEATURE" "Idee: Crash-Detection Accelerometer + Notfall-SMS (sensors_plus)" ;;
  6) emit "INFO" "FEATURE" "Idee: Vehicle-Profile mit Tank-Verbrauch → ETA inkl. Tank-Stopps" ;;
  7) emit "INFO" "FEATURE" "Idee: Weekly-Stats Dashboard (km, Kurven, Top-Stil, Lieblings-Region)" ;;
  8) emit "INFO" "FEATURE" "Idee: Apple-Watch Companion mit Manöver-Banner (watch_connectivity)" ;;
  9) emit "INFO" "FEATURE" "Idee: Strava-Export für gefahrene Routen (.gpx, oauth)" ;;
esac

# ── 6. Rotation: UX-Optimierungen ───────────────────────────────────────────
UX_SLOT=$(( ROTATION % 6 ))
case $UX_SLOT in
  0) emit "INFO" "UX_OPT" "Idee: Haptic-Feedback bei Manöver-Banner (HapticFeedback.lightImpact)" ;;
  1) emit "INFO" "UX_OPT" "Idee: Pull-to-Refresh auf Home/Community (RefreshIndicator wrap)" ;;
  2) emit "INFO" "UX_OPT" "Idee: Skeleton-Loader für Community-Cards statt Spinner" ;;
  3) emit "INFO" "UX_OPT" "Idee: Map-Compass-Indicator wenn Heading != 0° (Mapbox-Built-in)" ;;
  4) emit "INFO" "UX_OPT" "Idee: Long-Press auf Save-Chip → Direkt umbenennen statt nur speichern" ;;
  5) emit "INFO" "UX_OPT" "Idee: Confetti-Animation beim ersten Level-Up nach Badge-Unlock" ;;
esac

# ── 7. Rotation: Performance-Ideen ──────────────────────────────────────────
PERF_SLOT=$(( ROTATION % 5 ))
case $PERF_SLOT in
  0) emit "INFO" "PERF" "Idee: const-Constructor-Audit via flutter analyze --suggestions" ;;
  1) emit "INFO" "PERF" "Idee: Image-Cache-Limit hochsetzen (PaintingBinding.imageCache.maximumSize)" ;;
  2) emit "INFO" "PERF" "Idee: Mapbox-Style precache für offline-Cluster (drei top-Regionen)" ;;
  3) emit "INFO" "PERF" "Idee: Postgres-Index Audit auf pool_demand_log.logged_at" ;;
  4) emit "INFO" "PERF" "Idee: Edge-Function code-splitting — generate-cruise-route-v2 ist 30kB" ;;
esac

# ── 8. Rotation: Backend/DB-Ideen ──────────────────────────────────────────
BE_SLOT=$(( ROTATION % 4 ))
case $BE_SLOT in
  0) emit "INFO" "BACKEND" "Idee: Pool-Rotation Telemetrie als pg_cron Daily-Report (avg last_suggested_at)" ;;
  1) emit "INFO" "BACKEND" "Idee: Route-Rating User-Feedback Schema (1-5 Sterne, freitext)" ;;
  2) emit "INFO" "BACKEND" "Idee: Group-Routes geteilt → group_routes Tabelle mit RLS" ;;
  3) emit "INFO" "BACKEND" "Idee: Trip-Templates (User speichert Mehrtages-Tour als Vorlage)" ;;
esac

echo "[$TS] scout-done" >> "$LOG"
