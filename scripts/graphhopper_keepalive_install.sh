#!/usr/bin/env bash
# =============================================================================
# Portabler GraphHopper-Keepalive — EINMAL pro Mini-PC laufen (OHNE sudo).
#
#   bash graphhopper_keepalive_install.sh
#
# Erkennt die aktuell laufenden GraphHopper-Prozesse automatisch (egal welcher
# User/Pfad/Port), schreibt einen Watchdog der sie bei Crash neu startet, und
# installiert eine Crontab (@reboot + jede Minute). Damit ueberlebt GraphHopper
# Reboots + Crashes — ohne sudo, ohne systemd. Idempotent.
#
# Voraussetzung: GraphHopper laeuft GERADE (das Skript liest die Startkommandos
# aus den laufenden Prozessen). Falls nicht: GH einmal manuell starten, dann das.
# =============================================================================
set -euo pipefail
GHDIR="${GH_DIR:-$HOME/graphhopper}"
KA="$GHDIR/keepalive.sh"
CMDS="$GHDIR/.gh_cmds"
mkdir -p "$GHDIR"

echo "[keepalive] erkenne laufende GraphHopper-Prozesse ..."
mapfile -t CFGS < <(pgrep -af 'graphhopper-web.jar server' | grep -oE 'server [^ ]+\.ya?ml' | awk '{print $2}' | sort -u)
if [ "${#CFGS[@]}" -eq 0 ]; then
  echo "[keepalive] FEHLER: kein laufender GraphHopper gefunden. Starte GH zuerst, dann erneut."
  exit 1
fi

: > "$CMDS"
for cfg in "${CFGS[@]}"; do
  line="$(pgrep -af 'graphhopper-web.jar server' | grep -F "server $cfg" | head -1)"
  echo "${line#* }" >> "$CMDS"   # PID am Anfang abschneiden -> volles java-Kommando
  echo "[keepalive] erkannt: $cfg"
done

cat > "$KA" <<'KA_EOF'
#!/usr/bin/env bash
# Auto-generiert vom Keepalive-Installer. Startet jeden erkannten GH neu, falls weg.
GHDIR="${GH_DIR:-$HOME/graphhopper}"
[ -f "$GHDIR/.gh_cmds" ] || exit 0
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  cfg="$(printf '%s' "$cmd" | grep -oE 'server [^ ]+\.ya?ml' | awk '{print $2}')"
  [ -z "$cfg" ] && continue
  if ! pgrep -f "server $cfg" >/dev/null 2>&1; then
    log="$GHDIR/keepalive-$(basename "$cfg").log"
    nohup bash -c "$cmd" >> "$log" 2>&1 &
  fi
done < "$GHDIR/.gh_cmds"
KA_EOF
chmod +x "$KA"

# Robust gegen `set -e`: grep gibt Exit 1 wenn ALLE Alt-Zeilen entfernt werden →
# darf die Subshell NICHT abbrechen, sonst bekommt `crontab -` leeren Input und
# loescht die Crontab. Darum `|| true` + getrennter Aufbau.
NEWCRON="$( { crontab -l 2>/dev/null | grep -v 'graphhopper/keepalive.sh' || true; } )"
printf '%s\n@reboot %s\n* * * * * %s\n' "$NEWCRON" "$KA" "$KA" | grep -v '^$' | crontab -

echo "[keepalive] installiert. Crontab:"
crontab -l | grep keepalive.sh
"$KA" >/dev/null 2>&1 || true
echo "[keepalive] OK — GH-Prozesse aktiv: $(pgrep -fc 'graphhopper-web.jar server')"
