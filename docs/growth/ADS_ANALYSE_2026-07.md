# Werbung in CruiseConnect — Komplette Analyse & Umsetzungsplan

**Stand:** 19.07.2026 · **Research:** 3 Sonnet-5-Agenten (`ads-ux-formats`, `accounts-websites`, `branch-analyse`) · **Bericht/Umsetzung:** Fable 5
**Branch:** `growth/monetization-ads-notifications` (rebased auf origin/main `2c79723`, 4 Commits voraus, **nichts nach main gemergt** — Merge erst ab August)

---

## 1. Was bereits GEBAUT und LIVE ist (ohne Drittanbieter)

### House-Ads-System (Eigen-/Direktvermarktung)
Der wirtschaftlich beste erste Hebel für eine deutschsprachige Auto-Nische
(Research: Direktdeals erzielen **40–60 % höhere effektive CPMs** als
programmatische Restplatz-Vermarktung, kein Nutzerdaten-Abfluss, kein
Policy-Risiko, kein Consent-Overhead).

| Baustein | Ort | Status |
|---|---|---|
| Tabelle `house_ads` (Bild, Headline, CTA, Ziel-URL, Zeitfenster, Gewicht, Zähler) | Supabase, Migration `house_ads_first_party` | ✅ live |
| RLS: Clients lesen nur aktive Kampagnen; Zählung über SECURITY-DEFINER-RPC `house_ad_track` | Supabase | ✅ live |
| Bild-Hosting auf eigenem CDN | `tiles.cruiseconnector.at/ads/` (R2, Upload via rclone) | ✅ 2 Bilder live |
| `HouseAdService` (Laden, gewichtete Rotation, Impression-/Klick-Tracking) | `lib/data/services/house_ad_service.dart` | ✅ Commit `9a70d6a` |
| Bild-Werbekarte im Entdecken-Feed (ANZEIGE-Badge = Kennzeichnungspflicht DE/AT, CTA-Button, externer Link) | `community_page.dart` `_buildDiscoverAdCard()` | ✅ Commit `9a70d6a` |
| Sichtbarkeits-Garantie bei dünnem Feed (genau 1 Anzeige ans Ende, wenn Rotation nicht griff) | `community_page.dart` `_buildDiscoverTab()` | ✅ |
| 2 Demo-Kampagnen (Premium-Teaser ×2 Gewicht, „Dein Logo hier?" ×1) | `house_ads`-Tabelle | ✅ geseedet |
| Branch-APK 1.5.1+79 | auf Vuckos Samsung installiert | ✅ |

**Kampagnen-Verwaltung ohne App-Release:** Bild nach `r2:cruise-tiles/ads/`
hochladen → Zeile in `house_ads` einfügen (image_url, headline, cta_label,
target_url, weight, optional starts_at/ends_at) → erscheint beim nächsten
Feed-Laden. Deaktivieren: `active=false`. Erfolg messen: Spalten
`impressions`/`clicks`.

### Community-Sichtbarkeits-Toggle (separater Auftrag, im Haupt-Checkout)
Nur der **Owner** kann eine Community nachträglich privat ↔ öffentlich
schalten: `CommunityChatService.setCommunityVisibility()` (ehrlicher Fehler
bei RLS-Block statt stillem Fehlschlag) + ⋯-Menüpunkt „Öffentlich machen" /
„Auf privat stellen" in der Detail-Seite (optimistisch mit Revert,
Erklärungs-Snackbar). `flutter analyze` sauber.

---

## 2. Sonnet-Research: Wie Werbung am besten einbauen

### Formate & Frequenz (geplante Werte validiert)
- **Native im Entdecken-Feed alle ~6 Posts** ✅ (üblicher Korridor 1 pro 4–8 Items; später A/B 5 vs. 8)
- **Interstitial nach Routensuche, max. alle 5 Min** ✅ (Standard 1–3/Session, 3–5 Min Abstand; IMMER vorladen)
- **App-Open-Ad**: NUR in echter Lade-/Splash-Phase, nie nach sichtbarem Content, nicht beim allerersten App-Start (Google-Guidance — sonst Play-Policy-Verstoß)
- **Rewarded** (Empfehlung als Ergänzung): Opt-in („24 h werbefrei" / „Extra-Neusuche"), störungsfrei, höchste eCPMs
- **Google Play „Better Ads"-Policy (seit 09/2022):** Vollbild-Ads, die mitten in einer Aktivität unterbrechen, sind verboten — nur an echten Übergangspunkten. Verstoß = App-Ablehnung/Deaktivierung.

### Fahr-Kontext (wichtig für uns)
- Googles „Driver Distraction Guidelines" gelten NUR für Android-Auto-/Automotive-Oberflächen, **nicht** für Handy-Apps — unsere Regel **„niemals Werbung während der Navigation"** ist rechtlich nicht erzwungen, bleibt aber aus Sicherheits-/Haftungs-/Vertrauensgründen fix.
- Waze-Referenzmuster, falls je Ads in Fahrnähe: „Zero-Speed Takeover" (nur bei Stillstand, +3 s Wartezeit, weg beim Anfahren).
- CarPlay/Android Auto können technisch **keine** Ads rendern (nur feste Templates) — Monetarisierung bleibt auf Handy-Screens.

### Pflichten VOR der ersten AdMob-Anzeige (DACH)
1. **UMP/TCF-Consent** (seit 16.01.2024 EWR/UK, 31.07.2024 CH): Google-zertifizierte CMP zwingend, sonst nur „Limited Ads" (massiv weniger Umsatz). Einrichtung: AdMob → Privacy & messaging → „European regulations message" (kostenlos, kein Dritt-CMP nötig); `google_mobile_ads` bringt UMP-Support mit.
2. **iOS ATT**: `NSUserTrackingUsageDescription` in Info.plist (sonst Crash beim Request) + `SKAdNetworkItems` (Google-Liste); ATT-Antwort VOR erstem Ad-Load abwarten. SDK ≥ 11.2.0 (Privacy Manifest `PrivacyInfo.xcprivacy`).
3. **Play Console**: App content → „Ads" deklarieren (führt zum „Enthält Werbung"-Label) + Data Safety (Werbe-ID) — Falschangabe = Suspendierungsrisiko.
4. **App Store Connect**: Privacy Nutrition Labels — „Data Used to Track You" / „Third-Party Advertising".

### Realistische Umsatz-Erwartung (ehrlich)
- eCPM DACH: Banner 0,5–1,5 $, **Native ~3,3 $**, Interstitial 5–8 $, Rewarded hoch einstellig bis niedrig zweistellig
- Spürbarer Umsatz (>1.000 $/Monat) beginnt erst ab **~10.000+ DAU**; unter 1.000 DAU schwanken Fill-Rates 70–98 %
- Für CruiseConnect (<5k DAU) bedeutet AdMob im August: **niedrig- bis mittel-dreistellige €/Monat** — Lern-/Validierungsschritt, kein Umsatz-Hebel
- **Darum: House-Ads/Direktdeals first** (dieses Dokument, Abschnitt 1), AdMob ergänzend; Mediation (AppLovin MAX etc.) erst ab ~5.000 DAU sinnvoll

---

## 3. Welche Webseiten/Konten wir brauchen (Schritt-für-Schritt)

### A. AdMob (admob.google.com)
1. Konto mit Google-Account anlegen; **Zahlungsdaten sofort hinterlegen** (ohne Verifizierung keine Ad-Auslieferung); Zahlungsart SEPA; Steuerinfo i. d. R. **W-8BEN** (DBA AT–USA vom Steuerberater bestätigen lassen); Auszahlung ab ~100 $-Äquivalent, vorher Identitäts-/Adress-Verifizierung (PIN-Brief).
2. Apps → Add app → **beide Apps** anlegen und **mit dem Store-Eintrag verlinken** (Pflicht für „published"-Status).
3. Ad-Units anlegen (Native fürs Feed, Interstitial, App-Open, Rewarded) → IDs per `--dart-define` in `monetization_config.dart` (Struktur existiert auf diesem Branch; Google-Test-IDs sind Default).
4. Privacy & messaging → **European regulations message** aktivieren (= UMP-Consent, Pflicht).
5. Max. Ad-Content-Rating passend zum App-Rating setzen.

### B. app-ads.txt auf cruiseconnector.at (seit 2025 faktisch PFLICHT)
1. Website in **beiden** Store-Einträgen hinterlegen: Play Console (Store-Einstellungen → Kontaktdaten → Website) und App Store Connect (Marketing-URL). **24 h warten.**
2. Datei **exakt** unter `https://cruiseconnector.at/app-ads.txt` (Root, kein Unterordner; Cloudflare-Site → einfach als statische Datei deployen). Inhalt (eine Zeile, echte Publisher-ID aus AdMob → Apps → View all apps → app-ads.txt → „How to set up"):
   ```
   google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
   ```
3. **24 h warten** (AdMob-Crawl) → in AdMob die Verifizierung **manuell anstoßen** (passiert nicht automatisch).

### C. RevenueCat (app.revenuecat.com) — Abo-Modell
1. Projekt anlegen, iOS- + Android-App hinzufügen (Bundle-ID/Package).
2. **App Store Connect**: Nutzer und Zugriff → Integrationen → In-App-Purchase → **In-App-Purchase-Key (.p8)** generieren (**nur 1× herunterladbar!**) + Issuer-ID → in RevenueCat hinterlegen.
3. **Play Console**: Abos lassen sich erst NACH einem Build-Upload auf irgendeinen Track anlegen → dann `basic_monthly` + `premium_monthly`; Service-Account-JSON (Play Developer API) für RevenueCat.
4. Entitlements **exakt** `basic` und `premium`, Offering `default` (die Paywall dieses Branches — `subscription_tier_page.dart` — erwartet genau diese IDs; ohne Keys läuft sie im Vorschaumodus).
5. Keys per `--dart-define=REVENUECAT_IOS_KEY=… / REVENUECAT_ANDROID_KEY=…`.

### D. Ablauf-Empfehlung bis August
1. **Jetzt:** House-Ads laufen lassen, erste Direktdeal-Gespräche (Reifen/Zubehör/Versicherung der Szene) — Werbekarten dafür existieren schon
2. **≥ 2 Wochen vor Launch:** AdMob-Konto + app-ads.txt (24-h-Fristen!), RevenueCat + Store-Produkte
3. **Launch August:** UMP-Consent + ATT einbauen (Branch), AdMob-Native in denselben Entdecken-Slot mischen, SubscriptionProvider-Gating (Free sieht Ads, Basic/Premium nicht)

---

## 4. Branch-Zustand (Beleg)

```
fd85a62 chore(growth): Version 1.5.1+79 (über Store-78 installierbar)
9a70d6a feat(ads): House-Ads mit Bildern im Entdecken-Feed — ohne Drittanbieter
9214971 Revert "revert(monetization): Abo- + Werbesystem aus main entfernen"
452e873 feat(growth): Android-13+ POST_NOTIFICATIONS-Laufzeitdialog + Growth-Plan
2c79723 (origin/main) fix(onboarding): …
```
- hinter origin/main: **0** · vor origin/main: **4** · nichts nach main gemergt
- Juni-WIP gesichert als `growth/wip-backup-2026-06-polish`
- `flutter analyze lib/`: 0 Issues
