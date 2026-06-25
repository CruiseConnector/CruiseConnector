# Cruise Connector — Secrets-Checkliste für den Kollegen

> **Diese Datei enthält KEINE echten Werte — nur die Namen, Orte und „wo bekomme ich das her".**
> Die echten Werte schickst du (Vucko) ihm **separat über einen sicheren Kanal**
> (Passwort-Manager / verschlüsselt — NIE per normaler Mail/WhatsApp im Klartext).
> Alles unten ist `gitignored` und liegt **nicht** im Repo.

---

## 1) Flutter-App — `lib/config/secrets.dart`
Vorlage liegt schon im Repo: `lib/config/secrets.example.dart`.
Der Kollege macht: `cp lib/config/secrets.example.dart lib/config/secrets.dart` und trägt ein:

| Key | Was | Wo herbekommen |
|-----|-----|----------------|
| `supabaseUrl` | Supabase Projekt-URL (`https://<ref>.supabase.co`) | Supabase Dashboard → Project Settings → API → Project URL |
| `supabaseAnonKey` | Supabase **anon** Key (öffentlich, RLS-geschützt) | Supabase Dashboard → Project Settings → API → `anon` `public` |
| `googleWebClientId` | Google OAuth **Web** Client-ID (öffentlich) | Google Cloud Console → APIs & Services → Credentials |
| `googleIosClientId` | Google OAuth **iOS** Client-ID (öffentlich) | Google Cloud Console → Credentials → iOS-Client |

> Supabase-Projekt-Ref: **tlcfaxvvqzobmzwvfnvb** (CruiseConnector).

## 2) Firebase / Push — native Config-Dateien (gitignored)
Diese beiden Dateien musst du dem Kollegen direkt geben (oder er holt sie aus der Firebase-Console):

| Datei | Plattform | Wo herbekommen |
|-------|-----------|----------------|
| `android/app/google-services.json` | Android Push (FCM) | Firebase Console → Projekt → Android-App → google-services.json |
| `ios/Runner/GoogleService-Info.plist` | iOS Push (FCM/APNs) | Firebase Console → Projekt → iOS-App → GoogleService-Info.plist |
| **APNs-Auth-Key** `AuthKey_XXXX.p8` | iOS Push-Zertifikat | Apple Developer → Keys → Apple Push Notifications (.p8). In Firebase Console → Cloud Messaging → APNs hochladen. |

> Bundle-ID iOS/Android: **com.vucko.cruiserconnect** (muss in Firebase exakt so heißen).

## 3) Android Release-Signing — `android/key.properties` (gitignored)
Für signierte Release-Builds / Play Store. Datei + Keystore separat schicken:

| Eintrag | Was |
|---------|-----|
| `storeFile` | Pfad zur `.jks`/`.keystore`-Datei (Keystore selbst MIT schicken) |
| `storePassword` | Keystore-Passwort |
| `keyAlias` | Key-Alias |
| `keyPassword` | Key-Passwort |

> Ohne diese Datei kann der Kollege nur **Debug** bauen (zum Entwickeln reicht das).
> Für eigene Test-Geräte genügt `flutter build apk --release` mit Debug-Signing? Nein —
> Release braucht den Keystore. Zum reinen Entwickeln/Testen: `flutter run` (Debug).

## 4) Supabase Edge-Function-Secrets (Backend)
Werden NICHT im Code gesetzt, sondern per `supabase secrets set KEY=...` (oder Dashboard →
Edge Functions → Secrets). Diese Env-Variablen nutzen die Functions:

| Env-Variable | Zweck |
|--------------|-------|
| `SUPABASE_URL` | Projekt-URL (serverseitig) |
| `SUPABASE_ANON_KEY` | Anon Key |
| `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` / `CRUISERCONNECT_SERVICE_ROLE_KEY` | **Service-Role-Key (GEHEIM, Admin!)** — Supabase Dashboard → API → `service_role` |
| `GRAPHHOPPER_URL`, `GRAPHHOPPER_DE_URL`, `GRAPHHOPPER_EU_URL` | Endpunkte der selbst-gehosteten GraphHopper-Server (Mini-PCs) |
| `GEOCODER_PROVIDER`, `GEOCODER_KIND`, `GEOCODER_BASE_URL`, `NOMINATIM_URL`, `PHOTON_URL` | Adress-Suche (A→B) — Geocoder-Konfiguration |
| `FCM_SERVICE_ACCOUNT` | Firebase Service-Account-JSON für Server-Push (GEHEIM) |
| `PUSH_WEBHOOK_SECRET` | Schutz des Push-Webhooks (GEHEIM) |
| `ROUTE_POOL_CURATION_CRON_SECRET`, `ROUTE_POOL_HEALING_CRON_SECRET` | Schutz der Cron-Worker (GEHEIM) |
| `DEBUG_LOG` | optionaler Debug-Schalter |

## 5) Infrastruktur-Zugänge (nicht im Repo)
| Dienst | Was der Kollege braucht |
|--------|--------------------------|
| **Supabase** | Einladung als Projekt-Mitglied **oder** Personal Access Token (für `supabase` CLI). Project-Ref `tlcfaxvvqzobmzwvfnvb`. |
| **GraphHopper (2 Mini-PCs)** | Host/IP + Port der beiden Server (DE/EU) + ggf. Zugangsdaten. Routing läuft darüber. |
| **Cloudflare R2** (Karten-Tiles `tiles.cruiseconnector.at` / `eu.pmtiles`) | Account-ID, R2 Access-Key-ID + Secret, Bucket-Name — nur falls er Tiles ändern/hochladen will. |
| **Apple Developer** | Team-Einladung (für iOS-Signing/Provisioning/TestFlight) + APNs `.p8`. |
| **Firebase Console** | Projekt-Zugriff (für Push-Config + APNs-Key). |
| **Google Play Console** | Zugriff, falls er Android veröffentlichen soll. |

---

### So schickst du es ihm sicher
1. **Diese Datei** (Namen/Anleitung) kann ganz normal geteilt werden — keine Geheimnisse drin.
2. Die **echten Werte** dazu: über Passwort-Manager (1Password/Bitwarden „Sicher teilen"),
   verschlüsseltes Archiv, oder direkt im Supabase/Firebase/Apple-Team **einladen** (dann
   braucht er die Keys gar nicht im Klartext).
3. **Service-Role-Key, FCM-Service-Account, Cron-Secrets, Keystore-Passwörter** sind die
   wirklich kritischen — niemals im Klartext in Chat/Mail.
