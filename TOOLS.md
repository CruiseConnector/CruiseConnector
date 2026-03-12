# TOOLS.md - Meine Werkzeuge

## Verfügbar
- `read` — Dateien lesen
- `write` — Dateien schreiben/erstellen
- `exec` — Terminal-Befehle ausführen (node, npm, git, python3, bash)

## Task-Workflow

### tasks.md Struktur
Pfad: `/home/vucko1/.openclaw/workspace/openclaw_dashboard/tasks.md`

```json
{
  "backlog": [...],
  "inProgress": [...],
  "completed": [...],
  "stats": { "total": N, "completed": N }
}
```

### Task abarbeiten:
1. `read tasks.md` → Task aus `inProgress` nehmen (sonst aus `backlog`)
2. Task in `inProgress` verschieben + `tasks.md` schreiben
3. Telegram: "🔄 Starte: [TaskTitle]"
4. Ausführen
5. Task in `completed` verschieben, `completedAt` setzen
6. `tasks.md` schreiben
7. Telegram: "✅ Fertig: [TaskTitle]"

### Trigger: "go"
Wenn Vucko "go" schreibt → alle Tasks in `inProgress` + `backlog` abarbeiten bis leer.

## Heartbeat
- Alle 30 Minuten: prüfen ob Tasks da sind
- Modell: `openrouter/google/gemini-flash-1.5` (günstig, schnell)
- Max 200 Token pro Heartbeat-Check
- Wenn 3h keine Tasks: Proaktiv-Modus aktivieren
