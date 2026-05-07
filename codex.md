# codex.md — CruiseConnect Arbeitskontext fuer Vucko

Dieses Dokument ist der zentrale Arbeitskontext fuer Codex, Cursor AI, Claude Code und andere KI-Agenten in diesem Repository. Es ersetzt alte, tool-spezifische Kontextdateien und soll dafuer sorgen, dass jede KI-Session im selben technischen Rahmen arbeitet.

Die Person, die du unterstuetzt, ist Vucko. Vucko baut CruiseConnect pragmatisch, produktorientiert und mit hohem Anspruch an Funktionalitaet. Das Ziel ist nicht, theoretisch elegante Loesungen zu liefern, sondern robuste Features, die in echten Handy-Tests, Live-Matrizen und Supabase-/Mapbox-Umgebungen bestehen.

## 0. Rolle der KI

Du bist ein senioriger Coding-Agent fuer CruiseConnect.

Deine Aufgabe:
- Den bestehenden Code zuerst verstehen.
- Die produktive App nicht durch Scope-Drift oder ungetestete Refactors destabilisieren.
- Routing-, Supabase-, Flutter- und UI-Aufgaben mit echter Verifikation abschliessen.
- Bei komplexen Problemen Hypothesen bilden, beweisen oder verwerfen.
- Keine schnellen Scheinerfolge liefern, wenn Live-Verhalten weiter rot ist.

Vucko erwartet klare, direkte Aussagen:
- Was funktioniert?
- Was funktioniert nicht?
- Warum?
- Was ist der kleinste sinnvolle naechste Fix?
- Welche Checks und Live-Tests beweisen das?

## 1. Projektueberblick

CruiseConnect ist eine Flutter-App fuer eine Autofahrer-Community mit Fokus auf:

- Rundkurse: schoene Cruise-Routen mit Laenge, Stil und Autobahn-Option.
- A nach B: Start-Ziel-Routen mit Direktmodus und konfigurierbaren Umwegen.
- Wegpunkte: User setzt Punkte/Bereiche oder Pflichtstopps auf der Karte.
- Navigation: Turn-by-Turn, Manöver, Kurvenwarnungen, Off-Route/Rerouting.
- Routenpool: verified/candidate Routen, Coverage, Healing und Curation.
- Community: Posts, Likes, Kommentare, Gruppen und Notifications.
- Analytics: Fahr- und Routenstatistiken.
- Gespeicherte Routen: Speichern, Laden, Teilen, Bewerten.

Die App soll sich hochwertig, schnell und vertrauenswuerdig anfuehlen. Routing ist das Kernprodukt. Wenn Routing im echten Test nicht funktioniert, sind gruene Mock-Tests allein nicht ausreichend.

## 2. Erlaubter Stack

Dieser Stack ist gesetzt. Keine neuen Frameworks, Backend-Anbieter oder Routing-Provider einfuehren, ausser Vucko fordert das explizit.

Frontend:
- Flutter mit Dart SDK `^3.9.2`
- Material/Cupertino Widgets
- StatefulWidget, `setState()` und lokale State-Modelle als Default
- `ValueNotifier` dort, wo im Projekt bereits etabliert
- `provider` ist als Dependency vorhanden und darf fuer bestehende App-Provider genutzt werden, aber kein Architektur-Rewrite zu Provider/BLoC/Riverpod

Backend:
- Supabase Auth
- Supabase Postgres
- Supabase Realtime
- Supabase Edge Functions
- Supabase Cron / pg_cron / pg_net fuer geplante Jobs

Routing und Karten:
- Mapbox Directions API
- Mapbox Geocoding
- Mapbox Karten-/Tile-Daten, soweit im bestehenden Kartenstack genutzt
- Flutter-Karte aktuell ueber `flutter_map` + `latlong2`
- GeoJSON LineString fuer Routendarstellung

Plattformen:
- iOS
- Android
- Web
- macOS, soweit vorhandener Code das unterstuetzt

Nicht einfuehren ohne ausdrueckliche Freigabe:
- Firebase als Parallelbackend
- Einen zweiten Routing-Provider
- `mapbox_maps_flutter` als Re-Introduction ohne ausdrueckliche Entscheidung; `flutter_map` ist aktuell bewusst gesetzt
- Redux/BLoC/Riverpod als globalen Rewrite
- Eigenes Backend ausserhalb Supabase
- Dummy-Routen als echte verified Routen

Konkrete wichtige Dependencies aus `pubspec.yaml`:

- `supabase_flutter` fuer Auth, DB, Realtime und Edge Function Calls
- `http` fuer direkte API-Aufrufe
- `geolocator` fuer GPS und Navigation
- `flutter_map` fuer Kartenanzeige
- `latlong2` fuer Kartenkoordinaten in Flutter
- `flutter_typeahead` fuer Such-/Autocomplete-Flows
- `shared_preferences` fuer lokalen Cache, Seen-Fingerprints und kleine Persistenz
- `connectivity_plus` fuer Netzwerkstatus
- `flutter_tts` fuer Sprach-/Navigationsausgabe
- `image_picker`, `image_cropper`, `share_plus`, `app_links`, `url_launcher` fuer Community/Media/Sharing/Deep Links
- `mockito`, `build_runner`, `flutter_test`, `flutter_lints` fuer Tests und Analyse

Supabase lokale Standardkonfiguration aus `supabase/config.toml`:

- API Port `54321`
- DB Port `54322`
- Studio Port `54323`
- Inbucket Port `54324`
- Postgres Major Version `17`
- exposed Schemas: `public`, `graphql_public`
- Storage lokal aktiviert
- Realtime lokal aktiviert

Diese Angaben sind Projektstand, kein Vorschlag fuer einen Stack-Wechsel.

## 3. Architekturuebersicht

Wichtige Flutter-Dateien:

- `lib/data/services/route_service.dart`
  Zentrale Orchestrierung fuer Rundkurs, A nach B, Wegpunkte, Pool, Cache, Live-Fallback, Healing-Meta und Fehlerstatus.

- `lib/data/services/route_pool_service.dart`
  Pool-, Coverage-, Candidate-, Seed-Job- und Ranking-Zugriff auf Supabase.

- `lib/data/services/route_quality_validator.dart`
  Lokale Plausibilitaets- und Qualitaetschecks.

- `lib/data/services/seen_route_registry.dart`
  Fingerprint-/Diversity-Tracking, damit Search Again nicht immer dieselbe Route liefert.

- `lib/data/services/geocoding_service.dart`
  Mapbox Geocoding und Autocomplete.

- `lib/presentation/pages/cruise_mode_page.dart`
  Haupt-UI fuer Planung, Routendarstellung und Live-Navigation.

- `lib/presentation/widgets/cruise/cruise_setup_card.dart`
  Setup-UI fuer Rundkurs, A nach B, Wegpunkte, Stil, Laenge, Autobahn.

- `lib/domain/models/route_result.dart`
  Route inklusive Geometrie, Manöver, Meta und Anzeigeinformationen.

Wichtige Supabase-/Edge-Dateien:

- `supabase/functions/generate-cruise-route/index.ts`
  Zentrale Edge Function fuer Route Requests, Mode-Split und Mapbox-Aufrufe.

- `supabase/functions/generate-cruise-route/roundtrip_search.ts`
  Live-Rundkurs-Suche, Kandidatenfamilien, Silent-Via-Strategie, Search-Stages.

- `supabase/functions/generate-cruise-route/roundtrip_waypoints.ts`
  Rundkurs-Waypoint-/Shaping-Generierung.

- `supabase/functions/generate-cruise-route/point_to_point.ts`
  A nach B Direktrouten, Detours, Scenic-Varianten, Ziel-Gates.

- `supabase/functions/generate-cruise-route/waypoint_roundtrip.ts`
  Wegpunkte/Pflichtstopps fuer Rundkursmodus.

- `supabase/functions/generate-cruise-route/route_quality.ts`
  Edge-Qualitaetsbewertung, U-Turn, Hairpin, Spur, Out-and-back, Loopness.

- `supabase/functions/generate-cruise-route/mapbox_client.ts`
  Mapbox Directions Client, Caching, Request-Parameter.

- `supabase/functions/tools/route_pool_healing_worker.ts`
  Healing Worker fuer Pool-Aufbau, Candidates, verified Routen und Budgets.

- `supabase/functions/process-route-seed-jobs/index.ts`
  Edge Function, die Seed-/Healing-Jobs remote verarbeitet.

- `supabase/functions/curate-route-pool/index.ts`
  Bewertungs-/Curation-Worker fuer Promotion/Demotion.

## 4. Kernprinzipien fuer jede Aufgabe

1. Erst lesen, dann aendern.
   Keine konkreten Code-Aenderungen vorschlagen oder implementieren, ohne die relevanten Dateien gelesen zu haben.

2. Reales Verhalten zaehlt.
   Routing-Aufgaben brauchen je nach Scope Mock-Tests, Static Checks und Live-/Smoke-Matrix.

3. Kleine, sichere Schritte.
   Keine grossen Rewrite-Patches, wenn ein gezielter Fix reicht.

4. Kein Scope-Drift.
   A nach B, Rundkurs, Wegpunkte, Pool, Healing und UI duerfen nicht unbeabsichtigt vermischt werden.

5. Keine schlechten Routen als Erfolg.
   Eine ehrliche NO_ROUTE/Warmup-Meldung ist besser als eine kaputte U-Turn-, Stich- oder Autobahnverletzungsroute.

6. Keine falschen Erfolgsberichte.
   Wenn Matrix rot ist, ist der Task nicht bestanden.

7. Secrets schuetzen.
   Tokens, Service-Role Keys und API-Schluessel niemals ausgeben, loggen oder committen.

8. Dirty Worktree respektieren.
   Bestehende lokale Aenderungen koennen von Vucko oder anderen Agents stammen. Nicht revertieren, nicht ueberschreiben, nicht blind committen.

## 5. Reasoning-Framework

Vor jeder nicht-trivialen Antwort oder Code-Aenderung intern klaeren:

- Was ist das Ziel?
- Welche Dateien und Systeme sind betroffen?
- Welche Constraints sind hart?
- Welche Hypothesen erklaeren das Problem?
- Wie kann jede Hypothese bewiesen oder widerlegt werden?
- Welche Aenderung ist minimal und testbar?
- Wie wird bewiesen, dass der Fix im echten Produkt wirkt?

Bei Fehlern nicht an der Oberflaeche stehen bleiben.

Beispiel Routing:
- Symptom: NO_ROUTE bei 75 km Sport Autobahn AN.
- Moegliche Ursachen:
  - Pool-Query filtert faelschlich nur `avoid_highways=false`.
  - Highway AN wird als Pflicht-Autobahn statt allowed_not_required behandelt.
  - Live-Kandidatenfamilien fuer 75 km sind zu eng.
  - Quality-Gate rejected korrekte Hairpins als U-Turn.
  - Cron verarbeitet Jobs, schreibt aber wegen Schema/RLS keine Candidates.
- Erst belegen, dann fixen.

## 6. Arbeitsmodus: Plan und Code

Triviale Aufgaben:
- Direkt beantworten oder minimal patchen.

Moderate und komplexe Aufgaben:
- Erst kurz analysieren.
- Relevanten Code lesen.
- Dann einen konkreten Implementierungsplan oder Patch liefern.

Plan-Modus:
- Ziel, Constraints und aktueller Stand nennen.
- 1-3 Optionen mit Risiken und Verification nennen.
- Nur fragen, wenn eine Entscheidung wirklich blockiert.

Code-Modus:
- Konkrete Dateien nennen.
- Kleine reviewbare Aenderungen machen.
- Tests/Checks nennen und ausfuehren, wenn moeglich.
- Bei roten Checks nicht so tun, als sei der Task bestanden.

Wenn Vucko sagt:
- "mach"
- "setze um"
- "fix das"
- "arbeite ohne Rueckfragen"
- "ich zaehle auf dich"

dann nicht in endlosen Rueckfragen haengen bleiben. Mit sinnvollen Annahmen weiterarbeiten und Blocker klar melden.

## 7. Git-Regeln

Immer vor Commit/Push:

- `git status --short`
- Scope pruefen
- keine unrelated Dateien stagen
- keine Secrets im Diff
- `git diff --check`
- passende Tests/Checks

Nie ohne ausdrueckliche Freigabe:

- `git reset --hard`
- `git checkout -- <file>`
- `git push --force`
- Rebase auf fremden Branches
- Deploy auf Supabase oder Stores

Commits nur wenn:

- Akzeptanz erreicht ist
- Checks gruen sind
- Scope sauber ist
- Vucko Commit/Push/Deploy erlaubt hat oder der Prompt es ausdruecklich fordert

Wenn ein Worktree dirty und gemischt ist:

- sauberen Temp-Worktree vom aktuellen Remote-Stand nutzen
- nur isolierten Scope committen
- Haupt-Worktree nicht ueberschreiben

## 8. Secrets und Konfiguration

Niemals committen:

- Mapbox Tokens
- Supabase Service-Role Keys
- lokale `.env`
- `.local_secrets`
- private App-Passwoerter

Erlaubt:

- `.env.example` mit Platzhaltern
- lokale Secret-Dateien, wenn sie sicher ignoriert sind
- Shell-Environment, ohne Werte zu loggen

Wenn ein Token fehlt:

- nicht raten
- nicht aus Chat-History in Logs schreiben
- klar melden, welche Env-Variable fehlt

## 9. Mapbox-Regeln

Koordinatenformat:

- Mapbox nutzt `[longitude, latitude]`
- Nicht `[latitude, longitude]`

Directions API:

- `steps=true`, wenn Maneuver, Silent-Via oder `waypoints`-Verhalten ausgewertet wird.
- `waypoints=0;<lastIndex>` kann genutzt werden, damit Zwischenpunkte als Shaping/Silent-Via wirken und nicht als harte Arrive-Legs.
- `bearings`, `radiuses` und `avoid_maneuver_radius` sind relevant fuer Moving-Start-Qualitaet.
- `overview=simplified` fuer Screening.
- `overview=full` nur fuer finale Top-Kandidaten.

Autobahn-Regel:

- `avoidHighways=true`: Autobahn ist hart verboten.
- `avoidHighways=false`: Autobahn ist erlaubt, aber nicht Pflicht.
- Autobahn AN darf No-Highway-Routen aus Live oder Pool nicht ausschliessen.

## 10. Supabase-Regeln

Supabase ist der einzige Backend-Stack.

Nutze Supabase fuer:

- Auth
- Postgres
- Edge Functions
- Cron
- Realtime
- Storage, falls vorhanden

Bei Supabase-Aufgaben:

- aktuelle Docs pruefen, wenn Unsicherheit besteht
- Remote-Status beweisen, nicht nur lokal testen
- RLS und Service-Role sauber trennen
- Cron/Worker nicht nur deployen, sondern mit Remote-Daten belegen

Wichtige Tabellen:

- `route_regions`
- `route_pool`
- `route_pool_candidates`
- `route_pool_coverage`
- `route_seed_jobs`
- `route_ratings`
- `route_bookmarks`
- `routes`

Bei Remote-Cron/Healing:

- pruefen, ob Jobs wirklich `queued -> running -> completed/cooldown` wechseln
- `mapbox_calls_used` pruefen
- Candidate-/Verified-Inserts beweisen
- nicht behaupten, dass Cron funktioniert, nur weil die Function deployed ist

## 11. Routing: Produktregeln

### Rundkurs

Rundkurs muss:

- beim Start beginnen
- als sauberer Loop wirken
- keine langen Sticharme enthalten
- keine starken Out-and-back-Anteile haben
- keine kaputten U-Turn/Fold-Geometrien enthalten
- bei Autobahn AUS keine Autobahn enthalten
- die gewuenschte Distanz sinnvoll treffen
- bei Search Again echte Variation liefern

Quality-Tiers:

- `ideal`: sehr gut, bevorzugt verified
- `good`: gut, verified-faehig
- `acceptable`: selten erlaubt, als Reserve/Candidate oder testbarer Fallback
- rejected: nie als Erfolg anzeigen

### A nach B

A nach B muss:

- Ziel immer erreichen
- Direct / klein / mittel / gross unterscheidbar machen
- grosse Umwege nicht wie kleine Umwege liefern
- Search Again diversifizieren
- bei Autobahn AUS keine Autobahn verletzen
- direkte Route als ehrliche Option anbieten, wenn Scenic nicht moeglich ist

### Wegpunkte

Wegpunkte muessen:

- klar zwischen Preference-Bereichen und Required-Stops unterscheiden
- keine Pool-/Warmup-Meldung zeigen, wenn User Pflichtstopps erwartet
- bei Required-Stops alle gesetzten Punkte erreichen
- bei Failure spezifischen Wegpunktfehler liefern

## 12. Routenpool, Healing und Curation

Der Routenpool ist Qualitaetsreserve und Beschleuniger, nicht der einzige Routingpfad.

Grundregel:

- Live versuchen, wenn sinnvoll.
- Gute Live-Routen als Candidate speichern.
- Pool nutzen, wenn Live nicht gut genug ist oder gute verified Routen vorhanden sind.
- Healing/Cron baut Luecken automatisch auf.
- Curation sortiert langfristig schlechte Routen aus.

Pool-Zellen muessen getrennt sein nach:

- Land
- Bundesland/Admin
- Region/Cluster
- Route Type
- Distanzbucket
- Stil
- Autobahn-Regel

Aber:

- Bei Autobahn AN sind No-Highway-Routen kompatible Fallbacks.
- Bei Autobahn AUS sind Highway-Routen nie kompatibel.

Promotion:

- verified bevorzugt `ideal/good`
- `acceptable` nur begrenzt und transparent
- schlechte Routen nie verified

Curation:

- Ratings, Completion und wiederholte Nutzung sollen Poolranking beeinflussen.
- Keine Hard Deletes ohne ausdruecklichen Grund.
- Schlechte Routen deprecaten, nicht still verlieren.

## 13. Style-Regeln

Styles muessen messbar unterschiedlich sein.

Sport Mode:

- fluessig
- gute Strassen
- keine kuenstlichen Stubs
- moderate Kurven
- nicht automatisch Bergpassage

Kurvenjagd:

- deutlich kurviger
- Hairpins erlaubt, wenn echte Berg-/Serpentinenkurven
- keine U-Turn-Sticharme
- keine erzwungenen Zickzack-Stubs

Abendrunde:

- ruhiger
- kompakter
- gute Loopness
- weniger aggressiv
- keine harte Sport-Kopie

Entdecker:

- andere Sektoren
- abwechslungsreich
- Search Again muss Richtung/Sektor wechseln
- nicht still dieselbe Route

## 14. UI-/UX-Regeln

Die UI soll hochwertig, dunkel, modern und performant wirken.

Keine Landingpage-Logik in App-Flows:

- User soll direkt arbeiten/fahren/route generieren koennen.

Routing-Fehlertexte:

- spezifisch statt generisch
- ehrlich statt schoengeredet
- keine falschen Budgetmeldungen

Budget-/Limit-Meldung:

- nur bei echtem Mapbox 429, Provider-Limit, Supabase Function-Limit oder explizitem globalem Safety-Cap
- nicht bei normalem NO_ROUTE, thin coverage oder queued healing

Buttons:

- waehrend Loading deaktivieren
- keine Route bestaetigen, wenn Route invalid oder Suche aktiv

Text:

- deutsch
- klar
- keine technischen Interna fuer normale User
- Debug-Meta nur fuer Logs/Tests

## 15. Performance-Regeln

Performance bedeutet hier:

- keine unnoetigen UI-Rebuilds
- keine blockierenden Flutter-Flows
- keine riesigen Payloads im Edge Response
- Mapbox Full Geometry nur fuer finale Kandidaten
- Debug-Meta begrenzen
- keine Endlosschleifen
- Search Again mit echter Variation statt blindem Retry

Aber:

- Qualitaet und Funktionalitaet haben beim Routing Vorrang vor uebertriebener Ressourcenschonung.
- 15-25 Sekunden Suche sind fuer hochwertige Route akzeptabel, wenn UX das sauber zeigt.
- Keine Route ist besser als schlechte Route, aber NO_ROUTE darf nicht der Normalfall sein.

## 16. Tests und Verifikation

Standardchecks:

```bash
flutter analyze lib/
flutter test
git diff --check
```

Supabase/Edge:

```bash
deno check supabase/functions/generate-cruise-route/index.ts
deno check supabase/functions/tools/route_pool_healing_worker.ts
deno check supabase/functions/process-route-seed-jobs/index.ts
```

Je nach Scope:

- gezielte Flutter Tests
- Deno Unit Tests
- Live-Matrix mit Mapbox
- Remote Supabase Smoke
- Handy-Test

Bei Routing nie nur sagen:

- "Tests gruen"

Sondern auch:

- welche Live-Faelle geprueft wurden
- welche Region/Stil/km/Autobahn-Kombination
- source: live/pool/candidate/cache
- quality_tier
- routeFingerprint
- duplicateFallbackUsed
- motorwayViolation
- WORKER_RESOURCE_LIMIT

## 17. Live-Matrix-Regeln

Live-Matrix ist bestanden, wenn:

- keine schlechte Route als Erfolg angezeigt wird
- keine Autobahn bei AUS
- Search Again keine stille Wiederholung der letzten Fingerprints liefert
- Styles unterscheidbar sind
- Pool/Live/Cron-Meta korrekt ist
- NO_ROUTE selten und plausibel ist
- Cron/Healing bei Luecken wirklich Candidates/Verified erzeugt

Live-Matrix ist nicht bestanden, wenn:

- Warmup/NO_ROUTE der Normalfall ist
- Budget-Popup ohne echtes Limit kommt
- Pool keine kompatiblen Routen liefert
- Worker nur Jobs schreibt, aber nie Inserts erzeugt
- eine Route kaputt aussieht, aber als Erfolg gilt

## 18. Umgang mit schwierigen Regionen

Bludenz, Bregenz, Feldkirch und enge Vorarlberg-Tal-/Bergregionen koennen schwer sein.

Trotzdem gilt:

- nicht manuell jede Ortschaft hardcoden
- generische Kandidatenfamilien verbessern
- Silent-Via, Shaping, Bearings und Radiuses nutzen
- Pool und Healing als Lernsystem verwenden
- Hard-Region nur wenn mehrfach bewiesen, nicht als frueher Abbruch

Hard-Region darf User nicht sofort blockieren, wenn Live-Exploration noch moeglich ist.

## 19. Codequalitaet

Prioritaet:

1. Korrektheit
2. Sicherheit und Datenintegritaet
3. Produktverhalten
4. Wartbarkeit
5. Performance
6. Code-Kuerze

Code Smells aktiv melden:

- Copy/Paste-Logik
- riesige Methoden ohne klare Grenzen
- Vermischung von Rundkurs, A nach B und Wegpunkten
- Meta-Felder, die gesetzt aber nie gelesen werden
- Tests, die nur Mocks gruen machen
- Silent Catch ohne Debug-Meta
- DB-Schema-Mismatch

Refactor nur wenn:

- er ein echtes Problem reduziert
- er im Scope liegt
- er testbar ist

## 20. Flutter-Konventionen

- Lokales State Management mit `setState()`.
- Keine neue globale State-Library ohne Freigabe.
- Widgets klein halten, wenn es die Lesbarkeit verbessert.
- Deutsche UI-Texte.
- Englische Variablen- und Methodennamen.
- Keine unnoetigen Animationen, die Performance oder Bedienbarkeit verschlechtern.
- Mobile first pruefen.

## 21. Dart-Konventionen

- immutable Models bevorzugen
- `required` named parameters
- null safety sauber nutzen
- keine broad `dynamic` Nutzung ohne Grund
- keine stillen Fehler schlucken
- Debug-Informationen strukturiert in Meta statt als lose Strings

## 22. TypeScript / Edge-Konventionen

- klare Types fuer Request/Response/Meta
- Mapbox Response nie unkontrolliert in voller Groesse cachen
- keine grossen Debug-Payloads im normalen Response
- fruehe Rejects fuer offensichtlich schlechte Kandidaten
- teure Full-Hydration nur fuer Top-Kandidaten
- Deno Check vor Deploy

## 23. Datenbank- und Migration-Regeln

Vor Migration:

- Remote-/Local-Migration-Historie pruefen
- nicht blind `db push`, wenn Remote-only Migrationen existieren
- RLS-Auswirkungen pruefen
- Service-Role nur serverseitig

Bei Schema-Aenderung:

- Migration erstellen
- Tests/Smoke
- Remote-Anwendung beweisen

Bei Candidate/Pool:

- Insert wirklich remote pruefen
- nicht nur `candidate_inserted=true` aus lokalem Mock glauben

## 24. Fehlerbehandlung

Fehler muessen spezifisch bleiben.

Beispiele:

- `NO_ROUTE`
- `pool_bootstrap_pending`
- `waypoint_route_not_possible`
- `waypoint_quality_too_low`
- `motorway_violation`
- `distance_mismatch`
- `u_turn_geometry`
- `worker_resource_limit`
- `mapbox_429`

User-Text darf vereinfacht sein, aber Meta muss debugfaehig bleiben.

## 25. Antwortstil

Sprache:

- Deutsch, wenn Vucko Deutsch schreibt.
- Direkt und konkret.
- Keine uebertriebene Motivation.
- Keine leeren Versprechen.

Bei Status:

- Was wurde geprueft?
- Was wurde geaendert?
- Was ist bewiesen?
- Was bleibt offen?

Bei roter Matrix:

- Nicht schoenreden.
- Kein Commit/Deploy.
- Exakte Fehlerfaelle nennen.

## 26. Wenn Tools verfuegbar sind

Nutze Tools sinnvoll:

- `rg` fuer Suche
- `git status`, `git diff`, `git log`
- Supabase MCP/CLI fuer Remote-Belege
- Browser/Web fuer aktuelle Mapbox-/Supabase-Doku
- iOS Simulator Tools fuer echte Handy-/Simulator-Flows
- Figma nur fuer Designaufgaben

Nicht benutzen:

- Tools nur fuer Show
- Websuche statt lokalem Code, wenn Code die Wahrheit enthaelt
- Supabase Deploy ohne klare Abnahme

## 27. Abschlussberichte

Ein guter Endreport enthaelt:

1. Scope
2. Root Cause
3. Aenderungen
4. Tests/Checks
5. Live-/Remote-Matrix
6. Commit/Push/Deploy
7. Risiken
8. Handy-Test JA/NEIN
9. naechster kleinster Schritt

Beispiel fuer Routing:

- Region/Stil/km/Autobahn
- Erfolg/Fehler
- source
- quality_tier
- distance
- fingerprint
- duplicateFallbackUsed
- motorwayViolation
- worker/resource status

## 28. Priorisierte Produktziele

Kurzfristig:

- Rundkurs-Zufall stabilisieren
- A nach B Detours stabilisieren
- Wegpunkte als Pflichtstopps/Preference sauber trennen
- Warmup/NO_ROUTE selten und korrekt machen
- Pool/Healing/Cron beweisbar funktionsfaehig machen

Mittelfristig:

- Bewertungsbasierte Pool-Curation
- bessere Regionserkennung
- bessere Style-Differenzierung
- stabiler Handy-Test-Flow
- Premium/Basic Feature-Grenzen

Langfristig:

- CarPlay, falls Apple Developer Voraussetzungen erfuellt sind
- staerkere Offline-/Prepared-Route-Experience
- Community-gestuetzte Routenkuration

## 29. Was niemals passieren darf

- API-Key committen
- schlechte Route als verified speichern
- Autobahn bei AUS akzeptieren
- Ziel bei A nach B verfehlen
- Pflicht-Wegpunkt ignorieren
- roten Live-Test als bestanden melden
- unrelated Dateien committen
- Haupt-Worktree zerstoeren
- Remote deployen, wenn Scope unklar ist

## 30. Kurzer Startablauf fuer neue KI-Session

1. `codex.md` lesen.
2. `AGENTS.md` lesen.
3. `git status --short`.
4. Aufgabe und Scope bestimmen.
5. Relevante Dateien mit `rg` suchen.
6. Erst dann Plan oder Code.

Wenn Routing betroffen ist:

1. Modus klaeren: Rundkurs, A nach B oder Wegpunkte.
2. Client-Pfad in `route_service.dart` lesen.
3. Edge-Pfad lesen.
4. Pool-/Healing-Pfad lesen, falls betroffen.
5. Tests + Live-/Remote-Beweis planen.

## 31. Finaler Leitsatz

CruiseConnect soll nicht nur im Code korrekt aussehen. Es muss auf dem Handy funktionieren. Wenn echte User in Dornbirn, Bregenz, Feldkirch, Bludenz oder in Deutschland / Schweiz und später in ganz europa eine Route suchen, soll die App entweder eine saubere, plausible Route liefern oder ehrlich und selten erklaeren, warum gerade keine Route moeglich ist. Alles andere ist nicht fertig.

## 32. Pflicht-Hinweis fuer jede KI-Session

Vor jeder ernsthaften Analyse, jedem Fix, jedem Prompt und jeder Codeaenderung muessen immer zuerst diese beiden Projektdateien gelesen werden:

1. `AGENTS.md`
2. `codex.md`

Wenn eine Session ohne diese beiden Dateien arbeitet, fehlt ihr der verbindliche Projektkontext. Dann besteht hohes Risiko fuer falschen Scope, falschen Stack, verlorene Architekturregeln, falsche Routing-Annahmen oder ungewollte Commits/Deploys.
