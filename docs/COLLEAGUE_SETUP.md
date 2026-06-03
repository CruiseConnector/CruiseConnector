# Dev-Onboarding — CruiseConnect (für einen neuen Kollegen)

> Ziel: Kollege klont das Repo und kann **programmieren + Routen testen** —
> mit dem Minimum an Secrets. GraphHopper ist hinter der Supabase-Edge
> abstrahiert, d.h. **für die App-Entwicklung braucht er KEINE GraphHopper-Keys.**

---

## 0. Architektur in 30 Sekunden (damit klar ist, was was braucht)

```
Flutter-App ──► Supabase (Auth + DB)                         [braucht: secrets.dart]
Flutter-App ──► Supabase Edge "generate-cruise-route-v2" ──► GraphHopper (PC1/PC2)
                  ▲ die Edge kennt die GraphHopper-URLs       [Server-Secret, NICHT in der App]
Flutter-App ──► Karten-Tiles (self-hosted R2 + Mapbox-Fallback)  [braucht: Mapbox-Token]
```

**Kernpunkt:** Die App spricht **nie direkt** mit GraphHopper. Sie ruft die
Supabase-Edge-Funktion, und **die** spricht mit GraphHopper. Die GraphHopper-URLs
liegen als **Supabase-Secret** (server-seitig), nicht im App-Code. → Für normale
App-Arbeit reicht `secrets.dart` (3 Werte). GraphHopper-Zugang braucht er nur,
wenn er die **Edge-Funktion** oder den **GraphHopper-Server selbst** anfasst.

---

## 1. Pflicht: App lauffähig machen (deckt ~90 % der Arbeit ab)

### 1.1 Toolchain
```bash
# Flutter SDK (Version siehe pubspec.yaml / .fvmrc), Xcode (iOS), Android Studio
flutter --version
git clone <REPO-URL> && cd CruiserConnect
flutter pub get
```

### 1.2 Secrets-Datei anlegen (das EINE, was er von dir braucht)
```bash
cp lib/config/secrets.example.dart lib/config/secrets.dart
```
Dann in `lib/config/secrets.dart` die 3 Werte eintragen (du gibst sie ihm, s. §4):

| Feld | Was | Woher |
|---|---|---|
| `supabaseUrl` | `https://<projekt-id>.supabase.co` | Supabase → Project Settings → API → URL |
| `supabaseAnonKey` | Publishable/Anon-Key | Supabase → Project Settings → API → anon/publishable key |
| `mapboxPublicToken` | `pk.…` Public Token | account.mapbox.com → Tokens |

> `lib/config/secrets.dart` ist **gitignored** (`.gitignore` Zeile 49) — wird nie
> committet. Niemals echte Keys in `secrets.example.dart` schreiben.

### 1.3 Starten
```bash
flutter run            # Simulator/Gerät auswählen
```
**Routensuche funktioniert sofort** — die deployte Edge + GraphHopper laufen
bereits auf deinen PCs. Der Kollege braucht dafür **weder GraphHopper-URLs noch
Tailscale**.

> iOS aufs **echte Gerät**: Wenn der CarPlay-Antrag bei Apple noch nicht
> freigegeben ist, in `ios/Runner/Runner.entitlements` das
> `com.apple.developer.carplay-maps`-Entitlement auskommentieren (sonst
> Signier-Fehler). Steht als Kommentar drin.

---

## 2. Nur falls er die ROUTING-LOGIK (Edge-Funktion) ändert

Die Routing-Logik lebt in `supabase/functions/generate-cruise-route-v2/index.ts`.
Zum Deployen:

```bash
# Supabase CLI installieren + einloggen (einmalig)
brew install supabase/tap/supabase
supabase login                      # öffnet Browser → Access-Token

# Deployen (verify_jwt kommt aus supabase/config.toml — NICHT entfernen!)
supabase functions deploy generate-cruise-route-v2 --project-ref <PROJEKT-ID>
```

Die GraphHopper-URLs braucht er **lokal nicht** — sie sind bereits als Supabase-
Secrets gesetzt. Nur falls neu/zurückgesetzt:
```bash
# Server-Secrets (Werte = die Tailscale-/Cloudflare-URLs deiner PCs)
supabase secrets set GRAPHHOPPER_URL="<PC1-URL>" --project-ref <PROJEKT-ID>
supabase secrets set GRAPHHOPPER_EU_URL="<PC2-URL>" --project-ref <PROJEKT-ID>
```

> ⚠️ **Wichtig (sonst bricht Routing komplett):**
> - `supabase/config.toml` muss den Block `[functions.generate-cruise-route-v2]`
>   mit `verify_jwt = false` haben. Fehlt er, weist das Gateway den App-Key als
>   „Invalid JWT" ab → „keine Route" auf echten Geräten.
> - GraphHopper ehrt `custom_model` **nur per POST** (nicht GET) — `callGraphHopper`
>   schickt POST. Nicht auf GET zurückbauen, sonst wirken Autobahn-/Stil-Filter nicht.

---

## 3. Nur falls er GraphHopper selbst laufen lassen / debuggen will

GraphHopper läuft self-hosted auf deinen PCs (PC1 = DACH, PC2 = EU), erreichbar
über **Tailscale**. Zwei Wege:

- **A — Deinen Tailnet beitreten (empfohlen):** Du lädst ihn in dein Tailscale-
  Netz ein (Tailscale Admin → Invite). Dann erreicht er die GH-Server unter ihren
  `…ts.net`-URLs direkt (Health-Check: `curl https://<gh-host>/health`).
- **B — Eigenes lokales GraphHopper:** Anleitung in
  [`docs/GRAPHHOPPER_MIGRATION.md`](GRAPHHOPPER_MIGRATION.md) +
  [`docs/PC2_SETUP_MONTAG.md`](PC2_SETUP_MONTAG.md). Braucht eine OSM-`.pbf` +
  die 4 Custom-Models (`motorcycle_scenic/kurvenjagd/abendrunde/entdecker`).

> Es gibt **keinen API-Key** für GraphHopper — es ist ein offener self-hosted
> Server. Der „Zugang" = im selben Tailscale-Netz sein bzw. die URL kennen.

---

## 4. So gibst du ihm die Werte — SICHER (nicht über Git/Slack-Klartext)

| Wert | Sensibilität | Wie teilen |
|---|---|---|
| `supabaseUrl` | öffentlich | egal |
| `supabaseAnonKey` / Mapbox-Public-Token | client-seitig (ship in der App) | 1Password / Bitwarden geteilter Tresor, oder verschlüsselt |
| **Supabase Access-Token** (Edge-Deploy) | **hoch (Admin)** | nur via Passwort-Manager; besser: Kollege macht eigenen `supabase login` |
| **GraphHopper-URLs** (Tailscale/Cloudflare) | mittel | Passwort-Manager; ODER er ist im Tailnet, dann kennt er die Hosts ohnehin |
| Android-Keystore / Apple-Signing | hoch | nur du baust Releases, ODER Passwort-Manager + Apple-Team-Einladung |

**Goldene Regel:** Echte Keys gehören **nie** ins Repo. `secrets.dart`,
`android/key.properties`, `*.jks` sind gitignored — das so lassen.

---

## 5. Schnell-Checkliste für den Kollegen

- [ ] `flutter pub get`
- [ ] `cp lib/config/secrets.example.dart lib/config/secrets.dart` + 3 Werte rein
- [ ] `flutter run` → App startet, Login, Routensuche liefert eine Route
- [ ] (optional) `supabase login` — nur für Edge-Deploys
- [ ] (optional) Tailscale-Einladung annehmen — nur für direkten GraphHopper-Zugang

Wenn die Routensuche eine Route liefert, ist alles Nötige integriert. 🎉
