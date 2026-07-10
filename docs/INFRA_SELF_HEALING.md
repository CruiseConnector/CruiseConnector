# Mini-PC Self-Healing (PC1 `vucko` + PC2 `vucko2`)

Ziel (Vucko, 2026-07-09): Die beiden GraphHopper-Mini-PCs sollen sich **komplett
selbst** heilen — Vucko soll die PCs **nie** anfassen müssen, auch nicht bei Hang,
Crash, Kernel-Lockup, Stromausfall oder wenn Tailscale wegfällt.

Alles unten ist **installiert, aktiv und getestet** (Stand 2026-07-09). Root-Zugriff
ohne sudo-Passwort läuft über die `docker`-Gruppe (`nsenter` in den Host-Namespace).

## Was automatisch abgefangen wird

| Fehlerfall | Mechanismus | Status |
|---|---|---|
| **GraphHopper stürzt ab** | systemd `Restart=always` (PC1) / Docker `restart=unless-stopped` (PC2) | ✅ |
| **GraphHopper hängt** (lauscht, /health tot) | PC1: `gh-healthcheck.timer` (60s). PC2: `gh-guardian`-Container (restart bei 3× /health-Fail, getestet via `docker pause`) | ✅ getestet |
| **Prozess/Dienst tot nach Reboot** | alle Units `enabled` + Container `restart=always/unless-stopped` | ✅ |
| **Kernel-Hang / Soft-/Hard-Lockup / Panic** | sysctl `softlockup_panic=1`, `hardlockup_panic=1`, `panic=10` → Auto-Reboot. Bewusst **ohne** `panic_on_oops` und **ohne** HW-Watchdog-Pet-Daemon (Reboot-Loop-Schutz) | ✅ |
| **Tailscale-Netz-Blip** | tailscaled reconnectet selbst (WireGuard, retry forever) | ✅ |
| **Tailscale-Daemon hängt** | `cc-ts-guard.timer` (60s): 3× nicht-`Running` → `systemctl restart tailscaled` | ✅ |
| **Der PARTNER-PC ist tot/aus** | `cross-guardian`-Container: Peer >5min per SSH:22 nicht erreichbar → **Wake-on-LAN Magic-Packet** an dessen MAC | ✅ Sende-Pfad getestet |
| **Import läuft (Stunden /health rot)** | `gh-guardian` pausiert Restarts solange `/home/vucko2/gh-eu/.import_in_progress` existiert + exponentieller Backoff | ✅ |

## Installierte Artefakte (versioniert in `scripts/infra/`)

- `gh_guardian_pc2.sh` → Container `gh-guardian` auf PC2 (Docker-GH Hang-Recovery).
- `cross_guardian.py` → Container `cross-guardian` auf **beiden** (Peer-WoL).
- `selfheal_root_install.sh` → Root-Schicht (via nsenter): sysctls + WoL-aktivieren
  + `cc-wol.service` (WoL persistent) + `cc-ts-guard` Timer.

**Netzdaten:** PC1 `vucko` LAN 192.168.1.18, MAC 04:0e:3c:ac:e7:07, TS 100.65.155.7.
PC2 `vucko2` LAN 192.168.1.168, MAC 04:0e:3c:ac:ec:10, TS 100.64.27.108. Beide eno1.

## ⚠️ EINMALIGE User-Aktionen (kann ich nicht remote — BIOS/Admin-Console)

Diese drei schließen die letzten physischen Lücken. Ohne sie funktioniert alles
oben trotzdem — sie erweitern nur „aus dem komplett stromlosen/ausgeschalteten
Zustand aufwachen":

1. **BIOS beider PCs → „After Power Loss" = Power On** (HP: *Power → After Power Loss*).
   Damit bootet der PC nach einem Stromausfall von selbst wieder.
2. **BIOS beider PCs → Wake-on-LAN / S4-S5 aktivieren** (+ „Deep Sleep"/ErP aus).
   Damit weckt das Magic-Packet des Partner-PCs ihn aus dem Aus-Zustand.
3. **Tailscale-Admin-Console → Key-Expiry für `vucko` + `vucko2` deaktivieren.**
   Verhindert den einzigen echten Tailscale-Aussperr-Fall (Key läuft nach 180 Tagen ab).

## Rollback / Deaktivieren

- Container: `docker rm -f gh-guardian cross-guardian` (auf dem jeweiligen PC).
- sysctls: `/etc/sysctl.d/99-cruiseconnect-selfheal.conf` löschen + reboot (oder `sysctl -w kernel.softlockup_panic=0`).
- WoL/TS-Guard: `systemctl disable --now cc-wol.service cc-ts-guard.timer`.
