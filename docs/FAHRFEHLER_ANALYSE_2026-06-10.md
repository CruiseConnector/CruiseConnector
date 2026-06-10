# Fahrfehler-Analyse & Vollverifikation — 2026-06-10

**Frage:** „Warum habe ich oft Fehler während dem Fahren?"
**Antwort:** Vier unabhängige Ursachen, alle mit Code-Beleg gefunden, gefixt und gemessen.

---

## Ursache 1 — Linien-Glitches: das 3-km-Fenster wurde permanent neu gepusht

**Symptom:** Rote Route flackerte/risse ab, wirkte „kaputt"; nur ~3 km sichtbar, dahinter Nichts.

**Root Cause (Code):** `cruise_mode_page.dart` schnitt die sichtbare Route auf ein
3-km-Fenster und schob es **alle ~25 m Fahrt komplett neu** in die GPU-Quelle
(alter Sliding-Window-Block, `_routeRedrawDistanceMeters = 25.0`). Jeder Push
= voller GeoJSON-Rebuild während der Renderer arbeitet → sichtbare Glitches +
„Route endet im Nichts"-Optik.

**Fix (`388d1fd`):** Architektur umgedreht:
- Rote Linie = **komplette Reststrecke**, wird **genau 1× pro Route** gepusht
  (statisch → kann physikalisch nicht mehr flackern).
- Neuer **grauer Driven-Trail** (eigene GPU-Quelle, über der roten Linie) wächst
  alle ~4 m hinter dem Puck und „frisst" die rote Linie mit scharfem Schnitt am
  Puck auf → **abgefahren = grau, zu fahren = rot** (die geforderte andere
  Anzeige der Reststrecke), Stück für Stück mitgeladen.

**Messwert:** Geometrie-Pushes der sichtbaren Route: vorher ~1×/25 m
(≈ 2.000 Pushes auf 50 km), nachher **1× pro Route** + Mini-Trail-Updates.
**Fahrbeweis:** Sequenzen 96,5→95,6 km und 1,3→0,4 km (50-s-Abstand, Trail
wächst exakt am Puck, null Glitches); 8,5-km-Manöveranweisung während der
Fahrt = Beweis, dass weit mehr als 3 km geladen sind.

---

## Ursache 2 — U-Turn-Einbiegungen: das Backend ignorierte die Fahrtrichtung

**Symptom:** Nach Reroute Anweisungen in Straßen, in denen man sofort wenden muss.

**Root Cause (Code):** Der Client sendete `current_heading` seit jeher mit
(`route_service.dart`, Request-Builder), aber die Edge-Funktion
`generate-cruise-route-v2/index.ts` hat das Feld **nie gelesen** — der
GraphHopper-Request enthielt **0× ein `heading`**. GH durfte Routen gegen die
Fahrtrichtung beginnen.

**Fix (`7940619`, deployt):** `req.current_heading` → GraphHopper-`heading` am
Startpunkt + `heading_penalty: 120` (Start gegen Fahrtrichtung kostet 2
Fahrminuten → nur wenn keine Alternative existiert). Aktiv für Direkt-, Umweg-
und Wegpunkt-Reroutes.

**Messwert/Beweis:** Live-Request mit `heading: 200°` → HTTP 200, valide Route.
Live-Abweichfahrt (SIM_DEVIATE, echte Straßen): Reroute begann mit normaler
Weiterfahranweisung („links halten zur L202"), **kein U-Turn**, Fahrt lief bis
zur automatischen Zielankunft durch.

---

## Ursache 3 — A→B endete neben dem Ziel: Ziel-Verschiebung + zu laxe Validierung

**Symptom:** Route führte am Zielmarker vorbei und endete ~1 km dahinter
(Bregenz→Götzis-Screenshot).

**Root Cause (Code), zweiteilig:**
1. **Edge:** Die Direkt-Snap-Varianten verschoben bei Snap-Problemen auch das
   **Ziel** um bis ±0,010° (~±1,1 km, `eLatOff/eLngOff` in den
   `directVariants`) — und eine Ziel-Offset-Variante konnte das Rennen
   gewinnen, obwohl das exakte Ziel erreichbar war.
2. **Client:** `_pointToPointDestinationReached` akzeptierte eine Route, wenn
   **irgendeiner der letzten 30 Punkte** ≤ 2 km am Ziel lag — eine Route, die
   am Ziel **vorbeifährt**, bestand den Check.

**Fix (`7940619`):** (a) Edge: gestufte Phasen — Ziel exakt → ±150 m → ±1,1 km,
spätere Phase nur wenn alle vorherigen scheitern. (b) Client:
`_overshootTrimForDestination` schneidet den Überschuss-Tail hinter dem
zielnächsten Punkt ab (Manöver/Distanz/Dauer/Tempolimits mitkorrigiert,
loop-sicher für Wegpunkt-Rundkurse).

**Messwert:** Ende→Ziel vorher ~1.000 m, nachher **5 m** (live gemessen, direkt
UND Umweg; Overshoot-Delta 0 m). **Sichtbeweis:** Sim-Zoom — Linie endet IM
Marker (2 Modi).

---

## Ursache 4 — Sporadischer Absturz beim ersten Karten-Öffnen (SIGABRT)

**Symptom:** App stürzte „manchmal einfach ab", bevorzugt beim ersten Öffnen
der Cruise-Seite.

**Root Cause (Forensik ohne dSYM, `e382317`):** Alle **9 Crash-Reports**
(5./8./9./10. Juni) byte-identisch auf dem Main-Thread. Disassembly des
Binaries an der Absturzadresse zeigt die **Web-Mercator-Inverse**
(π-Konstante + `atan(exp(…))`) mit anschließendem Aufruf des
mbgl-**LatLng-Konstruktors**; die Fehlertexte
(„latitude must not be NaN", „must be between -90 and 90") stehen im Binary.
Mechanik: erste Kamera-/Layout-Operation **bevor die View eine Größe hat** →
Division durch 0 → Breitengrad = ∞ → nativer C++-Throw (für Flutter unfangbar)
→ SIGABRT. Log bestätigt: Crash 50 ms nach Karten-Initialisierung.

**Fix (`e382317`):** (1) **Size-Gate** — native Karte wird erst gebaut, wenn das
Layout eine endliche Größe ≥ 2 px liefert. (2) **Kamera-Sanity** — Start-Koordinaten
und Zoom hart validiert (NaN/∞/Range-Clamp).

**Messwert:** Historische Basisrate: 3 Crashes in 9 Minuten (5. Juni) bei genau
diesem Muster. Nach dem Fix: **4/4 Repro-Läufe crashfrei**
(`integration_test/first_open_crash_test.dart`, mountet die Karte direkt =
exakter Crash-Pfad; Assertion `nativeMapInTree=1` beweist, dass die native
Karte wirklich gebaut wurde), 0 neue Crash-Reports. Harness liegt im Repo —
jederzeit wiederholbar.

---

## Verifikations-Matrix dieser Session (alles selbst am PC ausgeführt)

| Test | Ergebnis | Beleg |
|---|---|---|
| Rundkurs-Fahrt (Fahrsimulator 70 km/h) | ✅ | Trail wächst am Puck, 96,5→95,6 km, Kreisverkehr sauber |
| Off-Route → Reroute → Zielankunft | ✅ | echte Straßen-Abweichung, kein U-Turn, Auto-Abschluss |
| A→B direkt (29,4 km) | ✅ | Linie endet IM Marker; live 5 m |
| A→B Kleiner Umweg (27,2 km) | ✅ | Linie endet IM Marker |
| Wegpunkte (75,6 km, 2 Stopps) | ✅ | kein „no routes" |
| Trip-Modus (29,6 km, 2 Stopps) | ✅ | kein „no routes" |
| Trip-Abweichfahrt | ✅ | Reroute behält Rest-Stopps (26 km Rest statt 5-km-Direktweg) |
| Mid-Drive-Kill → Resume-Card | ✅ | Card mit Live-Fortschritt nach App-Kill + Standort-Versatz |
| Erstopen-Crash-Repro | ✅ 4/4 crashfrei | first_open_crash_test, nativeMapInTree=1 |
| Edge-Live-Messungen | ✅ | Ende→Ziel 5 m; heading akzeptiert; Loop-Naht 25 m |

**Offen (hardware-/zugriffsgebunden, nicht code-gebunden):**
1. Resume-Durchklick als Sichttest — Maus-Event-Kette des Macs nach ~14 h tot
   (App-/Sim-/Device-Neustart halfen nicht). Alle drei Software-Alternativen
   wurden gebaut und enden an derselben Grenze: XCTest und flutter-run
   installieren einen FRISCHEN App-Container ohne Login-Session (die App steht
   auf dem Anmelde-Screen — dessen Titel ist ebenfalls „Willkommen zurück!",
   was die erste Test-Probe falsch-positiv machte). Der VM-Service-Eval-Kanal
   funktioniert nachweislich (Intent-Setzen lief live), scheitert aber am
   selben ausgeloggten Container. → 2-Minuten-Test nach Mac-Neustart ODER nach
   einmaligem Login; alle Code-Fixes (`802d646`) sind drin.
2. Android-Emulator eingeloggt — erfordert Anmeldung in den User-Account
   (Sicherheitsgrenze). Das echte Galaxy A34 lief eingeloggt fehlerfrei durch
   dieselben Flows.

## Commits dieser Session
`73bc3ae` Einzeichnen-Animation · `4422185` Linie −20 % · `111c007` CarPlay 25/50/75/100 + Android-Auto-Planer · `388d1fd` Voll-Route + Driven-Trail · `7940619` A→B-Endpunkt + Heading + Trip-Skip · `5c0ccf5` Trip-Zwischenspeichern/Resume (solo) · `802d646` Resume-Härtung · `e382317` Erstopen-Crash-Fix · `518b399`/`335d9db` Crash-Repro-Harness · `27db358` iOS-Artefakte. Edge-Funktion `generate-cruise-route-v2` live deployt.
