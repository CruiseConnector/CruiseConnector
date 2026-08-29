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
    this.anzeigeName,
    this.schrittTitel,
  });

  /// TECHNISCHE Version ohne Build-Nummer, z. B. `1.5.28`. Muss zeichengleich
  /// mit der `version:` aus der pubspec.yaml sein, sonst findet
  /// [AppChangelog.fuerVersion] den Eintrag nicht und es erscheint kein
  /// Hinweis. Diese Nummer sieht der Nutzer NICHT, wenn [anzeigeName] gesetzt
  /// ist.
  final String version;

  /// 2026-08-26 (vucko): „mache auch noch 1.3 bei den Neuigkeiten in der App,
  /// nicht 1.5.28."
  ///
  /// Was der Nutzer im Update-Blatt liest. Die technische Nummer laeuft
  /// intern weiter (Store, Build-Nummer, Wiedererkennung des Eintrags), nach
  /// aussen zaehlt die Ausgabe. Ohne Angabe wird [version] angezeigt.
  final String? anzeigeName;

  /// Was im Blatt ueber den Punkten steht.
  String get sichtbareVersion => anzeigeName ?? version;

  /// 2026-08-26 (vucko): „ueberall steht Ruhigere Navigation, schau dass die
  /// Titel besser sind."
  ///
  /// Der Versionstitel stand auf JEDEM Schritt gleich — bei sieben Schritten
  /// siebenmal derselbe Satz, waehrend darunter jedes Mal etwas anderes stand.
  /// Jetzt bekommt jeder Schritt seine eigene Ueberschrift. Sie muss so lang
  /// sein wie [punkte]; fehlt sie, bleibt es beim Versionstitel, damit alte
  /// Eintraege unveraendert weiterlaufen.
  final List<String>? schrittTitel;

  /// Ueberschrift fuer Schritt [i].
  String titelFuer(int i) {
    final t = schrittTitel;
    if (t == null || t.length != punkte.length) return titel;
    return t[i];
  }

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
      version: '1.5.30',
      anzeigeName: '1.3.1',
      titel: 'Genauer, privater und ganz Deutschland',
      schrittTitel: <String>[
        'Die Navigation weiß, wo du bist',
        'Kurze Fahrten zählen jetzt',
        'Hinter dir ist vorbei',
        'Die Ankunftszeit stimmt jetzt',
        'Ganz Deutschland an Bord',
        'Meldungen schon vor der Fahrt',
        'Stau weg heißt weg',
        'Teilen ohne Wohnort',
        'Bescheid bei Neuigkeiten',
        'Offline nur mit deinem Ja',
      ],
      punkte: <String>[
        'Startest du nicht am Routenanfang, hängt die Anzeige nicht mehr '
            'fest. Entfernung und Reststrecke stimmen ab dem ersten Meter.',
        'Eine Fahrt zählt ab drei Kilometern, egal wie lang die geplante '
            'Route war. Vorher brauchte eine 100 km Runde volle 20 km.',
        'Die Anweisung blieb manchmal stehen, obwohl du längst abgebogen '
            'warst. Gefahrene Manöver verschwinden jetzt sofort.',
        'Die Fahrzeit war zu zuversichtlich gerechnet, auf langen Strecken '
            'um fast ein Drittel. Jetzt ist sie an echten Fahrten geeicht.',
        'Im Norden Deutschlands kamen keine Routen. Jetzt gibt es Rundkurse '
            'und Strecken im ganzen Land.',
        'Baustellen, Unfälle und Staus siehst du schon vor dem Losfahren '
            'auf der Karte. Der neue Schalter blendet alle Meldungen aus '
            'und ein.',
        'Meldet jemand einen Stau oder Unfall als vorbei, ist er sofort '
            'weg. Baustellen verschwinden erst, wenn es mehrere melden.',
        'Geteilte Fahrten zeigen nur den Streckenverlauf, ohne Karte und '
            'Ortsnamen. Start und Ziel werden gekürzt, dein Zuhause bleibt '
            'privat.',
        'Du bekommst Bescheid, wenn Gefolgte posten und in deinen '
            'Communities geschrieben wird. Die Glocke im Chat schaltet je '
            'Community stumm.',
        'Die Offlinekarte für Österreich, Deutschland und die Schweiz lädt '
            'erst nach deiner Zustimmung. Ohne dein Ja lädt nichts.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.28',
      anzeigeName: '1.3',
      titel: 'Ruhigere Navigation',
      // 2026-08-26 (vucko): Jeder Schritt bekommt seine eigene Ueberschrift.
      // Vorher stand auf allen sieben Schritten derselbe Versionstitel.
      schrittTitel: <String>[
        'Die Ansage bleibt stehen',
        'Keine Neuberechnung ohne Grund',
        'Angekommen ist angekommen',
        'Links und rechts stimmen',
        'Ohne Empfang geht es weiter',
        'Baustellen bleiben sichtbar',
        'Meilensteine fallen auf',
        'Geteilte Runden starten sofort',
      ],
      punkte: <String>[
        'Nach einer Neuberechnung konnte die Ansage minutenlang verschwinden. '
            'Das ist behoben.',
        'Fährst du sauber auf der Strecke, wird nichts mehr neu berechnet. '
            'Auch nicht im Kreisverkehr.',
        'Parkst du neben dem Ziel statt direkt davor, endet die Navigation '
            'jetzt trotzdem.',
        'An engen Gabelungen war die Richtung manchmal vertauscht. '
            'Jetzt stimmt sie.',
        'Ohne Empfang wird alles weiter aufgezeichnet und später vollständig '
            'nachgetragen.',
        'Gemeldete Baustellen verschwinden nicht mehr und werden vorher '
            'angesagt, mit Entfernung.',
        'Marken wie 1.000 km gehen nicht mehr unbemerkt vorbei.',
        'Eine geteilte Runde startet beim ersten Tippen. In der Karte einer '
            'Fahrt kannst du ziehen und zoomen.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.25',
      titel: 'Aufgezeichnete Runden wieder fahrbar, Karte zum Zoomen',
      punkte: <String>[
        'Runden, die jemand aufgezeichnet hat, liessen sich nicht starten. Es '
            'kam nur die Meldung, dass die Route nicht geladen werden kann. '
            'Schuld war eine Lücke in der Aufzeichnung, etwa durch einen '
            'Tunnel oder weil die App kurz im Hintergrund war. Jede fünfte '
            'gespeicherte Route war betroffen.',
        'Das galt überall, nicht nur bei geteilten Runden aus der Community: '
            'auch auf der Startseite, in den Lesezeichen, bei den '
            'Lieblingsrouten im Profil und beim Auswählen einer Route für '
            'eine Gruppenfahrt.',
        'In der Karte einer Fahrt kannst du jetzt ziehen und zoomen und dir '
            'ansehen, wie jemand wirklich gefahren ist.',
        'Beim Höchsttempo stand bei geteilten Fahrten ein Zeichen ohne Wert. '
            'Solche Kacheln bleiben jetzt einfach weg.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.24',
      titel: 'Kreisverkehre ohne Fehlalarm, Kroatien wird erkannt',
      punkte: <String>[
        'Im Kreisverkehr meldete die App bisher, du seist nicht auf der '
            'Strecke, und rechnete sie neu. Das lag an einem Messfehler '
            'genau am Kreisverkehr und nicht daran, wie du gefahren bist. '
            'Eine Neuberechnung kommt jetzt nur noch, wenn du wirklich von '
            'der Strecke abkommst.',
        'Kroatien war der App bisher gar kein Land. Wer in Pula stand, dem '
            'wurde "Route bleibt in Italien" angezeigt. Jetzt steht dort '
            'Kroatien.',
        'Schlimmer war die stille Folge davon: im Landesinneren von Istrien '
            'wurden Runden ab etwa 80 Kilometern abgelehnt, obwohl sie '
            'komplett in Kroatien lagen. Das geht jetzt.',
        'Auch an der slowenischen Küste stimmt das Land nun. Koper und '
            'Piran galten bisher als Italien.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.23',
      titel: 'Umlaute im Namen, Abzeichen nebeneinander, Regionen aus deinem Land',
      punkte: <String>[
        'Dein Benutzername darf jetzt ä, ö, ü und ß enthalten. Vorher hat '
            'das Eingabefeld diese Zeichen schon beim Tippen verschluckt.',
        'Damit sich niemand als jemand anders ausgeben kann, gelten '
            '"müller" und "mueller" als derselbe Name. Ist einer vergeben, '
            'ist der andere belegt.',
        'Wer sich über Google oder Apple angemeldet hat und dessen Name '
            'schon vergeben war, bekam bisher gar kein Profil. Das ist '
            'behoben.',
        'Deine Abzeichen standen wegen eines Rechenfehlers untereinander '
            'statt nebeneinander. Jetzt passen drei in eine Reihe, und die '
            'Sammlung ist beim Aufklappen weniger als halb so lang.',
        'Die Stufe eines Abzeichens ist besser zu erkennen: das Symbol hebt '
            'sich deutlicher vom Hintergrund ab.',
        'Beim Wählen einer Region siehst du nur noch die aus deinem Land. '
            'Bist du in Deutschland, tauchen keine österreichischen '
            'Bundesländer mehr auf.',
        'Als Admin kannst du Fahrzeugart und Region deiner Community jetzt '
            'auch nachträglich ändern, nicht mehr nur beim Erstellen.',
        'Das Abzeichen fürs Onboarding gab es bisher schon für die kurze '
            'Tour. Jetzt bekommst du es erst, wenn du alle zwölf Aufgaben '
            'zum Start erledigt hast.',
        'Die Karte mit deinen ersten Aufgaben bleibt sichtbar, bis wirklich '
            'alles erledigt ist, und zeigt dir deinen Fortschritt.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.22',
      titel: 'Beitreten nur noch bewusst, Abzeichen aufgeräumt, Meldung am Nachmittag',
      punkte: <String>[
        'Ein Tipp auf eine fremde Community hat dich bisher sofort zum '
            'Mitglied gemacht. Jetzt öffnet sich erst eine Vorschau mit Bild, '
            'Beschreibung, Mitgliederzahl und Gründungsdatum, und du '
            'entscheidest selbst.',
        'Communities kannst du jetzt anpinnen. Beim Erstellen legst du fest, '
            'ob sie für Autofahrer, Motorradfahrer oder beide ist und in '
            'welcher Region, und danach kannst du filtern.',
        'Tippst du oben auf den Namen einer Community, siehst du jetzt auch '
            'als normales Mitglied alle Eckdaten. Ändern kann sie weiterhin '
            'nur ein Admin.',
        'Beiträge mit der Einstellung "Nur Follower" erreichen jetzt wirklich '
            'alle deine Follower, auch die, denen du selbst nicht folgst. '
            'Vorher blieben sie bei einseitiger Folge unsichtbar.',
        'Deine Sammlung an Abzeichen war endlos lang. Jetzt sind die Familien '
            'zugeklappt, und du siehst auf einen Blick, woran du gerade bist.',
        'Die Stufe eines Abzeichens erkennst du jetzt auch an der Füllung, '
            'nicht nur am Rand. Dazu zwölf neue Abzeichen für Garage, '
            'Beiträge, Hashtags und Meldungen.',
        'Nachrichten im Chat einer Community kannst du sechs Stunden lang '
            'bearbeiten und wahlweise für alle oder nur für dich löschen.',
        'Die tägliche Meldung zum Wetter kommt jetzt am Nachmittag statt um '
            'acht Uhr früh, jeden Tag zu einer anderen Zeit und mit einem '
            'anderen Text.',
        'Deine Anordnung der Startseite hängt jetzt an deinem Konto und ist '
            'auf einem neuen Handy sofort wieder da.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.21',
      titel: 'Kein Festhängen mehr, Hashtags zeigen wer mitmacht',
      punkte: <String>[
        'Wichtigster Fehler: Der Hinweis "Routing verstehen" konnte sich auf '
            'großen Bildschirmen nicht mehr schließen lassen. Der Knopf gab '
            'erst frei, wenn man bis ans Ende gescrollt hatte, und wenn der '
            'Text ohne Scrollen hineinpasste, ging das nie. Die App wirkte '
            'dann eingefroren. Behoben, und es gibt jetzt immer ein Kreuz '
            'zum Schließen.',
        'Wir haben danach die ganze App durchsucht und fünf weitere Stellen '
            'gefunden, an denen man festsitzen konnte, darunter die '
            'Rechtstexte beim ersten Start. Überall gilt jetzt: es führt '
            'immer ein Weg heraus, auch ohne Netz und ohne Berechtigung.',
        'Konntest du die Rechtstexte nicht öffnen, weil auf deinem Handy '
            'kein Browser erlaubt ist, kamst du nicht in die App. Jetzt '
            'werden drei Wege probiert, und zur Not steht die Adresse zum '
            'Kopieren direkt im Fenster.',
        'Bei einem Hashtag siehst du jetzt, wie viele Leute ihn benutzt '
            'haben. Tippst du die Zahl an, siehst du wer, und wie oft.',
        'Deine Anordnung der Startseite hängt jetzt an deinem Konto. '
            'Meldest du dich auf einem neuen Handy an, sind deine Kacheln '
            'genauso wie vorher.',
        'Fahrzeugmarken: Golf, Polo und ähnliche Modellnamen im alten '
            'Profilfeld gehören jetzt zur richtigen Marke.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.20',
      titel: 'Doppelte XP für alle, Marken sortiert sich, Punkte zeigen was neu ist',
      punkte: <String>[
        'Die Woche mit doppelten XP war bisher für niemanden erreichbar: sie '
            'verlangte eine abgeschlossene Gruppenfahrt, und die hatte in der '
            'ganzen Geschichte der App noch nie jemand geschafft. Jetzt '
            'genügt es, eine Gruppenfahrt zu erstellen.',
        'Die Liste für den Start hat drei neue Aufgaben: ein Auto in die Garage '
            'stellen, drei Abzeichen sammeln und die ersten fünfzig Kilometer '
            'fahren. Acht von elf reichen für die Bonuswoche.',
        'Nach der Fahrt siehst du bei deinen XP jetzt auch, wie lange deine '
            'Bonuswoche noch läuft und auf welchen Multiplikator du morgen '
            'kommst.',
        'Fahrzeugmarken werden zusammengefasst: BMW, Bmw und bmw sind jetzt '
            'dieselbe Marke. Auch Vw und Volkswagen gehören zusammen.',
        'Neu in der Auswertung: eine Übersicht aller Marken in der '
            'Community. Tippst du eine an, siehst du, wer welches Fahrzeug '
            'fährt. Umschaltbar zwischen Autos, Motorrädern und allen.',
        'Kleine Punkte zeigen dir jetzt, wo etwas Neues passiert ist: am '
            'Symbol für Communities, an den einzelnen Reitern und an der '
            'jeweiligen Community. Der Punkt verschwindet erst, wenn du dort '
            'warst, und er merkt sich das über Geräte hinweg.',
        'Communities, die jünger als eine Woche sind, tragen jetzt den '
            'Hinweis "Vor kurzem erstellt". In der Community selbst siehst '
            'du das Gründungsdatum.',
        'Hashtags: Schreibst du ein Wort mit Raute in einen Beitrag, kannst '
            'du danach suchen und findest alles dazu.',
        'Der Filter nach Umkreis bei den Gruppenfahrten merkt sich deine '
            'Einstellung und filtert jetzt schon auf dem Server. Vorher '
            'konnten nahe Gruppen herausfallen, bevor der Filter überhaupt '
            'griff.',
        'Neues Abzeichen für alle, die eine Community gegründet haben.',
        'Wer die Startseite umgebaut und dabei die Kachel "Heute für dich" '
            'entfernt hatte, konnte die Aufgabe "Eine Route speichern" nicht '
            'mehr abschließen. Das ist behoben, und deine eigene Anordnung '
            'bleibt beim Onboarding erhalten.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.19',
      titel: 'Einladungen funktionieren wieder, Communities bekommen ein Gesicht',
      punkte: <String>[
        'Wer zu einer Gruppenfahrt eingeladen wird, kommt jetzt auch hinein. '
            'Bisher zeigte die App "Diese Gruppe ist nicht mehr verfügbar", '
            'obwohl es die Gruppe gab. Das galt für die Glocke, den geteilten '
            'Link und die Meldung am Sperrbildschirm.',
        'Ein Einladungslink geht nicht mehr verloren, wenn du noch kein Konto '
            'hast. Nach dem Anmelden landest du direkt bei der Einladung.',
        'In der Glocke steht jetzt, zu welcher Fahrt du eingeladen wirst, '
            'statt nur "zu einer Gruppe".',
        'Communities haben jetzt ein Bild. Jeder Admin kann es setzen, '
            'ändern und wieder entfernen.',
        'Alle Einstellungen deiner Community an einer Stelle: Bild, Name, '
            'Beschreibung, wer schreiben darf, öffentlich oder privat, '
            'Einladungscode und Mitglieder. Erreichbar über das Menü in der '
            'Übersicht und im Chat.',
        'Stellst du eine Community auf privat, führt ein alter geteilter Link '
            'nicht mehr direkt hinein, sondern schickt dir eine Anfrage, die '
            'du annehmen oder ablehnen kannst.',
        'Vor dem Umschalten zwischen öffentlich und privat fragt die App '
            'jetzt nach. Vorher reichte ein Fehltipp im Menü.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.18',
      titel: 'Gemeldete Baustellen bleiben stehen, Stau erkennt sich selbst',
      punkte: <String>[
        'Meldest du eine Baustelle, bleibt sie jetzt zwei Wochen sichtbar '
            'statt zwölf Stunden. Vorher war deine eigene Meldung schon weg, '
            'wenn du am nächsten Tag wieder dort vorbeigefahren bist.',
        'Eine Meldung ohne festen Standort lebte bisher nur eine Viertelstunde. '
            'Der Standort wird jetzt direkt beim Melden mitgeschickt, damit '
            'deine Meldung von Anfang an voll zählt.',
        'Bestätigt jemand deine Meldung, bleibt sie länger stehen. Melden '
            'mehrere, dass die Stelle frei ist, verschwindet sie früher.',
        'Die Warnung kommt jetzt früh genug: auf der Autobahn rund einen halben '
            'Kilometer vorher statt zweihundert Meter, dazu eine kurze Ansage, '
            'damit du nicht auf den Bildschirm schauen musst.',
        'Gefragt wirst du höchstens dreimal pro Fahrt und nie zweimal zur '
            'gleichen Stelle. Während eines Abbiegemanövers kommt nie eine '
            'Abfrage.',
        'Steht der Verkehr, merkt die App das von selbst und fragt einmal nach. '
            'Eine rote Ampel, eine Ortsdurchfahrt oder eine Pause an der '
            'Tankstelle lösen bewusst nichts aus.',
      ],
    ),
    ChangelogEintrag(
      version: '1.5.17',
      titel: 'Streak verzeiht einen Tag, XP werden nachvollziehbar, Abzeichen in Farbe',
      punkte: <String>[
        'Vergisst du einen Tag zu fahren, ist deine Serie nicht sofort weg. '
            'Erst zwei Tage Pause setzen sie zurück.',
        'Während der Woche mit doppelten XP baust du auf dem doppelten Wert '
            'auf: nach einem Tag 2,1 fach, nach zwei Tagen 2,2 fach und so '
            'weiter. Vergisst du in dieser Woche einen Tag, landest du wieder '
            'bei 2,0 statt ganz unten.',
        'Nach der Fahrt siehst du jetzt, wie deine XP zustande kommen: die '
            'Punkte für die Strecke, dann dein Multiplikator, dann das '
            'Ergebnis. Vorher stand dort eine andere Zahl als die, die '
            'gutgeschrieben wurde.',
        'Abzeichen haben Farben, Formen und Symbole je Stufe: Bronze mit '
            'Flamme, Türkis mit Blitz, Violett mit Funken. Über der Sammlung '
            'siehst du auf einen Blick, wo du überall stehst und was als '
            'nächstes dran ist.',
        'Das Tutorial erklärt jetzt die ganze App, auch Chats, Auswertung, '
            'Profil und Garage sowie das, was nach der Fahrt passiert.',
        'Das Abzeichen Startklar kommt nachträglich an, wenn du die ersten '
            'Aufgaben erledigt hast. Dazu drei neue Aufgaben: dein '
            'erster Beitrag, deine erste abgeschlossene Gruppenfahrt und '
            'deine erste gefahrene Runde.',
      ],
    ),
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
        'Kommst du nach einem Wechsel in eine andere App oder einem Neustart '
            'zurück, läuft die Fahrt ohne Antippen weiter. Gruppenfahrten, Touren mit '
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
        'Deine ersten Aufgaben sind antippbar: Die App bringt dich hin und '
            'zeigt dir an Ort und Stelle, was zu tun ist. Das Einrichten der '
            'Strecke erklärt sich auf Wunsch Schritt für Schritt.',
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
            'automatisch. Danach warten die ersten Aufgaben mit dem '
            'Abzeichen Startklar und einer Woche doppelter XP.',
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
