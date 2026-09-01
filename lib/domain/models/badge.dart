/// Ein Badge das der Nutzer verdienen kann.
class Badge {
  /// 2026-08-14 (vucko Tutorial-Badge): badge_15 „Gründungszeit" bekommt JEDER
  /// registrierte Nutzer. Die Beschreibung trägt den Platzhalter
  /// [membershipDatePlaceholder], den die Renderer zur Anzeige dynamisch mit
  /// dem Beitrittsmonat (profiles.created_at) ersetzen — [Badge.all] bleibt
  /// dadurch const, der Sonderfall lebt in [resolveDescription].
  static const String membershipBadgeId = 'badge_15';

  /// 2026-08-14 (vucko Starter-Paket): badge_16 „Startklar" gibt es zusammen
  /// mit der Doppel-XP-Woche.
  ///
  /// 2026-08-25: Die Schwelle ist ACHT von zwoelf Starter-Aufgaben
  /// (`StarterAufgabenService.aufgabenFuerBoost`) und BLEIBT dort. Sie ist der
  /// Preis fuer die Bonuswoche und muss erreichbar bleiben — gemessen am
  /// 24.08. hatte die frueher unerreichbare Schwelle dazu gefuehrt, dass 0 von
  /// 183 Nutzern den Boost je bekommen haben.
  ///
  /// 2026-08-25, ZWEITE ENTSCHEIDUNG — DIESES ABZEICHEN IST *DIE* BELOHNUNG
  /// DER STARTER-LISTE. Vucko woertlich: „das abzeichen nach dem onboarding
  /// soll startklar heissen und nicht durchgespielt" und „man bekommt ein
  /// badge 1000 XP + noch einen 2 fach boost der 7 Tage lang aktiv ist".
  ///
  /// Es gab zwei Kandidaten fuer denselben Namen, und keiner liess sich
  /// entziehen (`profiles.badges` ist seit dem 06.05. append-only):
  ///
  ///   badge_16 „Startklar"      183 von 202 Profilen — aber ALLE aus der
  ///                             Migration vom 24.08., verdient hat es keiner.
  ///   badge_58 „Durchgespielt"  1 Profil (Vucko), und das noch aus der Zeit,
  ///                             als die Bedingung das Tutorial allein war.
  ///
  /// ENTSCHIEDEN WURDE FUER badge_16, aus drei Gruenden:
  ///  1. Es traegt den Namen, den Vucko verlangt, bereits — badge_58 koennte
  ///     ihn nicht bekommen, ohne dass es zwei „Startklar" gaebe.
  ///  2. Sein Emblem ist der Zuendschluessel (`amber_ignition`). Das ist das
  ///     Bild fuer „jetzt kann es losgehen", nicht fuer „alles abgehakt".
  ///  3. 183 Profile tragen es schon. Haette badge_58 die Belohnung bekommen,
  ///     waere badge_16 fuer 183 Leute ein Abzeichen ohne jede Bedeutung
  ///     geworden — und weggenommen haette man es ihnen trotzdem nicht.
  ///
  /// AN DIESER EINEN BEDINGUNG (`StarterAufgabenService.paketVerdient`)
  /// haengt seit dem 25.08. die GANZE Belohnung, und zwar gemeinsam:
  /// dieses Abzeichen, 1000 XP (`GamificationService.starterPaketBonusXp`)
  /// und sieben Tage doppelte XP. Eine Belohnung fuer eine Sache.
  ///
  /// DIE EHRLICHE ALTLAST: Fuer die 183 Profile aus der Migration ist der
  /// Abzeichen-Teil dieser Belohnung schon ausgegeben. Sie werden die
  /// Verleihung nie sehen, weil `newlyQualifiedBadgeIds` nur meldet, was noch
  /// nicht im Profil steht, und Entziehen verboten ist. Was bei ihnen
  /// ankommt, sind die 1000 XP und die Bonuswoche — gemessen am 25.08. hatte
  /// genau 1 von 202 Profilen ueberhaupt ein `starter_bonus_ende`, der Boost
  /// ist fuer praktisch alle noch offen.
  static const String starterBadgeId = 'badge_16';

  /// 2026-08-24 (Aufgabe 10a, vucko woertlich): „dass community ein enzelnes
  /// badge bekommen [...] und man dafuer bei den analytics ein badge bekommt
  /// aber nur eins das heisst Gruende eine Community wenn man draufklickt und
  /// sonnst nur Community heisst wenn es das nicht schon gibt."
  ///
  /// GEPRUEFT am 24.08.: Ein solches Abzeichen gab es NICHT. „Community-Stimme"
  /// (badge_36) ist etwas anderes, naemlich fuenfzehn geteilte Routen.
  ///
  /// Bewusst OHNE Familie und OHNE Stufe („aber nur eins"): Es gibt kein
  /// „zwei Communities" und kein „zehn Communities", genau wie bei badge_15
  /// und badge_16. Damit landet es im Block „Weitere" der Sammlung, traegt
  /// keine roemische Ziffer und laesst sich nicht zu einer Stufenleiter
  /// ausbauen.
  ///
  /// Die Bedingung liefert die Datenbank, nicht der Client: die RPC
  /// `meine_community_gruendung()` aus Migration 20260824103000. Sie liest
  /// `communities.founder_id` — eine eigene, SCHREIB-EINMALIGE Spalte. Wichtig
  /// und dort ausfuehrlich begruendet: Der GRUENDER ist NICHT dasselbe wie ein
  /// Admin. `community_members.role = 'owner'` ist die Admin-Rolle (gemessen:
  /// 7 Zeilen auf 6 Communities), und `communities.owner_id` wird umgeschrieben,
  /// sobald der Gruender die Community verlaesst. Ueber beide bekaemen mehrere
  /// Leute je Community dieses Abzeichen.
  static const String communityGruenderBadgeId = 'badge_57';

  /// 2026-08-24 (Auftrag vom 24.08., vucko woertlich): „das tutorial bzw. das
  /// onboarding soll einmal pro account absolviert werden und man soll dafuer
  /// auch ein badge bekommen wenn man es abgeschlossen hat wie startklar".
  ///
  /// 2026-08-25, DIE BEDINGUNG WURDE ANGEHOBEN. Vucko woertlich: „es soll
  /// passend sein dafuer weil ich jetzt nur das tutorial bekommen habe und
  /// nicht das onboarding [...] also einfach alle funktionen einmal
  /// durchgetestet haben die es in der app gibt".
  ///
  /// Bis dahin genuegte die EINE Starter-Aufgabe „tutorial", also die Fuehrung
  /// mit den Leuchtkreisen. GEMESSEN am 25.08.: genau ein Profil von 199
  /// traegt badge_58 — und dieses Profil hatte zehn von zwoelf Aufgaben
  /// erledigt, „Einen Hashtag benutzen" und „Eine Gruppenfahrt erstellen"
  /// standen offen. Das Abzeichen sass also am falschen Ereignis.
  ///
  /// AB JETZT: `StarterAufgabenService.alleAufgabenErledigt`, also ALLE
  /// ZWOELF Aufgaben.
  ///
  /// ABGRENZUNG ZU badge_16 „Startklar" — die beiden messen seitdem klar
  /// Verschiedenes, statt fast dasselbe:
  ///
  ///   badge_16 = ACHT von zwoelf (`aufgabenFuerBoost`). Die Boost-Schwelle,
  ///              zusammen mit der Doppel-XP-Woche.
  ///   badge_58 = ZWOELF von zwoelf. Die vollstaendige Liste.
  ///
  /// badge_58 ist damit das SPAETERE der beiden und nicht mehr das fruehere.
  ///
  /// 2026-08-25, ABENDS — DIESES ABZEICHEN IST NICHT DIE BELOHNUNG.
  ///
  /// Vucko: „das abzeichen nach dem onboarding soll startklar heissen und
  /// nicht durchgespielt." Die Belohnung der Starter-Liste ist ab jetzt
  /// ausschliesslich [starterBadgeId] „Startklar", zusammen mit 1000 XP und
  /// der Doppel-XP-Woche. badge_58 bekommt davon NICHTS: keine XP, keine
  /// Bonuswoche, und der Belohnungskasten der Karte nennt es nicht.
  ///
  /// Es bleibt trotzdem stehen, und zwar mit voller Absicht:
  ///  * Streichen wuerde es seinem einen Traeger WEGNEHMEN.
  ///    `GamificationService.normalizeBadgeIds` verwirft jede Kennung, die
  ///    nicht in [all] steht, und schreibt die bereinigte Liste beim naechsten
  ///    Sync ins Profil zurueck. Der Eintrag waere nicht nur unsichtbar,
  ///    sondern weg.
  ///  * Ohne Bedingung waere es ein Abzeichen, das 201 von 202 Profilen fuer
  ///    immer gesperrt sehen. Die Sammlung zeigt „x von N freigeschaltet";
  ///    N ist dann nie erreichbar.
  ///  * Und die letzten vier Aufgaben der Liste brauchen ein Ziel. Die
  ///    Belohnung faellt bei acht — was danach kommt, waere sonst unbezahlte
  ///    Restarbeit.
  ///
  /// Damit messen die beiden endgueltig Verschiedenes, statt fast dasselbe:
  /// badge_16 ist ein BELOHNUNGSPAKET bei acht, badge_58 ein reines
  /// Sammler-Abzeichen bei zwoelf.
  ///
  /// WARUM DIE BELOHNUNG NICHT AUF ZWOELF GEHT — die Zahl, die es entscheidet.
  /// GEMESSEN am 25.08. ueber alle 202 Profile, nur die acht serverseitig
  /// ableitbaren Aufgaben: ein Beitrag 9, ein Hashtag 0 (in Worten: null),
  /// eine beendete Fahrt 18, eine Gruppenfahrt 1, ein Auto in der Garage 66,
  /// eine gespeicherte Route 19, drei Abzeichen 6, fuenfzig Kilometer 9 —
  /// und alle acht zusammen: 0. Eine Belohnung bei zwoelf waere heute fuer
  /// niemanden erreichbar. Genau dieser Fehler hat am 24.08. dazu gefuehrt,
  /// dass 0 von 183 Nutzern den Boost je bekommen haben. Er wird hier nicht
  /// wiederholt.
  ///
  /// BESTANDSSCHUTZ: Wer badge_58 heute schon traegt, behaelt es.
  /// `profiles.badges` ist seit dem 06.05. append-only (Waechter
  /// `preserve_profile_badges`), ein Entziehen waere ein Bruch dieses
  /// Schutzes. Ab jetzt verdient man es haerter.
  ///
  /// Der Abschluss selbst liegt seit Migration 20260824150000 am KONTO
  /// (`profiles`), nicht mehr nur in den SharedPreferences. Diese Datei legt
  /// nur den Katalog-Eintrag an; vergeben wird er an der Serverseite.
  static const String alleAufgabenBadgeId = 'badge_58';

  /// 2026-08-25: Der alte Name dieser Kennung.
  ///
  /// Er hat gelogen, und genau darueber ist Vucko gestolpert: „das abzeichen
  /// nach dem onboarding soll startklar heissen und nicht durchgespielt."
  /// Das Abzeichen NACH dem Onboarding ist [starterBadgeId] „Startklar". Was
  /// hier haengt, ist das Sammler-Abzeichen fuer alle zwoelf Aufgaben.
  ///
  /// Der alte Name bleibt als Alias stehen, damit die Startseiten-Karte
  /// weiterlaeuft, waehrend sie umgebaut wird. Neuer Code nimmt
  /// [alleAufgabenBadgeId].
  static const String onboardingBadgeId = alleAufgabenBadgeId;
  static const String membershipDatePlaceholder = '{datum}';


  const Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.category,
    this.assetPath,
    this.familie,
    this.stufe = 0,
  });

  final String id;
  final String name;
  final String description;
  final String emoji;
  final String category;
  final String? assetPath;

  /// 2026-08-18 (Aufgabe 4.2, vucko Sprachnachricht 09 vom 16.08.):
  /// „Mehrstufige Badges, das heisst, Kurvenkoenig gibt es drei Stufen, und von
  /// den anderen Badges auch."
  ///
  /// Schluessel der Familie, zu der dieses Badge gehoert (z. B. 'kurven').
  /// null = gehoert zu keiner Familie (Gruendungszeit, Startklar).
  ///
  /// GRUNDREGEL: Bestehende IDs und ihre Schwellwerte wurden NIE geaendert,
  /// nur gruppiert. Eine neue Stufe ist immer eine NEUE ID. Dadurch braucht es
  /// keine Datenmigration und `profiles.badges` bleibt zeichengleich gueltig.
  final String? familie;

  /// 1, 2 oder 3 innerhalb der Familie. 0 = stufenlos (Meilenstein ohne
  /// Rangfolge, z. B. Level 100 oder Stilbewusst).
  final int stufe;

  /// Alle aktuell verfügbaren Badges.
  ///
  /// Badge 02 ersetzt das alte `01_first_drive`-Achievement. Badge 01 ist
  /// jetzt der Level-10-Meilenstein.
  static const List<Badge> all = [
    Badge(
      id: 'badge_01',
      name: 'Level 10',
      description: 'Erreiche Level 10.',
      emoji: '\u{1F680}',
      category: 'level',
      familie: 'level',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_01_level_bronze.png',
    ),
    Badge(
      id: 'badge_02',
      name: 'Erste Fahrt',
      description: 'Fahre deine erste Route bis zum Ende.',
      emoji: '\u{1F3C1}',
      category: 'routes',
      familie: 'fahrten',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_02_strasse_bronze.png',
    ),
    Badge(
      id: 'badge_03',
      name: 'Level 25',
      description: 'Erreiche Level 25.',
      emoji: '\u{1F6E1}\uFE0F',
      category: 'level',
      familie: 'level',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_03_level_silber.png',
    ),
    Badge(
      id: 'badge_04',
      name: 'Gruppen-Finisher',
      description: 'Schließe deine erste gestartete Gruppenfahrt komplett ab.',
      emoji: '\u{1F465}',
      category: 'groups',
      familie: 'gruppenfahrt',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_04_turbo_bronze.png',
    ),
    Badge(
      id: 'badge_05',
      name: 'Erster Routenpost',
      description: 'Poste deine erste Route.',
      emoji: '\u{1F4E3}',
      category: 'social',
      familie: 'geteilt',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_05_pin_bronze.png',
    ),
    Badge(
      id: 'badge_06',
      name: '500 km',
      description: 'Fahre insgesamt 500 km.',
      emoji: '\u{1F30D}',
      category: 'distance',
      familie: 'distanz',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_06_lenkrad_bronze.png',
    ),
    Badge(
      id: 'badge_07',
      name: 'Gründe eine Gruppe',
      description: 'Erstelle deine erste öffentliche oder private Gruppe.',
      emoji: '\u{1F91D}',
      category: 'groups',
      familie: 'gegruendet',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_07_fahne_bronze.png',
    ),
    Badge(
      id: 'badge_08',
      name: 'Level 50',
      description: 'Erreiche Level 50.',
      emoji: '\u{1F3C5}',
      category: 'level',
      familie: 'level',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_08_level_gold.png',
    ),
    Badge(
      id: 'badge_09',
      name: '5 Routen gespeichert',
      description: 'Speichere 5 verschiedene Routen.',
      emoji: '\u{1F5FA}\uFE0F',
      category: 'saved',
      familie: 'gespeichert',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_09_lesezeichen_bronze.png',
    ),
    Badge(
      id: 'badge_10',
      name: '2.500 km',
      description: 'Fahre insgesamt 2.500 km.',
      emoji: '\u{1F3C6}',
      category: 'distance',
      familie: 'distanz',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_10_lenkrad_silber.png',
    ),
    Badge(
      id: 'badge_13',
      name: '10.000 km',
      description: 'Fahre insgesamt 10.000 km.',
      emoji: '\u{1F451}',
      category: 'distance',
      familie: 'distanz',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_13_lenkrad_gold.png',
    ),
    Badge(
      id: 'badge_14',
      name: 'Level 100',
      description: 'Erreiche das maximale Level 100.',
      emoji: '\u{1F48E}',
      category: 'level',
      familie: 'level',
      assetPath: 'lib/images/badges/badge_14_level100_pokal_diamant.png',
    ),
    // 2026-08-14 (vucko Tutorial-Badge): Mitgliedschafts-Badge für alle.
    // Asset: badge_12 (Gold-Zielflagge) war eine ungenutzte Lücke in der
    // Bildserie und dient hier als Platzhalter, bis ein eigenes Bild kommt.
    Badge(
      id: membershipBadgeId,
      name: 'Gründungszeit',
      description: 'Dabei seit $membershipDatePlaceholder.',
      emoji: '\u{1F31F}',
      category: 'membership',
      assetPath: 'lib/images/badges/badge_15_gruendungszeit_aurora.png',
    ),
    // 2026-08-14 (vucko Starter-Paket): Belohnung fuer die Starter-Aufgaben.
    //
    // 2026-08-25: „Alle Starter-Aufgaben erledigt" war falsch — badge_16 haengt
    // an ACHT von zwoelf (StarterAufgabenService.aufgabenFuerBoost), und seit
    // heute gehoert „alle zwoelf" badge_58. Zwei Abzeichen mit demselben Text
    // waeren genau die Verwechslung, die den Auftrag ausgeloest hat.
    Badge(
      id: starterBadgeId,
      name: 'Startklar',
      description:
          'Die wichtigsten Starter-Aufgaben erledigt. Dein Einstieg ist '
          'geschafft.',
      emoji: '\u{1F511}',
      category: 'membership',
      assetPath: 'lib/images/badges/badge_16_startklar_aurora.png',
    ),
    // 2026-08-15 (vucko): „erstelle mit unserem Layout noch viel weitere
    // Badges, die passend sind." Sechs neue Stufen, alle aus Daten
    // berechenbar, die calculateAndSync ohnehin schon laedt. Die Embleme sind
    // stilechte Farbvarianten der bestehenden Bildserie (der Bild-Dienst hat
    // aktuell kein Guthaben fuer frische Motive; Austausch spaeter = nur den
    // assetPath ersetzen).
    Badge(
      id: 'badge_17',
      name: 'Stammfahrer',
      description: 'Zehn Fahrten bis zum Ende gebracht. Du bist angekommen.',
      emoji: '\u{1F698}',
      category: 'routes',
      familie: 'fahrten',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_17_strasse_silber.png',
    ),
    Badge(
      id: 'badge_18',
      name: 'Dauerbrenner',
      description: 'Fünfzig abgeschlossene Fahrten. Das ist kein Hobby mehr.',
      emoji: '\u{2699}\uFE0F',
      category: 'routes',
      familie: 'fahrten',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_18_strasse_gold.png',
    ),
    Badge(
      id: 'badge_19',
      name: 'Konvoi-Kapitän',
      description:
          'Fünf Gruppenfahrten gemeinsam beendet. Auf dich ist Verlass.',
      emoji: '\u{1F697}',
      category: 'groups',
      familie: 'gruppenfahrt',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_19_turbo_silber.png',
    ),
    Badge(
      id: 'badge_20',
      name: 'Langstrecke',
      description:
          'Über 100 Kilometer in einer einzigen Fahrt. Respekt.',
      emoji: '\u{1F6E3}\uFE0F',
      category: 'distance',
      familie: 'langstrecke',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_20_langstrecke_bronze.png',
    ),
    Badge(
      id: 'badge_21',
      name: 'Streckenscout',
      description:
          'Fünf Routen mit der Community geteilt. Andere fahren deine Wege.',
      emoji: '\u{1F4CD}',
      category: 'social',
      familie: 'geteilt',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_21_pin_silber.png',
    ),
    Badge(
      id: 'badge_22',
      name: 'Vielfahrer',
      description:
          'Fünfundzwanzig Stunden hinterm Steuer. Die Straße kennt dich.',
      emoji: '\u{23F1}',
      category: 'distance',
      familie: 'stunden',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_22_uhr_silber.png',
    ),
    // 2026-08-16 (vucko Testfahrt T6): „die Badges sollen mehr werden" —
    // vierzehn weitere Stufen, alle aus Fahrt-Sessions und Zaehlern
    // berechenbar, die calculateAndSync ohnehin laedt. Fortschritt zu jedem
    // in [badgeFortschrittFuer]. Embleme wieder als stilechte Farbvarianten
    // der Bildserie (Austausch spaeter = nur den assetPath ersetzen).
    Badge(
      id: 'badge_23',
      name: 'Frühstarter',
      description:
          'Eine Fahrt vor acht Uhr morgens gestartet. Die Straßen gehören dir.',
      emoji: '\u{1F305}',
      category: 'routes',
      familie: 'frueh',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_23_frueh_bronze.png',
    ),
    Badge(
      id: 'badge_24',
      name: 'Nachtschwärmer',
      description: 'Nach 22 Uhr noch unterwegs. Die Nacht ist deine Strecke.',
      emoji: '\u{1F319}',
      category: 'routes',
      familie: 'nacht',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_24_nacht_bronze.png',
    ),
    Badge(
      id: 'badge_25',
      name: 'Wochenendfahrer',
      description: 'Fünf Fahrten am Wochenende. Samstag ist Cruise-Tag.',
      emoji: '\u{1F4C6}',
      category: 'routes',
      familie: 'wochenende',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_25_wochenende_bronze.png',
    ),
    Badge(
      id: 'badge_26',
      name: 'Serienfahrer',
      description: 'Sieben Tage in Folge gefahren. Das nennt man Gewohnheit.',
      emoji: '\u{1F525}',
      category: 'routes',
      familie: 'serie',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_26_serie_silber.png',
    ),
    Badge(
      id: 'badge_27',
      name: 'Kurvenkönig',
      description: 'Zehn Kurvenjagd-Fahrten bis zum Ende. Kein Bogen zu eng.',
      emoji: '\u{1F3CE}',
      category: 'routes',
      familie: 'kurven',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_27_kurven_silber.png',
    ),
    Badge(
      id: 'badge_28',
      name: 'Stilbewusst',
      description:
          'Alle vier Stile gefahren: Kurvenjagd, Sport Mode, Abendrunde und '
          'Entdecker.',
      emoji: '\u{1F3A8}',
      category: 'routes',
      familie: 'stile',
      assetPath: 'lib/images/badges/badge_28_stilbewusst_aurora.png',
    ),
    Badge(
      id: 'badge_29',
      name: 'Rundkurs-Fan',
      description: 'Fünfzehn Rundkurse. Immer wieder gern nach Hause.',
      emoji: '\u{1F501}',
      category: 'routes',
      familie: 'rundkurs',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_29_rundkurs_silber.png',
    ),
    Badge(
      id: 'badge_30',
      name: 'Zielstrebig',
      description: 'Fünfzehn Fahrten von A nach B. Du weißt, wo du hinwillst.',
      emoji: '\u{1F3AF}',
      category: 'routes',
      familie: 'zielstrebig',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_30_ziel_silber.png',
    ),
    Badge(
      id: 'badge_31',
      name: '1.000 km',
      description: 'Tausend Kilometer insgesamt. Vierstellig.',
      emoji: '\u{1F4CF}',
      category: 'distance',
      familie: 'distanz',
      assetPath: 'lib/images/badges/badge_31_1000km_gold.png',
    ),
    Badge(
      id: 'badge_32',
      name: '5.000 km',
      description: 'Fünftausend Kilometer insgesamt. Halber Weg zur Legende.',
      emoji: '\u{1F310}',
      category: 'distance',
      familie: 'distanz',
      assetPath: 'lib/images/badges/badge_32_meilenstein_5000km_diamant.png',
    ),
    Badge(
      id: 'badge_33',
      name: '100 Stunden',
      description: 'Hundert Stunden am Lenkrad. Die Straße kennt deinen Namen.',
      emoji: '\u{231B}',
      category: 'distance',
      familie: 'stunden',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_33_100h_bronze.png',
    ),
    Badge(
      id: 'badge_34',
      name: 'Sammler',
      description: 'Fünfzehn Routen gespeichert. Deine Sammlung wächst.',
      emoji: '\u{1F4DA}',
      category: 'saved',
      familie: 'gespeichert',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_34_lesezeichen_silber.png',
    ),
    Badge(
      id: 'badge_35',
      name: 'Gruppengründer',
      description: 'Drei Gruppen gegründet. Du bringst Leute zusammen.',
      emoji: '\u{1F46A}',
      category: 'groups',
      familie: 'gegruendet',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_35_fahne_silber.png',
    ),
    Badge(
      id: 'badge_36',
      name: 'Community-Stimme',
      description: 'Fünfzehn Routen geteilt. Andere fahren, was du findest.',
      emoji: '\u{1F5E3}\uFE0F',
      category: 'social',
      familie: 'geteilt',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_36_pin_gold.png',
    ),
    // 2026-08-18 (Aufgabe 4.2, vucko Sprachnachricht 09 vom 16.08.):
    // „Mehrstufige Badges, das heisst, Kurvenkoenig gibt es drei Stufen, und
    // von den anderen Badges auch." Zwanzig neue Stufen, die die bestehenden
    // Familien auf je drei auffuellen. Kein bestehender Schwellwert wurde
    // angefasst, keine ID umbenannt.
    //
    // Die Embleme sind bewusst die Bilder der jeweiligen Familie: die
    // vorhandenen PNG wiegen 0,6 bis 1,4 MB je Datei (zusammen 31 MB), zwanzig
    // weitere waeren rund 20 MB mehr im Installationspaket. Die Stufe zeigt
    // stattdessen eine roemische Ziffer auf der Kachel.
    Badge(
      id: 'badge_37',
      name: 'Konvoi-Legende',
      description: 'Zwanzig Gruppenfahrten gemeinsam beendet. Ohne dich '
          'faehrt keiner los.',
      emoji: '\u{1F699}',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_37_turbo_gold.png',
      familie: 'gruppenfahrt',
      stufe: 3,
    ),
    Badge(
      id: 'badge_38',
      name: 'Szenegründer',
      description: 'Zehn Gruppen gegründet. Du baust eine ganze Szene auf.',
      emoji: '\u{1F3D9}\uFE0F',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_38_fahne_gold.png',
      familie: 'gegruendet',
      stufe: 3,
    ),
    Badge(
      id: 'badge_39',
      name: 'Archivar',
      description: 'Vierzig Routen gespeichert. Dein Archiv ist beachtlich.',
      emoji: '\u{1F5C3}\uFE0F',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_39_lesezeichen_gold.png',
      familie: 'gespeichert',
      stufe: 3,
    ),
    Badge(
      id: 'badge_40',
      name: 'Zehn Stunden',
      description: 'Zehn Stunden am Lenkrad. Der Anfang einer langen Strecke.',
      emoji: '\u{23F0}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_40_uhr_bronze.png',
      familie: 'stunden',
      stufe: 1,
    ),
    Badge(
      id: 'badge_41',
      name: 'Kurvenfreund',
      description: 'Drei Kurvenjagd-Fahrten beendet. Du hast Geschmack '
          'gefunden.',
      emoji: '\u{1F300}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_41_kurven_bronze.png',
      familie: 'kurven',
      stufe: 1,
    ),
    Badge(
      id: 'badge_42',
      name: 'Kurvenmeister',
      description: 'Fünfundzwanzig Kurvenjagd-Fahrten. Jede Serpentine kennt '
          'dich.',
      emoji: '\u{1F40D}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_42_kurven_gold.png',
      familie: 'kurven',
      stufe: 3,
    ),
    Badge(
      id: 'badge_43',
      name: 'Weitfahrer',
      description: 'Über 200 Kilometer in einer einzigen Fahrt. Ein ganzer '
          'Tag Straße.',
      emoji: '\u{1F3DC}\uFE0F',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_43_langstrecke_silber.png',
      familie: 'langstrecke',
      stufe: 2,
    ),
    Badge(
      id: 'badge_44',
      name: 'Grenzgänger',
      description: 'Über 300 Kilometer am Stück. Das ist eine Reise, keine '
          'Runde.',
      emoji: '\u{1F3D4}\uFE0F',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_44_langstrecke_gold.png',
      familie: 'langstrecke',
      stufe: 3,
    ),
    Badge(
      id: 'badge_45',
      name: 'Wochenend-Stammgast',
      description: 'Zwanzig Fahrten am Wochenende. Der Samstag gehört dem '
          'Auto.',
      emoji: '\u{1F576}\uFE0F',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_45_wochenende_silber.png',
      familie: 'wochenende',
      stufe: 2,
    ),
    Badge(
      id: 'badge_46',
      name: 'Wochenend-Legende',
      description: 'Fünfzig Fahrten am Wochenende. Zwei Tage, ein Plan.',
      emoji: '\u{1F389}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_46_wochenende_gold.png',
      familie: 'wochenende',
      stufe: 3,
    ),
    Badge(
      id: 'badge_47',
      name: 'Drei in Folge',
      description: 'Drei Tage hintereinander gefahren. Der Anfang einer Serie.',
      emoji: '\u{1F331}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_47_serie_bronze.png',
      familie: 'serie',
      stufe: 1,
    ),
    Badge(
      id: 'badge_48',
      name: 'Dreißig Tage Serie',
      description: 'Dreißig Tage in Folge gefahren. Das schafft kaum jemand.',
      emoji: '\u{26A1}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_48_serie_gold.png',
      familie: 'serie',
      stufe: 3,
    ),
    Badge(
      id: 'badge_49',
      name: 'Runden-Einsteiger',
      description: 'Fünf Rundkurse gefahren. Immer schön wieder heim.',
      emoji: '\u{1F502}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_49_rundkurs_bronze.png',
      familie: 'rundkurs',
      stufe: 1,
    ),
    Badge(
      id: 'badge_50',
      name: 'Runden-Legende',
      description: 'Fünfzig Rundkurse. Deine Heimatrunden sind Kult.',
      emoji: '\u{1F3A1}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_50_rundkurs_gold.png',
      familie: 'rundkurs',
      stufe: 3,
    ),
    Badge(
      id: 'badge_51',
      name: 'Wegfinder',
      description: 'Fünf Fahrten von A nach B. Du hast ein Ziel vor Augen.',
      emoji: '\u{1F9ED}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_51_ziel_bronze.png',
      familie: 'zielstrebig',
      stufe: 1,
    ),
    Badge(
      id: 'badge_52',
      name: 'Zielsicher',
      description: 'Fünfzig Fahrten von A nach B. Umwege sind für andere.',
      emoji: '\u{1F3F9}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_52_ziel_gold.png',
      familie: 'zielstrebig',
      stufe: 3,
    ),
    Badge(
      id: 'badge_53',
      name: 'Morgenroutine',
      description: 'Zehn Fahrten vor acht Uhr gestartet. Der Wecker klingelt '
          'gern.',
      emoji: '\u{2615}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_53_frueh_silber.png',
      familie: 'frueh',
      stufe: 2,
    ),
    Badge(
      id: 'badge_54',
      name: 'Sonnenaufgangsjäger',
      description: 'Dreißig Frühfahrten. Du siehst den Tag vor allen anderen.',
      emoji: '\u{1F304}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_54_frueh_gold.png',
      familie: 'frueh',
      stufe: 3,
    ),
    Badge(
      id: 'badge_55',
      name: 'Nachtfahrer',
      description: 'Zehn Fahrten nach 22 Uhr. Die leeren Straßen sind deine.',
      emoji: '\u{1F989}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_55_nacht_silber.png',
      familie: 'nacht',
      stufe: 2,
    ),
    Badge(
      id: 'badge_56',
      name: 'Mitternachtsclub',
      description: 'Dreißig Nachtfahrten. Der Mond kennt deine Route.',
      emoji: '\u{1F30C}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_56_nacht_gold.png',
      familie: 'nacht',
      stufe: 3,
    ),
    // 2026-08-24 (Aufgabe 10a): Das eine Community-Abzeichen. Kachelname
    // „Community", beim Antippen die Anleitung „Gruende eine Community" —
    // genau Vuckos Wortlaut. Die Beschreibung IST hier die Anleitung, weil
    // stufenlose Abzeichen keinen Fortschrittsbalken haben (badgeBedingungFuer
    // liefert null, weil sie in keiner Familie stehen); das Detail-Blatt zeigt
    // dann Name und Beschreibung, und mehr braucht es nicht.
    //
    // Emblem: badge_35_founder_ruby.png, dasselbe Gruender-Motiv wie beim
    // Gruppengruender. Ein eigenes Bild waere schoener, kostet aber 0,6 bis
    // 1,4 MB im Installationspaket; Austausch spaeter = nur den assetPath
    // ersetzen.
    Badge(
      id: communityGruenderBadgeId,
      name: 'Community',
      description: 'Gründe eine Community.',
      emoji: '\u{1F3D8}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_57_community_aurora.png',
    ),
    // 2026-08-24 (Auftrag vom 24.08.): Das Abzeichen fuer das abgeschlossene
    // Onboarding. Stufenlos wie badge_15 und badge_16 — es gibt kein „zweites
    // Tutorial". Abgrenzung zu „Startklar" siehe [onboardingBadgeId].
    //
    // Emblem: badge_11 war die letzte ungenutzte Luecke der Bildserie (das
    // Motiv wurde nie einem Abzeichen zugeordnet) und ist ein Lenkrad — das
    // passende Bild fuer „jetzt darfst du losfahren".
    // 2026-08-25 (vucko): Name und Beschreibung nachgezogen. „Eingewiesen /
    // Das Tutorial einmal komplett durchgespielt." beschrieb die alte
    // Bedingung (eine Aufgabe von zwoelf). Seit heute sind es ALLE zwoelf.
    // Bewusst OHNE Zahl im Text: die Zahl steht in
    // StarterAufgabenService.aufgaben und wuerde hier stumm veralten.
    Badge(
      id: alleAufgabenBadgeId,
      name: 'Durchgespielt',
      description:
          'Jede Starter-Aufgabe erledigt. Du hast alle Funktionen der App '
          'einmal benutzt.',
      emoji: '\u{1F393}',
      category: 'membership',
      assetPath: 'lib/images/badges/badge_58_durchgespielt_aurora.png',
    ),
    // -----------------------------------------------------------------
    // 2026-08-24 (Auftrag vom 24.08., vucko woertlich): „erstelle fuer die
    // genannten kategorien selber noch badges [...] Routen, Kurven,
    // Kilometer, Gruppenfahrten, Community, Beitraege, Hashtags, Meldungen
    // (Baustellen und Stau), Fahrzeuge in der Garage, Streak, Fruehaufsteher,
    // Nachtfahrten."
    //
    // GEPRUEFT: Von dieser Liste hatten Routen, Kurven, Kilometer,
    // Gruppenfahrten, Streak, Frueh und Nacht bereits je drei Stufen, und
    // KEINE einzige Familie stand auf nur einer Stufe. Die Luecken waren
    // ganze BEREICHE der App ohne jedes Abzeichen:
    //
    //   Garage      86 Fahrzeuge bei 62 Nutzern — und kein Abzeichen dafuer.
    //   Beitraege   10 Beitraege von 7 Nutzern. Die vorhandene Familie
    //               „Geteilte Routen" misst NUR Beitraege mit angehaengter
    //               Route (`posts.shared_route_id`); davon gibt es in der
    //               ganzen Geschichte der App GENAU NULL. Diese Leiter ist
    //               also fuer jeden unerreichbar, und der normale Beitrag
    //               zaehlte nirgends.
    //   Hashtags    Seit Migration 20260824102000 gibt es `post_hashtags`,
    //               bisher 0 Zeilen. Vucko nennt Hashtags ausdruecklich.
    //   Meldungen   8 Meldungen von 2 Nutzern, eine Person allein hat 7.
    //
    // ALLE SCHWELLEN SIND AUS DIESEN ZAHLEN ABGELEITET, nicht geraten. Es gibt
    // 183 Konten, aber nur 15 Menschen haben je eine Fahrt beendet. Ein
    // Abzeichen fuer „1000 Beitraege" waere Hohn — die dritte Stufe liegt
    // deshalb bei 20 und nicht bei 100.
    //
    // Regel wie gehabt: neue ID statt geaenderter Schwelle, damit es keine
    // Datenmigration braucht.
    // -----------------------------------------------------------------
    Badge(
      id: 'badge_59',
      name: 'Erstes Auto',
      description: 'Dein erstes Fahrzeug steht in der Garage.',
      emoji: '\u{1F527}',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_59_garage_bronze.png',
      familie: 'garage',
      stufe: 1,
    ),
    Badge(
      id: 'badge_60',
      name: 'Volle Garage',
      description: 'Drei Fahrzeuge im Profil. Für jede Laune eines.',
      emoji: '\u{1F6E0}\uFE0F',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_60_garage_silber.png',
      familie: 'garage',
      stufe: 2,
    ),
    Badge(
      id: 'badge_61',
      name: 'Fuhrpark',
      description: 'Fünf Fahrzeuge in der Garage. Mehr hat hier niemand.',
      emoji: '\u{1F9F0}',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_61_garage_gold.png',
      familie: 'garage',
      stufe: 3,
    ),
    Badge(
      id: 'badge_62',
      name: 'Erster Beitrag',
      description: 'Dein erster Beitrag in der Community.',
      emoji: '\u{1F4DD}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_62_sprechblase_bronze.png',
      familie: 'beitraege',
      stufe: 1,
    ),
    Badge(
      id: 'badge_63',
      name: 'Mitredner',
      description: 'Fünf Beiträge geschrieben. Man kennt deinen Namen.',
      emoji: '\u{1F4F0}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_63_sprechblase_silber.png',
      familie: 'beitraege',
      stufe: 2,
    ),
    Badge(
      id: 'badge_64',
      name: 'Vielschreiber',
      description: 'Zwanzig Beiträge. Ohne dich wäre es hier still.',
      emoji: '\u{1F3A4}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_64_sprechblase_gold.png',
      familie: 'beitraege',
      stufe: 3,
    ),
    Badge(
      id: 'badge_65',
      name: 'Erster Hashtag',
      description: 'Einen Beitrag mit einem Hashtag versehen.',
      emoji: '\u{23}\uFE0F\u{20E3}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_65_hashtag_bronze.png',
      familie: 'hashtags',
      stufe: 1,
    ),
    Badge(
      id: 'badge_66',
      name: 'Themensetzer',
      description: 'Fünf Beiträge mit Hashtag. Deine Themen finden andere.',
      emoji: '\u{1F516}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_66_hashtag_silber.png',
      familie: 'hashtags',
      stufe: 2,
    ),
    Badge(
      id: 'badge_67',
      name: 'Trendmacher',
      description: 'Zwanzig Beiträge mit Hashtag. Du gibst das Thema vor.',
      emoji: '\u{1F9F5}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_67_hashtag_gold.png',
      familie: 'hashtags',
      stufe: 3,
    ),
    Badge(
      id: 'badge_68',
      name: 'Erste Meldung',
      description: 'Eine Baustelle oder einen Stau gemeldet.',
      emoji: '\u{26A0}\uFE0F',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_68_warndreieck_bronze.png',
      familie: 'meldungen',
      stufe: 1,
    ),
    Badge(
      id: 'badge_69',
      name: 'Aufmerksam',
      description: 'Fünf Meldungen abgesetzt. Andere fahren dank dir sicherer.',
      emoji: '\u{1F6A7}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_69_warndreieck_silber.png',
      familie: 'meldungen',
      stufe: 2,
    ),
    Badge(
      id: 'badge_70',
      name: 'Straßenwacht',
      description: 'Zwanzig Meldungen abgesetzt. Die Strecke ist bei dir in '
          'guten Händen.',
      emoji: '\u{1F9BA}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_70_warndreieck_gold.png',
      familie: 'meldungen',
      stufe: 3,
    ),
  ];

  static Badge? getById(String id) {
    try {
      return all.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Deutsche Monatsnamen ohne intl-Locale-Initialisierung — die App nutzt
  /// bisher nirgends DateFormat mit 'de', und ein fester Satz Namen kann in
  /// keinem Widget-Test an fehlender Locale-Registrierung scheitern.
  static const List<String> _germanMonths = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  /// 'MMMM yyyy' auf Deutsch, z.B. 'August 2026'.
  static String formatMonthYearDe(DateTime date) {
    return '${_germanMonths[date.month - 1]} ${date.year}';
  }

  /// Beschreibung zur ANZEIGE auflösen: beim Mitgliedschafts-Badge wird der
  /// Datums-Platzhalter durch den Beitrittsmonat ersetzt (Fallback: heute).
  /// Alle anderen Badges liefern ihre Beschreibung unverändert.
  static String resolveDescription(Badge badge, {DateTime? memberSince}) {
    if (badge.id != membershipBadgeId) return badge.description;
    final since = memberSince ?? DateTime.now();
    return badge.description.replaceAll(
      membershipDatePlaceholder,
      formatMonthYearDe(since),
    );
  }

  // ---------------------------------------------------------------------
  // 2026-08-18 (Aufgabe 4.2): Stufen-Hilfen. Bewusst KEIN eigenes
  // Familien-Objekt in [all] — die Liste ist const und wird an vielen Stellen
  // flach durchlaufen. Die Familie ergibt sich aus [familie] und [stufe].
  // ---------------------------------------------------------------------

  /// Roemische Ziffer zur Stufe. Leer bei stufenlosen Badges.
  ///
  /// 2026-08-19 (vucko woertlich): „schau das sie andere Farben andere Formen
  /// andere Symbole haben ... das die niedrigste Stufe Bronze / Rot ist, die
  /// beste lila oder blau ist"
  ///
  /// Farbe, Form und Symbol einer Stufe stehen NICHT hier, sondern in
  /// `lib/presentation/widgets/badge_stufen_stil.dart` — das Modell darf kein
  /// Flutter kennen. Diese Liste bleibt die Rangfolge-Wahrheit; der Test
  /// `test/presentation/badge_stufen_darstellung_test.dart` vergleicht beide
  /// Dateien und schlaegt fehl, wenn sie auseinanderlaufen.
  static const List<String> stufenZeichen = ['', 'I', 'II', 'III'];

  /// Alle Badges einer Familie, nach Stufe sortiert. Stufenlose Meilensteine
  /// derselben Familie (z. B. Level 100) haengen hinten dran.
  static List<Badge> familienBadges(String familie) {
    final treffer = all.where((b) => b.familie == familie).toList();
    treffer.sort((a, b) {
      final sa = a.stufe == 0 ? 99 : a.stufe;
      final sb = b.stufe == 0 ? 99 : b.stufe;
      if (sa != sb) return sa.compareTo(sb);
      // Innerhalb der stufenlosen: nach Schwelle, damit 1.000 vor 5.000 steht.
      final za = badgeBedingungFuer(a.id)?.stufe.schwelle ?? 0;
      final zb = badgeBedingungFuer(b.id)?.stufe.schwelle ?? 0;
      return za.compareTo(zb);
    });
    return treffer;
  }

  /// Hoechste erreichte Stufe einer Familie zu einer Menge erreichter IDs.
  /// 0 = noch keine Stufe erreicht.
  static int hoechsteErreichteStufe(
    String familie,
    Set<String> erreichteBadgeIds,
  ) {
    var hoechste = 0;
    for (final badge in all) {
      if (badge.familie != familie || badge.stufe == 0) continue;
      if (!erreichteBadgeIds.contains(badge.id)) continue;
      if (badge.stufe > hoechste) hoechste = badge.stufe;
    }
    return hoechste;
  }

  /// Die naechste noch nicht erreichte Stufe einer Familie (null = alle da).
  static Badge? naechsteStufe(String familie, Set<String> erreichteBadgeIds) {
    for (final badge in familienBadges(familie)) {
      if (!erreichteBadgeIds.contains(badge.id)) return badge;
    }
    return null;
  }

  /// Reihenfolge der Familien in der Sammlung.
  static List<String> get familienReihenfolge =>
      [for (final f in badgeFamilien) f.schluessel];
}

/// Fortschritt zu einem noch gesperrten Badge.
///
/// 2026-08-15 (vucko): „bei den gesperrten soll man sehen, was sie machen
/// muessen — z. B. 1000 km fahren — und wenn sie schon 274 gefahren sind, den
/// Fortschritt, damit sie sehen: mir fehlen nicht mehr so viele."
class BadgeFortschritt {
  const BadgeFortschritt({
    required this.aktuell,
    required this.ziel,
    required this.einheit,
    required this.anleitung,
  });

  final double aktuell;
  final double ziel;

  /// „km", „Fahrten", „Std", „Level" …
  final String einheit;

  /// Ein Satz, was zu tun ist.
  final String anleitung;

  double get anteil => ziel <= 0 ? 0 : (aktuell / ziel).clamp(0.0, 1.0);

  /// „1.008 von 2.500 km"
  ///
  /// 2026-08-26 (vucko, Aufgabe 8): Hier stand „1007.5 von 2500 km" — eine
  /// Nachkommastelle, die niemanden interessiert, und vierstellige Zahlen ohne
  /// Trennung. Auf einem Handy im Fahrzeug ist das schwer zu erfassen.
  ///
  /// Die Nachkommastelle bleibt nur, wo sie wirklich etwas aussagt: unter zehn
  /// (etwa „2,5 von 5 Std"). Darueber wird gerundet.
  String get zahlen =>
      '${zahlMitTausenderpunkt(aktuell)} von '
      '${zahlMitTausenderpunkt(ziel)} $einheit';
}

/// Eine Zahl, wie sie in Fortschritts- und Challenge-Anzeigen stehen soll.
///
/// Eine Quelle fuer alle Stellen, damit kuenftige Challenges dasselbe Format
/// bekommen und nicht jede Anzeige ihr eigenes erfindet.
String zahlMitTausenderpunkt(double wert) {
  if (wert.abs() < 10 && wert != wert.roundToDouble()) {
    return wert.toStringAsFixed(1).replaceAll('.', ',');
  }
  final ganz = wert.round();
  final ziffern = ganz.abs().toString();
  final puffer = StringBuffer();
  for (var i = 0; i < ziffern.length; i++) {
    if (i > 0 && (ziffern.length - i) % 3 == 0) puffer.write('.');
    puffer.write(ziffern[i]);
  }
  return ganz < 0 ? '-$puffer' : puffer.toString();
}
/// Kennzahl, an der eine Badge-Familie gemessen wird.
///
/// 2026-08-18 (Aufgabe 4.2): Frueher stand jede Bedingung zweimal im Code —
/// als `if`-Zeile in `GamificationService.calculateAndSync()` und als
/// `case`-Zweig in [badgeFortschrittFuer]. Beide konnten auseinanderlaufen.
/// Jetzt gibt es EINE Datentabelle ([badgeFamilien]); Freischaltung und
/// Fortschritt lesen dieselben Zeilen.
enum BadgeMetrik {
  level,
  gesamtKm,
  gesamtStunden,
  fahrten,
  gruppenfahrten,
  geteilteRouten,
  gegruendeteGruppen,
  gespeicherteRouten,
  laengsteFahrt,
  kurvenjagd,
  wochenendFahrten,
  serieTage,
  rundkurse,
  aNachBFahrten,
  fruehFahrten,
  nachtFahrten,
  gefahreneStile,
  // 2026-08-24 (Auftrag vom 24.08.): vier Bereiche, die bisher kein Abzeichen
  // hatten. Die Werte liefert `GamificationService.calculateAndSync` — drei
  // davon liegen dort schon vor (`fahrzeugAnzahl`, `postZahlen.gesamt`), die
  // Hashtag- und Meldungszahl muss es noch laden.
  fahrzeuge,
  beitraege,
  hashtagBeitraege,
  meldungen,
}

/// Eine Schwelle und das Badge, das sie freischaltet.
class BadgeStufe {
  const BadgeStufe({
    required this.id,
    required this.schwelle,
    required this.anleitung,
  });

  final String id;
  final double schwelle;

  /// Ein Satz, was zu tun ist. Wird im Overlay ueber dem Balken gezeigt.
  final String anleitung;
}

/// Eine Familie von Badges, die dieselbe Kennzahl in Stufen misst.
class BadgeFamilie {
  const BadgeFamilie({
    required this.schluessel,
    required this.titel,
    required this.metrik,
    required this.einheit,
    this.stufen = const [],
    this.ohneStufe = const [],
  });

  /// Technischer Schluessel, steht auch in [Badge.familie].
  final String schluessel;

  /// Ueberschrift in der Sammlung.
  final String titel;

  final BadgeMetrik metrik;

  /// „km", „Fahrten", „Std" …
  final String einheit;

  /// GENAU DREI Stufen, aufsteigend — oder leer bei bewusst stufenlosen
  /// Familien. Vuckos Vorgabe vom 16.08.: drei Stufen je Familie, nicht fuenf.
  final List<BadgeStufe> stufen;

  /// Meilensteine derselben Kennzahl OHNE Rangfolge. Sie werden in der
  /// Sammlung unter derselben Ueberschrift gezeigt, tragen aber keine
  /// roemische Ziffer, weil sie die Familie sonst auf fuenf Stufen aufblaehen
  /// wuerden.
  final List<BadgeStufe> ohneStufe;

  bool get istGestuft => stufen.isNotEmpty;

  List<BadgeStufe> get alleStufen => [...stufen, ...ohneStufe];
}

/// DIE Tabelle. Eine neue Stufe ist eine Zeile hier plus ein Eintrag in
/// [Badge.all] — keine Code-Aenderung an der Freischaltung.
///
/// Bestehende Schwellwerte wurden beim Gruppieren NICHT angefasst.
const List<BadgeFamilie> badgeFamilien = [
  BadgeFamilie(
    schluessel: 'distanz',
    titel: 'Kilometer',
    metrik: BadgeMetrik.gesamtKm,
    einheit: 'km',
    stufen: [
      BadgeStufe(
        id: 'badge_06',
        schwelle: 500,
        anleitung: 'Fahre insgesamt 500 Kilometer.',
      ),
      BadgeStufe(
        id: 'badge_10',
        schwelle: 2500,
        anleitung: 'Fahre insgesamt 2.500 Kilometer.',
      ),
      BadgeStufe(
        id: 'badge_13',
        schwelle: 10000,
        anleitung: 'Fahre insgesamt 10.000 Kilometer.',
      ),
    ],
    // 1.000 und 5.000 km liegen ZWISCHEN den drei Stufen. Sie bleiben
    // erhalten (bestehende IDs werden nie geaendert), zaehlen aber nicht als
    // Stufe, sonst haette die Familie fuenf davon.
    ohneStufe: [
      BadgeStufe(
        id: 'badge_31',
        schwelle: 1000,
        anleitung: 'Fahre insgesamt 1.000 Kilometer.',
      ),
      BadgeStufe(
        id: 'badge_32',
        schwelle: 5000,
        anleitung: 'Fahre insgesamt 5.000 Kilometer.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'fahrten',
    titel: 'Abgeschlossene Fahrten',
    metrik: BadgeMetrik.fahrten,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_02',
        schwelle: 1,
        anleitung: 'Fahre eine Route bis zum Ende.',
      ),
      BadgeStufe(
        id: 'badge_17',
        schwelle: 10,
        anleitung: 'Bringe zehn Fahrten bis zum Ende.',
      ),
      BadgeStufe(
        id: 'badge_18',
        schwelle: 50,
        anleitung: 'Bringe fünfzig Fahrten bis zum Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'level',
    titel: 'Level',
    metrik: BadgeMetrik.level,
    einheit: 'Level',
    stufen: [
      BadgeStufe(
        id: 'badge_01',
        schwelle: 10,
        anleitung: 'Sammle XP bis Level 10.',
      ),
      BadgeStufe(
        id: 'badge_03',
        schwelle: 25,
        anleitung: 'Sammle XP bis Level 25.',
      ),
      BadgeStufe(
        id: 'badge_08',
        schwelle: 50,
        anleitung: 'Sammle XP bis Level 50.',
      ),
    ],
    // Level 100 ist das Maximallevel, danach kommt nichts mehr. Ein Abschluss,
    // keine vierte Stufe.
    ohneStufe: [
      BadgeStufe(
        id: 'badge_14',
        schwelle: 100,
        anleitung: 'Erreiche Level 100.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'stunden',
    titel: 'Stunden am Steuer',
    metrik: BadgeMetrik.gesamtStunden,
    einheit: 'Std',
    stufen: [
      BadgeStufe(
        id: 'badge_40',
        schwelle: 10,
        anleitung: 'Fahre insgesamt 10 Stunden.',
      ),
      BadgeStufe(
        id: 'badge_22',
        schwelle: 25,
        anleitung: 'Fahre insgesamt 25 Stunden.',
      ),
      BadgeStufe(
        id: 'badge_33',
        schwelle: 100,
        anleitung: 'Fahre insgesamt 100 Stunden.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'langstrecke',
    titel: 'Langstrecke',
    metrik: BadgeMetrik.laengsteFahrt,
    einheit: 'km',
    stufen: [
      BadgeStufe(
        id: 'badge_20',
        schwelle: 100,
        anleitung: 'Fahre einmal über 100 Kilometer am Stück.',
      ),
      BadgeStufe(
        id: 'badge_43',
        schwelle: 200,
        anleitung: 'Fahre einmal über 200 Kilometer am Stück.',
      ),
      BadgeStufe(
        id: 'badge_44',
        schwelle: 300,
        anleitung: 'Fahre einmal über 300 Kilometer am Stück.',
      ),
    ],
  ),
  // Vuckos ausdruecklicher Wunsch: „Kurvenkoenig gibt es drei Stufen." Die 3
  // als Einstieg, weil heute niemand ueber 4 Kurvenjagd-Fahrten kommt.
  BadgeFamilie(
    schluessel: 'kurven',
    titel: 'Kurvenjagd',
    metrik: BadgeMetrik.kurvenjagd,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_41',
        schwelle: 3,
        anleitung: 'Bringe drei Fahrten im Stil Kurvenjagd zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_27',
        schwelle: 10,
        anleitung: 'Bringe zehn Fahrten im Stil Kurvenjagd zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_42',
        schwelle: 25,
        anleitung: 'Bringe fünfundzwanzig Fahrten im Stil Kurvenjagd zu Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'rundkurs',
    titel: 'Rundkurse',
    metrik: BadgeMetrik.rundkurse,
    einheit: 'Rundkurse',
    stufen: [
      BadgeStufe(
        id: 'badge_49',
        schwelle: 5,
        anleitung: 'Bringe fünf Rundkurse zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_29',
        schwelle: 15,
        anleitung: 'Bringe fünfzehn Rundkurse zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_50',
        schwelle: 50,
        anleitung: 'Bringe fünfzig Rundkurse zu Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'zielstrebig',
    titel: 'Von A nach B',
    metrik: BadgeMetrik.aNachBFahrten,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_51',
        schwelle: 5,
        anleitung: 'Bringe fünf Fahrten von A nach B zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_30',
        schwelle: 15,
        anleitung: 'Bringe fünfzehn Fahrten von A nach B zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_52',
        schwelle: 50,
        anleitung: 'Bringe fünfzig Fahrten von A nach B zu Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'serie',
    titel: 'Serie',
    metrik: BadgeMetrik.serieTage,
    einheit: 'Tage',
    stufen: [
      BadgeStufe(
        id: 'badge_47',
        schwelle: 3,
        anleitung: 'Fahre an drei Tagen hintereinander.',
      ),
      BadgeStufe(
        id: 'badge_26',
        schwelle: 7,
        anleitung: 'Fahre an sieben Tagen hintereinander.',
      ),
      BadgeStufe(
        id: 'badge_48',
        schwelle: 30,
        anleitung: 'Fahre an dreißig Tagen hintereinander.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'wochenende',
    titel: 'Wochenende',
    metrik: BadgeMetrik.wochenendFahrten,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_25',
        schwelle: 5,
        anleitung: 'Bringe fünf Fahrten am Samstag oder Sonntag zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_45',
        schwelle: 20,
        anleitung: 'Bringe zwanzig Fahrten am Samstag oder Sonntag zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_46',
        schwelle: 50,
        anleitung: 'Bringe fünfzig Fahrten am Samstag oder Sonntag zu Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'frueh',
    titel: 'Früh unterwegs',
    metrik: BadgeMetrik.fruehFahrten,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_23',
        schwelle: 1,
        anleitung: 'Starte eine Fahrt vor acht Uhr morgens (mindestens 5 km).',
      ),
      BadgeStufe(
        id: 'badge_53',
        schwelle: 10,
        anleitung: 'Starte zehn Fahrten vor acht Uhr morgens.',
      ),
      BadgeStufe(
        id: 'badge_54',
        schwelle: 30,
        anleitung: 'Starte dreißig Fahrten vor acht Uhr morgens.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'nacht',
    titel: 'Nachts unterwegs',
    metrik: BadgeMetrik.nachtFahrten,
    einheit: 'Fahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_24',
        schwelle: 1,
        anleitung: 'Sei nach 22 Uhr noch unterwegs (mindestens 5 km).',
      ),
      BadgeStufe(
        id: 'badge_55',
        schwelle: 10,
        anleitung: 'Sei bei zehn Fahrten nach 22 Uhr unterwegs.',
      ),
      BadgeStufe(
        id: 'badge_56',
        schwelle: 30,
        anleitung: 'Sei bei dreißig Fahrten nach 22 Uhr unterwegs.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'gruppenfahrt',
    titel: 'Gruppenfahrten',
    metrik: BadgeMetrik.gruppenfahrten,
    einheit: 'Gruppenfahrten',
    stufen: [
      BadgeStufe(
        id: 'badge_04',
        schwelle: 1,
        anleitung: 'Beende eine Gruppenfahrt gemeinsam.',
      ),
      BadgeStufe(
        id: 'badge_19',
        schwelle: 5,
        anleitung: 'Beende fünf Gruppenfahrten gemeinsam.',
      ),
      BadgeStufe(
        id: 'badge_37',
        schwelle: 20,
        anleitung: 'Beende zwanzig Gruppenfahrten gemeinsam.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'gegruendet',
    titel: 'Gegründete Gruppen',
    metrik: BadgeMetrik.gegruendeteGruppen,
    einheit: 'Gruppen',
    stufen: [
      BadgeStufe(
        id: 'badge_07',
        schwelle: 1,
        anleitung: 'Erstelle eine Gruppe.',
      ),
      BadgeStufe(
        id: 'badge_35',
        schwelle: 3,
        anleitung: 'Gruende drei Gruppen.',
      ),
      BadgeStufe(
        id: 'badge_38',
        schwelle: 10,
        anleitung: 'Gruende zehn Gruppen.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'geteilt',
    titel: 'Geteilte Routen',
    metrik: BadgeMetrik.geteilteRouten,
    einheit: 'Routen',
    stufen: [
      BadgeStufe(
        id: 'badge_05',
        schwelle: 1,
        anleitung: 'Teile eine Route.',
      ),
      BadgeStufe(
        id: 'badge_21',
        schwelle: 5,
        anleitung: 'Teile fünf Routen mit der Community.',
      ),
      BadgeStufe(
        id: 'badge_36',
        schwelle: 15,
        anleitung: 'Teile fünfzehn Routen mit der Community.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'gespeichert',
    titel: 'Gespeicherte Routen',
    metrik: BadgeMetrik.gespeicherteRouten,
    einheit: 'Routen',
    stufen: [
      BadgeStufe(
        id: 'badge_09',
        schwelle: 5,
        anleitung: 'Speichere fünf verschiedene Routen.',
      ),
      BadgeStufe(
        id: 'badge_34',
        schwelle: 15,
        anleitung: 'Speichere fünfzehn verschiedene Routen.',
      ),
      BadgeStufe(
        id: 'badge_39',
        schwelle: 40,
        anleitung: 'Speichere vierzig verschiedene Routen.',
      ),
    ],
  ),
  // Vier von vier Stilen — darueber gibt es nichts, also bewusst ohne Stufen.
  BadgeFamilie(
    schluessel: 'stile',
    titel: 'Fahrstile',
    metrik: BadgeMetrik.gefahreneStile,
    einheit: 'Stile',
    ohneStufe: [
      BadgeStufe(
        id: 'badge_28',
        schwelle: 4,
        anleitung:
            'Fahre je eine Route in Kurvenjagd, Sport Mode, Abendrunde und '
            'Entdecker zu Ende.',
      ),
    ],
  ),
  // ---------------------------------------------------------------------
  // 2026-08-24 (Auftrag vom 24.08.): Vier Familien fuer Bereiche, die bisher
  // kein einziges Abzeichen hatten. Herleitung der Schwellen aus der
  // Produktivdatenbank, gemessen am 24.08. — siehe auch der Block ueber
  // badge_59 in [Badge.all].
  // ---------------------------------------------------------------------
  //
  // GEMESSEN: 86 Fahrzeuge bei 62 Nutzern, 18 Leute haben zwei oder mehr, 2
  // haben drei oder mehr, das Maximum sind FUENF. Die dritte Stufe liegt
  // deshalb genau auf diesen fuenf: erreichbar, aber bisher von genau einer
  // Person erreicht. Eine Stufe bei zehn Autos waere eine Zierleiste ohne Tuer.
  BadgeFamilie(
    schluessel: 'garage',
    titel: 'Garage',
    metrik: BadgeMetrik.fahrzeuge,
    einheit: 'Fahrzeuge',
    stufen: [
      BadgeStufe(
        id: 'badge_59',
        schwelle: 1,
        anleitung: 'Trage dein Auto im Profil ein.',
      ),
      BadgeStufe(
        id: 'badge_60',
        schwelle: 3,
        anleitung: 'Trage drei Fahrzeuge in deine Garage ein.',
      ),
      BadgeStufe(
        id: 'badge_61',
        schwelle: 5,
        anleitung: 'Trage fünf Fahrzeuge in deine Garage ein.',
      ),
    ],
  ),
  // GEMESSEN: 10 Beitraege von 7 Nutzern, das Maximum sind ZWEI pro Person.
  // Die erste Stufe steht deshalb auf 1 (sieben Leute haetten sie sofort),
  // die dritte auf 20 — das ist das Zehnfache des heutigen Rekords und damit
  // ein Fernziel, kein Hohn wie „hundert Beitraege" bei zehn insgesamt.
  //
  // WICHTIG, nicht mit „Geteilte Routen" verwechseln: Jene Familie misst
  // `posts.shared_route_id`, also nur Beitraege MIT angehaengter Route. Davon
  // gibt es in der ganzen Geschichte der App null. Diese hier zaehlt jeden
  // Beitrag.
  BadgeFamilie(
    schluessel: 'beitraege',
    titel: 'Beiträge',
    metrik: BadgeMetrik.beitraege,
    einheit: 'Beiträge',
    stufen: [
      BadgeStufe(
        id: 'badge_62',
        schwelle: 1,
        anleitung: 'Schreibe deinen ersten Beitrag.',
      ),
      BadgeStufe(
        id: 'badge_63',
        schwelle: 5,
        anleitung: 'Schreibe fünf Beiträge.',
      ),
      BadgeStufe(
        id: 'badge_64',
        schwelle: 20,
        anleitung: 'Schreibe zwanzig Beiträge.',
      ),
    ],
  ),
  // GEMESSEN: `post_hashtags` (Migration 20260824102000) hat 0 Zeilen — die
  // Funktion ist zwei Tage alt. Die erste Stufe ist deshalb bewusst EIN
  // Hashtag: genau Vuckos „benutze einen hashtag". Gezaehlt werden eigene
  // BEITRAEGE mit mindestens einem Hashtag, nicht die Hashtags selbst; sonst
  // brächte ein einziger Beitrag mit zwanzig Schlagworten die hoechste Stufe.
  BadgeFamilie(
    schluessel: 'hashtags',
    titel: 'Hashtags',
    metrik: BadgeMetrik.hashtagBeitraege,
    einheit: 'Beiträge',
    stufen: [
      BadgeStufe(
        id: 'badge_65',
        schwelle: 1,
        anleitung: 'Setze in einen Beitrag einen Hashtag.',
      ),
      BadgeStufe(
        id: 'badge_66',
        schwelle: 5,
        anleitung: 'Schreibe fünf Beiträge mit Hashtag.',
      ),
      BadgeStufe(
        id: 'badge_67',
        schwelle: 20,
        anleitung: 'Schreibe zwanzig Beiträge mit Hashtag.',
      ),
    ],
  ),
  // GEMESSEN: 8 Meldungen von 2 Nutzern, eine Person allein hat 7. Die zweite
  // Stufe steht auf 5 (diese Person haette sie), die dritte auf 20.
  //
  // Gezaehlt werden EIGENE Meldungen in `road_incidents` (Spalte
  // `reported_by`). Bestaetigungen fremder Meldungen zaehlen bewusst NICHT:
  // die sind ein Tastendruck und laden zum Klicken auf Verdacht ein — genau
  // das, wogegen der Missbrauchsschutz vom 26.07. gebaut wurde.
  BadgeFamilie(
    schluessel: 'meldungen',
    titel: 'Meldungen',
    metrik: BadgeMetrik.meldungen,
    einheit: 'Meldungen',
    stufen: [
      BadgeStufe(
        id: 'badge_68',
        schwelle: 1,
        anleitung: 'Melde eine Baustelle oder einen Stau.',
      ),
      BadgeStufe(
        id: 'badge_69',
        schwelle: 5,
        anleitung: 'Setze fünf Meldungen ab.',
      ),
      BadgeStufe(
        id: 'badge_70',
        schwelle: 20,
        anleitung: 'Setze zwanzig Meldungen ab.',
      ),
    ],
  ),
];

/// Die Kennzahlen eines Nutzers in der Form, die [badgeFamilien] versteht.
///
/// Freischaltung (GamificationService) und Anzeige (Sammlung) fuellen dieselbe
/// Tabelle — dadurch koennen sie nicht auseinanderlaufen.
Map<BadgeMetrik, double> badgeMetriken({
  int level = 0,
  double totalKm = 0,
  double totalHours = 0,
  int completedRides = 0,
  int completedGroupRides = 0,
  int routePosts = 0,
  int createdGroups = 0,
  int savedRoutes = 0,
  double longestRideKm = 0,
  int fruehFahrten = 0,
  int nachtFahrten = 0,
  int wochenendFahrten = 0,
  int besteSerieTage = 0,
  int kurvenjagdFahrten = 0,
  int gefahreneStile = 0,
  int rundkurse = 0,
  int aNachBFahrten = 0,
  int fahrzeuge = 0,
  int beitraege = 0,
  int hashtagBeitraege = 0,
  int meldungen = 0,
}) {
  return {
    BadgeMetrik.level: level.toDouble(),
    BadgeMetrik.gesamtKm: totalKm,
    BadgeMetrik.gesamtStunden: totalHours,
    BadgeMetrik.fahrten: completedRides.toDouble(),
    BadgeMetrik.gruppenfahrten: completedGroupRides.toDouble(),
    BadgeMetrik.geteilteRouten: routePosts.toDouble(),
    BadgeMetrik.gegruendeteGruppen: createdGroups.toDouble(),
    BadgeMetrik.gespeicherteRouten: savedRoutes.toDouble(),
    BadgeMetrik.laengsteFahrt: longestRideKm,
    BadgeMetrik.kurvenjagd: kurvenjagdFahrten.toDouble(),
    BadgeMetrik.wochenendFahrten: wochenendFahrten.toDouble(),
    BadgeMetrik.serieTage: besteSerieTage.toDouble(),
    BadgeMetrik.rundkurse: rundkurse.toDouble(),
    BadgeMetrik.aNachBFahrten: aNachBFahrten.toDouble(),
    BadgeMetrik.fruehFahrten: fruehFahrten.toDouble(),
    BadgeMetrik.nachtFahrten: nachtFahrten.toDouble(),
    BadgeMetrik.gefahreneStile: gefahreneStile.toDouble(),
    BadgeMetrik.fahrzeuge: fahrzeuge.toDouble(),
    BadgeMetrik.beitraege: beitraege.toDouble(),
    BadgeMetrik.hashtagBeitraege: hashtagBeitraege.toDouble(),
    BadgeMetrik.meldungen: meldungen.toDouble(),
  };
}

/// Alle Badge-IDs, deren Schwelle mit diesen Kennzahlen erreicht ist.
///
/// Das ist die gesamte Freischaltungslogik. Frueher waren das rund dreissig
/// einzelne `if`-Zeilen im GamificationService.
List<String> erfuellteBadgeIds(Map<BadgeMetrik, double> metriken) {
  final ids = <String>[];
  for (final familie in badgeFamilien) {
    final wert = metriken[familie.metrik] ?? 0;
    for (final stufe in familie.alleStufen) {
      if (wert >= stufe.schwelle) ids.add(stufe.id);
    }
  }
  return ids;
}

/// Die Familie, in der dieses Badge steht (null bei stufenlosen Badges wie
/// Gruendungszeit).
BadgeFamilie? badgeFamilieVon(String schluessel) {
  for (final familie in badgeFamilien) {
    if (familie.schluessel == schluessel) return familie;
  }
  return null;
}

/// Die Tabellen-Zeile zu einer Badge-ID.
({BadgeFamilie familie, BadgeStufe stufe})? badgeBedingungFuer(String badgeId) {
  for (final familie in badgeFamilien) {
    for (final stufe in familie.alleStufen) {
      if (stufe.id == badgeId) return (familie: familie, stufe: stufe);
    }
  }
  return null;
}

/// Fortschritt zu EINEM bestimmten Badge, gemessen an dessen eigener Schwelle.
BadgeFortschritt? badgeFortschrittAus(
  String badgeId,
  Map<BadgeMetrik, double> metriken,
) {
  final zeile = badgeBedingungFuer(badgeId);
  if (zeile == null) return null;
  return BadgeFortschritt(
    aktuell: metriken[zeile.familie.metrik] ?? 0,
    ziel: zeile.stufe.schwelle,
    einheit: zeile.familie.einheit,
    anleitung: zeile.stufe.anleitung,
  );
}

/// Fortschritt zur NAECHSTEN noch nicht erreichten Stufe einer Familie.
///
/// 2026-08-18 (Aufgabe 4.2): Vuckos Wunsch aus der Testfahrt war woertlich
/// „wenn sie schon 274 gefahren sind soll man den fortschritt sehen". In der
/// Sammlung steht die Familie als Block; der Balken zeigt deshalb nicht die
/// erste Stufe, sondern die naechste, die noch fehlt. Ist alles erreicht,
/// liefert die Funktion null (dann gibt es nichts mehr anzuzeigen).
BadgeFortschritt? badgeFamilienFortschritt({
  required String familie,
  required Set<String> erreichteBadgeIds,
  required Map<BadgeMetrik, double> metriken,
}) {
  final f = badgeFamilieVon(familie);
  if (f == null) return null;
  final wert = metriken[f.metrik] ?? 0;
  BadgeStufe? naechste;
  for (final stufe in f.alleStufen) {
    if (erreichteBadgeIds.contains(stufe.id)) continue;
    if (naechste == null || stufe.schwelle < naechste.schwelle) {
      naechste = stufe;
    }
  }
  if (naechste == null) return null;
  return BadgeFortschritt(
    aktuell: wert,
    ziel: naechste.schwelle,
    einheit: f.einheit,
    anleitung: naechste.anleitung,
  );
}

/// Die EINE Stelle, die weiss, wie weit jemand von jedem Badge entfernt ist.
///
/// Liest dieselbe Tabelle wie die Freischaltung ([badgeFamilien]), kann also
/// nicht mehr davon abweichen. Badges ohne messbaren Fortschritt
/// (Gruendungszeit, Startklar) liefern null.
BadgeFortschritt? badgeFortschrittFuer({
  required String badgeId,
  required int level,
  required double totalKm,
  required double totalHours,
  required int completedRides,
  required int completedGroupRides,
  required int routePosts,
  required int createdGroups,
  required int savedRoutes,
  required double longestRideKm,
  int fruehFahrten = 0,
  int nachtFahrten = 0,
  int wochenendFahrten = 0,
  int besteSerieTage = 0,
  int kurvenjagdFahrten = 0,
  int gefahreneStile = 0,
  int rundkurse = 0,
  int aNachBFahrten = 0,
  int fahrzeuge = 0,
  int beitraege = 0,
  int hashtagBeitraege = 0,
  int meldungen = 0,
}) {
  return badgeFortschrittAus(
    badgeId,
    badgeMetriken(
      level: level,
      totalKm: totalKm,
      totalHours: totalHours,
      completedRides: completedRides,
      completedGroupRides: completedGroupRides,
      routePosts: routePosts,
      createdGroups: createdGroups,
      savedRoutes: savedRoutes,
      longestRideKm: longestRideKm,
      fruehFahrten: fruehFahrten,
      nachtFahrten: nachtFahrten,
      wochenendFahrten: wochenendFahrten,
      besteSerieTage: besteSerieTage,
      kurvenjagdFahrten: kurvenjagdFahrten,
      gefahreneStile: gefahreneStile,
      rundkurse: rundkurse,
      aNachBFahrten: aNachBFahrten,
      fahrzeuge: fahrzeuge,
      beitraege: beitraege,
      hashtagBeitraege: hashtagBeitraege,
      meldungen: meldungen,
    ),
  );
}
