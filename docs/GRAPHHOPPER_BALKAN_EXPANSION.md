# GraphHopper Balkan-Erweiterung — Runbook (der „richtige" Fix)

**Ziel:** GraphHopper deckt auch RS/ME/MK/AL/XK/BG/RO/GR ab → Routing überall
via eigenem Graph, **kein Mapbox-Fallback mehr nötig**.

**Warum nötig:** Der aktuelle Graph `dach-italy-balkan.osm.pbf` deckt trotz
Namens nur DACH + IT + SI + HR (+teils BA) ab. Getestet 2026-07-09: alle
anderen Balkanstaaten → `point_off_road` / `coverage_out_of_bounds`.

> ⚠️ **Produktions-Outage:** Der Reimport nimmt den betroffenen Server für
> **~1–3 h offline** (Graph-Neuberechnung). In der Zeit übernimmt der jeweils
> ANDERE PC (Failover) bzw. der App-Pool. **Nur in einem verkehrsschwachen
> Fenster machen, PC1 und PC2 NACHEINANDER** (nie beide gleichzeitig).
> Solange NICHT durchgeführt, bleibt der Mapbox-Coverage-Fallback die Brücke.

---

## Schritt 1 — Karten-PBF bauen (auf dem Mac, kein Server-Impact)

```bash
# Basis-Extract vom PC holen (falls nicht lokal):
scp vucko1@vucko2:~/graphhopper/data/dach-italy-balkan.osm.pbf ~/graphhopper_balkan_build/

BASE_PBF=~/graphhopper_balkan_build/dach-italy-balkan.osm.pbf \
  bash scripts/graphhopper_build_balkan_pbf.sh
# → ~/graphhopper_balkan_build/dach-balkan-full.osm.pbf  (lädt 8 Länder + merge)
```

## Schritt 2 — PBF auf den PC kopieren

```bash
scp ~/graphhopper_balkan_build/dach-balkan-full.osm.pbf \
    vucko1@vucko2:~/graphhopper/data/
```

## Schritt 3 — Reimport auf PC2 (danach identisch auf PC1)

```bash
ssh vucko1@vucko2
cd ~/graphhopper

# 3a. Config auf die neue PBF zeigen — NUR die datareader-Zeile ändern,
#     PROFILE UNVERÄNDERT lassen (motorcycle_scenic/_kurvenjagd/_abendrunde/
#     _entdecker + car). Ein Profil-Mismatch = GH-Crash-Loop "Profiles do not
#     match" (siehe Memory routing_car_profile_drift).
sed -i 's#datareader.file:.*#datareader.file: /home/vucko1/graphhopper/data/dach-balkan-full.osm.pbf#' config/config.yml

# 3b. Service stoppen + ALTEN Graph-Cache löschen (erzwingt Neu-Import).
#     Der Ordnername steht in config.yml unter `graph.location:` (oft `graph-cache`).
sudo systemctl stop graphhopper_dach
GRAPHDIR=$(grep -E '^\s*graph.location' config/config.yml | awk '{print $2}')
mv "$GRAPHDIR" "${GRAPHDIR}.bak_$(date +%s)"   # Backup statt löschen — Rollback möglich

# 3c. Import kann mehr RAM brauchen als der Betrieb (größere Fläche).
#     Wenn der Import OOMt: -Xmx im systemd-Unit temporär auf 14–16g,
#     danach zurück auf 10g. (Unit: /etc/systemd/system/graphhopper_dach.service)
sudo systemctl start graphhopper_dach
journalctl -u graphhopper_dach -f    # bis "Started server" / Import fertig (~1–3 h)
```

## Schritt 4 — Verifizieren (Belgrad muss jetzt via graphhopper kommen)

```bash
# lokal am PC:
curl -s "http://localhost:8989/route?point=44.7866,20.4489&point=44.67,20.65&profile=car&points_encoded=false" \
  | head -c 300      # → gültige Geometrie statt "Cannot find point"

# End-to-end über die Edge (von überall) — sollte src=graphhopper zeigen:
cd /Users/vucko/Development/CruiserConnect
python3 scratchpad/balkan_matrix.py   # (das Diagnose-Skript aus dieser Session)
```

## Schritt 5 — PC1 identisch (Redundanz)

Schritte 2–4 mit `vucko1@vucko` wiederholen (Port 8991, `graphhopper_de`).
Erst starten, wenn PC2 wieder grün ist (nie beide gleichzeitig offline).

## Schritt 6 — Mapbox-Fallback entfernen (nach erfolgreicher Verifikation)

Sobald beide PCs den Balkan liefern, den Coverage-Fallback in
`supabase/functions/generate-cruise-route-v2/index.ts` entfernen
(`tryMapboxCoverageFallback` + der Aufruf im Fehler-Ausgang) und neu deployen.
Dann läuft **alles** über GraphHopper, kein Mapbox mehr.

---

### Rollback
Import kaputt/zu langsam? `sudo systemctl stop graphhopper_dach`,
`mv ${GRAPHDIR}.bak_* ${GRAPHDIR}`, `datareader.file` in config.yml zurück auf
`dach-italy-balkan.osm.pbf`, `start`. Server ist in Minuten wieder auf dem alten Graph.
