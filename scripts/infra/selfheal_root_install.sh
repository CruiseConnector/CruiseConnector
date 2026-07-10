#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# CruiseConnect Self-Healing — Root-Schicht (idempotent).
# Läuft als root im HOST-Namespace (via: docker run --privileged --pid=host
# alpine nsenter -t 1 -m -u -n -i sh /home/<user>/selfheal_root_install.sh eno1).
#
# Bewusst OHNE Hardware-Watchdog-Pet-Daemon (Reboot-Loop-Risiko auf remote Prod).
# Kernel-Hang-Recovery läuft über die sicheren Lockup-Detektoren (sysctl), die
# NUR bei echtem CPU-Wedge/Panic auslösen. Kein Reboot bei Disk-I/O-Last.
#
# Deckt ab:
#   1) Kernel-Panic / Soft-/Hard-Lockup  -> automatischer Reboot (sysctl panic=10)
#   2) Wake-on-LAN am NIC aktiv + persistent  (Peer kann den PC per Magic-Packet wecken)
#   3) Tailscale-Selfheal-Timer  (wenn der Daemon hängt: restart; reconnect ist sonst automatisch)
# ─────────────────────────────────────────────────────────────────────────────
set -u
IFACE="${1:-eno1}"
log(){ echo "[selfheal-root] $*"; }

log "IFACE=$IFACE  host=$(hostname)"

# ── 1) Kernel-Hang -> Reboot (sicher; nur echte Lockups) ─────────────────────
cat > /etc/sysctl.d/99-cruiseconnect-selfheal.conf <<EOF
# CruiseConnect Self-Healing: bei echtem Kernel-Hang/Panic automatisch rebooten.
# Loest NUR bei genuinem CPU-Lockup/Panic aus (nicht bei Disk-I/O-Wait).
# BEWUSST OHNE panic_on_oops: ein nicht-fataler Oops (z.B. Storage/Driver-WARN)
# waehrend des mehrstuendigen Graph-Imports wuerde sonst zum Reboot eskalieren
# und koennte loopen. panic=10 + Lockup-Detektoren decken echte Haenger ab.
kernel.panic = 10
kernel.softlockup_panic = 1
kernel.hardlockup_panic = 1
kernel.watchdog = 1
kernel.nmi_watchdog = 1
EOF
sysctl -p /etc/sysctl.d/99-cruiseconnect-selfheal.conf >/dev/null 2>&1 && log "sysctls applied" || log "sysctl apply had warnings"
# Aggressives panic_on_oops explizit ZURUECKNEHMEN (Reviewer-Auflage): ein
# nicht-fataler Oops soll NICHT rebooten (Loop-Schutz waehrend Import).
sysctl -w kernel.panic_on_oops=0 >/dev/null 2>&1 && log "panic_on_oops reset to 0 (safe)"

# ── 2) Wake-on-LAN aktivieren + persistent ───────────────────────────────────
if ! command -v ethtool >/dev/null 2>&1; then
  log "ethtool fehlt -> apt-get install"
  (apt-get update -qq && apt-get install -y -qq ethtool) >/dev/null 2>&1 || log "ethtool-install FEHLGESCHLAGEN (kein Netz?)"
fi
if command -v ethtool >/dev/null 2>&1; then
  ETHTOOL=$(command -v ethtool)   # echte Binary-Pfad (Ubuntu: /usr/sbin/ethtool)
  SUPP=$("$ETHTOOL" "$IFACE" 2>/dev/null | awk -F': ' '/Supports Wake-on/{print $2}')
  log "ethtool=$ETHTOOL  WoL supported modes: ${SUPP:-unknown}"
  "$ETHTOOL" -s "$IFACE" wol g 2>/dev/null && log "WoL 'g' (magic packet) enabled live" || log "WoL live-enable failed (NIC/driver?)"
  # Persistenz über einen systemd-Oneshot-Boot-Hook (absoluter ethtool-Pfad):
  cat > /etc/systemd/system/cc-wol.service <<EOF
[Unit]
Description=CruiseConnect: enable Wake-on-LAN (magic packet) on $IFACE
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=$ETHTOOL -s $IFACE wol g
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable cc-wol.service >/dev/null 2>&1 && log "cc-wol.service enabled (persistent)" || log "cc-wol enable failed"
  CURWOL=$(ethtool "$IFACE" 2>/dev/null | awk -F': ' '/Wake-on:/{print $2; exit}')
  log "WoL current: ${CURWOL:-unknown}  (g=magic ON, d=OFF)"
else
  log "WoL uebersprungen (kein ethtool)"
fi

# ── 3) Tailscale-Selfheal (Daemon-Hang -> restart; Reconnect sonst automatisch)
cat > /usr/local/bin/cc_ts_guard.sh <<'EOF'
#!/bin/sh
# Restartet tailscaled nur wenn der Backend-State ueber mehrere Checks NICHT Running ist.
# (Reconnect nach Netz-Blip macht tailscaled selbst; das hier faengt HAENGENDE Daemons.)
STATE=$(tailscale status --json 2>/dev/null | tr -d ' \n' | grep -o '"BackendState":"[^"]*"' | head -1 | cut -d'"' -f4)
CNT_FILE=/run/cc_ts_guard.fails
if [ "$STATE" = "Running" ] || [ "$STATE" = "Starting" ]; then rm -f "$CNT_FILE"; exit 0; fi
N=$(cat "$CNT_FILE" 2>/dev/null || echo 0); N=$((N+1)); echo "$N" > "$CNT_FILE"
logger -t cc-ts-guard "tailscale BackendState=$STATE fail=$N"
# Erst nach 3 aufeinanderfolgenden Fails (Timer 60s) neustarten -> ~3min Toleranz.
if [ "$N" -ge 3 ]; then
  logger -t cc-ts-guard "restarting tailscaled (state=$STATE)"
  systemctl restart tailscaled
  rm -f "$CNT_FILE"
fi
exit 0
EOF
chmod +x /usr/local/bin/cc_ts_guard.sh
cat > /etc/systemd/system/cc-ts-guard.service <<EOF
[Unit]
Description=CruiseConnect: Tailscale hang self-heal
[Service]
Type=oneshot
ExecStart=/usr/local/bin/cc_ts_guard.sh
EOF
cat > /etc/systemd/system/cc-ts-guard.timer <<EOF
[Unit]
Description=CruiseConnect: run Tailscale self-heal every 60s
[Timer]
OnBootSec=90
OnUnitActiveSec=60
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now cc-ts-guard.timer >/dev/null 2>&1 && log "cc-ts-guard.timer enabled+started" || log "cc-ts-guard enable failed"

log "DONE. Verify: sysctl kernel.panic ; ethtool $IFACE|grep Wake-on ; systemctl list-timers|grep cc-ts"
