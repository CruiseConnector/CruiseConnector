---
name: test-route
description: Startet eine Simulations-Testfahrt oder analysiert die Routenlogik mit flutter analyze + Debug-Logs. Nutze wenn der User die App testen, Routing-Probleme debuggen oder einen Build-Check machen will.
argument-hint: [optional: analyze | build | clean]
---

## Test & Debug Workflow für CruiseConnect

### Was soll getestet werden?
Argument: $ARGUMENTS

### Option 1: Code-Analyse (default)
```bash
cd /Users/vucko/Development/CruiserConnect
flutter analyze lib/
```

Prüfe die Ergebnisse:
- **Errors** → sofort fixen
- **Warnings** → dem User melden mit Vorschlag
- **Infos** → ignorieren (außer bei neuen Dateien)

### Option 2: `analyze` — Tiefe Routing-Analyse
Lies die Kerndateien und prüfe auf logische Fehler:

1. `lib/data/services/route_service.dart` — Sind alle Manöver-Typen abgedeckt?
2. `lib/presentation/pages/cruise_mode_page.dart` — Ist die Navigation-State-Machine konsistent?
3. `lib/presentation/widgets/cruise/cruise_curve_warning.dart` — Sind die Schwellenwerte sinnvoll?

Erstelle eine Checkliste:
- [ ] Alle Mapbox maneuver types haben Icon-Mapping
- [ ] Alle modifier-Varianten werden behandelt
- [ ] U-Turns werden gefiltert (beide Richtungen)
- [ ] Nur letztes "arrive" wird als Ziel angezeigt
- [ ] Off-Route Detection hat vernünftige Schwellen
- [ ] Kurvendetektion ignoriert GPS-Rauschen

### Option 3: `build` — iOS Build testen
```bash
cd /Users/vucko/Development/CruiserConnect
flutter build ios --debug 2>&1 | tail -20
```

### Option 4: `clean` — Clean Build
```bash
cd /Users/vucko/Development/CruiserConnect
flutter clean && flutter pub get && cd ios && pod install --repo-update && cd ..
```

### Nach jedem Test
Fasse die Ergebnisse kurz zusammen und schlage nächste Schritte vor.
