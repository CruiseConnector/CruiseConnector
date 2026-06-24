# Growth-Branch — Monetarisierung, Ads, Notifications, Monitoring

> Branch: `growth/monetization-ads-notifications`
> Zweck: ein **eigener, dauerhaft vom `main` getrackter** Branch, auf dem alles
> rund um Geldverdienen + Infrastruktur getestet wird, **bevor** es in `main`
> landet. Modell wie der CarPlay-Branch.

---

## 1. Branch immer aktuell halten (Sync vom main-Stand)

Wie beim CarPlay-Branch wird **per REBASE** auf `main` synchronisiert — NICHT
`git merge main` (das verwässert die Historie und macht spätere Rebases kaputt).

```bash
# auf dem Growth-Branch:
git fetch origin
git rebase origin/main
# Konflikte lösen, dann:
git push --force-with-lease
```

Faustregel: **vor jeder Arbeitssitzung** kurz `git fetch && git rebase origin/main`,
damit der Kollege-Stand mitkommt (er pusht regelmäßig auf `origin/main`).

---

## 2. Android-Notifications — Live-Diagnose (2026-06-24)

**Wichtigste Erkenntnis:** Die Push-Pipeline ist NICHT leer — sie ist fast
vollständig korrekt gebaut. Belegt mit Live-Daten aus dem App-Projekt
`tlcfaxvvqzobmzwvfnvb`:

| Schicht | Status | Beleg |
|---|---|---|
| Android FCM-Token | ✅ | `user_device_tokens`: 3 android, zuletzt heute 14:54 |
| Notification-Erzeugung | ✅ | `notifications`: weather 702×, follow 6×, group_* 40× |
| `send-push` FCM-Nachricht | ✅ | enthält `notification`-Block + `android.notification.channel_id=cruise_default` |
| AndroidManifest | ✅ | `POST_NOTIFICATIONS` + `default_notification_channel_id` deklariert |
| Client-Channel/Handler | ✅ | `cruise_default` erstellt, Foreground-Handler verkabelt |

### Gefundene Lücken / Maßnahmen

1. **(behoben in diesem Branch) Android 13+ `POST_NOTIFICATIONS`-Laufzeitdialog**
   wurde nicht explizit erzwungen. `FirebaseMessaging.requestPermission()` löst
   ihn je nach Plugin-Version nicht zuverlässig aus → OS unterdrückt sonst ALLE
   Notifications still (Token da, Server schickt, nichts erscheint = exakt das
   Symptom). Fix: zusätzlich `AndroidFlutterLocalNotificationsPlugin
   .requestNotificationsPermission()` in `push_notification_service.dart`.

2. **(offen, operativ) Feuert der DB-Trigger `trg_notify_push_on_notification`
   wirklich `send-push`?** In `net._http_response` (7 Tage) tauchten nur die
   Routen-Crons auf, kein `send-push` — aber pg_net **löscht Antworten nach
   Stunden**, daher nicht eindeutig. **Definitiver Test:** eine Test-Notification
   auf das eigene Konto inserten und das `send-push`-Log live beobachten (Push
   muss in Sekunden am Handy ankommen). Erst dann ist klar, ob noch ein
   Backend-Fix nötig ist (z. B. Secret `PUSH_WEBHOOK_SECRET` / `FCM_SERVICE_ACCOUNT`).

3. **(offen, Politur) Eigenes Notifications-Small-Icon.** Ohne
   `com.google.firebase.messaging.default_notification_icon` nimmt Android das
   bunte App-Icon → kann als weißes Quadrat in der Statusleiste erscheinen
   (Notification kommt trotzdem). Monochromes Icon nachliefern.

4. **(offen, geräteabhängig) Samsung-Akku-Optimierung.** Samsung drosselt FCM im
   Hintergrund aggressiv. Ggf. Nutzer-Hinweis „App von Akku-Optimierung ausnehmen".

---

## 3. Ads — „Werbung schalten" richtig verstehen

**Wichtige Klarstellung — zwei völlig verschiedene Dinge:**

- **Apple Search Ads / Google Ads (App-Kampagnen)** = du ZAHLST, um neue Nutzer
  zu gewinnen (deine App erscheint im Store/Such-Ergebnis). Das ist **Marketing-
  Ausgabe**, kein Einkommen.
- **Werbung IN der App, um Geld zu verdienen** = du brauchst ein **Ad-Network-SDK**.
  **Apple hat KEIN In-App-Werbenetzwerk.** Die relevanten Netzwerke sind:
  **Google AdMob** (für Flutter Standard, offizielles `google_mobile_ads`-Paket),
  Meta Audience Network, Unity Ads, AppLovin MAX (Mediation), ironSource.

### Empfehlung
- **Start: Google AdMob** (`google_mobile_ads`). Ein SDK, beide Plattformen,
  beste Flutter-Unterstützung.
- **Später (Skalierung):** AppLovin MAX als Mediation drüber, um Fill-Rate/eCPM
  zu maximieren.

### Was DU einrichten musst (kann ich nicht für dich anlegen — Account/Zahlung)
1. AdMob-Konto erstellen, App registrieren (`com.vucko.cruiserconnect`, iOS+Android).
2. Ad-Units anlegen: **Rewarded Video** (für das Such-Limit-Gate), **Banner**
   (Home/Community), **Interstitial** (nach Fahrtende).
3. App-ID + Ad-Unit-IDs notieren.

### Was ICH dann im Code mache
- `google_mobile_ads` ins `pubspec`, `GADApplicationIdentifier` in `Info.plist` +
  `applicationId`-Meta in `AndroidManifest`, `SKAdNetworkItems` (iOS).
- Ad-Platzierungen nach dem Monetarisierungsplan (Rewarded vor 4./5. Suche,
  Banner, Interstitial) — **niemals während aktiver Navigation** (Sicherheit).
- **Pflicht in DACH/EU: Consent (UMP SDK).** Vor personalisierter Werbung muss ein
  GDPR-Consent-Dialog (Googles User Messaging Platform) gezeigt werden, auf iOS
  zusätzlich App Tracking Transparency (ATT). Rechtlich erforderlich.

---

## 4. Premium / Subscription — Bestand & Lücken

**Gute Nachricht:** `route_service.dart` hat **schon** eine Tier-Logik
(`free/basic/premium`, `_isFreeTier()`, `_isBasicTier()`,
`lastRouteSubscriptionTier`), aktuell hart auf `'premium'`. Der Routing-Layer
versteht Tiers also bereits. Es fehlt nur die **User-Ebene**:

1. `profiles.tier` (oder `is_premium` + Ablaufdatum) als Source-of-Truth in der DB.
2. **IAP-SDK** — Empfehlung **RevenueCat (`purchases_flutter`)**: kapselt App
   Store + Play Billing, Trials, „Founder Lifetime", Webhook → setzt `profiles.tier`.
   (Digitale Abos MÜSSEN über Apple/Google-Billing laufen — Stripe ist für den
   In-App-Unlock auf iOS nicht erlaubt.)
3. Feature-Gates client-seitig an `tier` hängen (Wochen-Such-Counter, Rundkurs-
   Tiefe, Speichern, Teilen, Gruppe erstellen …) — siehe Monetarisierungsplan.

---

## 5. Monitoring — Empfehlung

| Zweck | Tool | Warum |
|---|---|---|
| **App-Crashes (inkl. native SIGABRT)** | **Firebase Crashlytics** | Gratis/unbegrenzt, schon im Firebase-Projekt, fängt genau die nativen MapLibre-Crashes der Vergangenheit |
| **Reiche Dart-Fehler + Performance-Traces** | Sentry (`sentry_flutter`) | Optional zusätzlich; Breadcrumbs, Release-Health, Tracing |
| **Produkt-Analytics + Funnels + Feature-Flags** | **PostHog** | Großzügiger Free-Tier; Funnels (Conversion!), Session-Replay, Feature-Flags können direkt das Paywall-/Gate-Flag liefern |
| **Heimserver/GraphHopper-Uptime** | UptimeRobot | Gratis; pingt den Routing-Endpoint, alarmiert bei Ausfall |
| **Supabase** | eingebaute Logs + Advisors | bereits vorhanden (genutzt für diese Diagnose) |

**Start-Stack (minimal, fast alles gratis):** Crashlytics (Crashes) + PostHog
(Funnels/Flags) + UptimeRobot (Heimserver). Sentry später bei Bedarf.

---

## 6. Reihenfolge (Vorschlag)

1. Android-Notification-Permission-Fix verifizieren (Live-Test + Geräte-Build). ← **jetzt**
2. Monitoring einbauen (Crashlytics zuerst — billig, sofort Nutzen).
3. Premium-Gerüst: `profiles.tier` + RevenueCat + Feature-Gates (nach deinem Go).
4. AdMob einbauen, sobald du Konto + Ad-Unit-IDs hast (inkl. UMP-Consent).
