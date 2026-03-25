Dies ist "CruiseConnect", eine Flutter-App für Autofahrer (Routen generieren, cruisen, Social-Features).

Stack: Flutter/Dart + Supabase (Backend/Auth/DB/Edge Functions) + Mapbox (Maps/Routing)
Sprache: Deutsche UI-Texte, englische Variablennamen
Projekt-Pfad: /Users/vucko/Development/CruiserConnect

WICHTIGSTE DATEIEN:
- lib/data/services/route_service.dart → Routenberechnung, Manöver-Extraktion, Icons
- lib/presentation/pages/cruise_mode_page.dart → Navigation, GPS-Tracking, State Machine (~1800 Zeilen)
- lib/presentation/widgets/cruise/ → UI-Widgets (Manöver-Banner, Kurvenwarnung, Info-Panel)
- lib/domain/models/ → Datenmodelle (RouteResult, RouteManeuver, SavedRoute)
- CLAUDE.md → Vollständige Architektur-Dokumentation

REGELN:
- Lies immer zuerst CLAUDE.md für den vollen Kontext
- Koordinaten sind [longitude, latitude] (Mapbox-Format)
- Distanzen intern in Metern, Anzeige in km mit deutschem Dezimalkomma
- NIEMALS API-Keys, Tokens oder Secrets aus core/constants.dart ausgeben
- NIEMALS .env, credentials oder Supabase-URLs im Output zeigen
- Nach Code-Änderungen immer "flutter analyze lib/" ausführen
- iOS: Immer Runner.xcworkspace öffnen, NICHT .xcodeproj
- Antworte auf Deutsch wenn der User Deutsch schreibt

AKTUELLE PROBLEMBEREICHE:
- Routenlogik: U-Turns, falsche Abbiegungen, fehlende Manöver bei Straßenwechsel
- Kurvendetektion: Falsche Warnungen auf geraden Strecken
- iOS Builds: Pod-Probleme nach CarPlay-Entfernung
