# Fehlerbehebungs-Plan

## Fehler 1: Layout und Banner auf fremden Profilen
**Problem:**
Die Profilseite von anderen Nutzern (`user_profile_page.dart`) sieht anders aus als das eigene Profil (`profile_page.dart`). Der Profil-Banner des Nutzers wird nicht angezeigt, und das generelle Layout (Position des Avatars, Statistiken, Bio mit "mehr"-Funktion) ist nicht konsistent. Statt "Profil bearbeiten" soll dort an gleicher Stelle dynamisch der "Folgst du" / "Folgen" Button sitzen.

**Geplante Implementierungen in `lib/presentation/pages/user_profile_page.dart`:**
1. **Banner laden und anzeigen:**
   - `banner_url` aus den Profil-Statistiken abgreifen.
   - Die `AppBar` zu einer `SliverAppBar` mit `FlexibleSpaceBar` (inklusive ShaderMask und Gradient) umbauen, exakt wie in `profile_page.dart`.
2. **Kopfbereich (Avatar & Button) anpassen:**
   - Avatar unter dem Banner so anordnen, wie bei der eigenen Profilseite.
   - Den `_buildFollowButton(compact: true)` rechts neben den Avatar setzen, an die Position, wo sonst "Profil bearbeiten" steht.
3. **Statistiken und Bio angleichen:**
   - Die Stats-Reihe (Fahrten, Gefahren, Follower, Folgt) exakt so anordnen.
   - Die `_buildBio`-Methode aus `profile_page.dart` übernehmen, sodass lange Bios zusammengeklappt und per Klick auf "mehr" ausgeklappt werden können.
   - Die Garagen-Darstellung (`VehicleGarageCarousel`) auf das exakt gleiche Design heben.

## Fehler 2: Profilbild-Upload schlägt fehl (RLS Policy Error)
**Problem:**
Beim Hochladen eines Profilbildes (Avatar) erscheint der Fehler: `StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)`. Das bedeutet, dass die Supabase Storage Row-Level Security (RLS) Policy für den Bucket `avatars` den Upload (Insert/Update) blockiert. Banner und Auto-Bilder funktionieren hingegen.

**Geplante Implementierungen in Supabase / SQL Migration:**
1. **Storage RLS Policies überprüfen und anpassen:**
   - In Supabase für den Bucket `avatars` sicherstellen, dass authentifizierte User Bilder hochladen, updaten und löschen dürfen, sofern die Datei ihrer eigenen User-ID entspricht (z.B. über `auth.uid()`).
   - Eine SQL-Migration oder Anleitung vorbereiten, um die Policy für den `avatars`-Bucket korrekt zu setzen.

## Fehler 3: Mitgliederverwaltung und Owner-Rechte in Gruppen
**Problem:**
In einer Gruppe kann man aktuell Mitgliedern über ein Stern-Icon die Owner-Rolle geben, aber nicht mehr entziehen. Zusätzlich soll das Dropdown für alle Aktionen in einem 3-Punkte-Menü vereint werden. Der ursprüngliche Ersteller der Gruppe bekommt eine separate Bezeichung ("Ersteller" statt nur "Owner"). Owner sollen zudem wählen können, ob sie Fahrer oder Mitfahrer sind, und man soll auf die Profile der Nutzer gelangen können.

**Geplante Implementierungen in `lib/presentation/pages/group_lobby_page.dart` & `SocialService`:**
1. **Ersteller- und Owner-Rollen anpassen:**
   - Abgleich, ob ein User nur "Owner" ist oder auch der ursprüngliche `created_by`-User in der Datenbank.
   - UI-Anzeige anpassen: Der ursprüngliche Ersteller wird als "Ersteller" markiert, zusätzliche Admins als "Owner".
   - Auch Owner und Ersteller können jederzeit über die UI ihre Fahrer-Rolle (Fahrer / Mitfahrer) verwalten und wechseln. Diese Rollen müssen in der Listenansicht gut erkennbar dargestellt sein.
2. **Mitglieder-Aktionen umbauen (3-Punkte-Menü):**
   - Das bisherige Inline-/Stern-Layout für Rollen entfernen.
   - Bei Tipp auf die 3 Punkte neben einem Mitglied geht ein Menü auf.
   - Optionen im Menü:
     - "Rolle ändern (Fahrer/Mitfahrer)"
     - "Owner geben" (wenn man selbst Owner/Ersteller ist und der andere User normaler Fahrer ist)
     - "Owner wegnehmen" (wenn der andere User bereits Owner ist; Ersteller kann anderen Ownern die Rolle nehmen)
     - "Aus Gruppe kicken"
3. **Profil-Verlinkung & Gruppenlogik:**
   - Bei einem Klick auf das Profilbild eines Mitglieds öffnet sich dessen Profilseite (`UserProfilePage`).
   - Verlassen der Gruppe: Die Gruppe wird erst dann gelöscht, wenn der *letzte* verbleibende Owner (oder Ersteller) die Gruppe verlässt.

## Fehler 4: Abgeschnittene Gruppen-Namen in Listen
**Problem:**
Sowohl in der Community-Ansicht unter "Aktive Gruppen" als auch auf der eigenen und fremden Profilseite im "Gruppen"-Tab werden lange texte abgeschnitten (Ellipsis).

**Geplante Implementierungen in `lib/presentation/pages/community_page.dart` (und ggf. Profil-Tabs):**
1. **Erweiterbare UI für Gruppennamen:**
   - Anstatt den Text starr abzuschneiden, wird eine Interaktion hinzugefügt, um den vollen Namen hervorzuheben also man klickt auf den tab aktive gruppen in der community page diser wird ehrvorgehebt und deswegen auch vollständig gezeigt sollte aber nicht übertieben sein weil man sollt ja auch noch wissen wo feed und wo entdecken ist auf der Profil Seite genau das gleiche.
   - Ideal: Zeige eine kleine Tooltip-ähnliche Box oder fahre den Text aus (`AnimatedSize` / `Text(maxLines: null)` nach Tap), wenn der Name zu lang ist.

## Fehler 5: Privatsphäre-Sperre & Follow-Status Logik
**Problem:**
Private Profile sollen komplett versteckt bleiben, solange man nicht befreundet ist. In der Suche werden die Follow-Statusse (Folgen / Angefragt / Folge ich) nicht korrekt und dynamisch angezeigt.

**Geplante Implementierungen:**
1. **Harte Privatsphäre auf der Profilseite (`user_profile_page.dart`):**
   - Wenn ein Konto privat ist und der Status *nicht* `accepted` lautet, werden **alle** Metadaten (Banner, Bio, Link, Garage, Posts, Follower-Listen) ausgeblendet. Nur Avatar, Handle und der Button ("Angefragt" / "Folgen") bleiben sichtbar.
2. **Follow-Button & Status-Routing (`SocialService` & UI):**
   - Bei Status-Wechsel von `pending` zu `accepted` (via Benachrichtigung oder Anfrage-Seite) ändert sich der Text überall korrekt auf "Folge ich".
   - In Such-Listen (Community/Search) muss der Button sofort den korrekten Zustand anzeigen: "Folgen" (noch nichts), "Angefragt" (Anfrage ausstehend) oder "Folge ich" (bereits befreundet).

## Fehler 6: Benachrichtigungen (Glocke) für Friends & Gruppen
**Problem:**
Es fehlen verschiedene In-App-Benachrichtigungen für soziale Interaktionen und Gruppen-Ereignisse. Follow-Anfragen können teilweise im Tab "Freundschaftsanfragen" angenommen werden, sollen aber auch in den Benachrichtigungs-Verlauf.

**Geplante Implementierungen (`SocialService` & Notifications):**
1. **Follow-Anfragen in der Glocke:**
   - Eintreffende Follow-Anfragen lösen eine Notification aus.
   - Aus der Notification heraus kann direkt über "Annehmen" / "Ablehnen" entschieden werden. Der Status wird sofort geupdatet.
2. **Gruppen-Benachrichtigungen:**
   - Wenn Person A eine *öffentliche* Gruppe erstellt und Person B ihr beidseitig folgt (Follow-Follow/Freund), erhält Person B eine Einladungs- oder Info-Notification.
   - Wenn ein User einer beliebigen Gruppe (privat/öffentlich) beitritt, erhält der *Ersteller* (oder Owner) eine Notification darüber.

## Fehler 7: Absolute Blockier-Konsequenzen
**Problem:**
Das Blockieren eines Nutzers greift nicht tief genug. Blockierte User sehen teilweise noch Profilinhalte.

**Geplante Implementierungen:**
1. **Beidseitige Profil-Sperrung:**
   - Wird ein User blockiert, gilt ein "Mutual Blindness"-Prinzip. Wenn A B blockiert, zieht B's Profil für A und A's Profil für B exakt gleich aus: "Dieser Nutzer hat Sie blockiert" inkl. Platzhalter-Avatar. Weder Banner, Garage noch Statistiken laden.
2. **Keine Erwähnungen (@Mentions):**
   - Blockierte Benutzer können in Posts/Kommentaren nicht mehr per `@` markiert werden bzw. die Markierung verlinkt nicht mehr.
3. **Gruppen-Ausschluss:**
   - Ein User kann die Gruppe eines Users, den er blockiert hat (oder von dem er blockiert wurde), niemals einsehen oder ihr beitreten – nicht über Links, nicht über Gruppen-Codes und nicht über den Feed.

## Fehler 8: Eigene Follower verwalten (Entfernen)
**Problem:**
Man kann User, die einem bereits folgen, nicht aus der eigenen Follower-Liste entfernen.

**Geplante Implementierungen in `profile_page.dart` (Follower-Liste) & `SocialService`:**
1. **Neue UI-Optionen in der Follower-Liste:**
   - In der Listendarstellung der Follower (über `_showFollowList`) wird ein 3-Punkte-Menü bei jedem Follower ergänzt.
   - Optionen: "Follower entfernen" (löst die Follow-Beziehung von deren Seite zu dir auf) und "Blockieren" (kompletter Block, siehe Fehler 7).
2. **Backend-Logik (`SocialService`):**
   - Methode `removeFollower(followerId)` hinzufügen, welche den entsprechenden Datensatz aus der Datenbank löscht, sodass dir diese Person nicht mehr folgt.

## Fehler 9: Echtzeit-Standorte zu langsam
**Problem:**
In Gruppenfahrten aktualisieren sich die Live-Standorte der anderen Nutzer auf der Karte zu langsam/nicht flüssig genug in Echtzeit.

**Geplante Implementierungen:**
1. **Standort-Update-Frequenz optimieren:**
   - Intervalle für Positions-Broadcasts im `LocationService` oder in Gruppenfahrten verringern.
   - supabase Realtime (oder entsprechenden Socket) sicherstellen, dass er auf niedrige Latency konfiguriert ist, damit Cursor flüssig über die Karte ziehen.

## Fehler 10: Routen-Ansicht minimieren & Hintergrund-Navigation
**Problem:**
Wenn der Admin eine Route in der Gruppe startet, werden alle wartenden Mitglieder reingezogen. Man sollte jedoch aus der Navi-Kartenansicht zurück in die Gruppen-Lobby (oder die App) können, während die Live-Locations *im Hintergrund* / als Picture-in-picture (bzw. auf Server-Level) weiterlaufen. Auch App-Wechsel (z.B. zu Spotify) dürfen den Live-Standort nicht unterbrechen.

**Geplante Implementierungen:**
1. **Navigation zur Gruppe zurück (Minimieren & App-Navigation):**
   - In der aktiven Fahr-Ansicht einen "Minimieren"- oder "Zurück"-Button anbieten, ohne stattdessen die komplette Navigation abzubrechen.
   - Man muss nahtlos von der Map-Ansicht in die Gruppen-Lobby und von dort aus weiter in die normale App-Ansicht wechseln können, während die Fahrt/Route im Hintergrund aktiv bleibt. dann kann man reinteoretisch auf die Aktive Gruppe klicken und von dort aus wieder in die Map ansicht zu kommen und dann weil alles im Hintergrund gelaufen ist ganz normal weiterfahren können und für jeden anderen User hat es deinen Live Standort dauerhaft bewegt.
2. **Hintergrund-Standort / Background Execution:**
   - Sicherstellen, dass das Flutter Location-Plugin (z.B. `flutter_background_geolocation` oder `geolocator` im Background Mode) konfiguriert ist.
   - Erfordert iOS/Android Permissions für `Always Allow` bzw. Foreground-Services mit lokaler Notification ("Navigation wird ausgeführt..."), damit die Standorte selbst beim Spotify-Wechsel live bleiben.

## Fehler 11: Map-Marker (Avatare) und Verlassen-Status
**Problem:**
Die Standorte anderer Fahrer in der Gruppen-Navigation sollen individueller erkennbar sein. Außerdem muss klar ersichtlich sein, wenn ein Nutzer die Gruppe verlassen hat, anstatt dass der Standort einfach einfriert oder verschwindet.

**Geplante Implementierungen:**
1. **Benutzerdefinierte Map-Marker:**
   - **Andere Nutzer:** Der Standort-Pin auf der Karte zeigt das jeweilige Profilbild (Avatar) des Nutzers.
   - **Eigener Nutzer:** Der eigene Standort bleibt (wie bisher) als blauer Navigations-Punkt/Pfeil bestehen.
2. **"Verlassen"-Markierung:**
   - Wenn ein Nutzer die aktive Gruppe (oder Navigation) verlässt, bleibt sein letzter bekannter Standort auf der Karte kurzzeitig oder dediziert markiert.
   - Dieser Marker wird dann visuell mit einem roten "X" (oder Ausgegraut mit X) überlagert, um zu signalisieren, dass der Fahrer die Session verlassen hat.

## Fehler 12: Aktive Gruppen-Fahrten hervorheben & Benachrichtigen
**Problem:**
Wenn der Owner eine Fahrt für eine Gruppe startet, ist das in der App-Übersicht für die anderen Mitglieder nicht auffällig genug markiert und es fehlt eine direkte Benachrichtigung.

**Geplante Implementierungen:**
1. **Visuelle Hervorhebung (Animation/Leuchten) der Gruppen-Kachel:**
   - In der Profil- oder Community-Ansicht erhält die Listen-Kachel (Card) der jeweiligen Gruppe einen aktiven, animierten Zustand (z.B. pulsierender Rahmen, "Live"-Badge oder ein leichtes Leuchten), sobald die Route vom Owner gestartet wurde.
2. **Push-/In-App-Benachrichtigung (Glocke):**
   - Sobald die Fahrt losgeht, wird eine Notification an alle Gruppenmitglieder gesendet (zu sehen in der Benachrichtigungs-Glocke und idealerweise als Push).
   - Bei Klick auf die Benachrichtigung gelangt das Mitglied direkt in die aktive Gruppen-/Routen-Ansicht.
