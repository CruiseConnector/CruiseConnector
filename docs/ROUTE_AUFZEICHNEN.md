# Route selbst aufzeichnen

Stand: 2026-08-03 · Branch `feature/route-selbst-aufzeichnen`

Bisher konnte die App Routen nur **generieren**. Wer seine eigene Lieblingsstrecke
fuhr, konnte sie weder speichern noch bewerten noch teilen. Das geht jetzt.

## Ablauf für den Nutzer

```
Cruise → Rundkurs → Planungs-Typ „Aufzeichnen"
   ↓  „Aufzeichnung starten"   (keine Routenberechnung, es geht sofort los)
   … fahren …                  (Panel zeigt Fahrzeit + bisher aufgezeichnete km)
   ↓  „Aufzeichnung beenden"
Abschluss-Sheet: bewerten ⭐ · benennen · Foto · Speichern
   ↓  „Speichern & veröffentlichen"
Post-Editor mit angehängter Strecke
```

In der **Gruppenfahrt** startet der Leader die Aufzeichnung, alle Mitglieder
werden mitgenommen und zeichnen **ihren eigenen** Track auf. Jeder bekommt am
Ende sein eigenes Abschluss-Sheet.

## Warum es so gebaut ist

**Der GPS-Track war schon da.** `DrivenTrackRecorder` zeichnet bei *jeder* Fahrt
auf — mit Lücken-Erkennung, Genauigkeits- und Geschwindigkeitsfilter. Das Feature
musste ihn nur ohne geplante Route benutzbar machen.

**Die Navigations-Pipeline schaltet sich selbst ab.** In
`cruise_mode_page.dart` steht in `_onLocationUpdate` die Zeile

```dart
if (!_isRouteConfirmed || _fullRouteCoordinates.length < 2) return;
```

Beim Aufzeichnen bleibt `_fullRouteCoordinates` leer → Routen-Matching,
Off-Route-Erkennung, Rerouting, Manöver und Sprachansagen laufen gar nicht erst
an. Es musste dafür **kein einziger** bestehender Zweig umgebaut werden. Das
Aufzeichnen des Tracks selbst hängt eine Zeile darüber an `_isRouteConfirmed` und
läuft weiter.

**Alles Neue hängt an `_isRecordingMode`.** Ist der Getter `false`, verhält sich
die App exakt wie vorher — inklusive Abschluss-Sheet ohne Veröffentlichen-Button.

## Was wo geändert wurde

| Datei | Änderung |
|---|---|
| `lib/data/services/driven_track_recorder.dart` | **Neu:** `toStandaloneRouteResult()` — Track → `RouteResult` ohne Quell-Route. Die bestehende `toRouteResult()` ist unangetastet. |
| `lib/presentation/widgets/cruise/cruise_setup_card.dart` | Dritter Planungs-Typ „Aufzeichnen" (eigene Zeile, weil das Wort für ein Drittel Kartenbreite zu lang ist) + Hinweis-Block. Länge/Stil/Autobahn/Standort/Länder werden ausgeblendet — sie hätten keine Wirkung. |
| `lib/presentation/widgets/cruise/drive_control_panel.dart` | Optionale `startLabel`/`stopLabel`/`startIcon`. Ohne Override unverändert. |
| `lib/presentation/pages/cruise_mode_page.dart` | `_isRecordingMode`, `_startRecordingSession()`, `_onRecordingStopped()`, `_publishRecordedRoute()`, Gruppen-Session. Completion-Pfad um je einen frühen Zweig ergänzt. |
| `lib/presentation/widgets/cruise/cruise_completion_dialog.dart` | Optionaler `onPublish`-Callback → Button „Speichern & veröffentlichen". **Nur** gerendert, wenn der Callback gesetzt ist. |
| `lib/data/services/saved_routes_service.dart` | `saveRoute()` liefert die Routen-ID (`Future<void>` → `Future<String?>`) — nötig fürs Veröffentlichen. Für alle bisherigen Aufrufer eine No-Op. |
| `lib/data/services/group_route_data_builder.dart` | **Neu:** `buildRecordingSession()` / `isRecordingSession()` — Marker ohne Geometrie. |

### Zwei Stellen, an denen bewusst abgewichen wird

- **XP:** `_calculateCompletionProgressFraction()` rechnet gefahren/geplant. Ohne
  Planung käme 0 heraus und damit kein XP. Beim Aufzeichnen gilt darum 100 % —
  was gefahren wurde, *ist* die Strecke.
- **Routen-Pool:** `RouteCompletionCandidateService.submitCandidate` wird
  übersprungen. Der Pool speist die *generierten* Routen (Qualitäts-Scoring,
  Wiederverwendung durch andere Nutzer); ein GPS-Track hat weder
  Planungs-Parameter noch Quality-Tier und gehört dort nicht hinein.

## Testen

```bash
flutter analyze lib/ test/
flutter test test/services/driven_track_recorder_standalone_test.dart \
             test/services/driven_track_recorder_test.dart
```

Der bestehende `driven_track_recorder_test.dart` muss unverändert grün bleiben —
er ist der Beweis, dass der alte Pfad nicht angefasst wurde.

**Im Simulator:**

1. Cruise → Rundkurs → **Aufzeichnen** → *Aufzeichnung starten*
2. Simulation laufen lassen (FAB) → Panel zählt Zeit und km hoch
3. *Aufzeichnung beenden* → Sheet mit Strecke, Bewertung, Titel
4. *Speichern & veröffentlichen* → Post-Editor mit angehängter Route
5. Gegencheck: Profil → gespeicherte Routen enthält die Strecke

**Regression (wichtigster Punkt):** Eine normale Zufalls-Fahrt generieren und
abschließen. Manöver, Kurvenwarnung, Rerouting, XP und Abschluss-Sheet müssen
sich exakt wie vorher verhalten — und im Sheet darf **kein**
Veröffentlichen-Button auftauchen.
