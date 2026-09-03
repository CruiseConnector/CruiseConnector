# Store-Texte für 1.3.1 (technisch 1.5.32+115)

Stand 02.09.2026.

## Wichtig vorab: welchen Zeitraum diese Texte abdecken

Am 02.09. bei Apple nachgefragt, nicht vermutet:

```
curl -s "https://itunes.apple.com/lookup?id=6767208020&country=at"
→ Version 1.3, veröffentlicht 2026-08-26
```

Im App Store liegt also **1.3**, technisch 1.5.28. Die Ausgaben 1.5.29,
1.5.30 und 1.5.31 wurden gebaut, haben den Store aber nie erreicht. Kein
Nutzer hat je ein Blatt mit 1.3.1 oder 1.3.2 gesehen.

Deshalb decken diese Texte **alles seit 1.3** ab und nicht nur die Arbeit
vom 02.09. Wer aus dem Store aktualisiert, springt von 1.3 direkt hierher.

Nebenbefund: In der Datenbank stand als App-Store-Adresse die Kennung
`6749841801`. Die Apple-Suche liefert dafür null Treffer. Da diese Adresse
das Update-Tor benutzt, wären gesperrte iPhone-Nutzer auf eine leere
Store-Seite geschickt worden. Ist auf `6767208020` korrigiert.

---

## App Store, Feld „Neue Funktionen" (max. 4000 Zeichen)

```
Beim Fahren

• Rechts neben der Karte standen bis zu sechs Knöpfe. Jetzt sind es höchstens vier, und in den Einstellungen legst du selbst fest, welche.
• Über den Knöpfen sitzt ein Griff. Einmal tippen und die Karte ist frei, noch einmal tippen und sie sind wieder da.
• Die Lautstärke der Ansage stellst du auf den Prozentpunkt genau ein statt in groben Sprüngen.
• Der Schalter für fremde Meldungen liegt jetzt bei den Punkten auf der Karte.

Routen

• Eine Route von A nach B kommt spürbar schneller. Die Suche hat eine Frist und probiert nicht mehr endlos im Hintergrund weiter.
• Kleiner, mittlerer und großer Umweg lieferten oft gar keine Strecke. Jetzt kommt am Ende immer eine, notfalls eine schlichtere.
• Vorgeschlagene Strecken schicken dich nicht mehr in eine Straße hinein, aus der du sofort wieder herausdrehen musst.
• Ganz Deutschland ist an Bord.

Sicherheit und Privatsphäre

• Startest du vor deiner Wohnung, endet die Strecke nicht mehr genau dort. Das Ziel liegt jetzt ein Stück davor.
• Beim Teilen einer Fahrt bleibt dein Wohnort außen vor.

Community

• Teilst du eine Community, öffnet der Link jetzt die App. Vorher führte er ins Leere. Ohne App kommt eine Seite mit allen Angaben.
• Auf cruiseconnector.at siehst du die öffentlichen Communities und die aktuellen Zahlen.

Behoben

• Nach dem Freischalten eines Abzeichens blieb die App manchmal stehen. Und ein Abzeichen geht nicht mehr verloren.
• Ein Aussetzer der Verbindung konnte Erfahrung, Kilometer, Level oder die Garage leeren. Das kann nicht mehr passieren.
• Eine gefahrene Strecke ließ sich nicht speichern. Jetzt geht es, und Fotos lassen sich nachträglich hinzufügen.
• Verliert das Handy unterwegs die Ortung, zieht die gespeicherte Strecke keine gerade Linie mehr über die Lücke.
• Höchsttempo und Schnitt stimmen. Kopierst du eine Strecke aus einer Community, zeigt sie nicht mehr die Werte der anderen Person.
• Registrieren geht wieder. Anmelden klappt auch mit dem Benutzernamen.
• Die Ankunftszeit stimmt, und die Neuberechnung bleibt nicht mehr hängen.
```

Zeichen: rund 2000. Passt.

---

## Play Store, Feld „Neuerungen" (max. 500 Zeichen)

Das Feld ist streng begrenzt. Deshalb nur das, was man sofort merkt.

```
• Höchstens vier Knöpfe beim Fahren, und du wählst welche. Wegklappen geht auch.
• Lautstärke der Ansage auf den Prozentpunkt genau.
• Routen von A nach B kommen schneller, Umwege finden wieder etwas.
• Keine Strecken mehr, die dich mitten auf der Straße wenden lassen.
• Dein Ziel liegt nicht mehr direkt vor deiner Haustür.
• Geteilte Communities öffnen die App.
• Fahrten, Abzeichen und Garage gehen nicht mehr verloren.
```

Zeichen: 428. Passt unter 500.

---

## Was NICHT in den Text gehört

- Die Serverarbeit (Kontingente, Zwischenspeicher, Datenbankfunktionen).
  Interessiert niemanden, der die App benutzt.
- Die Zahl der behobenen Fehler. „14 Fehler behoben" klingt nach einer App,
  die 14 Fehler hatte.
- Die technische Versionsnummer 1.5.32. Nach außen zählt 1.3.1.
- Alles, was noch nicht wirklich läuft. Der Play Store ist weiterhin in der
  Testphase; der Text verspricht dazu nichts.
