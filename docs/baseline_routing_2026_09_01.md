# Baseline Routing — gemessen am 01.09.2026, vor jeder Aenderung

Gemessen gegen die LIVE-Edge `generate-cruise-route-v2` mit genau den
Feldnamen, die die App schickt. Jede Zeile ist ein einzelner Aufruf.

| Art | Fall | Dauer | Ergebnis | km | Bemerkung |
|---|---|---|---|---|---|
| a_nach_b | Feldkirch->Bregenz | 1.8s | OK | 43.0 |  |
| a_nach_b | Dornbirn->Bludenz | 1.3s | OK | 44.2 |  |
| a_nach_b | Muenchen->Rosenheim | 1.2s | OK | 63.1 |  |
| umweg_small | Feldkirch->Bregenz | 1.3s | OK | 43.0 |  |
| umweg_small | Dornbirn->Bludenz | 1.2s | OK | 44.2 |  |
| umweg_medium | Feldkirch->Bregenz | 1.3s | OK | 43.0 |  |
| umweg_medium | Dornbirn->Bludenz | 1.7s | OK | 44.2 |  |
| umweg_large | Feldkirch->Bregenz | 1.7s | OK | 43.0 |  |
| umweg_large | Dornbirn->Bludenz | 1.4s | OK | 44.2 |  |
| rundkurs | Feldkirch-40 | 1.25s | OK | 29.7 | Abweichung 26% |
| rundkurs | Feldkirch-80 | 1.26s | OK | 87.3 | Abweichung 9% |
| rundkurs | Bregenz-40 | 1.39s | OK | 42.8 | Abweichung 7% |
| rundkurs | Bregenz-80 | 1.3s | OK | 104.5 | Abweichung 31% |
| rundkurs | Muenchen-40 | 1.26s | OK | 37.7 | Abweichung 6% |
| rundkurs | Muenchen-80 | 1.34s | OK | 84.8 | Abweichung 6% |
| rundkurs | Graz-40 | 1.54s | OK | 34.9 | Abweichung 13% |
| rundkurs | Graz-80 | 1.4s | OK | 78.2 | Abweichung 2% |

## Zusammenfassung

- A nach B: 3/3 erfolgreich, min 1.2s / median 1.3s / max 1.8s
- Umwege klein/mittel/gross: 6/6 erfolgreich, min 1.2s / median 1.4s / max 1.7s
- Rundkurs: 8/8 erfolgreich, min 1.25s / median 1.34s / max 1.54s

## Zwei Befunde schon aus der Baseline

1. **Die Edge-Funktion ist nicht langsam.** Sie antwortet durchgehend in 1,2
   bis 1,8 Sekunden und liefert in 17 von 17 Aufrufen eine Route. Die vom
   Auftraggeber erlebte Wartezeit und das "findet gar keine Route" koennen
   dort also nicht entstehen.
2. **Der Umweg wirkt auf Edge-Ebene gar nicht.** klein, mittel und gross
   liefern fuer dasselbe Paar exakt dieselbe Distanz (43,0 km Feldkirch nach
   Bregenz, 44,2 km Dornbirn nach Bludenz). Entweder ignoriert die Edge das
   Feld, oder der Umweg entsteht im Client durch mehrere Anfragen.

## Nebenbefund: ein fachlicher Fehler kommt als 500 zurueck

Ein Aufruf ohne `targetLocation` (falscher Feldname) laesst die Funktion
abstuerzen: `TypeError: Cannot read properties of undefined (reading
'latitude')`, belegt im Protokoll `function_logs`. Laut CLAUDE.md darf ein
fachlicher Fehler nie als 5xx ausgeliefert werden — der Client fordert bei
5xx zum Wiederholen auf, was hier sinnlos ist.
