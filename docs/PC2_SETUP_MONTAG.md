# PC2 Setup als GraphHopper-Mirror — Montag-Plan

**Ziel:** 2. Mini-PC als identischer Mirror — verdoppelt Kapazität + Failover.

**Vorrausetzung:** PC2 ist Tailscale-verbunden, Hostname bekannt (du sagst mir Montag).
Annahme: `vucko2` mit Tailscale (anpassen falls anders).

---

## 🚀 Montag-Workflow (du machst auf deinem Mac)

### Schritt 1: Tailscale-Connectivity verifizieren

```bash
# Mac kann PC2 sehen?
ssh -o ConnectTimeout=10 vucko1@vucko2 'hostname && uname -a'
```

Wenn das klappt → weiter. Wenn nicht → Tailscale-Authentifizierung prüfen.

### Schritt 2: Bootstrap (Java + Verzeichnisse)

```bash
ssh vucko1@vucko2 << 'BOOTSTRAP'
sudo apt update
sudo apt install -y openjdk-21-jre-headless curl rsync htop
mkdir -p ~/graphhopper/bin ~/graphhopper/config ~/graphhopper/data
java -version
BOOTSTRAP
```

### Schritt 3: GraphHopper rsync von PC1 → PC2

**Dauert ~5-10 Min wegen Graph-Cache-Files** (1.7GB DACH + 4.5GB DE):

```bash
# Auf PC1 starten und alles nach PC2 transferieren
ssh vucko1@vucko 'rsync -avz --progress \
  --include="bin/" --include="bin/graphhopper-web.jar" \
  --include="config/" --include="config/*" \
  --include="data/" --include="data/graph-cache/" --include="data/graph-cache/**" \
  --include="data/graph-cache-de/" --include="data/graph-cache-de/**" \
  --include="data/*.osm.pbf" \
  --exclude="*" \
  ~/graphhopper/ vucko1@vucko2:~/graphhopper/'
```

### Schritt 4: systemd-Units kopieren

```bash
# Files vom Mac (worktree) auf PC2 kopieren
scp /Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f/docs/systemd_graphhopper_dach.service \
    /Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f/docs/systemd_graphhopper_de.service \
    vucko1@vucko2:/tmp/

# Auf PC2 installieren
ssh vucko1@vucko2 << 'INSTALL'
sudo cp /tmp/systemd_graphhopper_dach.service /etc/systemd/system/graphhopper_dach.service
sudo cp /tmp/systemd_graphhopper_de.service /etc/systemd/system/graphhopper_de.service
sudo systemctl daemon-reload
sudo systemctl enable --now graphhopper_dach.service
sudo systemctl enable --now graphhopper_de.service
sleep 30  # warten bis GH bootet
curl -s http://localhost:8989/health  # erwarte: OK
curl -s http://localhost:8991/health  # erwarte: OK
INSTALL
```

### Schritt 5: Tailscale-Funnel für Public-Access

**Wichtig**: PC2 braucht andere Funnel-Ports als PC1, da `vucko.taildddd94.ts.net` für PC1 reserviert ist.

```bash
ssh vucko1@vucko2 << 'FUNNEL'
sudo tailscale funnel --bg --https=443 http://localhost:8989
sudo tailscale funnel --bg --https=8443 http://localhost:8991
tailscale funnel status
# Output zeigt dir die public URL — z.B. https://vucko2.taildddd94.ts.net
FUNNEL
```

**Notiere dir die ausgegebenen URLs** — die werden gleich als Supabase-Secrets gesetzt.

### Schritt 6: Sag mir die URLs

Schreib mir die 2 Funnel-URLs (z.B. `https://vucko2.taildddd94.ts.net` + `:8443`).
Dann mache ich autonom:
- Supabase-Secrets `GRAPHHOPPER_URL_2` + `GRAPHHOPPER_DE_URL_2` setzen
- Edge v2 Code-Update für Random-Pick zwischen beiden Servern
- Test-Sweep mit 24 routes über beide Server verteilt

---

## 🛡 Was passiert dann automatisch

**Edge v2 Load-Balancing** (mache ich am Code, kommt sobald deine URLs durch sind):

```typescript
const SERVERS_DACH = [
  Deno.env.get('GRAPHHOPPER_URL'),
  Deno.env.get('GRAPHHOPPER_URL_2'),
].filter(Boolean);
// Random-Pick + Fallback bei Error
const url = SERVERS_DACH[Math.floor(Math.random() * SERVERS_DACH.length)];
```

**Vorteile** ab Montag:
- ✅ **2× Kapazität** (~5.000-10.000 DAU statt 2.000)
- ✅ **Failover gratis**: einer down → anderer übernimmt
- ✅ **Auto-Seeder kann „critical"-Tier** ausnutzen ohne einen PC zu überlasten
- ✅ **Wartung möglich**: PC1 rebooten ohne Downtime

---

## 🔄 Falls dir Montag was nicht klappt

Probleme die auftauchen können:
1. **"Permission denied" bei sudo** → User braucht sudo-Rights auf PC2
2. **Tailscale-Funnel braucht extra Auth** → `tailscale up --advertise-funnel`
3. **Graph-Cache rsync sehr langsam** → Tailscale ist 1Mbps free; ggf. via lokales LAN

Sag einfach Bescheid wenn ein Schritt hängt, ich debug live mit dir.

---

## 📊 ROI

| Aktion | Dauer | Effekt |
|---|---|---|
| rsync graph-caches | ~10 min | spart 30-60min LM-Preparation |
| systemd install | ~3 min | Auto-Restart wie PC1 |
| Funnel-Setup | ~2 min | Public reachability |
| Edge-Update (ich) | ~5 min | Load-Balancing live |
| **Total** | **~20 min** | **2× Kapazität + Failover** |

Lohnt sich definitiv für 0€ extra Cost.
