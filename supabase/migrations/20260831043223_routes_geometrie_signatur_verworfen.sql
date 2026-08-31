-- 2026-08-31 — Ein VERWORFENER Weg, hier festgehalten damit ihn niemand
-- nochmal geht.
--
-- Der Plan war, SavedRoute.routeSignature serverseitig nachzubauen, damit
-- Listen ohne Geometrie auskommen. Zwei Funktionen dafuer waren angelegt
-- (routes_geometrie_punkte, routes_geometrie_signatur) und sind in derselben
-- Nacht wieder entfernt worden.
--
-- GRUND: Postgres rundet die DEZIMALZAHL, Dart den BINAERWERT. Von vierzehn
-- gezielten Faellen liefen zwei auseinander:
--     9.00005     -> Server 9.0001     Dart 9.0000
--     -47.12345   -> Server -47.1235   Dart -47.1234
--     negative Null -> Server 0.0      Dart -0.0
-- Bei rund 3000 Zahlen ueber alle Strecken tritt so ein Gleichstand
-- irgendwann ein. Dann halten zwei identische Strecken einander fuer
-- verschieden, und der Nutzer bekommt eine doppelte Zeile in seiner Sammlung.
--
-- Der tragfaehige Weg braucht die Funktionen nicht: beim Speichern legt
-- _buildExistingRouteInsert in route_fingerprint ENTWEDER den echten
-- Fingerprint ODER genau diese Signatur ab. Der Wert steht also schon in der
-- Datenbank und stammt immer aus demselben Dart-Code. Siehe
-- SavedRoutesService.liegtGleichwertigeStreckeInDerSammlung.

drop function if exists public.routes_geometrie_signatur(jsonb, text, text, double precision);
drop function if exists public.routes_geometrie_punkte(jsonb);
