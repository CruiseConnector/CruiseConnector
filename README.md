# CruiseConnect

Eine Flutter-App für Autofahrer: Routen generieren, cruisen, Community.

## Tech-Stack

- **Flutter** (Dart)
- **Mapbox Maps SDK** – Karte & Navigation
- **Supabase** – Backend (Auth, Datenbank, Edge Functions)
- **Geolocator** – GPS-Position

---

## Setup (lokale Entwicklung)

### 1. Repository klonen

```bash
git clone <dein-repo-url>
cd CruiserConnect
```

### 2. API-Keys einrichten

Die echten Keys sind **nicht** im Repository (aus Sicherheitsgründen gitignored).
Du musst sie einmalig lokal anlegen:

```bash
# Template kopieren
cp lib/config/secrets.example.dart lib/config/secrets.dart
```

Öffne dann `lib/config/secrets.dart` und trage deine Keys ein:

| Variable | Wo findest du sie? |
|---|---|
| `mapboxPublicToken` | [account.mapbox.com](https://account.mapbox.com/) → Tokens |
| `supabaseUrl` | Supabase Dashboard → Project Settings → API → URL |
| `supabaseAnonKey` | Supabase Dashboard → Project Settings → API → **anon** key |

> **Wichtig:** `secrets.dart` niemals committen! Sie ist in `.gitignore` eingetragen.

### 3. Dependencies installieren

```bash
flutter pub get
```

### 4. App starten

```bash
flutter run
```

---

## Projektstruktur

```
lib/
├── config/
│   ├── secrets.dart          ← GITIGNORED – echte Keys (lokal anlegen)
│   └── secrets.example.dart  ← Template (committed)
├── core/
│   └── constants.dart        ← AppConstants (liest aus secrets.dart)
├── data/
│   └── services/             ← API-Services (Geocoding, Routen, Auth, ...)
├── domain/
│   └── models/               ← Datenmodelle (RouteResult, SavedRoute, ...)
└── presentation/
    ├── pages/                ← Screens (Login, Home, CruiseMode, ...)
    └── widgets/              ← Wiederverwendbare UI-Komponenten
```

---

## Benötigte API-Keys

| Key | Dienst | Typ |
|---|---|---|
| `MAPBOX_PUBLIC_TOKEN` | Mapbox | Public (beginnt mit `pk.`) |
| `SUPABASE_URL` | Supabase | Projekt-URL |
| `SUPABASE_ANON_KEY` | Supabase | Anon/Public Key |

---

## Wichtige Hinweise für Entwickler

- **Secrets niemals committen.** `lib/config/secrets.dart` ist gitignored.
- Der Mapbox Token ist ein **Public Token** – er ist für Client-seitige Nutzung gedacht. Trotzdem sollte er nicht öffentlich sein (Quota-Missbrauch möglich).
- Der Supabase Anon Key ist ebenfalls ein Public Key, aber Row Level Security (RLS) schützt die Daten im Backend.

---

## 🌐 Web-Entwicklung (kein Xcode nötig)

### Lokal im Browser testen
```bash
make web-dev
# Öffnet: http://localhost:8080
```

### Vom Handy testen (selbes WLAN)
```bash
make web-local
# Öffnet: http://DEINE-IP:8080
# → IP findest du mit: ipconfig getifaddr en0 (Mac)
```

### Auf Vercel deployen (empfohlen, kostenlos)

**Einmalig einrichten (2 Minuten):**
1. [vercel.com](https://vercel.com) → Account erstellen (GitHub Login)
2. „Add New Project" → dein GitHub Repo auswählen
3. Vercel erkennt `vercel.json` automatisch
4. → Fertig! Bei jedem `git push` wird automatisch deployed

**URL:** `https://cruiserconnect-XXXX.vercel.app`

**CI/CD via GitHub Actions (optional, für mehr Kontrolle):**

Für den automatischen Deploy über GitHub Actions brauchst du 3 Secrets in GitHub (Settings → Secrets → Actions):

| Secret | Wo finden? |
|---|---|
| `VERCEL_TOKEN` | vercel.com → Account Settings → Tokens |
| `VERCEL_ORG_ID` | vercel.com → Settings → General → Team ID |
| `VERCEL_PROJECT_ID` | Vercel Projekt → Settings → General → Project ID |

### Backup-Option: Netlify
1. [netlify.com](https://netlify.com) → „New site from Git" → GitHub Repo verbinden
2. `netlify.toml` wird automatisch erkannt
3. → Automatischer Deploy bei jedem Push

### Bekannte Limitierungen auf Web
- **mapbox_maps_flutter** – das native Mapbox SDK unterstützt Web nicht direkt; Mapbox GL JS ist via `web/index.html` eingebunden
- **GPS / Geolocator** – funktioniert im Browser (via Permissions API), aber weniger präzise als nativ
- **flutter_tts** – Text-to-Speech hat eingeschränkte Browser-Unterstützung
- **image_picker** – Kamera-Zugriff funktioniert im Browser, aber nur über HTTPS
