# CURRENT_FOCUS — Routing (Stand: 2026-04-16)

## Aktueller Schwerpunkt
Aktuell liegt der Fokus auf **Routing-Qualität** (Rundkurs & A→B) und messbarer Verbesserung im echten Ergebnis.

### Rundkurs (Loop)
- **Rundkurs-Qualität**: keine Start-Loops, keine Selbstkreuzungen/Spaghetti, saubere Manöver
- **Rundkurs-Diversität**: gleiche Einstellungen sollen **nicht** immer „fast identische“ Routen liefern

### A→B
- **Umwege**: „Umweg-Stufen“ müssen sichtbar unterschiedlich sein (nicht nur kosmetisch)
- **avoidHighways / Stil / Distanz**: Einstellungen dürfen nicht „unterlaufen“ werden

### Querschnitt
- **Latenz**: keine Request-Lawinen; klare Budgets/Timeouts
- **Worst Case**: „no-route“ wirklich nur, wenn keine plausible Route möglich ist
- **Benchmarks**: echte Benchmarks/Live-Ergebnisse höher gewichten als reine Theorie oder Mock-Tests

## Nicht aufmachen, wenn nicht nötig
- Keine UI-/Design-Überarbeitung „nebenbei“
- Kein Wechsel des State-Managements (kein Provider/BLoC/Riverpod)
- Keine großen Refactors (Umbenennungen, Ordnerstruktur, Formatierung über viele Dateien)
- Keine Änderungen an unrelated Features (Community/Analytics/Offline), sofern Routing-Aufgabe es nicht verlangt
- Keine Secrets/Keys in Doku/Logs/Diffs (insb. `lib/core/constants.dart`)

## Relevante Pfade (schneller Einstieg)
- `/Users/vucko/Development/CruiserConnect/lib/data/services/route_service.dart`
- `/Users/vucko/Development/CruiserConnect/lib/data/services/route_quality_validator.dart`
- `/Users/vucko/Development/CruiserConnect/supabase/functions/generate-cruise-route/index.ts`
- `/Users/vucko/Development/CruiserConnect/lib/presentation/pages/cruise_mode_page.dart`

