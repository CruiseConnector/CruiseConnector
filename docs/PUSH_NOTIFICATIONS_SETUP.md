# Push-Notifications — Setup & Aktivierung

> Echte Handy-Push (auch wenn die App geschlossen ist) für **alle**
> Notification-Typen: Likes, Kommentare, Reposts, Follows, Freundschafts-
> anfragen, Gruppen-Events, tägliche Wetter-Empfehlung.

## Architektur (max. in Supabase, Firebase nur als Zustellrohr)

```
Event (Like/Comment/Repost/Weather/…)
   └─► INSERT in public.notifications        ← bestehende DB-Trigger + daily-weather-push
        └─► AFTER-INSERT-Trigger trg_notify_push_on_notification (pg_net)
             └─► Edge-Function  send-push
                  ├─ lädt user_device_tokens des Empfängers
                  ├─ rendert (title, body) serverseitig
                  └─ FCM HTTP v1  ─►  Android (FCM)  /  iOS (APNs)  ─►  Gerät
```

* **Daten/Auth bleiben zu 100 % in Supabase.** Firebase/FCM ist ausschließlich
  der Auslieferungskanal (auf iOS zwingend via APNs).
* Der Code ist **scharf, aber inaktiv**, bis die Secrets unten gesetzt sind:
  ohne `push_webhook_secret` ist der DB-Trigger ein No-op; ohne
  `FCM_SERVICE_ACCOUNT` antwortet die Function mit `skipped`.

---

## Was der Code bereits mitbringt (erledigt)

| Bereich | Datei |
|---|---|
| Token-Tabelle + RLS + `register_device_token()` RPC + Fanout-Trigger | `supabase/migrations/20260531120000_push_device_tokens_and_webhook.sql` |
| Versand-Function (FCM HTTP v1, JWT-Signing, tote Tokens aufräumen) | `supabase/functions/send-push/index.ts` |
| `verify_jwt = false` für send-push | `supabase/config.toml` |
| Flutter Push-Service (Permission, Token, Foreground-Notif, Deep-Link-Hook) | `lib/data/services/push_notification_service.dart` |
| Firebase-Optionen (Android/iOS) | `lib/firebase_options.dart` |
| Firebase-Init beim Start | `lib/main.dart` |
| Token-Registrierung nach Login | `lib/presentation/pages/home_page.dart` |
| Android FCM-Default-Channel | `android/app/src/main/AndroidManifest.xml` |
| iOS Background-Mode + Push-Entitlement | `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements` |

---

## Externe Schritte — NUR DU (ich habe keinen Zugriff auf Firebase Console / Secrets)

### 1. Firebase Service-Account-Key holen
Firebase Console → Projekt **cruise-connect-a1772** → ⚙️ Projekteinstellungen →
**Dienstkonten** → *Neuen privaten Schlüssel generieren* → JSON herunterladen.
→ Das ist ein **Secret**. Nicht committen, nicht teilen.

### 2. Secrets setzen (zwei Stellen, gleicher Webhook-Wert)

**a) Supabase Edge-Function-Secrets** (Runtime der Function):
```bash
# Service-Account-JSON (einzeilig als String)
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/Downloads/cruise-connect-a1772-xxxx.json)"
# Frei wählbares, langes Zufalls-Secret für die Webhook-Auth
supabase secrets set PUSH_WEBHOOK_SECRET="<lange-zufalls-zeichenkette>"
```

**b) Supabase Vault** (damit der DB-Trigger den Webhook aufrufen darf) — im
SQL-Editor / `supabase db query`:
```sql
-- GLEICHER Wert wie PUSH_WEBHOOK_SECRET oben:
select vault.create_secret('<lange-zufalls-zeichenkette>', 'push_webhook_secret');
-- route_pool_healing_project_url existiert bereits (von den Cron-Workern) und
-- wird als Basis-URL wiederverwendet. Falls nicht:
-- select vault.create_secret('https://tlcfaxvvqzobmzwvfnvb.supabase.co', 'route_pool_healing_project_url');
```

### 3. Migration anwenden + Function deployen
```bash
supabase db push                       # legt user_device_tokens + Trigger an
supabase functions deploy send-push    # verify_jwt=false steht in config.toml
```

### 4. Client bauen
```bash
flutter pub get
cd ios && pod install && cd ..         # nur iOS / macOS-Build
```

### 5. iOS zusätzlich (für APNs)
* **Apple Developer → Certificates, IDs & Profiles → Keys** → APNs-Auth-Key
  (`.p8`) erstellen (Key-ID + Team-ID notieren).
* **Firebase Console → Cloud Messaging → Apple-App** → APNs-Auth-Key hochladen.
* **Xcode → Runner → Signing & Capabilities** → *Push Notifications* +
  *Background Modes → Remote notifications* aktivieren.
* ⚠️ **Bundle-ID prüfen:** `ios/Runner/GoogleService-Info.plist` enthält aktuell
  den Platzhalter `com.example.cruiseConnect`. Stimmt das nicht mit der echten
  iOS-Bundle-ID überein, in der Firebase Console eine iOS-App mit der korrekten
  Bundle-ID anlegen, neue `GoogleService-Info.plist` ziehen und die `ios`-Werte
  in `lib/firebase_options.dart` aktualisieren.

---

## Test
1. App auf einem **echten Gerät** (Push läuft nicht im iOS-Simulator) starten,
   einloggen → beim ersten Start kommt die Notification-Permission-Abfrage.
2. Gegencheck: in `user_device_tokens` sollte jetzt eine Zeile mit deinem Token stehen.
3. Auslösen, z. B.:
   * jemand liked/kommentiert deinen Post, **oder**
   * Wetter-Push manuell: `supabase functions invoke daily-weather-push`
4. App in den Hintergrund → die Push sollte als System-Pop-up erscheinen.

---

## Bekannte Grenzen (bewusst, fürs MVP)
* **Server-seitige Pro-Typ-Stummschaltung fehlt noch.** Die Switches in den
  App-Settings filtern aktuell nur den *In-App-Toast*; eine echte Push geht für
  alle Typen raus. Wenn du einzelne Typen vom Handy-Push ausnehmen willst,
  braucht es eine `user_notification_prefs`-Tabelle, die `send-push` vor dem
  Versand prüft (klein, kann ich nachziehen).
* **Like-Aggregation:** Der Webhook feuert bei `INSERT`. Beim ersten Like im
  10-Minuten-Fenster kommt eine Push; weitere Likes werden in-app aggregiert,
  lösen aber keinen erneuten Push aus (bewusst — kein Spam).
* **Deep-Link bei Push-Tap:** Hook ist vorhanden (`_handleTapData`), das Routing
  zu Post/Profil/Gruppe ist noch ein TODO (analog zum bestehenden App-Links-Flow).
