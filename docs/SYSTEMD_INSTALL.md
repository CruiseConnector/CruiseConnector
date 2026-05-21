# systemd Auto-Restart für GraphHopper (Task 17)

**Wartet auf:** User-sudo-Permission auf vucko1@vucko

Installiert 2 systemd-Units (DACH 8989 + DE 8991) mit `Restart=always`.
Damit überleben beide GH-Server PC-Reboots + GH-Crashes (max 20s downtime).

## Install-Schritte (auf vucko1@vucko als root)

```bash
# 1. Files auf den Server kopieren
sudo cp graphhopper_dach.service /etc/systemd/system/
sudo cp graphhopper_de.service /etc/systemd/system/

# 2. Aktuelle Prozesse stoppen
pkill -f graphhopper-web

# 3. Units aktivieren + starten
sudo systemctl daemon-reload
sudo systemctl enable graphhopper_dach.service
sudo systemctl enable graphhopper_de.service
sudo systemctl start graphhopper_dach.service
sudo systemctl start graphhopper_de.service

# 4. Verify
sudo systemctl status graphhopper_dach.service
sudo systemctl status graphhopper_de.service

# 5. Logs ansehen falls nötig
journalctl -u graphhopper_dach.service -f
journalctl -u graphhopper_de.service -f
```

## Verhalten nach Install

- **Reboot**: beide Server starten automatisch nach `network-online`
- **Crash**: Restart nach 20 s (RestartSec=20)
- **OOM**: MemoryMax=12G/6G verhindert Host-OOM, GH wird gekillt + Restart
- **Tailscale**: After=tailscaled stellt sicher dass Tunnels nach Server-Start verfügbar sind

## Rollback

```bash
sudo systemctl disable graphhopper_dach.service graphhopper_de.service
sudo systemctl stop graphhopper_dach.service graphhopper_de.service
sudo rm /etc/systemd/system/graphhopper_dach.service /etc/systemd/system/graphhopper_de.service
sudo systemctl daemon-reload
# Manuelles Start wie zuvor
```
