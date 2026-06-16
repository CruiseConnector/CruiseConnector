# Navigation Video Audit 2026-06-16

Quelle:
- `/Users/vucko/Downloads/ScreenRecording_06-16-2026 14-23-05_1.MP4` (9:07)
- `/Users/vucko/Downloads/ScreenRecording_06-16-2026 17-53-40_1.MP4` (3:58)
- Kontaktboegen: `/tmp/cruise_video_frames/codex/long_10s`, `/tmp/cruise_video_frames/codex/short_5s`

## Harte Befunde

### 9:07 Video

| Zeit | Beobachtung | Risiko | Fix / Status |
| --- | --- | --- | --- |
| 00:00-00:40 | Banner bleibt auf `Neuberechnung - Route wird angepasst - bitte weiterfahren`. | Fahrer hat 40s keine konkrete Fuehrung. | `RouteService` hat fuer `reroute_request` jetzt kurzes Timeout/1 Attempt statt 26s-Minimum; Redock hat `maxSearchMsOverride`. |
| 00:50 | Neue Fuehrung erscheint erst danach (`700m rechts halten`). | Reroute ist zu spaet. | Reroute-Live-Request blockiert nicht mehr lang; zusaetzlich 4s Max-OffRoute-Cap. |
| 02:10-04:10 | Lange Anweisung `7,3 km Scharf links abbiegen auf Stadtstrasse` rund um komplexe Kreisverkehr-/Auffahrtsgeometrie. | Symbol/Text wirkt nicht wie realer Kreisverkehr oder Spurentscheidung. | GraphHopper-Kreisverkehr-Text gewinnt jetzt auch gegen falsches Abbiege-Sign; Exit wird aus Text gelesen. |
| 04:20-04:30 | Erneut `Neuberechnung`, danach neue Route. | Kurzzeitige Blindphase. | Neuer Banner zeigt nach 6s sicheren Hinweis; Reroute-Pfad ist zeitlich begrenzt. |
| 06:50-07:30 | Kreisverkehr Ausfahrt 2 (`300m -> 90m -> 20m`) danach lange Folgeanweisung. | Roundabout-Symbol/Exit muss stabil bleiben. | Roundabout-Felder werden beim Copy/Snap erhalten; Textbasierte GH-Erkennung erweitert. |
| 08:40-08:50 | Noch ein Reroute, diesmal ca. 10s. | Reroute darf nicht wieder in langen Tail laufen. | Aktueller Code: Trigger spaetestens nach 4s qualifizierter Off-Route; Request-Timeout 7-8s statt 26s+. |

### 3:58 Video

| Zeit | Beobachtung | Risiko | Fix / Status |
| --- | --- | --- | --- |
| 00:00-00:50 | Puck/faehrt sichtbar abseits der roten Route, Banner zeigt alte Manoever (`30m rechts`, dann `110m links`). | Fahrer bekommt alte oder irrefuehrende Anweisung. | Off-route Banner bleibt neutral; Reroute-Trigger hat 4s Max-Cap; Request blockiert nicht mehr 26s+. |
| 00:55 | `Neue Strecke zum Ziel wurde uebernommen`, Distanz springt ca. 1.9km -> 2.5km. | Commit kommt zu spaet und fuehlt sich sprunghaft an. | Reroute-Start nutzt frische Smoother-Prediction; Redock und Ziel-Reroute sind limitiert. |
| 02:45-03:25 | Kreisverkehr Ausfahrt 2 und danach Folgeanweisung. | Kreisverkehr-Icon/Exit muss zur gefahrenen Geometrie passen. | Geometrie-basierter Roundabout-Winkel bleibt aktiv; Text-Fallback fuer falsches Provider-Sign ergaenzt. |

## Code-Ursachen, die bestaetigt wurden

- `RouteService._invoke` hatte fuer alle Requests ein Mindesttimeout von 26s, auch wenn `max_search_ms` fuer Navigation-Reroutes auf 4500/6000ms stand.
- Der garantierte Redock-Fallback hatte kein eigenes `maxSearchMsOverride`.
- GraphHopper-Manoever wurden nur bei `sign == 6` als Kreisverkehr klassifiziert; expliziter Kreisverkehr-Text mit falschem Sign konnte deshalb als normales Abbiegen erscheinen.
- Der Accuracy-skalierte Off-Route-Fix-Zaehler konnte bei 60m Accuracy 15 Fixes verlangen. Das widerspricht der 4s-Anforderung, wenn der Zustand bereits qualifiziert und anhaltend off-route ist.

## Aktueller Nachweisstand

Gruen:
- `flutter analyze lib/`
- Reroute-/Render-/Icon-/Banner-Testmatrix: 164 Tests
- Zusaetzliche Reroute-Gating-Tests: 31 Tests
- iOS Release Build (no-codesign) erfolgreich
- Signierter iOS Release Build erfolgreich
- Installation des neuesten signierten Builds auf `Vuckos Reich (2)` erfolgreich; automatischer Start war wegen gesperrtem iPhone blockiert.

Noch nicht bewiesen:
- Reale Fahrt mit neuem Build bei 50-60 km/h und 100+ km/h.
- Ob die neue 4s-Cap in genau den Video-Situationen die gefuehlte Blindphase voll beseitigt.
- Ob High-Speed-Smoothness subjektiv Apple/Google-nah genug ist; dafuer braucht es eine neue Geraeteaufnahme oder Profiling.
