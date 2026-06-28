# Routing-Infra: „darf nie wieder ausgehen"

Root Cause der wiederkehrenden „keine Route / Temporärer Serverfehler":
Ein GraphHopper-Mini-PC ging aus (Strom/Reboot). Die systemd-Autostart-Units
waren **vorbereitet, aber nie aktiviert** (`docs/SYSTEMD_INSTALL.md` „wartet auf
sudo") → GraphHopper lief als manueller Prozess → nach Aus = weg, kein Auto-Start.

## 1. Ein-Befehl-Fix pro PC (einmalig, mit sudo)

Skript auf den Mini-PC kopieren und ausführen:

```bash
sudo bash scripts/graphhopper_bulletproof_boot.sh
```

Danach automatisch bei JEDEM Boot:
- **GraphHopper-Autostart** (`systemctl enable` — das fehlte) + `Restart=always`
  (Crash → 15 s) + **Health-Watchdog** alle 60 s (fängt Hänger ab, die ein
  reiner Crash-Restart nicht sieht).
- **Tailscale** kommt automatisch zurück (`tailscaled` enabled + `tailscale up --ssh`).
- **Wake-on-LAN** auf der NIC aktiviert (persistent via `wol-enable.service`).

Das Skript ist idempotent und gibt am Ende NIC + MAC + die BIOS-Schritte aus.

## 2. Einmalig im BIOS (nur direkt am Gerät, HP ProDesk 600 G5)

`F10` beim Booten → BIOS:
- **Advanced → Power-On Options → „After Power Loss" = Power On**
  → PC schaltet sich nach Stromausfall **von selbst** wieder ein. ⟵ wichtigster Punkt
- **Advanced → Built-In Device Options → „Wake On LAN" = On / Boot to Network**

## 3. Remote aufwecken (wenn der PC trotzdem mal aus ist)

Von einem Gerät im **selben Heimnetz** wie die Mini-PCs:

```bash
wakeonlan <MAC>     # macOS: brew install wakeonlan
```

(Tailscale `wake` gibt es NICHT; WoL braucht ein Gerät im selben LAN. Reiner
Tailscale-Overlay-Zugriff kann einen ausgeschalteten PC nicht aufwecken.)

## 4. App-seitige Garantie (bereits live, commit 4b11a6c + 7dfe293)

**Unabhängig von der Infra**: Wenn ALLE GraphHopper-Server weg sind, liefert die
App jetzt den nächstgelegenen, beim Seeden verifizierten **Pool-Rundkurs**
GH-unabhängig aus (geometrisch rebasiert, ohne Anfahrts-Leg) statt „Serverfehler".
Per Regressionstest gesichert (`route_service_coordinator_test.dart`,
„GH-Totalausfall …"). Zahlende Nutzer bekommen also auch während eines Ausfalls
eine fahrbare Route — vorausgesetzt der Pool hat Abdeckung in der Region (DACH dicht).

## 4b. Server-Failover: „einer fällt aus → der zweite übernimmt" (live, Edge-Fn)

Die Edge-Function (`generate-cruise-route-v2`) wählt pro Anfrage `{primary, fallback}`
und versucht bei Fehler/Timeout automatisch den Fallback-Server.

**Bug war:** der Fallback zeigte auf einen Server auf **derselben** Maschine
(PC2-DACH `GRAPHHOPPER_URL` + PC2-EU `GRAPHHOPPER_EU_URL` = beide PC2). Fiel PC2
aus, lief das „Failover" auf die tote Maschine → Serverfehler.

**Fix (deployed):** Fallback ist jetzt immer **PC1 = `GRAPHHOPPER_DE_URL`** (die
andere physische Maschine). PC2 aus → PC1 übernimmt automatisch.

**Damit das wirklich greift, müssen die Supabase-Secrets auf VERSCHIEDENE
Maschinen zeigen** (Dashboard → Project Settings → Edge Functions → Secrets):
- `GRAPHHOPPER_URL`  → PC2 (`vucko2-hp-prodesk…`), Port 8989  ← primary
- `GRAPHHOPPER_DE_URL` → **PC1** (`vucko`), Port 8991          ← cross-machine fallback
- `GRAPHHOPPER_EU_URL` → PC2, EU-Port

> Für **volle** Redundanz sollte PC1 dieselbe Karten-PBF wie PC2 haben
> (aktuell hat PC1-DE laut Code nur DE/Mittelost-Daten — für Vorarlberg/AT
> reicht die Bodensee-Abdeckung; TODO: PC1 mit derselben
> `dach-italy-balkan.osm.pbf` wie PC2 neu seeden, dann kann jeder PC alles).

## 4c. Zwei-Schichten-Garantie (Zusammenfassung)

1. **PC2 fällt aus** → Edge failt automatisch auf **PC1** (live, oben).
2. **Beide PCs aus** → die **App liefert Pool-Rundkurse** GH-unabhängig aus
   (commit 4b11a6c + 7dfe293, 1.0.4+57) — „der Routenpool übernimmt komplett,
   bis die Server wieder online sind". Greift überall wo der Pool Abdeckung hat
   (DACH dicht).

## 5. Status / Health prüfen

```bash
# am PC:
systemctl status graphhopper_dach graphhopper_de
journalctl -u graphhopper_dach -f
# von überall (gibt up/down des Primärservers):
curl -s -H "apikey: <anon>" \
  https://<project>.supabase.co/functions/v1/generate-cruise-route-v2/health
```

> Empfehlung: `/health` so erweitern, dass es ALLE drei Server (DACH/DE/EU)
> prüft statt nur den Primär — dann zeigt es echten Gesamtzustand.
