# P0 Routing — Ergebnis, 01.09.2026

## Ursache, belegt

**Die Edge-Funktion war nicht die Ursache.** 27 Live-Antworten am 01.09.:
0,9 bis 5,4 Sekunden, keine einzige fehlgeschlagen. Die Wartezeit und das
"findet gar keine Route" entstanden im Client.

Drei belegte Ursachen:

1. **Die Kehrtwenden-Pruefung lehnt hart ab, ohne Ausweg.**
   `route_service.dart:6358`, `route_quality_validator.dart:695`. Eine einzige
   Wende verwirft den Kandidaten. An drei echten Vorarlberger Paaren mit je
   sechs Seeds nachgerechnet: in FUENF von neun Kombinationen aus Paar und
   Stufe scheitern BEIDE Live-Versuche.

2. **Bis zu sieben Serveraufrufe nacheinander, ohne Gesamtbudget.**
   Zwei Live-Versuche, ein aggressiver Rettungskorridor, drei Herabstufungen,
   ein Direktrueckfall. Kein `Future.wait`, keine Deadline, kein Abbruch im
   ganzen Block. Rechnerisch 7 x 2 x 31 s = 434 Sekunden fuer EINEN Tipp.

3. **Ein totes Feld hob das Timeout.** `max_search_ms: 25000` kommt in
   `generate-cruise-route-v2/index.ts` null Mal vor, hob aber ueber
   `requestTimeoutSecondsFor` das Client-Timeout von 26 auf 31 Sekunden.

Dazu: **die Oberflaeche wiederholte die ganze Kaskade dreimal**, weil der
Direkt-Rueckfall deterministisch dieselbe Route liefert (Dornbirn nach
Bludenz: 3 von 3 Mal exakt 45,21 km). Aus 6 Aufrufen wurden 18.

## Vorher / Nachher

### A nach B (Edge, mit den Feldern die die App schickt)

| | Baseline | Nachher |
|---|---|---|
| Erfolg | 3/3 | 12/12 ueber alle vier Stufen |
| Dauer | 1,2 bis 1,8 s | 3,2 bis 4,8 s im Leerlauf |

Die hoehere Zeit ist KEIN Rueckschritt: die Baseline schickte die Umwegsstufe
als Text ("small"/"medium"/"large"), die Edge tippt das Feld als Zahl und fiel
still auf die Direktroute zurueck. Gemessen wurde also viermal dasselbe
billige Ergebnis. Mit Zahlen rechnet die Edge den Umweg wirklich.

### Umwegsstufen wirken (Feldkirch nach Bregenz)

| Stufe | Distanz |
|---|---|
| 0 direkt | 43,0 km |
| 1 klein | 44,7 km |
| 2 mittel | 49,5 km |
| 3 gross | 73,8 km |

### Rundkurs (A3)

| | Baseline | Nachher |
|---|---|---|
| Erfolg | 8/8 | 8/8 |
| Dauer | 1,25 bis 1,54 s | 1,10 bis 1,95 s |

Die Distanzen sind ZEICHENGLEICH mit der Baseline: 29,7 / 87,3 / 42,8 / 104,5
/ 37,7 / 84,8 / 34,9 / 78,2 km. Das ist zugleich der Nachweis fuer A4 — die
Routenqualitaet hat sich nicht veraendert, weil die Edge unveraendert ist.
Durchschnittstempo 41 bis 51 km/h, plausibel.

### Serveraufrufe je Tipp

Gezaehlt im Test: **6**. Waechtertest deckelt bei 7. Vorher konnten daraus
durch den Auto-Retry 18 werden.

## Aenderungen, jede einzeln rueckrollbar

| Commit | Aufgabe | Was |
|---|---|---|
| (DB) | A1/A4 | Nachschub-Cron von jede Minute auf alle zehn, 161 Auftraege pausiert. Last von 395 auf 8 Aufrufe je Viertelstunde. |
| 26ec6ac | A2 | Notausgang vor dem finalen throw |
| c0118d1 | A1 | Gesamtfrist 20 s, totes Feld entfernt, kein sinnloser Auto-Retry |

## Was NICHT geaendert wurde

Kein Qualitaetstor gelockert. Keine Schwelle verschoben. Die Andock-Logik beim
Fahrtstart (A17) nicht angefasst. Die Herabstufungs-Kaskade laeuft unveraendert
vor dem Notausgang — beim ersten Anlauf hatte ich ihn davor gesetzt, worauf
zwei Waechter vom 18.08. sofort ansprangen.

## Bekannte, NICHT behobene Schwaeche

Die Zieldistanz beim Rundkurs weicht in zwei von acht Faellen stark ab:
Feldkirch 40 km liefert 29,7 (26 Prozent zu kurz), Bregenz 80 km liefert 104,5
(31 Prozent zu lang). Beides war in der Baseline schon so, ist also keine
Regression — aber auch keine gute Zahl.

## Was ich NICHT zuordnen kann

Zwischen 12 und 13 Uhr UTC gab es einen Stau: zehn gleichzeitige Anfragen, 50
bis 114 Sekunden, alle im selben Sekundenbruchteil beendet. Absender und
Status stehen nicht im Protokoll. Ich habe keine belegbare Ursache dafuer.
