# CruiseConnect App-Legal-Audit nach Bereichen

Arbeitsfassung. Stand: 27. Juni 2026.

Dies ist keine Rechtsberatung, sondern eine technische und produktbezogene Legal-Checkliste auf Basis des aktuellen App-Repos. Die Website mit Testfahrer-Formular war in diesem Repo nicht enthalten; der Website-Teil basiert auf der Beschreibung: Name, E-Mail und Ueber-18-Bestaetigung werden nur fuer TestFlight-/Beta-Einladungen genutzt.

## Sofort wichtigste Luecken

1. Registrierung und Social Login haben aktuell keine sichtbare AGB-/Datenschutz-Zustimmung.
2. Website-Testfahrer-Anmeldung braucht eine eigene Datenschutzinfo direkt am Formular, inklusive Zweckbindung und Loeschfrist.
3. Gruppenfahrt-Hinweise sind gut formuliert, werden aber nur lokal per SharedPreferences gespeichert. Fuer Nachweisbarkeit braucht es serverseitige, versionierte Akzeptanz.
4. Routing-/Sicherheitshinweise sind ebenfalls nur lokal gespeichert und ohne Checkbox. Fuer Navigation und Gruppenfahrt sollte mindestens die Kernannahme versioniert protokolliert werden.
5. Reports existieren nur fuer Nutzer, Posts und Kommentare. Gruppen, Communitys, Chats, Routen, Bilder, Bewertungen und Gefahrenmeldungen brauchen eigene Report-Pfade.
6. Es gibt noch kein ersichtliches Moderationsdashboard und keine Report-E-Mail-Automation.
7. Settings enthalten Sicherheits-Hinweise, aber keine vollstaendige Legal-Sektion mit AGB, Datenschutz, Impressum, Community-Regeln, Event-Regeln, Drittanbieter-Hinweisen und Datenschutzanfrage.
8. Live-Standort, Gruppenfortschritt, Geschwindigkeit, Routen und Leaderboards muessen in Datenschutz und UI klarer erklaert werden.
9. Route-Sharing, Community-Route-Attachments und externe Shares koennen private Start-/Zielorte verraten. Vor dem Teilen braucht es Warnung oder Privacy-Check.
10. Test-/Debug-Seiten muessen in Produktionsbuilds unzugaenglich sein.

## Website-Testfahrer-Anmeldung

Status nach Beschreibung:

- Website hat bereits AGB.
- Nutzer koennen sich als Testfahrer anmelden.
- Erfasst werden Name, Ueber-18-Bestaetigung und E-Mail-Adresse.
- Zweck ist nur, Personen in TestFlight oder eine andere Testumgebung einzuladen.

Absicherung:

- Direkt am Formular kurzer Datenschutzhinweis: "Wir verwenden deine Angaben nur zur Pruefung und Verwaltung der Testfahrer-Teilnahme und zur Einladung in die Testumgebung."
- Keine Newsletter-/Marketing-Nutzung ohne getrennte freiwillige Einwilligung.
- Pflichtlink auf Datenschutz, AGB und Impressum.
- Ueber-18-Bestaetigung getrennt von AGB/Datenschutz.
- Speicherdauer festlegen: z. B. abgelehnte oder nicht eingeladene Anmeldungen nach X Monaten loeschen; eingeladene Testfahrer nach Ende der Testphase oder X Monate danach loeschen, soweit keine Sicherheits-/Nachweispflichten entgegenstehen.
- Datenweitergabe an Testplattform und technische Dienstleister in der Datenschutzerklaerung nennen.
- Kontakt fuer Loeschung/Auskunft: `privacy@cruiseconnect.app` oder `datenschutz@cruiseconnect.app`.
- Im Backend speichern: verwendete Datenschutzversion, Zeitpunkt, Quelle, Status der Einladung.

## App-Seiten und rechtliche Schutzpunkte

| Bereich / Datei | Was passiert in der App | Absicherung / To-do |
| --- | --- | --- |
| `auth_page.dart` | Leitet je nach Supabase-Session weiter. | Nach Login pruefen, ob aktuelle AGB/Datenschutz akzeptiert wurden. Ohne aktuelle Akzeptanz nicht in die App lassen. |
| `welcome_page.dart` | Einstieg, Konto erstellen, Login, Social Login. | Links auf AGB/Datenschutz sichtbar platzieren. Social Login darf nur starten, wenn Nutzer den Legal-Hinweis gesehen oder bestaetigt hat. |
| `register_page.dart` | Registrierung mit Username, E-Mail, Passwort; Social Login. | Pflicht-Checkboxen fuer AGB und Datenschutz, optional Ueber-18-Bestaetigung. Akzeptanz versioniert in DB speichern. |
| `login_page.dart` | Login, Social Login, E-Mail-Verifizierung erneut senden. | Bei bestehenden Accounts nach Login Legal-Version pruefen. Bei Social Login nach Rueckkehr blockierenden Legal-Screen anzeigen, falls Akzeptanz fehlt. |
| `settings_page.dart` | Privates Konto, Benachrichtigungen, Hinweise, Offline-Karte, Konto loeschen. | Eigene Sektion "Rechtliches": AGB, Datenschutz, Impressum, Community-Regeln, Gruppenfahrt-Regeln, Drittanbieter-Hinweise, Inhalte melden, Datenschutzanfrage. |
| `home_page.dart` / `home_content_page.dart` | Startbereich, Profile, Standort fuer Empfehlungen, Offline-Kartenstart. | Kurz erklaeren, wenn Standort fuer Empfehlungen oder Karten genutzt wird. Datenschutzerklaerung muss Standort, Cache und Empfehlungen abdecken. |
| `community_page.dart` | Feed, Discover, Gruppen, Reports fuer Post/User, Standortnahe Inhalte. | Feed-/Empfehlungsparameter transparent erklaeren. Report-Pfade fuer alle sichtbaren Inhalte anbieten. Standortnahe Discover-Funktionen in Datenschutz aufnehmen. |
| `create_post_page.dart` | Nutzer erstellen Textposts, ggf. mit geteilter Route. | Vor Teilen von Routen warnen, dass Start/Ziel/Verlauf private Orte zeigen koennen. Content-Regeln verlinken. |
| `interactive_post_card.dart`, `post_detail_page.dart`, `liked_posts_page.dart` | Likes, Kommentare, Reposts, Details, Route Attachment. | UGC-Regeln, Report fuer Kommentare/Posts, Hinweis bei Route-Sharing. Kommentar- und Repost-Inhalte moderierbar machen. |
| `profile_page.dart` | Eigenes Profil, Avatar, Banner, Fahrzeuge, externe Links, Posts, Routen, Gruppen. | Hinweis, dass Profilangaben/Fotos/Fahrzeugdaten je nach Sichtbarkeit oeffentlich sein koennen. Rechte an Bildern, Kennzeichen, Gesichtern und externen Links klar regeln. |
| `edit_profile_page.dart` | Profil, Bio, Link, Fahrzeugdaten, Fahrzeugbilder, Uploads. | Vor Uploads Hinweis: nur eigene oder berechtigte Bilder, keine erkennbaren Personen/Kennzeichen/private Orte ohne Berechtigung. Fahrzeugdaten koennen identifizierend sein. |
| `user_profile_page.dart` | Fremdprofile, Folgen, Blockieren, Melden, externe Links. | Report/Block ist vorhanden. Externe Links als Drittinhalte kennzeichnen; Impressum/AGB sollten Verantwortung fuer externe Links regeln. |
| `follow_requests_page.dart`, `blocked_users_page.dart` | Private Accounts, Follow-Requests, Blockliste. | Datenschutz erklaert soziale Beziehungen, Blocklisten, Sichtbarkeit und was beim Blockieren passiert. |
| `community_chats_tab.dart` | Communitys erstellen/joinen/verlassen/loeschen. | Community-Regeln beim Erstellen/Joinen verlinken. Admin-/Owner-Rolle klar: Nutzer verwalten Community, CruiseConnect bleibt Plattform. |
| `community_chat_detail_page.dart` | Community-Chat, Nachrichten, Routenanhaenge, Pins, Mitgliederverwaltung. | Report fuer einzelne Nachrichten und Communitys fehlt. Chat-Regeln und Moderationszugriff bei Meldungen in AGB/Datenschutz erklaeren. |
| `create_group_page.dart` | Gruppenfahrt mit Route, Startpunkt, Uhrzeit, Beschreibung, Sichtbarkeit. | Bestehender Gruppenfahrt-Hinweis ist gut, aber serverseitig speichern: `event_rules_version`, `creator_confirmed_at`, "CruiseConnect ist nicht Veranstalter". |
| `group_lobby_page.dart` | Mitglieder, Rollen, Owner-Rechte, Einladungen, Route starten, Leaderboard. | Vor Beitritt/Start Teilnehmerhinweis speichern. Rollen "Owner/Fahrer/Mitfahrer" nicht als Veranstalterrolle von CruiseConnect missverstehen lassen. |
| `group_chat_page.dart`, `group_chat_panel.dart` | Gruppenchat, Reaktionen, Bearbeiten/Loeschen eigener Nachrichten. | Report fuer Gruppenchat-Nachrichten fehlt. Loeschung ist Soft-Delete; Datenschutz muss erklaeren, ob geloeschte Nachrichten noch moderations-/backupbedingt existieren. |
| `cruise_mode_page.dart` | Navigation, Live-Fahrt, Position, Rerouting, TTS, Baustellen, Gruppenmodus, Fahrtabschluss. | Safety-Hinweis versioniert speichern. Hintergrundstandort, Geschwindigkeit, Route, Live-Standort, TTS und Fahrtmetriken in Datenschutz detailliert erklaeren. |
| `cruise_setup_card.dart` | Routenmodus, Start/Ziel, Wegpunkte, Autobahn, Stil, Adresssuche. | Routen bleiben Vorschlaege. Bei manuellen Wegpunkten und Adresssuche Datenschutz und Drittanbieter/Geocoding abdecken. |
| `routing_onboarding_sheet.dart` | Sicherheits- und Routing-Hinweise, lokal akzeptiert. | Fuer rechtliche Nachweisbarkeit zusaetzlich serverseitige Akzeptanz oder zumindest Account-gebundene Version speichern. |
| `group_safety_notice_sheet.dart` | "Keine Veranstaltung", Eigenverantwortung, kein Rennen, Checkbox. | Inhalt stark; aber nur lokal gespeichert. Beim Erstellen und Beitreten serverseitig speichern. |
| `location_always_notice_sheet.dart` | Erklaert Hintergrundstandort und OS-Berechtigung. | Datenschutzlink ergaenzen. Klar anzeigen, wann Hintergrundstandort aktiv ist und wie Nutzer ihn deaktivieren. |
| `notification_permission_notice_sheet.dart` | Erklaert Push-Mitteilungen. | Push-Token, Nachrichtentypen und Abmeldung in Datenschutzerklaerung aufnehmen. Marketing getrennt behandeln. |
| `ride_detail_page.dart` | Fahrt-/Routendetails, Fotos, Leaderboard, Teilen. | Fotos: Rechte/Einwilligungen/Kennzeichen. Leaderboards: Sichtbarkeit, Opt-out/Privatkonto-Regeln. Teilen kann Standortdaten offenlegen. |
| `saved_route_bookmarks_page.dart` | Routen speichern, umbenennen, loeschen, als Post teilen. | Vor oeffentlichem Teilen Privacy-Warnung. Loeschung: klaeren, was mit geteilten Kopien/Posts passiert. |
| `route_share_page.dart` | Externer Share mit Route/Story/Stickers. | Deutlicher Hinweis: externe Apps verarbeiten nach eigenen Bedingungen; Nutzer prueft, ob Route private Orte enthaelt. |
| `analytics_page.dart` | Statistiken, Leaderboards, Distanz, Routen, XP. | Ranking-Parameter, Sichtbarkeit, Privatkonto-Auswirkung, kein Geldwert von XP/Badges. Datenschutz fuer Fahrstatistiken. |
| `notifications_page.dart` | In-App-Notifications, Deeplinks zu Posts/Gruppen/Routen. | Benachrichtigungstypen und Push-/In-App-Daten in Datenschutz. Abgelaufene Gruppen sauber behandeln. |
| `maplibre_test_page.dart`, `maplibre_local_test.dart` | Testseiten fuer Karten/Offline-Modus. | Fuer Production blockieren oder nur Debug-Build. Testdaten/Drittanbieterzugriffe nicht unbeabsichtigt live ausliefern. |

## Services und Datenbereiche

`auth_service.dart`:

- verarbeitet E-Mail, Passwort, Social Login, Provider-Identitaeten, Account-Loeschung.
- braucht Legal-Acceptance nach Signup/Login und vor Social-Login-Abschluss.
- Datenschutzerklaerung muss Auth-Provider, Verifizierungsmails und Account-Loeschung erklaeren.

`social_service.dart`:

- verarbeitet Posts, Kommentare, Likes, Reposts, Follows, Gruppen, Profile, Fahrzeuge, Uploads, Blocks, Reports.
- AGB muessen UGC-Lizenz, verbotene Inhalte, Moderation, Sperren, Reports und Freistellung abdecken.
- Datenschutz muss soziale Graphen, Sichtbarkeit und Upload-Speicherung abdecken.

`content_reports` / `submit_content_report`:

- aktuell nur `user`, `post`, `comment`.
- erweitern auf `group`, `community`, `community_message`, `group_message`, `route`, `ride_photo`, `profile_asset`, `route_rating`, `construction_report`.
- Dashboard und E-Mail-Alarm ergaenzen.

`cruise_group_service.dart` / Gruppen-Migrations:

- Gruppen haben Mitglieder, Rollen, Live-Status, Startzeit, Route, Startort, Chat und 24h-Loeschung nach Abschluss.
- rechtlich klarstellen: Gruppe/Event wird vom Nutzer organisiert, nicht von CruiseConnect.
- Teilnahme-/Erstellerbestaetigung serverseitig versioniert speichern.

`navigation_progress_socket_service.dart`:

- sendet Positionsdaten ueber Realtime-Kanaele.
- Datenschutz: wer sieht Live-Daten, wann beginnt/endet Sharing, wie genau sind die Daten, wie lange werden sie gespeichert.

`group_chat_service.dart` / `community_chat_service.dart`:

- Chats, Nachrichten, Reaktionen, Loeschen/Bearbeiten.
- Datenschutz: Nachrichteninhalte, geloeschte Nachrichten, Moderationszugriff, Realtime, Aufbewahrung.
- AGB: keine Belaestigung, keine illegalen Absprachen, keine privaten Daten Dritter.

`saved_routes_service.dart`, `route_rating_service.dart`, `route_pool_service.dart`:

- Routen speichern, oeffentlich teilen, bewerten, empfehlen.
- Datenschutz und AGB: Route kann Aufenthaltsorte verraten; Bewertungen/Empfehlungen koennen moderiert und korrigiert werden.

`gamification_service.dart` / `analytics_page.dart`:

- XP, Level, Badges, Leaderboards, Fahrstatistik.
- AGB: kein Geldwert, keine garantierte Verfuegbarkeit, Missbrauch kann zu Korrektur/Sperre fuehren.
- Datenschutz: Rankingdaten, Fahrten, Profilbezug.

`push_notification_service.dart` / `notification_settings_service.dart`:

- Push-Token und Nachrichtentypen.
- Opt-in, Opt-out, Token-Loeschung und Anbieter in Datenschutz dokumentieren.

`offline_map_service.dart`, `map_style_service.dart`, `web/index.html`:

- Tiles, Offline-Cache, Kartendaten, CDN fuer Web-Cropper.
- Drittanbieter-/Lizenzhinweise und Copyright-Hinweise sichtbar machen.

`weather_service.dart`, `vehicle_api_service.dart`, `construction_report_service.dart`:

- Wetter, Fahrzeugdaten, Baustellen-/Gefahrenmeldungen.
- Drittanbieter, Datenqualitaet und "keine Verlaesslichkeitsgarantie" in AGB/Datenschutz.
- Crowd-Meldungen moderier- und reportbar machen.

## Pflichttexte und UI-Hinweise

Registrierung:

> Ich akzeptiere die Nutzungsbedingungen.

> Ich habe die Datenschutzerklaerung gelesen.

Optional, wenn die App nur ab 18 freigegeben werden soll:

> Ich bestaetige, dass ich mindestens 18 Jahre alt bin.

Gruppenfahrt erstellen:

> Ich erstelle diese Gruppenfahrt eigenverantwortlich. CruiseConnect ist nicht Veranstalter oder Mitveranstalter. Ich bin fuer Inhalt, Organisation, Sicherheit, Genehmigungen, Kommunikation und Einhaltung aller Gesetze selbst verantwortlich.

Gruppenfahrt beitreten:

> Diese Gruppenfahrt wird von Nutzern organisiert, nicht von CruiseConnect. Ich pruefe selbst, ob Treffpunkt, Route, Fahrzeug, Versicherung, Fahrerlaubnis, Wetter und Verkehrsbedingungen passen. Teilnahme erfolgt auf eigene Verantwortung.

Route teilen:

> Diese Route kann Orte zeigen, die Rueckschluesse auf dich oder andere zulassen. Pruefe Start, Ziel, Verlauf und Bilder, bevor du sie teilst.

Live-Standort:

> In dieser Gruppe koennen berechtigte Teilnehmer deinen Live-Standort, deine Route und deinen Fahrtfortschritt sehen, solange die Gruppenfahrt aktiv ist.

## Empfohlenes Datenmodell fuer Nachweise

`legal_acceptances`:

- `id`
- `user_id`
- `document_type`: `terms`, `privacy`, `community_guidelines`, `event_rules`, `routing_safety`, `location_notice`
- `document_version`
- `accepted_at`
- `locale`
- `platform`
- `app_version`

`event_group_confirmations`:

- `id`
- `group_id`
- `user_id`
- `role`: `creator`, `participant`
- `event_rules_version`
- `notice_version`
- `confirmed_at`

`reports` Erweiterung:

- `target_type`
- `target_id`
- `reported_user_id`
- `reason`
- `priority`
- `status`
- `decision`
- `decision_at`
- `moderator_id`
- `audit_log`

## Prioritaeten

P0 vor naechstem groesseren Test:

- AGB-/Datenschutz-Checkbox in Registrierung und Social-Login-Flow.
- Website-Testfahrer-Datenschutzhinweis mit Loeschfrist.
- Settings-Legal-Sektion.
- Server-Tabelle fuer Legal-Acceptance.
- Gruppenfahrt-Ersteller- und Teilnehmerbestaetigung serverseitig speichern.
- Report-Erweiterung mindestens fuer Gruppen, Communitys und Chat-Nachrichten.

P1 vor oeffentlichem Launch:

- Moderationsdashboard mit E-Mail-Alarm.
- Datenschutzdokument vollstaendig finalisieren.
- Drittanbieter-Hinweise finalisieren.
- Report-Buttons auf allen UGC-Flaechen.
- Route-Share-Warnung und Live-Standort-Statusanzeige.
- Debug/Testseiten aus Production entfernen.

P2 nach Launch, aber frueh:

- Transparenzseite fuer Ranking-/Empfehlungsparameter.
- Appeal-/Beschwerdeprozess fuer Moderationsentscheidungen.
- Automatische Risiko-Flags fuer Gruppenfahrten.
- Datenschutz-Export oder strukturierter Auskunftsprozess.
