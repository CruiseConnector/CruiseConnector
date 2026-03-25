---
name: build-ios
description: Baut die iOS-App, löst Build-Fehler und deployt auf das angeschlossene iPhone. Nutze wenn der User die App auf sein Gerät pushen will oder Build-Fehler hat.
argument-hint: [optional: clean | fix | run]
disable-model-invocation: true
---

## iOS Build & Deploy Workflow

### Modus: $ARGUMENTS

### Schritt 1: Projektstand prüfen
```bash
cd /Users/vucko/Development/CruiserConnect
flutter analyze lib/ 2>&1 | grep -E "error|Error" | head -10
```

Wenn Errors → zuerst fixen, dann weiter.

### Schritt 2: Build je nach Modus

**`run` (default) — Direkt auf iPhone starten:**
```bash
flutter run --release
```

**`clean` — Sauberer Neustart:**
```bash
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter run
```

**`fix` — Build-Fehler diagnostizieren und beheben:**
1. Build versuchen und Fehler sammeln:
```bash
flutter build ios --debug 2>&1 | tail -40
```

2. Häufige iOS-Probleme und Lösungen:
   - **"No such module 'Flutter'"** → `Runner.xcworkspace` statt `.xcodeproj` öffnen, oder `pod install` fehlt
   - **Signing-Fehler** → User muss in Xcode Team auswählen (Xcode → Runner → Signing & Capabilities)
   - **Pod-Konflikte** → `cd ios && pod deintegrate && pod install`
   - **CarPlay-Referenzen** → Wurden entfernt, aber prüfe ob `project.pbxproj` noch Reste hat
   - **Stale Build-Cache** → `flutter clean` + Derived Data löschen

3. Nach dem Fix nochmal bauen.

### Schritt 3: Ergebnis melden
- Build erfolgreich → Sage dem User dass die App bereit ist
- Build fehlgeschlagen → Zeige den Fehler und schlage konkreten Fix vor

### Wichtige Hinweise
- NIEMALS API-Keys oder Tokens im Output zeigen
- iOS Simulator reicht für UI-Tests, echtes iPhone für GPS/Navigation
- Bei Signing-Problemen: User braucht Apple Developer Account (kostenlos reicht für eigenes Gerät)
