#!/usr/bin/env bash
# 2026-07-25 (vucko „Werbung soll auch wirklich funktionieren, nicht nur in der
# Testversion"): Release-Builds MIT den echten AdMob-/RevenueCat-Schlüsseln.
#
# WARUM DIESES SCRIPT EXISTIERT
# monetization_config.dart liest alle IDs über String.fromEnvironment(...) und
# fällt ohne --dart-define auf Googles TEST-Ad-Units zurück. Ein schlichtes
# `flutter build apk --release` liefert deshalb eine App aus, die zwar Werbung
# ZEIGT, damit aber NULL verdient — und man sieht es der App nicht an (die
# Test-Anzeigen sehen aus wie echte, nur mit kleinem „Test mode"-Label).
# Genau das ist mehrfach passiert. Ab jetzt: Release NUR über dieses Script.
#
#   ./scripts/build_release.sh apk      → Android APK (Direktinstallation)
#   ./scripts/build_release.sh appbundle→ Play Store
#   ./scripts/build_release.sh ipa      → App Store
#   ./scripts/build_release.sh ios      → iOS ohne Archiv (Geräte-Install)
#
# EIGENE GERAETE ZUM TESTEN
# Ein Build mit echten Ad-Units auf dem EIGENEN Handy erzeugt echte Impressions.
# Google wertet das als ungueltigen Traffic (haeufigster Sperr-Grund ueberhaupt).
# Deshalb vor Geraete-Tests die Geraete-Hashes registrieren:
#
#   ADMOB_TEST_DEVICES="HASH1,HASH2" ./scripts/build_release.sh apk
#
# Den Hash gibt das SDK beim ersten Ad-Request selbst aus:
#   Android: adb logcat | grep -i "setTestDeviceIds"
#   iOS:     Xcode-Konsole nach "GADMobileAds.sharedInstance" durchsuchen
# Fuer den STORE-Build (ipa/appbundle) die Variable weglassen!
#
# Quelle der IDs: docs/MONETIZATION_SETUP.md (AdMob-Dashboard, Publisher
# pub-2489939412353241).
set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Verwendung: $0 {apk|appbundle|ipa|ios}" >&2
  exit 1
fi

# ── AdMob Ad-Unit-IDs (ECHT) ────────────────────────────────────────────────
ADMOB=(
  --dart-define=ADMOB_APPOPEN_IOS=ca-app-pub-2489939412353241/6412754277
  --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-2489939412353241/8314807544
  --dart-define=ADMOB_REWARDED_IOS=ca-app-pub-2489939412353241/2968333288
  --dart-define=ADMOB_NATIVE_IOS=ca-app-pub-2489939412353241/5824375577
  --dart-define=ADMOB_BANNER_IOS=ca-app-pub-2489939412353241/4277545526
  --dart-define=ADMOB_APPOPEN_ANDROID=ca-app-pub-2489939412353241/2685262250
  --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-2489939412353241/5219806111
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-2489939412353241/1557827508
  --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-2489939412353241/7111472285
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-2489939412353241/6624507267
)

# ── RevenueCat (Abos) ───────────────────────────────────────────────────────
# Ohne Key laeuft die Paywall im „Vorschau"-Modus: sichtbar, aber Kauf
# deaktiviert (purchasesConfigured == false).
REVENUECAT=(
  --dart-define=REVENUECAT_IOS_KEY=appl_wDKxupAHADKYKoJuKDZNhtQtHiP
)
# ACHTUNG Android: In RevenueCat existiert bislang KEINE Android-App, also gibt
# es noch keinen `goog_`-Key. Bis der angelegt ist, sind Abo-KAEUFE auf Android
# nicht moeglich (Werbung funktioniert unabhaengig davon). Sobald vorhanden hier
# ergaenzen:
#   --dart-define=REVENUECAT_ANDROID_KEY=goog_XXXXXXXX

# ── Testgeraete (optional, per Umgebungsvariable) ───────────────────────────
EXTRA=()
if [[ -n "${ADMOB_TEST_DEVICES:-}" ]]; then
  EXTRA+=(--dart-define=ADMOB_TEST_DEVICES="$ADMOB_TEST_DEVICES")
  echo "⚠  Testgeraete-Modus: $ADMOB_TEST_DEVICES"
  echo "   Dieser Build zeigt ECHTE Ad-Units, rechnet sie aber NICHT ab."
  if [[ "$TARGET" == "ipa" || "$TARGET" == "appbundle" ]]; then
    echo "   ✗ ABBRUCH: Store-Ziel ($TARGET) mit Testgeraeten waere fatal —" >&2
    echo "     kein Nutzer wuerde je eine abgerechnete Anzeige sehen." >&2
    exit 1
  fi
fi

if [[ "$TARGET" == "apk" || "$TARGET" == "appbundle" ]]; then
  # `flutter test` beschaedigt den Plugin-Registrant → vor jedem Android-Release
  # zwingend clean (bekannte Falle, sonst fehlen Plugins zur Laufzeit).
  echo "→ flutter clean (Android-Release-Pflicht nach Tests)"
  flutter clean >/dev/null
  flutter pub get >/dev/null
fi

echo "→ flutter build $TARGET --release  (mit echten Ad-/Abo-Schluesseln)"
flutter build "$TARGET" --release "${ADMOB[@]}" "${REVENUECAT[@]}" ${EXTRA[@]+"${EXTRA[@]}"}

echo
echo "✓ Fertig. Gebaut MIT echten AdMob-IDs — dieser Build verdient Geld."
echo "  Gegenprobe am Geraet: die Anzeigen duerfen KEIN „Test mode\"-Label mehr"
echo "  zeigen. Tut es das doch, lief der Build ohne dieses Script."
