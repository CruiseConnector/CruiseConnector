#!/usr/bin/env bash
# =============================================================================
# GraphHopper "Never Down" Bulletproof-Boot — EINMAL pro Mini-PC mit sudo laufen.
#
#   sudo bash graphhopper_bulletproof_boot.sh
#
# Macht den Routing-Server reboot-/crash-/stromausfall-fest:
#   1. systemd-Units fuer GraphHopper installieren + ENABLEN (Autostart bei Boot)
#      -> war bisher NUR vorbereitet, nie aktiviert (= Root Cause "alle paar Tage").
#   2. tailscaled bei Boot aktivieren (Tunnel kommt automatisch zurueck).
#   3. Wake-on-LAN auf der NIC persistent aktivieren (Remote-Einschalten moeglich).
#   4. Health-Watchdog-Timer (faengt Haenger ab, die Restart=always nicht sieht).
#   5. BIOS-Schritte fuer "nach Stromausfall selbst einschalten" ausgeben + MAC.
#
# Idempotent: mehrfaches Ausfuehren ist sicher.
# =============================================================================
set -euo pipefail

GH_USER="${GH_USER:-vucko1}"
GH_HOME="${GH_HOME:-/home/${GH_USER}/graphhopper}"
GH_CFG="${GH_HOME}/config"
JAR="${GH_HOME}/bin/graphhopper-web.jar"

log(){ printf '\033[1;36m[bulletproof]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[bulletproof]\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then echo "Bitte mit sudo ausfuehren: sudo bash $0"; exit 1; fi

# 2026-06-29 (vucko): Falls der no-sudo-Keepalive-Cron aktiv ist, ENTFERNEN —
# sonst kaempfen Cron-GH und systemd-GH um denselben Port (8989/8991). systemd
# uebernimmt ab hier die Verwaltung. (Cron des aufrufenden Users + GH_USER.)
for u in "${SUDO_USER:-}" "${GH_USER}"; do
  [ -z "$u" ] && continue
  ( crontab -u "$u" -l 2>/dev/null | grep -v 'graphhopper/keepalive.sh' || true ) | crontab -u "$u" - 2>/dev/null || true
done
log "Keepalive-Cron entfernt (systemd uebernimmt)."

# ---------------------------------------------------------------------------
# 1) systemd-Units schreiben (DACH 8989 + DE 8991) — nur fuer vorhandene Configs
# ---------------------------------------------------------------------------
write_unit(){ # name desc config xmx
  local name="$1" desc="$2" cfg="$3" xmx="$4"
  if [[ ! -f "${GH_CFG}/${cfg}" ]]; then
    warn "Config ${GH_CFG}/${cfg} fehlt -> Unit ${name} uebersprungen."
    return 1
  fi
  cat > "/etc/systemd/system/${name}.service" <<UNIT
[Unit]
Description=${desc}
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=${GH_USER}
Group=${GH_USER}
WorkingDirectory=${GH_CFG}
Environment="JAVA_OPTS=-Xmx${xmx} -server"
ExecStart=/usr/bin/java -Xmx${xmx} -server -jar ${JAR} server ${GH_CFG}/${cfg}
Restart=always
RestartSec=15
StartLimitIntervalSec=0
StandardOutput=append:${GH_HOME}/${name}.log
StandardError=append:${GH_HOME}/${name}.log
TasksMax=512
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
  return 0
}

ENABLED_UNITS=()
if write_unit graphhopper_dach "GraphHopper DACH Routing (8989)" config.yml 10g; then ENABLED_UNITS+=(graphhopper_dach); fi
if write_unit graphhopper_de   "GraphHopper DE Routing (8991)"   config-de.yml 5g;  then ENABLED_UNITS+=(graphhopper_de); fi

if [[ ${#ENABLED_UNITS[@]} -eq 0 ]]; then
  warn "Keine GraphHopper-Config gefunden unter ${GH_CFG}. Pruefe GH_USER/GH_HOME."
else
  systemctl daemon-reload
  pkill -f graphhopper-web 2>/dev/null || true
  sleep 2
  for u in "${ENABLED_UNITS[@]}"; do
    systemctl enable "${u}.service"      # <-- AUTOSTART BEI BOOT (das fehlte!)
    systemctl restart "${u}.service"
    log "Aktiviert + gestartet: ${u} ($(systemctl is-enabled ${u}.service), $(systemctl is-active ${u}.service))"
  done
fi

# ---------------------------------------------------------------------------
# 2) Tailscale bei Boot
# ---------------------------------------------------------------------------
if command -v tailscaled >/dev/null 2>&1; then
  systemctl enable --now tailscaled 2>/dev/null || true
  tailscale up --ssh 2>/dev/null || true
  log "tailscaled enabled ($(systemctl is-enabled tailscaled 2>/dev/null || echo n/a))"
fi

# ---------------------------------------------------------------------------
# 3) Wake-on-LAN persistent (NIC + systemd-Unit, das es nach jedem Boot setzt)
# ---------------------------------------------------------------------------
IFACE="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')"
MAC=""
if [[ -n "${IFACE:-}" ]] && command -v ethtool >/dev/null 2>&1; then
  ethtool -s "$IFACE" wol g 2>/dev/null || warn "WoL setzen fehlgeschlagen (NIC/Treiber?)."
  MAC="$(cat /sys/class/net/${IFACE}/address 2>/dev/null || true)"
  cat > /etc/systemd/system/wol-enable.service <<WOL
[Unit]
Description=Enable Wake-on-LAN on ${IFACE}
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${IFACE} wol g
[Install]
WantedBy=multi-user.target
WOL
  systemctl enable wol-enable.service 2>/dev/null || true
  log "Wake-on-LAN aktiviert auf ${IFACE} (MAC ${MAC:-unbekannt})"
else
  warn "ethtool/IFACE nicht gefunden -> WoL bitte manuell (apt install ethtool)."
fi

# ---------------------------------------------------------------------------
# 4) Health-Watchdog (faengt HAENGER ab — Restart=always sieht nur Crashes)
# ---------------------------------------------------------------------------
cat > /usr/local/bin/gh_healthcheck.sh <<'HC'
#!/usr/bin/env bash
# Prueft lokal beide Ports; bei keiner Antwort -> Unit hart neustarten.
check(){ curl -fsS -m 4 "http://127.0.0.1:$1/health" >/dev/null 2>&1; }
systemctl is-active --quiet graphhopper_dach.service && ! check 8989 && systemctl restart graphhopper_dach.service
systemctl is-active --quiet graphhopper_de.service   && ! check 8991 && systemctl restart graphhopper_de.service
exit 0
HC
chmod +x /usr/local/bin/gh_healthcheck.sh
cat > /etc/systemd/system/gh-healthcheck.service <<'HCU'
[Unit]
Description=GraphHopper local health watchdog
[Service]
Type=oneshot
ExecStart=/usr/local/bin/gh_healthcheck.sh
HCU
cat > /etc/systemd/system/gh-healthcheck.timer <<'HCT'
[Unit]
Description=Run GraphHopper health watchdog every 60s
[Timer]
OnBootSec=90
OnUnitActiveSec=60
AccuracySec=10
[Install]
WantedBy=timers.target
HCT
systemctl daemon-reload
systemctl enable --now gh-healthcheck.timer 2>/dev/null || true
log "Health-Watchdog aktiv (alle 60s)."

# ---------------------------------------------------------------------------
# 5) Manuelle BIOS-Schritte (einmalig, nur am Geraet moeglich)
# ---------------------------------------------------------------------------
cat <<INFO

========================================================================
 FERTIG. Ab jetzt: GraphHopper startet bei JEDEM Boot automatisch,
 restartet bei Crash/Haenger, Tailscale kommt automatisch zurueck.

 NOCH EINMALIG IM BIOS (nur direkt am PC, HP ProDesk 600 G5):
   F10 beim Booten -> BIOS:
   * Advanced -> Power-On Options -> "After Power Loss" = POWER ON
       => PC schaltet sich nach Stromausfall von selbst wieder ein.
   * Advanced -> Built-In Device Options -> "Wake On LAN" = Boot to Network/ON
   * (S5 Wake-on-LAN aktivieren, falls separat gelistet)

 Remote aufwecken (von einem PC im selben Heimnetz):
   wakeonlan ${MAC:-<MAC-Adresse>}        # apt/brew install wakeonlan
   NIC: ${IFACE:-?}   MAC: ${MAC:-unbekannt}
========================================================================
INFO
