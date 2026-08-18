# CruiseConnect — Regeln fuer die Arbeit an diesem Repo

Flutter/Dart + Supabase (Auth/DB/Edge Functions) + Mapbox/GraphHopper.
Deutsche UI-Texte, englische Variablennamen. Koordinaten sind ueberall
`[longitude, latitude]` (Mapbox-Format).

Die ausfuehrliche Architektur-Dokumentation liegt in
`/Users/vucko/Development/CLAUDE.md`. Dieses Dokument haelt die Regeln fest,
die sich aus konkreten Fehlern ergeben haben.

---

## Datenmodell: Welche Tabelle ist fuer eine Fahrt zustaendig?

Es gibt zwei Tabellen, die beide nach „Fahrt" klingen. Das hat am 18.08.2026
zu einem Defekt gefuehrt: der Rundkurs-Zweig legte keinen Trip an, der
A→B-Zweig schon. Gemessen: 12 Zeilen in `trips` von 2 Personen gegenueber
116 Zeilen in `user_drive_sessions`.

### `user_drive_sessions` ist FUEHREND fuer gefahrene Fahrten

Alles, was eine tatsaechlich absolvierte Fahrt betrifft, steht hier:

- Kilometer, Dauer, Hoechstgeschwindigkeit, Streckenverlauf, Foto
- XP (`xp_awarded`), Streak, Badges, Wochen- und Monatsrangliste
- Das Admin-Monitoring (`admin_monitor_metrics`, `_today`, `_history`,
  `_compare`, `_analytics`, `_leute`) liest ausschliesslich diese Tabelle.

Regeln:

- Eine gefahrene Fahrt = GENAU EINE Zeile. Unterbrechungen, App-Wechsel und
  Neustarts duerfen keine zweite Zeile erzeugen (sonst zaehlen Badges wie
  „Anzahl Fahrten" doppelt). Siehe `UnterbrocheneFahrtVerbuchung`.
- Wer Kilometer, XP oder Ranglisten auswertet, fragt diese Tabelle.
- Der UPDATE-Grant ist bewusst auf `photo_url` beschraenkt. Nicht lockern.

### `trips` ist die Planungs- und Gruppentabelle

Ein Trip ist ein VORHABEN, keine Abrechnung: mehrtaegige Touren, mehrere
Stopps, Gruppenfahrten. Er ist der Anker fuer Home-Card, Resume nach
App-Kill und den Rejoin in die Gruppen-Lobby (`group_id`).

Regeln:

- Ein Trip wird angelegt, wenn der Trip-Modus aktiv ist ODER eine Gruppe
  faehrt — in BEIDEN Zweigen, Rundkurs wie A→B. Die Bedingung muss an beiden
  Stellen in `cruise_mode_page.dart` zeichengleich sein.
- `total_distance_km` in `trips` ist die GEPLANTE Strecke, nicht die
  gefahrene. Fuer gefahrene Kilometer nie `trips` benutzen.
- Trips ohne zugehoerige Fahr-Session sind normal (geplant, nie gefahren).

---

## Weitere Regeln aus konkreten Fehlern

- **Laender-Klassifikation**: `CountryRegion` (Client) und `classifyCountry`
  (Edge `generate-cruise-route-v2`) muessen dieselbe Bandtabelle benutzen.
  Der Test `test/route/laender_klassifikation_test.dart` vergleicht beide
  Dateien und schlaegt fehl, wenn sie auseinanderlaufen. Das Heimatland wird
  serverseitig aus dem Startpunkt abgeleitet, NICHT vom Client uebernommen —
  alte App-Versionen bleiben installiert und senden falsche Werte.

- **HTTP-Status der Edge**: 422 = die Anfrage ist so nicht erfuellbar
  (ausserhalb der Abdeckung, kein Inlandsrundkurs, Punkt nicht an der
  Strasse). 5xx = unser Server hat ein Problem. Der Client fordert nur bei
  5xx zum Wiederholen auf. Nie einen fachlichen Fehler als 5xx ausliefern.

- **Abdeckung**: Die Wahrheit steht in GraphHopper `/info` (Bounding-Box),
  nicht in `route_pool_coverage` — die Tabelle enthaelt nur die Regionen mit
  vorberechneten Pools und ist als Abdeckungspruefung ungeeignet.

- **Nach jeder Code-Aenderung** `flutter analyze lib/` ausfuehren.
- **Datenbankzugriff** ausschliesslich ueber den Supabase-MCP.
- **Nach jedem `create table`/`alter table`** den Supabase-Advisor laufen
  lassen.
- **Niemals** Werte aus `lib/core/constants.dart` oder `secrets.dart`
  ausgeben.
