# CruiseConnect Legal-Umsetzungsplan

Arbeitsfassung. Stand: 27. Juni 2026.

Dieser Plan beschreibt, was technisch und organisatorisch umgesetzt werden sollte, damit Nutzungsbedingungen, Datenschutz, Community-Regeln, Events und Meldungen sauber in App und Website eingebunden werden.

## 1. Pflichtseiten auf der Website

Empfohlene URLs:

- `/terms` - Nutzungsbedingungen / AGB
- `/privacy` - Datenschutzerklaerung
- `/imprint` - Impressum / Anbieterkennzeichnung
- `/community-guidelines` - Community-Regeln
- `/event-rules` - Event- und Gruppenfahrt-Regeln
- `/third-party-notices` - Drittanbieter-, Karten-, Lizenz- und Copyright-Hinweise
- `/report` - optionales Webformular fuer Meldungen

Alle Seiten sollten ohne Login erreichbar sein und in App-Store-Eintraegen, App-Settings und Footer verlinkt werden.

## 1a. Website-Testfahrer-Anmeldung

Die eigentliche Website mit Testfahrer-Formular war in diesem Flutter-Repo nicht enthalten. Nach Beschreibung werden dort Name, E-Mail-Adresse und eine Ueber-18-Bestaetigung abgefragt, damit Personen in die Testumgebung eingeladen werden koennen.

Direkt am Formular sollte stehen:

- wer Verantwortlicher ist;
- dass Name, E-Mail und Ueber-18-Bestaetigung nur fuer Testfahrer-Auswahl, Kontakt zur Testphase und Testeinladung verwendet werden;
- dass keine Newsletter- oder Werbenutzung erfolgt, ausser es gibt eine getrennte, freiwillige Einwilligung;
- welche Testplattform oder welcher Dienst fuer Einladungen eingesetzt wird;
- wie lange nicht eingeladene Bewerbungen gespeichert werden;
- wie lange eingeladene Testfahrer-Daten nach Ende der Testphase gespeichert werden;
- wie Nutzer Auskunft, Loeschung oder Widerruf anfordern koennen;
- Link auf Datenschutz, AGB und Impressum.

Empfohlenes Datenmodell:

- `id`
- `name`
- `email`
- `age_confirmed_over_18`
- `signup_source`
- `privacy_version`
- `privacy_acknowledged_at`
- `terms_version`, falls AGB auch fuer die Testanmeldung akzeptiert werden sollen
- `terms_accepted_at`, falls AGB auch fuer die Testanmeldung akzeptiert werden sollen
- `test_invite_status`: `pending`, `invited`, `rejected`, `withdrawn`, `deleted`
- `invited_at`
- `deleted_at`

Keine vorausgewaehlten Checkboxen verwenden. Die Ueber-18-Bestaetigung sollte getrennt von AGB/Datenschutz stehen, damit klar ist, welche Erklaerung welchem Zweck dient.

## 2. E-Mail-Adressen

Empfohlene Postfaecher:

- `support@cruiseconnect.app` fuer allgemeine Hilfe
- `reports@cruiseconnect.app` fuer Meldungen zu Inhalten, Nutzern, Gruppen und Events
- `legal@cruiseconnect.app` fuer rechtliche Anfragen, Behoerdenkontakt und Beschwerden
- `privacy@cruiseconnect.app` oder `datenschutz@cruiseconnect.app` fuer Datenschutzanfragen
- `security@cruiseconnect.app` optional fuer Sicherheitsluecken und Missbrauch

Wichtig: Reports sollten nicht nur als E-Mail existieren. Sie sollten in einer Datenbank mit Status, Bearbeiter, Entscheidung und Audit-Log gespeichert werden.

## 3. Zustimmung bei Registrierung

Bei Registrierung keine vorausgewaehlten Checkboxen verwenden.

Pflicht-Checkboxen:

- "Ich akzeptiere die Nutzungsbedingungen."
- "Ich habe die Datenschutzerklaerung gelesen."

Direkt daneben Links auf `/terms` und `/privacy` setzen. Die Links sollten in einer In-App-WebView oder im Browser oeffnen.

Empfohlenes Datenmodell:

- `user_id`
- `terms_version`
- `terms_accepted_at`
- `privacy_version`
- `privacy_acknowledged_at`
- `accepted_locale`
- `app_version`
- `platform`
- `ip_country` optional, datenschutzrechtlich pruefen

Bei wesentlichen Aenderungen:

- neue Version veroeffentlichen;
- Nutzer beim naechsten App-Start blockierend informieren;
- erneute Zustimmung speichern;
- alte Versionen archivieren.

Wichtig aus dem App-Audit: `welcome_page.dart`, `register_page.dart`, `login_page.dart` und Social-Login-Flows enthalten aktuell keine sichtbare AGB-/Datenschutz-Zustimmung. Das muss vor oeffentlichem Testbetrieb umgesetzt werden. Social Login darf nicht am AGB-Flow vorbeigehen.

Zusatz fuer Testphase:

- Mindestalter oder Ueber-18-Bestaetigung auch in der App pruefen, nicht nur auf der Website;
- bei bestehendem TestFlight-/Beta-Zugang beim ersten App-Start AGB und Datenschutz versioniert akzeptieren lassen;
- bei Social Login nach erfolgreicher Rueckkehr pruefen, ob aktuelle Rechtstexte akzeptiert wurden, sonst blockierender Legal-Screen.

## 4. Links in der App

In den Settings dauerhaft anzeigen:

- Nutzungsbedingungen
- Datenschutzerklaerung
- Impressum
- Community-Regeln
- Event- und Gruppenfahrt-Regeln
- Drittanbieter-Hinweise
- Empfehlungs-/Ranking-Hinweise, falls Feeds oder Vorschlaege personalisiert werden
- Inhalte melden
- Konto loeschen
- Datenschutzanfrage stellen

Auf Eventseiten zusaetzlich:

- Event melden
- Organisator anzeigen
- Event-Regeln anzeigen
- Hinweis: "Von Nutzern organisiert, nicht von CruiseConnect"

Aktueller App-Stand:

- Settings enthalten Hinweise zu Routing, Gruppenfahrt und Hintergrundstandort.
- Settings enthalten noch keine dauerhaften Links auf AGB, Datenschutz, Impressum, Community-Regeln, Event-Regeln, Drittanbieter-Hinweise, Reportformular und Datenschutzanfrage.
- Die bestehende Account-Loeschung ist sichtbar, braucht aber in der Datenschutzerklaerung eine klare Erklaerung zu Restdaten, Reports, Backups und gesetzlichen Aufbewahrungspflichten.

## 5. Event-Erstellung

Beim Erstellen eines Events oder einer Gruppenfahrt sollte vor dem Veroeffentlichen eine eigene Bestaetigung angezeigt werden.

Vorgeschlagener Text:

"Ich erstelle dieses Event eigenverantwortlich. CruiseConnect ist nicht Veranstalter oder Mitveranstalter. Ich bin fuer Inhalt, Organisation, Sicherheit, Genehmigungen, Kommunikation und Einhaltung aller Gesetze selbst verantwortlich."

Pflicht-Checkboxen:

- "Ich akzeptiere die Event- und Gruppenfahrt-Regeln."
- "Dieses Event ist kein Rennen und fordert nicht zu gefaehrlichem oder rechtswidrigem Verhalten auf."
- "Ich habe alle erforderlichen Genehmigungen oder stelle sicher, dass keine erforderlich sind."

Empfohlene Event-Felder:

- Titel
- Beschreibung
- Organisator `user_id`
- Startzeit
- Treffpunkt
- optionale Route
- maximale Teilnehmerzahl
- Sichtbarkeit
- Status: `draft`, `published`, `under_review`, `removed`, `cancelled`
- `event_rules_version`
- `creator_confirmed_at`

## 6. Event-Teilnahme

Vor Teilnahme oder RSVP sollte ein kurzer Hinweis erscheinen:

"Dieses Event wird von Nutzern organisiert, nicht von CruiseConnect. Pruefe selbst, ob Treffpunkt, Route, Fahrzeug, Versicherung, Fahrerlaubnis, Wetter und Verkehrsbedingungen passen. Teilnahme erfolgt auf eigene Verantwortung."

Speichern:

- `user_id`
- `event_id`
- `joined_at`
- `participant_notice_version`
- `participant_confirmed_at`

## 7. Live-Standort und Gruppenfahrt-Hinweise

Vor Aktivierung von Live-Gruppenfahrt, Gruppen-Navigation oder Standortfreigabe sollte klar angezeigt werden:

"In dieser Gruppe koennen andere berechtigte Teilnehmer je nach Funktion deinen Live-Standort, deine Fahrtrichtung, Route oder deinen Fahrtfortschritt sehen. Teile diese Daten nur, wenn du damit einverstanden bist."

Technisch speichern:

- `user_id`
- `group_id`
- `location_sharing_enabled_at`
- `location_notice_version`
- `location_notice_confirmed_at`

Zusatzanforderungen:

- Standortfreigabe jederzeit deaktivierbar machen.
- Sichtbar anzeigen, wann Live-Standort aktiv ist.
- Keine heimliche Hintergrundfreigabe ohne klare Betriebssystem- und App-Hinweise.
- In Datenschutz genau erklaeren, wer welche Standortdaten sehen kann.

## 8. Automatische Event-Risiko-Flags

Events sollten automatisch zur Pruefung markiert werden, wenn Titel, Beschreibung oder Chat Hinweise enthalten auf:

- Rennen, Race, Sprint, illegal, Polizei umgehen
- Driften, Burnout, Blockade, Autobahn-Treffpunkt
- Alkohol, Drogen, Waffen, Gewalt
- sehr grosse Teilnehmerzahl
- private oder sensible Treffpunkte
- wiederholt gemeldete Organisatoren

Ein Flag sollte nicht automatisch loeschen, sondern `under_review` setzen oder Moderatoren benachrichtigen.

## 9. Meldefunktion in der App

Report-Buttons sollten verfuegbar sein fuer:

- Nutzerprofile
- Posts
- Kommentare
- Fotos / Videos
- Chats / Nachrichten
- Gruppen
- Events
- Routen
- Bewertungen

Aktueller App-Stand:

- Reports sind technisch fuer Nutzer, Posts und Kommentare vorhanden (`content_reports` und `submit_content_report`).
- Es fehlt nach Code-Stand ein Report-Pfad fuer Gruppenfahrten, Gruppen, Communitys, Community-Nachrichten, Gruppen-Chat-Nachrichten, Routen, Fahrzeug-/Profilbilder, geteilte Routen, Baustellen-/Gefahrenmeldungen und Bewertungen.
- Die DB-Migration beschreibt Admin-Workflows als spaeteren Aufbau; ein Moderationsdashboard und E-Mail-Alarm sind noch nicht umgesetzt.

Report-Gruende:

- Hass oder Diskriminierung
- Belaestigung oder Bedrohung
- Gewalt oder Gefahr
- Illegales Event oder gefaehrliche Gruppenfahrt
- Datenschutz / private Informationen
- Spam oder Betrug
- Sexuelle Inhalte
- Minderjaehrigenschutz
- Urheberrecht oder Marke
- Falsche Information
- Sonstiges

Report-Datenmodell:

- `id`
- `reporter_user_id`
- `target_type`
- `target_id`
- `reported_user_id`
- `reason`
- `details`
- `evidence_url`
- `status`: `open`, `triaged`, `action_taken`, `rejected`, `appealed`, `closed`
- `priority`: `low`, `normal`, `high`, `urgent`
- `created_at`
- `updated_at`
- `assigned_to`
- `moderator_notes`
- `decision`
- `decision_at`

## 10. Report-Benachrichtigung per E-Mail

Beim Eingang eines Reports sollte eine Serverfunktion:

- den Report speichern;
- Prioritaet berechnen;
- bei `urgent` sofort E-Mail an `reports@cruiseconnect.app` senden;
- bei normalen Reports Sammel-E-Mail oder Dashboard-Eintrag erzeugen;
- keine sensiblen Inhalte unnoetig vollstaendig per E-Mail versenden;
- Link zum Moderationsdashboard senden.

E-Mail-Betreff:

`[CruiseConnect Report] {priority} {target_type} {reason}`

## 11. Moderationsdashboard

Mindestfunktionen:

- Login nur fuer berechtigte Moderatoren;
- Liste offener Reports;
- Filter nach Prioritaet, Grund, Zieltyp und Status;
- Inhalt und Kontext anzeigen;
- Nutzerhistorie anzeigen;
- Entscheidung dokumentieren;
- Massnahmen ausloesen:
  - keine Aktion
  - Inhalt entfernen
  - Event sperren
  - Nutzer warnen
  - Nutzer temporaer sperren
  - Nutzer dauerhaft sperren
  - an rechtliche Stelle eskalieren
- Audit-Log unveraenderbar speichern;
- Beschwerde / Appeal erfassen.

## 12. DSA- und Plattform-Transparenz pruefen

Wenn CruiseConnect als Online-Plattform im Sinne einschlaegiger EU-Regeln einzuordnen ist, sollten diese Punkte geprueft und ggf. umgesetzt werden:

- zentrale Kontaktstelle fuer Nutzer und Behoerden;
- Notice-and-Action-Mechanismus fuer rechtswidrige Inhalte;
- klare Begruendung bei Entfernung, Sperre oder Reichweitenbeschraenkung;
- Beschwerdemoeglichkeit gegen Moderationsentscheidungen;
- internes Moderationsprotokoll mit Audit-Log;
- Transparenzbericht, falls gesetzlich erforderlich;
- Angaben zu den wichtigsten Parametern von Feeds, Rankings und Empfehlungen;
- Kennzeichnung von Werbung oder bezahlter Platzierung;
- Schutz Minderjaehriger bei Werbung, Profiling und Empfehlungen;
- Pruefung, ob Ausnahmen fuer Kleinst- oder Kleinunternehmen greifen.

## 13. Prioritaeten fuer Moderation

Sofort pruefen:

- konkrete Gewaltandrohung
- Gefahr fuer Leib und Leben
- Minderjaehrigenschutz
- illegale Strassenrennen oder gefaehrliche Gruppenfahrten
- Doxing / private Daten
- Selbstgefaehrdung oder Fremdgefaehrdung
- Betrug mit konkretem Schaden

Normale Pruefung:

- Spam
- Beleidigungen
- falsche Angaben
- Urheberrechtshinweise
- unpassende Fotos
- doppelte Inhalte

## 14. Datenschutz-Dokument separat erstellen

Die Datenschutzerklaerung muss getrennt von den AGB erstellt werden.

Sie sollte mindestens abdecken:

- Verantwortlicher
- Kontakt Datenschutz
- Konto- und Profildaten
- Standortdaten und Hintergrundstandort
- Routen, Fahrtdaten und Events
- Fotos, Videos und technische Begleitdaten
- Chats und Gruppen
- Reports und Moderationsdaten
- Push-Benachrichtigungen
- Crash-Logs und Diagnosedaten
- Hosting, Datenbank und technische Dienstleister
- Karten- und Routinganbieter
- Speicherdauer
- Rechtsgrundlagen
- Empfaenger / Drittlaender
- Rechte der Nutzer
- Konto- und Datenloeschung
- Minderjaehrige
- automatisierte Empfehlungen, Feeds und Sicherheitspruefungen
- Live-Standort in Gruppenfahrten
- Rechtsgrundlagen fuer Reports und Moderation
- Testfahrer-Anmeldung auf der Website, inklusive Zweckbindung, Speicherdauer und Testeinladung
- Drittanbieter fuer Auth, Hosting, Datenbank, Push, Karten, Routing, Wetter, Fahrzeugdaten, Testverteilung und Medienverarbeitung

## 15. Impressum

Fuer Website und App sollten Anbieterangaben leicht erreichbar sein:

- Firma / Name
- Rechtsform
- Anschrift
- Kontakt
- Registerdaten
- UID / VAT
- Vertretungsberechtigte Person
- Aufsichtsbehoerde, falls relevant
- weitere Pflichtangaben nach Land und Geschaeftsmodell

## 16. Drittanbieter-Hinweise

Eine separate Seite sollte alle externen Dienste und Lizenzhinweise aufnehmen, die nicht direkt in die AGB gehoeren.

Moegliche Kategorien:

- Karten
- Routing
- Hosting
- Datenbank
- Push
- Auth
- Analyse
- Crash Reporting
- Zahlungen
- Open-Source-Lizenzen

Diese Seite kann technisch und rechtlich detaillierter sein als die AGB.

## 17. Bezahlfunktionen und Widerruf

Vor Einfuehrung bezahlter Funktionen pruefen:

- Bruttopreise, Steuern und Laufzeiten klar anzeigen;
- automatische Verlaengerungen eindeutig erklaeren;
- Kuendigung direkt und einfach in der App ermoeglichen;
- Widerrufsbelehrung und Muster-Widerrufsformular bereitstellen, falls erforderlich;
- Button- und Bestellprozess fuer zahlungspflichtige Vertraege rechtssicher formulieren;
- digitale Inhalte / sofortige Leistungserbringung gesondert bestaetigen lassen, falls Widerruf erloeschen soll;
- App-Store-Regeln fuer In-App-Kaeufe beachten.

## 18. Release-Checkliste

Vor Livegang pruefen:

- AGB anwaltlich geprueft
- Datenschutzerklaerung anwaltlich geprueft
- Impressum final
- Website-Testfahrer-Formular mit eigener Datenschutzinfo und Loeschfrist
- Support- und Legal-E-Mails aktiv
- Report-Mail aktiv
- Report-Dashboard funktionsfaehig
- AGB-Checkbox nicht vorangekreuzt
- Zustimmung versioniert gespeichert
- Social Login blockiert ohne aktuelle AGB-/Datenschutz-Annahme
- Testfahrer akzeptieren AGB/Datenschutz beim ersten App-Start, auch wenn sie ueber Website eingeladen wurden
- Event-Ersteller-Bestaetigung aktiv
- Event-Teilnehmer-Hinweis aktiv
- Live-Standort-Hinweis aktiv, falls Gruppenfahrt-Livefunktionen genutzt werden
- Gruppenfahrt-Hinweise serverseitig/versioniert gespeichert, nicht nur lokal auf dem Geraet
- Settings verlinken alle Rechtstexte
- Report-Buttons fuer alle UGC- und Gruppenbereiche vorhanden
- Reports erzeugen Dashboard-Eintrag und zumindest dringende E-Mail
- Konto-Loeschung auffindbar
- App-Store-URLs fuer Privacy und Support gesetzt
- Drittanbieter-Hinweise vollstaendig
- DSA-/Plattformpflichten geprueft
- Verbraucherstreitbeilegung/ADR-Hinweis final geklaert
- Bezahlfunktionen/Widerruf nur live, wenn rechtlich fertig
