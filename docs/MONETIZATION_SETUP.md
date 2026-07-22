# Monetarisierung — Setup & Hand-off (Free / Basic / Premium + Werbung)

Stand 2026-07-10. Das **App-seitige System** ist gebaut (Abo-Tiers, Gating, Paywall).
Was hier steht, sind die Schritte, die **nur Vucko** in seinen Entwickler-Accounts
erledigen kann (Accounts kann ich nicht anlegen). Danach läuft alles scharf.

## Tier-Matrix (implementiert)
| Feature | Free | Basic | Premium |
|---|---|---|---|
| Routen generieren & cruisen | ✅ | ✅ | ✅ |
| Rangliste & Badges | ✅ | ✅ | ✅ |
| Community & Gruppen | ✅ | ✅ | ✅ |
| **Eigene Fahr-Statistiken** (km/Zeit/XP/Charts) | 🔒 | ✅ | ✅ |
| **Werbung** | zeigt Ads | keine | keine |
| Alle Premium-Extras | – | – | ✅ |

Quelle der Wahrheit: `SubscriptionProvider` (lib/application/providers/) →
RevenueCat customerInfo, Fallback DB `get_my_entitlement` (profiles.subscription_tier).
Capabilities: `showsAds`, `canSeeDrivingStats`. Paywall: `SubscriptionTierPage`.

## 1. RevenueCat (Abos)
1. Kostenlosen Account auf revenuecat.com anlegen, App verknüpfen (iOS + Android).
2. In App Store Connect + Play Console je **zwei** Auto-Renew-Abos anlegen:
   `basic_monthly`, `premium_monthly` (Preise legst du dort fest → Paywall zeigt sie automatisch).
3. In RevenueCat zwei **Entitlements** anlegen mit exakt diesen IDs: `basic`, `premium`
   (so heißen sie im Code: `MonetizationConfig.entitlementBasic/Premium`).
4. Ein **Offering** „default" mit den Paketen, deren Identifier `basic` bzw. `premium` enthalten
   (die Paywall matcht per Namens-Heuristik).
5. RevenueCat-**API-Keys** kopieren und beim Build setzen:
   `--dart-define=REVENUECAT_IOS_KEY=... --dart-define=REVENUECAT_ANDROID_KEY=...`
   (ohne Key läuft die Paywall im Vorschaumodus, Kauf deaktiviert).
6. RevenueCat-**Webhook** → schreibt in die `subscriptions`-Tabelle (Supabase), damit Server-Tier
   + Monitoring-Abo-Fenster sich füllen. (Edge-Function-Scaffold folgt; bis dahin trägt der
   DB-Trigger `subscriptions.plan → profiles.subscription_tier` das Entitlement nach.)

## 2. AdMob (Werbung)  ⚠️ noch NICHT im nativen Build aktiv
Die Ad-Placements sind vorbereitet (Test-Ad-IDs als Default). Zum Scharfschalten:
1. AdMob-Account anlegen, App (iOS + Android) registrieren → **App-IDs** bekommen.
2. Native Config eintragen (Test-App-ID reicht für Entwicklung):
   - Android `AndroidManifest.xml`: `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-…~…"/>`
   - iOS `Info.plist`: `GADApplicationIdentifier` + `SKAdNetworkItems`.
3. Ad-Units anlegen (App-Open, Interstitial, Rewarded, Native, Banner) → IDs per
   `--dart-define` setzen (siehe `MonetizationConfig`), sonst laufen die Google-Test-Ads.
4. **App-Tracking-Transparency** (iOS) + Datenschutz-Labels im Store deklarieren (Pflicht bei Ads).

### Geplante Placements (Free-Tier only)
- App-Start: App-Open-Ad (vorgeladen, keine Wartezeit).
- Community-/Gruppen-Feed: Native-Ad im Post-Format alle ~6 Posts.
- Home & Analytics: nicht-interaktives Ad-Widget.
- **Gruppen-Beitritt**: Rewarded-Video (Mittelweg-Entscheidung).
- **Routensuche**: kurzes Interstitial, gedrosselt (max. alle 5 min) — NICHT während der Navigation (AdMob-Policy + Sicherheit).

## 3. Vor Release
- `flutter pub get` ist erfolgt (RevenueCat + AdMob als Dependencies drin).
- **Device-Build + Test steht noch aus** (native Pods/Gradle der neuen SDKs).
- Store-Metadaten: Abo-Beschreibung, Datenschutz, ATT — sonst Ablehnung.

## Update 2026-07-22 — AdMob KOMPLETT eingerichtet (Dashboard + App)

**Dashboard fertig:** iOS- + Android-App angelegt, 10 Anzeigenblöcke erstellt,
DSGVO-Consent-Meldung „CruiseConnect DSGVO" (UMP) für beide Apps VERÖFFENTLICHT
(EN+DE, Nicht-einwilligen-Button aus, Ablehnen via „Optionen verwalten").
app-ads.txt liegt korrekt auf cruiseconnector.at (apex+www, 200, text/plain) —
Neu-Crawl angestoßen; „Anzeigenbereitstellung begrenzt" verschwindet, sobald
Google die Datei bestätigt (bis 24h).

**Echte App-IDs sind bereits nativ eingetragen** (Info.plist/AndroidManifest —
echte App-ID + Google-TEST-Unit-IDs als Dart-Defaults = empfohlenes Dev-Setup).

**Für den Release-Build die echten Ad-Unit-IDs setzen:**

```
flutter build ipa --release \
  --dart-define=ADMOB_APPOPEN_IOS=ca-app-pub-2489939412353241/6412754277 \
  --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-2489939412353241/8314807544 \
  --dart-define=ADMOB_REWARDED_IOS=ca-app-pub-2489939412353241/2968333288 \
  --dart-define=ADMOB_NATIVE_IOS=ca-app-pub-2489939412353241/5824375577 \
  --dart-define=ADMOB_BANNER_IOS=ca-app-pub-2489939412353241/4277545526 \
  --dart-define=ADMOB_APPOPEN_ANDROID=ca-app-pub-2489939412353241/2685262250 \
  --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-2489939412353241/5219806111 \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-2489939412353241/1557827508 \
  --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-2489939412353241/7111472285 \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-2489939412353241/6624507267 \
  --dart-define=REVENUECAT_IOS_KEY=appl_wDKxupAHADKYKoJuKDZNhtQtHiP
```

**App-seitig eingebaut (AdService, nur Free-Tier, live Tier-Check):**
App-Open direkt nach App-Öffnen + bei Resume; Rewarded-Video (30-60s) vor
Fahrt-Start (Cooldown 15 min, blockiert NIE); Interstitials nach Neusuche,
bei Gruppen-Beitritt und ab >5 Seitenwechseln (je eigene Cooldowns + globaler
90s-Mindestabstand zwischen Vollbild-Ads); Native-Ads als Posts im Entdecken-
Feed (House-Ads haben Vorrang), im Freunde-Feed (alle 6 Posts, lazy) und als
kompaktes Widget unterm Home-Dashboard. KEINE Werbung während der Navigation.
UMP-Consent läuft automatisch beim ersten Home-Aufbau; NSUserTrackingUsage-
Description ist gesetzt (ATT-Review-Risiko beseitigt).
