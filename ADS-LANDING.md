# Landing-Page-Audit — Cruise Connector

**Geprüft:** https://cruiseconnector.at · App Store AT (id6767208020)
**Datum:** 27.07.2026 · **Prüfer:** ads-landing
**Zweck:** Eignung als Zielseite für bezahlte Werbung (App-Installs)

---

## Gesamtbewertung: **47 / 100**

| Kategorie | Gewicht | Punkte | Beitrag |
|---|---|---|---|
| Message Match | 20 % | 45 | 9,0 |
| CTA-Klarheit | 20 % | 55 | 11,0 |
| Vertrauen & Sozialer Beweis | 15 % | **15** | 2,3 |
| Above the Fold | 15 % | 40 | 6,0 |
| Textqualität | 10 % | 70 | 7,0 |
| Formular & Reibung | 10 % | 55 | 5,5 |
| Mobil | 5 % | 65 | 3,3 |
| Ladegeschwindigkeit | 5 % | 60 | 3,0 |

**Einordnung:** Die Seite ist als Visitenkarte gut, als **Werbe-Zielseite noch nicht bereit**. Drei Befunde kosten bei bezahltem Traffic sofort Geld — sie sind unten als KRITISCH markiert und alle an einem Nachmittag behebbar.

---

## KRITISCH 1 — Die Überschrift steht nie still

**Befund (im Browser gemessen):** Das `<h1>` ist eine Endlos-Schreibmaschine. Drei Messungen im Abstand von 2,5 Sekunden:

```
t=0,0 s   "FINDE DEINE / NÄCHSTE FAHRT"
t=2,5 s   "FINDE DEINE / NÄCHSTE FA"      ← löscht gerade
t=5,5 s   "FINDE DEINE / NÄCHSTE"
```

Screenshots erwischten außerdem „FINDE DEINE **P**" und „FINDE DEINE **BES**". Die Seite tippt Sätze, löscht sie wieder und tippt den nächsten — dauerhaft.

**Warum das bei Werbung teuer ist:** Ein Besucher aus einer Anzeige entscheidet in **1,5–3 Sekunden**, ob er bleibt. In genau diesem Fenster sieht er einen halb gelöschten Satz. Und *Message Match* — die Deckung zwischen Anzeigen- und Seitenüberschrift — ist unmöglich, wenn die Seitenüberschrift ständig wechselt. Das ist mit 20 % die am höchsten gewichtete Kategorie im Raster.

**Behebung:** Die Animation für Besucher aus Kampagnen abschalten und **eine feste Überschrift** setzen, die exakt der Anzeige entspricht.

| | |
|---|---|
| **Vorher** | „FINDE DEINE NÄCHSTE FAHRT" (rotierend, halb sichtbar) |
| **Nachher A** | **„Die kurvigste Straße in deiner Nähe. In 3 Sekunden gefunden."** |
| **Nachher B** | **„Kurvige Rundkurse, die wieder zu Hause enden."** |
| **Nachher C** | **„Google Maps kennt die schnellste Route. Wir die schönste."** |

Variante C ist die stärkste für kalten Traffic — sie benennt den Wettbewerber, den jeder kennt, und dreht ihn um. Sie funktioniert gleichzeitig als Anzeigen-Headline, womit der Message Match automatisch sitzt.

Technisch reicht ein Parameter: bei `?ref=ads` die Rotation überspringen und den festen Text rendern.

---

## KRITISCH 2 — Kein einziger Vertrauensbeleg

**Befund:** Auf der ganzen Seite steht **kein** Nutzer-Zitat, **keine** Bewertung, **keine** Downloadzahl, **keine** Presseerwähnung. Im App Store: „noch nicht genügend Bewertungen oder Rezensionen". Auf der Seite liegen genau **2 Bilder** — bei einer Navigations-App also **keine einzige App-Ansicht**.

**Warum das bei Werbung teuer ist:** Bezahlter Traffic ist kalt. Er kennt dich nicht. Ohne Beleg trägt allein die Behauptung — und die kostet dann eben Geld pro Klick.

**Behebung, in dieser Reihenfolge:**

1. **App-Screenshots über die Falz.** Du hast sie bereits — in `~/Desktop/CruiseConnector_AppStore_Screenshots` und `~/Desktop/CruiseConnector_Insta`. Drei Stück reichen: Routen-Einstellung, gefundene Route auf der Karte, Live-Navigation. Eine Navi-App muss zeigen, wie sie aussieht.
2. **Zahlen statt Adjektive.** Was du belegen kannst: `40–180 km` und `3 Fahrmodi` stehen schon auf der Seite, aber weiter unten. Nach oben ziehen. Dazu, sobald vorhanden: Anzahl generierter Routen, Anzahl Testfahrer.
3. **Erste Bewertungen einsammeln.** 0 Bewertungen im App Store ist derzeit dein größter Hemmschuh — sowohl für die Store-Konversion als auch als Element auf der Seite. Bitte die bestehenden Beta-Fahrer aktiv um eine Bewertung, **bevor** du Werbebudget ausgibst.
4. **Gründer sichtbar machen.** Luca Schachner und David Vuckovic stehen bisher nur im Fußbereich. Zwei echte Namen mit Gesicht schlagen bei einer jungen App jedes Logo-Band.

---

## KRITISCH 3 — Drei gleichwertige Handlungsaufforderungen

**Befund über der Falz, mobil:**

```
[ IM APP STORE LADEN     ]  ← rot, gefüllt
[ ANDROID TESTER WERDEN  ]  ← Umriss, gleiche Größe
[ MEHR ERFAHREN          ]  ← Umriss, gleiche Größe
[ Cookie-Hinweis …       ]  ← verdeckt den Rest der Falz
```

Der rote Knopf hat guten Kontrast, aber zwei gleich große Alternativen direkt darunter zerstreuen die Entscheidung. Der Cookie-Hinweis frisst zusätzlich den unteren Teil des ersten Bildschirms.

**Behebung:**

- **Eine Aktion pro Kampagne.** Wer aus einer iOS-Anzeige kommt, sieht nur „Im App Store laden". Wer aus einer Android-Anzeige kommt, sieht nur „Android-Tester werden". Steuerbar über denselben Parameter wie oben.
- „Mehr erfahren" wird zum Textlink, nicht zum Knopf.
- Knopftext konkreter: statt „Im App Store laden" → **„Kostenlos laden — erste Route in 3 Sekunden"**. Nutzen statt Mechanik.
- Cookie-Hinweis als schmale Leiste am unteren Rand statt als Block über der Falz. Du setzt ohnehin nur technisch notwendige Cookies — das darf klein sein.

---

## Weitere Befunde

### App Store: Sprache steht auf Englisch

Der Eintrag listet unter Sprachen **„English"**, obwohl Titel, Untertitel und die komplette Beschreibung deutsch sind und die Zielgruppe DACH ist. Das kostet Sichtbarkeit in der deutschsprachigen Store-Suche. **In App Store Connect Deutsch als Hauptsprache ergänzen** — kostet nichts, wirkt sofort.

### Die Seite blockt Bots

Ein normaler HTTP-Abruf bekommt **403 Forbidden**; nur ein echter Browser kommt durch. Das betrifft mutmaßlich auch die Vorschau-Crawler von Meta und Google. **Vor der ersten Kampagne prüfen:** Anzeigenvorschau in Meta und Google testen und im Zweifel `facebookexternalhit`, `Googlebot` und `AdsBot-Google` durchlassen. Sonst wird die Anzeige abgelehnt oder ohne Vorschaubild ausgespielt.

### Formular für Android-Tester

Fünf Pflichtangaben: Vorname, Nachname, E-Mail plus zwei Häkchen. Für eine Beta-Anmeldung ist das viel. **Vorname und Nachname zu einem Feld zusammenlegen** oder ganz streichen — für die Play-Store-Einladung brauchst du technisch nur die Google-Mail. Der Hinweis „Nutze bitte die E-Mail deines Google-Kontos" steht *unter* dem Feld; er gehört als Platzhaltertext hinein.

### Was gut ist — nicht anfassen

- **Die Unterzeile ist stark:** „Erlebe die perfekte Route. Egal ob 50km, 100km, Kurvenjagd oder entspannte Abendrunde." Konkret, in der Sprache der Zielgruppe, ohne Marketingfloskeln. Die trägt eine Anzeige.
- **Der Live-Matcher** (Distanz schieben, Modus wählen, Loop verändert sich) ist der beste Teil der Seite — er zeigt das Produkt, statt es zu beschreiben. Er steht aber zu weit unten. **Nach oben, direkt unter die Falz.**
- Der FAQ-Bereich beantwortet echte Fragen, inklusive der zur künftigen Bezahlung. Ehrlich und richtig platziert.
- Rechtliches ist vollständig — Impressum, Datenschutz, AGB, Datenlöschung. Für Meta- und Google-Prüfungen ist das die Pflicht, und die ist erfüllt.

---

## Der neue erste Bildschirm

```
┌──────────────────────────────────────┐
│  Jetzt im App Store · kostenlos      │
│                                      │
│  Google Maps kennt die schnellste    │
│  Route. Wir die schönste.            │  ← fest, nicht animiert
│                                      │
│  Kurvige Rundkurse zwischen 40 und   │
│  180 km, die wieder zu Hause enden.  │
│  Für Auto und Motorrad in DACH.      │
│                                      │
│  [ Kostenlos laden — Route in 3 s ]  │  ← EIN Knopf
│    Mehr erfahren                     │  ← Textlink
│                                      │
│  [App-Screenshot: Karte mit Route]   │  ← Beleg
└──────────────────────────────────────┘
```

---

## Reihenfolge der Umsetzung

| # | Maßnahme | Aufwand | Wirkung |
|---|---|---|---|
| 1 | Feste Überschrift für Kampagnen-Traffic | 1 h | **hoch** |
| 2 | App-Screenshots über die Falz | 1 h | **hoch** |
| 3 | Auf eine Handlungsaufforderung reduzieren | 30 min | **hoch** |
| 4 | Bot-Zugriff für Anzeigen-Crawler prüfen | 30 min | **hoch** (sonst Ablehnung) |
| 5 | Deutsch im App Store ergänzen | 10 min | mittel |
| 6 | Cookie-Hinweis aus der Falz nehmen | 20 min | mittel |
| 7 | Live-Matcher nach oben | 1 h | mittel |
| 8 | Testerformular auf 1 Feld kürzen | 30 min | mittel |
| 9 | Erste App-Store-Bewertungen einsammeln | laufend | **hoch, aber langsam** |

**Empfehlung:** Punkte 1–4 vor der ersten bezahlten Anzeige erledigen. Das hebt die Bewertung von 47 auf geschätzt **68–72** und ist die Grenze, ab der bezahlter Traffic nicht verpufft.

---

## Ehrliche Einschränkungen dieses Audits

- Es gibt **keine echten Zahlen** — keine Konversionsrate, keine Absprungrate, keine Verweildauer. Die Bewertung beruht auf sichtbarer Struktur und Text, nicht auf gemessenem Verhalten.
- Die Ladegeschwindigkeit ist geschätzt, nicht gemessen (kein Lighthouse-Lauf).
- Geprüft wurde die deutsche Fassung bei 375 × 812 px und 1280 × 720 px.
