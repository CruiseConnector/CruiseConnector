#!/usr/bin/env bash
# Erzeugt ~/Desktop/CruiseConnector_Secrets.pdf mit ALLEN auf der Platte
# liegenden Secrets (App-Keys, Keystore, Edge-.env). Liest die Dateien direkt —
# die Werte erscheinen NICHT auf stdout. PDF via macOS-cupsfilter (Plaintext).
set -uo pipefail
ROOT="/Users/vucko/Development/CruiserConnect"
OUT="$HOME/Desktop/CruiseConnector_Secrets.pdf"
TXT="$(mktemp -t ccsecrets).txt"

dump() { # title, file
  echo "========================================================================"
  echo "$1"
  echo "========================================================================"
  if [ -f "$2" ]; then cat "$2"; else echo "(Datei nicht vorhanden: $2)"; fi
  echo
}

{
  echo "CRUISE CONNECTOR - SECRETS (VERTRAULICH)"
  echo "Erzeugt: $(date '+%Y-%m-%d %H:%M')  |  App 1.0.4+36"
  echo "Supabase-Ref: tlcfaxvvqzobmzwvfnvb  |  Bundle-ID: com.vucko.cruiserconnect"
  echo
  echo "!!! ACHTUNG: enthaelt LIVE-Geheimnisse (Supabase service_role, FCM,"
  echo "    Keystore-Passwoerter). Nur ueber sicheren Kanal teilen, nach Gebrauch"
  echo "    loeschen, NIE in Git/Cloud hochladen. !!!"
  echo
  dump "1) FLUTTER-APP  ->  lib/config/secrets.dart" "$ROOT/lib/config/secrets.dart"
  dump "2) ANDROID RELEASE-SIGNING  ->  android/key.properties" "$ROOT/android/key.properties"
  dump "3) SUPABASE EDGE-FUNCTION-SECRETS  ->  supabase/functions/.env" "$ROOT/supabase/functions/.env"

  echo "========================================================================"
  echo "4) FIREBASE / PUSH  (als DATEIEN mitschicken, nicht hier eingebettet)"
  echo "========================================================================"
  echo " - android/app/google-services.json   : $( [ -f "$ROOT/android/app/google-services.json" ] && echo vorhanden || echo FEHLT )"
  echo " - ios/Runner/GoogleService-Info.plist : $( [ -f "$ROOT/ios/Runner/GoogleService-Info.plist" ] && echo vorhanden || echo FEHLT )"
  echo " - APNs-Auth-Key (.p8) aus Apple Developer -> in Firebase Console hochladen"
  echo
  echo "========================================================================"
  echo "5) INFRASTRUKTUR-ZUGAENGE (nicht auf der Platte - separat einladen/teilen)"
  echo "========================================================================"
  echo " - Supabase: Projekt-Mitglied einladen ODER Personal Access Token (CLI)"
  echo " - GraphHopper (2 Mini-PCs): Host/IP + Port DE/EU (siehe .env oben)"
  echo " - Cloudflare R2 (Karten-Tiles): Account-ID, R2 Access-Key + Secret, Bucket"
  echo " - Apple Developer: Team-Einladung (Signing/TestFlight)"
  echo " - Firebase Console + Google Play Console: Zugriff einladen"
} > "$TXT"

/usr/sbin/cupsfilter "$TXT" > "$OUT" 2>/dev/null
RC=$?
rm -f "$TXT"
if [ "$RC" -eq 0 ] && [ -s "$OUT" ]; then
  echo "PDF geschrieben: $OUT"
  ls -la "$OUT"
else
  echo "FEHLER beim PDF-Erzeugen (rc=$RC)"; exit 1
fi
