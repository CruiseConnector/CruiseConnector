/// Ein Badge das der Nutzer verdienen kann.
class Badge {
  /// 2026-08-14 (vucko Tutorial-Badge): badge_15 „Gründungszeit" bekommt JEDER
  /// registrierte Nutzer. Die Beschreibung trägt den Platzhalter
  /// [membershipDatePlaceholder], den die Renderer zur Anzeige dynamisch mit
  /// dem Beitrittsmonat (profiles.created_at) ersetzen — [Badge.all] bleibt
  /// dadurch const, der Sonderfall lebt in [resolveDescription].
  static const String membershipBadgeId = 'badge_15';

  /// 2026-08-14 (vucko Starter-Paket): badge_16 „Startklar" gibt es fuer das
  /// Erfuellen der fuenf Starter-Aufgaben — zusammen mit der Doppel-XP-Woche.
  static const String starterBadgeId = 'badge_16';
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
      assetPath: 'lib/images/badges/badge_01_first_drive.png',
    ),
    Badge(
      id: 'badge_02',
      name: 'Erste Fahrt',
      description: 'Fahre deine erste Route bis zum Ende.',
      emoji: '\u{1F3C1}',
      category: 'routes',
      familie: 'fahrten',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_02_bronze_road.png',
    ),
    Badge(
      id: 'badge_03',
      name: 'Level 25',
      description: 'Erreiche Level 25.',
      emoji: '\u{1F6E3}\uFE0F',
      category: 'level',
      familie: 'level',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_03_silver_road_shield.png',
    ),
    Badge(
      id: 'badge_04',
      name: 'Gruppen-Finisher',
      description: 'Schließe deine erste gestartete Gruppenfahrt komplett ab.',
      emoji: '\u{1F465}',
      category: 'groups',
      familie: 'gruppenfahrt',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_04_silver_turbo_wings.png',
    ),
    Badge(
      id: 'badge_05',
      name: 'Erster Routenpost',
      description: 'Poste deine erste Route.',
      emoji: '\u{1F4E3}',
      category: 'social',
      familie: 'geteilt',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_05_silver_road_shield_alt.png',
    ),
    Badge(
      id: 'badge_06',
      name: '500 km',
      description: 'Fahre insgesamt 500 km.',
      emoji: '\u{1F30D}',
      category: 'distance',
      familie: 'distanz',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_06_silver_steering_wings.png',
    ),
    Badge(
      id: 'badge_07',
      name: 'Gründe eine Gruppe',
      description: 'Erstelle deine erste öffentliche oder private Gruppe.',
      emoji: '\u{1F91D}',
      category: 'groups',
      familie: 'gegruendet',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_07_silver_turbo.png',
    ),
    Badge(
      id: 'badge_08',
      name: 'Level 50',
      description: 'Erreiche Level 50.',
      emoji: '\u{1F3CE}\uFE0F',
      category: 'level',
      familie: 'level',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_08_silver_road_shield_alt_2.png',
    ),
    Badge(
      id: 'badge_09',
      name: '5 Routen gespeichert',
      description: 'Speichere 5 verschiedene Routen.',
      emoji: '\u{1F5FA}\uFE0F',
      category: 'saved',
      familie: 'gespeichert',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_09_gold_finish_flag.png',
    ),
    Badge(
      id: 'badge_10',
      name: '2.500 km',
      description: 'Fahre insgesamt 2.500 km.',
      emoji: '\u{1F3C6}',
      category: 'distance',
      familie: 'distanz',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_10_gold_steering.png',
    ),
    Badge(
      id: 'badge_13',
      name: '10.000 km',
      description: 'Fahre insgesamt 10.000 km.',
      emoji: '\u{1F451}',
      category: 'distance',
      familie: 'distanz',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_13_purple_crown_steering.png',
    ),
    Badge(
      id: 'badge_14',
      name: 'Level 100',
      description: 'Erreiche das maximale Level 100.',
      emoji: '\u{1F48E}',
      category: 'level',
      familie: 'level',
      assetPath: 'lib/images/badges/badge_14_purple_road_shield.png',
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
      assetPath: 'lib/images/badges/badge_12_gold_finish_flag_alt.png',
    ),
    // 2026-08-14 (vucko Starter-Paket): Belohnung fuer die Starter-Aufgaben.
    Badge(
      id: starterBadgeId,
      name: 'Startklar',
      description:
          'Alle Starter-Aufgaben erledigt. Dein Einstieg ist geschafft.',
      emoji: '\u{1F3C1}',
      category: 'membership',
      assetPath: 'lib/images/badges/badge_16_amber_ignition.png',
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
      assetPath: 'lib/images/badges/badge_17_copper_gauge.png',
    ),
    Badge(
      id: 'badge_18',
      name: 'Dauerbrenner',
      description: 'Fünfzig abgeschlossene Fahrten. Das ist kein Hobby mehr.',
      emoji: '\u{1F525}',
      category: 'routes',
      familie: 'fahrten',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_18_steel_piston.png',
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
      assetPath: 'lib/images/badges/badge_19_convoy_wings.png',
    ),
    Badge(
      id: 'badge_20',
      name: 'Langstrecke',
      description:
          'Über 100 Kilometer in einer einzigen Fahrt. Respekt.',
      emoji: '\u{1F6E3}',
      category: 'distance',
      familie: 'langstrecke',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_20_roadhorizon_gold.png',
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
      assetPath: 'lib/images/badges/badge_21_scout_pin.png',
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
      assetPath: 'lib/images/badges/badge_22_hours_teal.png',
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
      assetPath: 'lib/images/badges/badge_23_dawn_amber.png',
    ),
    Badge(
      id: 'badge_24',
      name: 'Nachtschwärmer',
      description: 'Nach 22 Uhr noch unterwegs. Die Nacht ist deine Strecke.',
      emoji: '\u{1F319}',
      category: 'routes',
      familie: 'nacht',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_24_night_indigo.png',
    ),
    Badge(
      id: 'badge_25',
      name: 'Wochenendfahrer',
      description: 'Fünf Fahrten am Wochenende. Samstag ist Cruise-Tag.',
      emoji: '\u{1F4C6}',
      category: 'routes',
      familie: 'wochenende',
      stufe: 1,
      assetPath: 'lib/images/badges/badge_25_weekend_lime.png',
    ),
    Badge(
      id: 'badge_26',
      name: 'Serienfahrer',
      description: 'Sieben Tage in Folge gefahren. Das nennt man Gewohnheit.',
      emoji: '\u{1F525}',
      category: 'routes',
      familie: 'serie',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_26_streak_flame.png',
    ),
    Badge(
      id: 'badge_27',
      name: 'Kurvenkönig',
      description: 'Zehn Kurvenjagd-Fahrten bis zum Ende. Kein Bogen zu eng.',
      emoji: '\u{1F3CE}',
      category: 'routes',
      familie: 'kurven',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_27_curve_crimson.png',
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
      assetPath: 'lib/images/badges/badge_28_styles_prism.png',
    ),
    Badge(
      id: 'badge_29',
      name: 'Rundkurs-Fan',
      description: 'Fünfzehn Rundkurse. Immer wieder gern nach Hause.',
      emoji: '\u{1F501}',
      category: 'routes',
      familie: 'rundkurs',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_29_loop_teal.png',
    ),
    Badge(
      id: 'badge_30',
      name: 'Zielstrebig',
      description: 'Fünfzehn Fahrten von A nach B. Du weißt, wo du hinwillst.',
      emoji: '\u{1F3AF}',
      category: 'routes',
      familie: 'zielstrebig',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_30_target_blue.png',
    ),
    Badge(
      id: 'badge_31',
      name: '1.000 km',
      description: 'Tausend Kilometer insgesamt. Vierstellig.',
      emoji: '\u{1F6E3}',
      category: 'distance',
      familie: 'distanz',
      assetPath: 'lib/images/badges/badge_31_1000km_gold.png',
    ),
    Badge(
      id: 'badge_32',
      name: '5.000 km',
      description: 'Fünftausend Kilometer insgesamt. Halber Weg zur Legende.',
      emoji: '\u{1F30D}',
      category: 'distance',
      familie: 'distanz',
      assetPath: 'lib/images/badges/badge_32_5000km_violet.png',
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
      assetPath: 'lib/images/badges/badge_34_collector_emerald.png',
    ),
    Badge(
      id: 'badge_35',
      name: 'Gruppengründer',
      description: 'Drei Gruppen gegründet. Du bringst Leute zusammen.',
      emoji: '\u{1F465}',
      category: 'groups',
      familie: 'gegruendet',
      stufe: 2,
      assetPath: 'lib/images/badges/badge_35_founder_ruby.png',
    ),
    Badge(
      id: 'badge_36',
      name: 'Community-Stimme',
      description: 'Fünfzehn Routen geteilt. Andere fahren, was du findest.',
      emoji: '\u{1F4E3}',
      category: 'social',
      familie: 'geteilt',
      stufe: 3,
      assetPath: 'lib/images/badges/badge_36_voice_coral.png',
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
      emoji: '\u{1F697}',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_19_convoy_wings.png',
      familie: 'gruppenfahrt',
      stufe: 3,
    ),
    Badge(
      id: 'badge_38',
      name: 'Szenegründer',
      description: 'Zehn Gruppen gegründet. Du baust eine ganze Szene auf.',
      emoji: '\u{1F465}',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_35_founder_ruby.png',
      familie: 'gegruendet',
      stufe: 3,
    ),
    Badge(
      id: 'badge_39',
      name: 'Archivar',
      description: 'Vierzig Routen gespeichert. Dein Archiv ist beachtlich.',
      emoji: '\u{1F4DA}',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_34_collector_emerald.png',
      familie: 'gespeichert',
      stufe: 3,
    ),
    Badge(
      id: 'badge_40',
      name: 'Zehn Stunden',
      description: 'Zehn Stunden am Lenkrad. Der Anfang einer langen Strecke.',
      emoji: '\u{23F1}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_22_hours_teal.png',
      familie: 'stunden',
      stufe: 1,
    ),
    Badge(
      id: 'badge_41',
      name: 'Kurvenfreund',
      description: 'Drei Kurvenjagd-Fahrten beendet. Du hast Geschmack '
          'gefunden.',
      emoji: '\u{1F3CE}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_27_curve_crimson.png',
      familie: 'kurven',
      stufe: 1,
    ),
    Badge(
      id: 'badge_42',
      name: 'Kurvenmeister',
      description: 'Fünfundzwanzig Kurvenjagd-Fahrten. Jede Serpentine kennt '
          'dich.',
      emoji: '\u{1F3C1}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_27_curve_crimson.png',
      familie: 'kurven',
      stufe: 3,
    ),
    Badge(
      id: 'badge_43',
      name: 'Weitfahrer',
      description: 'Über 200 Kilometer in einer einzigen Fahrt. Ein ganzer '
          'Tag Straße.',
      emoji: '\u{1F6E3}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_20_roadhorizon_gold.png',
      familie: 'langstrecke',
      stufe: 2,
    ),
    Badge(
      id: 'badge_44',
      name: 'Grenzgänger',
      description: 'Über 300 Kilometer am Stück. Das ist eine Reise, keine '
          'Runde.',
      emoji: '\u{1F30D}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_20_roadhorizon_gold.png',
      familie: 'langstrecke',
      stufe: 3,
    ),
    Badge(
      id: 'badge_45',
      name: 'Wochenend-Stammgast',
      description: 'Zwanzig Fahrten am Wochenende. Der Samstag gehört dem '
          'Auto.',
      emoji: '\u{1F4C6}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_25_weekend_lime.png',
      familie: 'wochenende',
      stufe: 2,
    ),
    Badge(
      id: 'badge_46',
      name: 'Wochenend-Legende',
      description: 'Fünfzig Fahrten am Wochenende. Zwei Tage, ein Plan.',
      emoji: '\u{1F3C6}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_25_weekend_lime.png',
      familie: 'wochenende',
      stufe: 3,
    ),
    Badge(
      id: 'badge_47',
      name: 'Drei in Folge',
      description: 'Drei Tage hintereinander gefahren. Der Anfang einer Serie.',
      emoji: '\u{1F525}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_26_streak_flame.png',
      familie: 'serie',
      stufe: 1,
    ),
    Badge(
      id: 'badge_48',
      name: 'Dreißig Tage Serie',
      description: 'Dreißig Tage in Folge gefahren. Das schafft kaum jemand.',
      emoji: '\u{1F525}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_26_streak_flame.png',
      familie: 'serie',
      stufe: 3,
    ),
    Badge(
      id: 'badge_49',
      name: 'Runden-Einsteiger',
      description: 'Fünf Rundkurse gefahren. Immer schön wieder heim.',
      emoji: '\u{1F501}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_29_loop_teal.png',
      familie: 'rundkurs',
      stufe: 1,
    ),
    Badge(
      id: 'badge_50',
      name: 'Runden-Legende',
      description: 'Fünfzig Rundkurse. Deine Heimatrunden sind Kult.',
      emoji: '\u{1F501}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_29_loop_teal.png',
      familie: 'rundkurs',
      stufe: 3,
    ),
    Badge(
      id: 'badge_51',
      name: 'Wegfinder',
      description: 'Fünf Fahrten von A nach B. Du hast ein Ziel vor Augen.',
      emoji: '\u{1F3AF}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_30_target_blue.png',
      familie: 'zielstrebig',
      stufe: 1,
    ),
    Badge(
      id: 'badge_52',
      name: 'Zielsicher',
      description: 'Fünfzig Fahrten von A nach B. Umwege sind für andere.',
      emoji: '\u{1F3AF}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_30_target_blue.png',
      familie: 'zielstrebig',
      stufe: 3,
    ),
    Badge(
      id: 'badge_53',
      name: 'Morgenroutine',
      description: 'Zehn Fahrten vor acht Uhr gestartet. Der Wecker klingelt '
          'gern.',
      emoji: '\u{1F305}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_23_dawn_amber.png',
      familie: 'frueh',
      stufe: 2,
    ),
    Badge(
      id: 'badge_54',
      name: 'Sonnenaufgangsjäger',
      description: 'Dreißig Frühfahrten. Du siehst den Tag vor allen anderen.',
      emoji: '\u{1F305}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_23_dawn_amber.png',
      familie: 'frueh',
      stufe: 3,
    ),
    Badge(
      id: 'badge_55',
      name: 'Nachtfahrer',
      description: 'Zehn Fahrten nach 22 Uhr. Die leeren Straßen sind deine.',
      emoji: '\u{1F319}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_24_night_indigo.png',
      familie: 'nacht',
      stufe: 2,
    ),
    Badge(
      id: 'badge_56',
      name: 'Mitternachtsclub',
      description: 'Dreißig Nachtfahrten. Der Mond kennt deine Route.',
      emoji: '\u{1F319}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_24_night_indigo.png',
      familie: 'nacht',
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

  String get zahlen {
    String f(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    return '${f(aktuell)} von ${f(ziel)} $einheit';
  }
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
        anleitung: 'Bringe fuenfzig Fahrten bis zum Ende.',
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
        anleitung: 'Fahre einmal ueber 100 Kilometer am Stueck.',
      ),
      BadgeStufe(
        id: 'badge_43',
        schwelle: 200,
        anleitung: 'Fahre einmal ueber 200 Kilometer am Stueck.',
      ),
      BadgeStufe(
        id: 'badge_44',
        schwelle: 300,
        anleitung: 'Fahre einmal ueber 300 Kilometer am Stueck.',
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
        anleitung: 'Bringe fuenfundzwanzig Fahrten im Stil Kurvenjagd zu Ende.',
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
        anleitung: 'Bringe fuenf Rundkurse zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_29',
        schwelle: 15,
        anleitung: 'Bringe fuenfzehn Rundkurse zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_50',
        schwelle: 50,
        anleitung: 'Bringe fuenfzig Rundkurse zu Ende.',
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
        anleitung: 'Bringe fuenf Fahrten von A nach B zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_30',
        schwelle: 15,
        anleitung: 'Bringe fuenfzehn Fahrten von A nach B zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_52',
        schwelle: 50,
        anleitung: 'Bringe fuenfzig Fahrten von A nach B zu Ende.',
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
        anleitung: 'Fahre an dreissig Tagen hintereinander.',
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
        anleitung: 'Bringe fuenf Fahrten am Samstag oder Sonntag zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_45',
        schwelle: 20,
        anleitung: 'Bringe zwanzig Fahrten am Samstag oder Sonntag zu Ende.',
      ),
      BadgeStufe(
        id: 'badge_46',
        schwelle: 50,
        anleitung: 'Bringe fuenfzig Fahrten am Samstag oder Sonntag zu Ende.',
      ),
    ],
  ),
  BadgeFamilie(
    schluessel: 'frueh',
    titel: 'Frueh unterwegs',
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
        anleitung: 'Starte dreissig Fahrten vor acht Uhr morgens.',
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
        anleitung: 'Sei bei dreissig Fahrten nach 22 Uhr unterwegs.',
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
        anleitung: 'Beende fuenf Gruppenfahrten gemeinsam.',
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
    titel: 'Gegruendete Gruppen',
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
        anleitung: 'Teile fuenf Routen mit der Community.',
      ),
      BadgeStufe(
        id: 'badge_36',
        schwelle: 15,
        anleitung: 'Teile fuenfzehn Routen mit der Community.',
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
        anleitung: 'Speichere fuenf verschiedene Routen.',
      ),
      BadgeStufe(
        id: 'badge_34',
        schwelle: 15,
        anleitung: 'Speichere fuenfzehn verschiedene Routen.',
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
    ),
  );
}
