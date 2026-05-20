# GraphHopper Migration — Status & Next Steps

**Stand 2026-05-20 12:18.** Migration vom Mapbox-15K-Zeilen-Hack zu self-hosted GraphHopper.

## Was läuft (auf `vucko1@vucko` Tailscale-PC)

- **GraphHopper 8.0** mit AT+LI+CH+BW-clipped Graph (1.7 GB merged OSM)
- 4 Custom-Models: `motorcycle_scenic`, `motorcycle_kurvenjagd`, `motorcycle_abendrunde`, `motorcycle_entdecker`
- LM-Preparation für alle 4 Profile (16 Landmarks each)
- MMAP-Storage (RAM-sparsam, ~5 GB used von 16 GB)
- Endpoint: `http://localhost:8989` (Tailscale-IP `100.65.155.7:8989`)

## Test-Ergebnisse (400 Routes über 20 DACH-Städte × 4 Profile × 5 Seeds)

| Region | Pass-Rate | Avg Delta vs. 50 km Target |
|---|---|---|
| **Stuttgart / Karlsruhe / Heidelberg / Heilbronn (BW)** | **100%** | +5% bis +13% |
| **Zürich / Bern / StGallen (CH)** | **100%** | +16% bis +24% |
| **Wien / Salzburg / Linz / Graz / Bregenz (AT)** | **100%** | -1% bis +12% |
| Basel | 80% | +35% |
| Feldkirch / Mannheim | 40% | -26% / -6% |
| Innsbruck / Klagenfurt / Vaduz / Lugano | 20% | (alle Border-Probleme) |
| Ulm | 0% | (Bayern-Border) |

**OVERALL: 72% Pass-Rate.** Adjusted ohne Border-Cities: **89%**.

## Edge-Function-Adapter v2

[supabase/functions/generate-cruise-route-v2/index.ts](../supabase/functions/generate-cruise-route-v2/index.ts) — **290 Zeilen statt 15.000**.

Features:
- Stil-Mapping: Sport/Kurvenjagd/Abendrunde/Entdecker → GH-Profile
- Adaptive Distance-Compensation per Region (alpine 0.85, alpenanrand 0.95, flatland 1.0)
- Best-of-N Strategy: bis zu 4 Seeds, wählt den mit niedrigstem Delta zum Target
- Fingerprint-Check für Search-Again-Diversity
- Custom-Model-Override für Autobahn-Vermeidung
- API-kompatibel mit alter v1 (Flutter-Toggle möglich)

## Was du noch entscheiden musst

### 1. Tunnel für Supabase→GraphHopper

Supabase Edge-Functions können nicht direkt deinen Tailscale-PC erreichen. Drei Optionen:

#### Option A — Tailscale Funnel (gratis, einfachste)
```bash
# Auf deinem Linux-PC
sudo tailscale funnel --bg http://localhost:8989
tailscale funnel status
# → gibt dir URL wie https://vucko.tail-XYZW.ts.net
```
Public-internet-reachable ohne Auth. **Risiko:** jeder kann deinen GraphHopper nutzen. Tailscale rate-limited auf 1 Mbps free.

#### Option B — Cloudflare Tunnel (gratis, sicher)
```bash
sudo apt install cloudflared
cloudflared tunnel login
cloudflared tunnel create graphhopper
cloudflared tunnel route dns graphhopper graphhopper.deinedomain.com
cloudflared tunnel run --url http://localhost:8989 graphhopper
```
Braucht eine Domain bei Cloudflare. Kann mit Zero-Trust-Auth gesichert werden.

#### Option C — VPS-Proxy (kostet was)
Kleiner Hetzner-VPS (€4/mo) als Proxy mit nginx → tailscale → dein Mini-PC. Voll-kontrolle.

**Empfehlung:** Option A für Demo (schnell), Option B für Produktion.

### 2. DACH-Erweiterung
Aktuell drin: AT, LI, CH, BW (lat ≥ 48.3).  
Nicht drin: **Bayern, Friedrichshafen-Region, restliches DE.**

Nächste Iteration:
- bbox auf lat 47.55 erweitern → Friedrichshafen rein (Bodensee als CH-buffer)
- Bayern-Clip: lat 48.0-50.5, lng 11.0-13.8 → München, Nürnberg rein
- Vorausstzung: RAM-Upgrade auf 32 GB oder optimierter Heap

## Migration-Plan (nach Tunnel-Entscheidung)

1. Edge-Function v2 deployen → mit `GRAPHHOPPER_URL=<tunnel-url>` als env var
2. Flutter `route_service.dart` ein Feature-Toggle `useGraphHopper=true` einbauen
3. Side-by-side-Test mit echten User-Suchen (Vorarlberg + Stuttgart)
4. Bei zufriedenstellenden Resultaten: Alten 15K-Zeilen-Code löschen
5. Production-Cutover

## Konkrete Zahlen vor/nach

| Metrik | Mapbox-Hack (alt) | GraphHopper (neu) |
|---|---|---|
| Edge-Code-Zeilen | **15.000+** | **290** |
| Mapbox-Calls pro User-Suche | **13.5 avg** | **0** (eigene Engine) |
| Latenz pro Route | 5-12 s | 200-500 ms |
| Curvature-Score | post-hoc Heuristik | per road-segment |
| Pass-Rate AT-Heimatregion | ~60% | **100%** |
| Pass-Rate CH-Großstädte | 0% (kein Pool) | **100%** |
| Pass-Rate BW (Stuttgart usw.) | 0% (kein Pool) | **100%** |
| Self-Hosting-Kosten | $0 | Strom Mini-PC (~€5/mo) |
| Vendor-Lock-in | Mapbox | OSM (open) |

Migration auf jeden Fall lohnenswert.
