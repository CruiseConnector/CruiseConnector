# HEARTBEAT.md - Ich lebe noch

_Dieser Agent läuft alle 30 Minuten. Er ist MAXIMAL sparsam._

## Aufgabe (in dieser Reihenfolge, nicht mehr):

1. `tasks.md` lesen
2. Gibt es Tasks in `inProgress` oder `backlog`? → "TASKS_PENDING"
3. Wann war der letzte Task? → Wenn >3h → "IDLE_TOO_LONG"  
4. Sonst → "ALL_CLEAR"

## Ausgabe-Format (NUR das, nichts anderes):

```
STATUS: TASKS_PENDING|IDLE_TOO_LONG|ALL_CLEAR
LAST_TASK: [ISO timestamp oder "never"]
PENDING: [Anzahl]
```

## Regeln:
- Kein erklärender Text
- Keine Begrüßung
- Keine Zusammenfassung
- Maximal 3 Zeilen Output
- Bei IDLE_TOO_LONG: Proaktiv-Modus in SOUL.md lesen und Idee per Telegram senden

## Modell-Empfehlung:
`openrouter/google/gemini-flash-1.5` — billigst, schnellst, reicht für diesen Check.
