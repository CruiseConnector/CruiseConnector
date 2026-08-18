/// Was sich pro Version geaendert hat — in der Sprache der Fahrer, nicht in
/// der Sprache des Repos.
///
/// 2026-08-09 (vucko): „Nach jedem Update soll ein Update-Log kommen, damit
/// die Leute wissen, was sich getaendert hat." Der Katalog liegt bewusst im
/// Code und nicht in der Datenbank: Ein Update-Hinweis muss auch dann
/// erscheinen, wenn das Handy gerade kein Netz hat.
///
/// PFLEGE: Bei jedem Release oben einen neuen Eintrag ergaenzen. Die Version
/// muss exakt der `version:` aus der pubspec.yaml entsprechen (ohne die
/// Build-Nummer nach dem `+`), sonst findet [AppChangelog.fuerVersion] sie
/// nicht und es erscheint kein Hinweis.
library;

class ChangelogEintrag {
  const ChangelogEintrag({
    required this.version,
    required this.titel,
    required this.punkte,
  });

  /// Marketing-Version ohne Build-Nummer, z. B. `1.5.10`.
  final String version;

  /// Eine Zeile, die den Kern des Updates auf den Punkt bringt.
  final String titel;

  /// Die einzelnen Neuerungen. Kurz, konkret, aus Nutzersicht.
  final List<String> punkte;
}

class AppChangelog {
  AppChangelog._();

  /// Neueste Version zuerst.
  // 2026-08-12 (vucko): „schau auch noch, dass das Update-Popup äöü verwendet
  // und im Satz keine Bindestriche hat."
  //
  // Deshalb hier: echte Umlaute statt ae/oe/ue, echtes ß, und KEINE
  // Gedankenstriche. Wo vorher ein Strich stand, ist der Satz umgeschrieben,
  // nicht nur der Strich ersetzt. Auch zusammengesetzte Wörter kommen ohne
  // Bindestrich aus, soweit die Rechtschreibung das hergibt.
  static const List<ChangelogEintrag> eintraege = <ChangelogEintrag>[
    ChangelogEintrag(
      version: '1.5.16',
      titel: 'Saubere Umwege, Abzeichen mit Stufen, Fahrt läuft weiter',
      punkte: <String>[
        'A nach B: Kleiner, mittlerer und großer Umweg unterscheiden sich '
            'jetzt wirklich. Vorher konnte dieselbe Strecke gleichzeitig als '
            'klein und als mittel durchgehen.',
        'Die Umwege fahren nicht mehr hin und auf derselben Straße zurück. '
            'Die Routenvorschläge kommen jetzt von beiden Seiten des Tals, '
            'nicht nur von einer.',
        'Verfährst du dich, führt dich die App zuerst auf deine Route '
            'zurück und probiert das mehrfach. Erst wenn das nicht klappt, '
            'geht es direkt zum Ziel. Dein gewählter Umweg bleibt dabei '
            'erhalten, auch bei Fahrten mit Zwischenstopps.',
        'Kommst du nach einem App-Wechsel oder einem Neustart zurück, läuft '
            'die Fahrt ohne Antippen weiter. Gruppenfahrten, Touren mit '
            'Stopps und Aufzeichnungen werden jetzt ebenfalls gesichert, '
            'samt Höchstgeschwindigkeit.',
        'Beim Erstellen einer Gruppe bleiben Rundkurs und A nach B sichtbar. '
            'Sie waren unter bestimmten Umständen einfach verschwunden.',
        'Bei Gruppenfahrten dreht sich die Karte nicht mehr grundlos.',
        'Abzeichen haben jetzt Stufen. Kurvenkönig gibt es dreimal, und die '
            'meisten anderen ebenso. Du siehst, wie weit du bis zur nächsten '
            'Stufe bist.',
        'Das Abzeichen für die Gründungszeit wird nur noch einmal verliehen '
            'statt bei jedem Öffnen der Startseite.',
        'Fährst du eine geteilte oder aufgezeichnete Strecke, bringt dich die '
            'App zuerst zum Startpunkt, damit du sie ganz fährst. Bei '
            'Rundkursen steigst du weiterhin dort ein, wo du bist.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.15',
      titel: 'Weiterfahren ohne Klick, schönere Umwege, mehr Abzeichen',
      punkte: <String>[
        'Wechselst du während der Fahrt kurz die App, läuft die Fahrt beim '
            'Zurückkommen einfach weiter. Kein erneutes Starten mehr.',
        'Wurde die App unterwegs vom System beendet, setzt die Fahrt an '
            'deiner Position von selbst fort. Alles bisher Gefahrene zählt '
            'mit, und eine nicht fortgesetzte Fahrt wird im Hintergrund '
            'trotzdem gutgeschrieben.',
        'A nach B mit Umweg: kleiner, mittlerer und großer Umweg sind jetzt '
            'klar unterscheidbar, und die Routen fahren als Schleife statt '
            'zu einem Punkt und wieder zurück.',
        'Kreisverkehre zeigen die richtige Ausfahrt im Symbol, und das '
            'Manöverbanner bleibt nicht mehr an der Einfahrt hängen. '
            'Gespeicherte und geteilte Routen bekommen jetzt volle '
            'Abbiegehinweise.',
        'Weniger unnötige Neuberechnungen, zum Beispiel nach einem Halt an '
            'der Ampel oder im Kreisverkehr.',
        'Die Starter-Aufgaben sind antippbar: Die App bringt dich hin und '
            'zeigt dir an Ort und Stelle, was zu tun ist. Das Strecken-Setup '
            'erklärt sich auf Wunsch Schritt für Schritt.',
        'Vierzehn neue Abzeichen, vom Frühstarter bis zur Community-Stimme. '
            'Gesperrte zeigen, was fehlt, zum Beispiel 274 von 1000 km.',
        'Neu auf der Startseite: die Rangliste mit den Top 3 und deiner '
            'Position, für die Woche und den Monat, klein oder groß.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.14',
      titel: 'Zuverlässiger unterwegs',
      punkte: <String>[
        'Bei A nach B mit Umweg bleibt der Umweg jetzt auch nach einem '
            'Verfahren erhalten. Die Route springt nicht mehr auf den '
            'direkten Weg.',
        'Eine unterbrochene Fahrt macht genau dort weiter, wo du warst. '
            'Gefahrene Kilometer und Zeit zählen weiter, nichts beginnt '
            'mehr bei null.',
        'Gespeicherte und geteilte Routen bekommen einen sauberen Zubringer '
            'zum besten Anschlusspunkt. Die Originalroute bleibt vollständig, '
            'Abkürzungen gibt es nie.',
        'Adressen lassen sich jetzt speichern und stehen bei der Zielsuche '
            'als Schnellzugriff bereit.',
        'Neu für alle: Das kurze Tutorial zum Mitmachen startet einmal '
            'automatisch. Danach warten die Starter-Aufgaben mit dem '
            'Startklar-Abzeichen und einer Woche doppelter XP.',
        'Sieben neue Abzeichen, vom Stammfahrer bis zum Vielfahrer. Antippen '
            'zeigt jetzt zu jedem eine kurze Beschreibung.',
        'Neues Tutorial: kurz, animiert und zum Mitmachen. Wer es abschließt, '
            'bekommt 125 XP.',
        'Ein neues Abzeichen für alle: Gründungszeit, mit dem Datum, seit '
            'wann du dabei bist. Du bekommst es gleich nach dem Update.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.13',
      titel: 'Gruppen, Vorschläge und ein Update, das alle bekommen',
      punkte: <String>[
        'Beim Aufnehmen zieht die App jetzt eine Linie hinter dir her. Du '
            'siehst live, wo du überall warst.',
        'Viele kleine Feinheiten in der Bedienung überarbeitet.',
        'Beim Anlegen einer Gruppe kannst du die Einstellungen wegdrücken und '
            'die Karte im Vollbild ansehen, genau wie in der Fahransicht.',
        'Die Route zeichnet sich nach dem Generieren auf der Karte. Du siehst '
            'sofort, wie sie verläuft.',
        'Die Startzeit ist optional. Ohne Zeit gilt die Ausfahrt als spontan, '
            'und die Auswahl ist ein einziges schönes Blatt statt zweier '
            'Dialoge.',
        'Entdecken schlägt dir deutlich mehr Leute vor: Freunde von Freunden '
            'und Fahrer aus deinem Land. Klickst du jemanden weg, rücken neue '
            'nach.',
        'Kontakte auf dem Startbildschirm führen direkt zu Entdecken, Gruppen '
            'und Events direkt zu den Gruppen. Und die Kacheln lassen sich '
            'jetzt viel leichter treffen.',
        'Bei der Zielsuche stehen die Vorschläge sofort im Blick. Du musst '
            'nicht mehr nach unten scrollen, um eine Adresse anzutippen.',
        'Einen gesetzten Stopp kannst du jetzt auch wieder verschieben oder '
            'einzeln löschen, in der Gruppe wie beim Cruisen.',
        'Nach der Fahrt kannst du sofort eine Gruppe planen oder die Strecke '
            'in der Community teilen.',
        'Das Mitdrehen der Karte ist jetzt standardmäßig aus. Wer es mag, '
            'schaltet es in den Einstellungen unter „Fahransicht“ wieder ein.',
        'Am Ziel beendet sich die Fahrt von selbst, sobald du stehst. Direkt '
            'am Ziel nach wenigen Sekunden, etwas weiter weg nach einer kurzen '
            'Wartezeit. Beim bloßen Vorbeifahren passiert weiterhin nichts.',
        'Beim Wechsel in eine andere App geht die Fahrt nicht mehr verloren. '
            'Ein zweiter Druck auf Fahrt starten kann die Route nicht mehr neu '
            'berechnen, und wenn Android die App doch einmal beendet, kommst '
            'du mit einem einzigen Tipp zurück in die laufende Fahrt.',
        'Wenn du die App bewertest, hilfst du uns enorm. Deshalb fragen wir '
            'nach jeder dritten Runde einmal nach, mehr nicht.',
        'Neu: Nach jedem Update siehst du genau hier, was sich geändert hat.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.12',
      titel: 'Gruppen einrichten wie beim Cruisen',
      punkte: <String>[
        'Beim Anlegen einer Gruppe kannst du die Einstellungen jetzt '
            'wegdrücken und die Karte im Vollbild ansehen, wie in der '
            'Fahransicht.',
        'Die Route zeichnet sich nach dem Generieren auf der Karte. Du siehst '
            'sofort, wie sie verläuft.',
        'Die Startzeit ist optional geworden. Ohne Zeit gilt die Ausfahrt als '
            'spontan, und die Auswahl ist ein einziges schönes Blatt statt '
            'zweier Dialoge.',
        'Kontakte auf dem Startbildschirm führen jetzt direkt zu Entdecken.',
        'Vorschläge sagen dir, warum jemand vorgeschlagen wird.',
        'Nach der Fahrt kannst du sofort eine Gruppe planen oder die Strecke '
            'in der Community teilen.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.11',
      titel: 'Bessere Routen, Gruppenfahrten und Rückmeldungen',
      punkte: <String>[
        'Die Fahrstile liefern wieder wirklich unterschiedliche Routen: '
            'Kurvenjagd sucht die kurvigen Strecken, der Sportmodus die '
            'flüssigen, die Abendrunde die gemütlichen.',
        'A nach B mit Umweg: klein ist rund doppelt so lang wie der direkte '
            'Weg, mittel dreifach, groß vierfach. Aus 20 km werden 40, 60 oder '
            '80 km.',
        'Gruppe einrichten: Die Karte lässt sich jetzt frei bewegen und das '
            'Formular einklappen. So siehst du die Route, bevor ihr losfahrt.',
        'Fahrer und Mitfahrer sind getrennt: Wer als Mitfahrer eingetragen '
            'ist, erscheint nicht mehr als eigenes Auto auf der Karte.',
        'Verfahren in der Gruppe: Statt ratlos stehenzubleiben bekommst du die '
            'Wahl zwischen zurück zur Gruppe, Gruppenroute übernehmen und '
            'eigene Route.',
        'Die Kamera dreht sich während der Gruppenfahrt nicht mehr wild.',
        'Neu in den Einstellungen: Rückmeldung schicken, mit Foto, direkt an '
            'uns.',
        'Kurven werden jetzt überall gleich und genau gezählt.',
      ],
    ),
  ];

  static ChangelogEintrag? fuerVersion(String version) {
    for (final eintrag in eintraege) {
      if (eintrag.version == version) return eintrag;
    }
    return null;
  }
}
