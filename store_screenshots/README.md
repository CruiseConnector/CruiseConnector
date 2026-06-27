# Store-Screenshots (CruiseConnector-Design)

Rahmt echte App-Screenshots ins App-Store/Play-Store-Marketing-Design.

## Ablauf
1. Echte Screenshots ins jeweilige raw/-Verzeichnis legen, benannt nach der ID:
   - raw/apple/<id>.png    (iPhone-Screenshots)
   - raw/android/<id>.png  (Samsung/Android-Screenshots)
2. `node compose.mjs`
3. Fertige Bilder landen in out/apple/ + out/android/ (Apple 1242x2688, Android 1080x2340).

Nur Features mit vorhandener raw-Datei werden gerendert (7-10 reichen).

## IDs / Features / Headlines
| ID          | Screen (was abfotografieren)                    | Headline |
|-------------|--------------------------------------------------|----------|
| route_end   | Fahrt-Ende „Route beendet" + Speichern           | Speichere deine besten Strecken. |
| dashboard   | Startseite (Willkommen, XP, Level, Wochenstats)  | Fahre. Steige auf. Werde Legende. |
| roundtrip   | Rundkurs-Planung (Route auf Karte + Setup)       | Finde Rundkurse die wirklich Spass machen. |
| navigation  | Live-Navigation (Fahrmodus, Manöver-Banner)      | Live-Navigation für jede Kurve. |
| community   | Community-Feed                                   | Vernetze dich mit anderen Fahrern. |
| group       | Gruppenfahrt (Live-Positionen)                   | Fahre zusammen. Bleibt synchron. |
| garage      | Garage (Fahrzeuge)                               | Deine Garage. Deine Maschinen. |
| stats       | Statistiken / Analytics                          | Behalte den Überblick. |
| share       | Teilen-Ansicht (Strava-Style)                    | Teile deine Fahrten. |
| offline     | Karte/Einstellungen (offline geladen)            | Ganz DACH. Offline. |
