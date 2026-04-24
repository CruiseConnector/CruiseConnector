# ROUTING_ACCEPTANCE — Akzeptanzkriterien (Routing)

Diese Kriterien gelten als **„Definition of Done“** für Routing-Änderungen.  
Hinweis: **Echte Benchmarks/Live-Ergebnisse** sind wichtiger als nur „theoretisch korrekt“ oder ausschließlich Mock-Tests.

## Allgemein (für Rundkurs & A→B)
- **Koordinaten korrekt**: Mapbox-Format **`[longitude, latitude]`** überall konsistent.
- **Keine Kraken-/Astformen**: Route franst nicht in viele Äste aus und kehrt nicht ständig zu denselben Knoten zurück.
- **Keine Start-/End-Artefakte**: keine Mikro-Schleifen am Start, keine sinnlosen Kehrtwenden.
- **Manöver-Qualität**:
  - keine unnötigen U-Turns (nur wenn real nötig)
  - keine „Arrive“-Spam-Manöver (Zwischen-Arrives reduzieren, letztes Arrive ok)
- **Latenz akzeptabel**: keine Request-Lawinen; klare Budgets/Timeouts; keine Endlos-Retries.
- **no-route nur Worst Case**: erst nach sinnvollen Fallbacks und nachvollziehbarer Begründung.

## Rundkurs (Loop)
Akzeptiert, wenn:
- **Runde ist wirklich eine Runde**: Start und Ziel liegen plausibel nah beieinander.
- **Geometrie plausibel**: keine Spaghetti-/Selbstkreuzungs-Orgie, keine mehrfachen fast identischen Teilstrecken.
- **Qualität > Distanz**: leichte Distanzabweichung ist ok, wenn die Route insgesamt deutlich besser ist.
- **Diversität**:
  - Bei gleicher Einstellung liefern mehrere Vorschläge **sichtbar unterschiedliche** Routen.
  - Keine „fast identischen“ Rundkurse, die nur minimal verschoben sind.

Beispiele (nicht akzeptiert):
- Ast-/Krakenform: mehrere Abzweige mit Rückkehr zum selben Punkt
- 2–3 Rundkurs-Vorschläge sind bei gleichen Settings praktisch identisch
- Startloop direkt am Startpunkt (z.B. kleine Kreis-/U-Turn-Schleife)

## A→B
Akzeptiert, wenn:
- **Umweg-Stufen sind real**: „kurz / mittel / lang“ (oder vergleichbar) unterscheiden sich klar in Strecke/Profil.
- **Einstellungen werden respektiert**:
  - `avoidHighways` führt nicht trotzdem zu überwiegender Autobahn-Nutzung
  - Stil/Distanz-Parameter wirken sichtbar
- **Keine absurden Umwege** (außer der Nutzer wählt ausdrücklich „lang“): Route bleibt plausibel.

Beispiele (nicht akzeptiert):
- Umweg-Stufen unterscheiden sich nur um wenige Prozent → Nutzer merkt keinen Unterschied
- „avoidHighways“ aktiv, aber Route nutzt Autobahn als Hauptanteil

## Messung / Nachweis (mindestens eins davon)
- Lokaler Benchmark-Lauf (z.B. `tool/route_service_local_benchmark.dart`)
- Live-Requests gegen Edge Function + Vergleich mehrerer Kandidaten (Qualität, Diversität, Latenz)
- Reproduzierbarer Testfall (Koordinaten/Settings), der vorher schlecht und nachher messbar besser ist

