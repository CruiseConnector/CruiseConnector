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
  });

  final String id;
  final String name;
  final String description;
  final String emoji;
  final String category;
  final String? assetPath;

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
      assetPath: 'lib/images/badges/badge_01_first_drive.png',
    ),
    Badge(
      id: 'badge_02',
      name: 'Erste Fahrt',
      description: 'Fahre deine erste Route bis zum Ende.',
      emoji: '\u{1F3C1}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_02_bronze_road.png',
    ),
    Badge(
      id: 'badge_03',
      name: 'Level 25',
      description: 'Erreiche Level 25.',
      emoji: '\u{1F6E3}\uFE0F',
      category: 'level',
      assetPath: 'lib/images/badges/badge_03_silver_road_shield.png',
    ),
    Badge(
      id: 'badge_04',
      name: 'Gruppen-Finisher',
      description: 'Schließe deine erste gestartete Gruppenfahrt komplett ab.',
      emoji: '\u{1F465}',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_04_silver_turbo_wings.png',
    ),
    Badge(
      id: 'badge_05',
      name: 'Erster Routenpost',
      description: 'Poste deine erste Route.',
      emoji: '\u{1F4E3}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_05_silver_road_shield_alt.png',
    ),
    Badge(
      id: 'badge_06',
      name: '500 km',
      description: 'Fahre insgesamt 500 km.',
      emoji: '\u{1F30D}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_06_silver_steering_wings.png',
    ),
    Badge(
      id: 'badge_07',
      name: 'Gründe eine Gruppe',
      description: 'Erstelle deine erste öffentliche oder private Gruppe.',
      emoji: '\u{1F91D}',
      category: 'groups',
      assetPath: 'lib/images/badges/badge_07_silver_turbo.png',
    ),
    Badge(
      id: 'badge_08',
      name: 'Level 50',
      description: 'Erreiche Level 50.',
      emoji: '\u{1F3CE}\uFE0F',
      category: 'level',
      assetPath: 'lib/images/badges/badge_08_silver_road_shield_alt_2.png',
    ),
    Badge(
      id: 'badge_09',
      name: '5 Routen gespeichert',
      description: 'Speichere 5 verschiedene Routen.',
      emoji: '\u{1F5FA}\uFE0F',
      category: 'saved',
      assetPath: 'lib/images/badges/badge_09_gold_finish_flag.png',
    ),
    Badge(
      id: 'badge_10',
      name: '2.500 km',
      description: 'Fahre insgesamt 2.500 km.',
      emoji: '\u{1F3C6}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_10_gold_steering.png',
    ),
    Badge(
      id: 'badge_13',
      name: '10.000 km',
      description: 'Fahre insgesamt 10.000 km.',
      emoji: '\u{1F451}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_13_purple_crown_steering.png',
    ),
    Badge(
      id: 'badge_14',
      name: 'Level 100',
      description: 'Erreiche das maximale Level 100.',
      emoji: '\u{1F48E}',
      category: 'level',
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
      assetPath: 'lib/images/badges/badge_17_copper_gauge.png',
    ),
    Badge(
      id: 'badge_18',
      name: 'Dauerbrenner',
      description: 'Fünfzig abgeschlossene Fahrten. Das ist kein Hobby mehr.',
      emoji: '\u{1F525}',
      category: 'routes',
      assetPath: 'lib/images/badges/badge_18_steel_piston.png',
    ),
    Badge(
      id: 'badge_19',
      name: 'Konvoi-Kapitän',
      description:
          'Fünf Gruppenfahrten gemeinsam beendet. Auf dich ist Verlass.',
      emoji: '\u{1F697}',
      category: 'group',
      assetPath: 'lib/images/badges/badge_19_convoy_wings.png',
    ),
    Badge(
      id: 'badge_20',
      name: 'Langstrecke',
      description:
          'Über 100 Kilometer in einer einzigen Fahrt. Respekt.',
      emoji: '\u{1F6E3}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_20_roadhorizon_gold.png',
    ),
    Badge(
      id: 'badge_21',
      name: 'Streckenscout',
      description:
          'Fünf Routen mit der Community geteilt. Andere fahren deine Wege.',
      emoji: '\u{1F4CD}',
      category: 'social',
      assetPath: 'lib/images/badges/badge_21_scout_pin.png',
    ),
    Badge(
      id: 'badge_22',
      name: 'Vielfahrer',
      description:
          'Fünfundzwanzig Stunden hinterm Steuer. Die Straße kennt dich.',
      emoji: '\u{23F1}',
      category: 'distance',
      assetPath: 'lib/images/badges/badge_22_hours_teal.png',
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

/// Die EINE Stelle, die weiss, wie weit jemand von jedem Badge entfernt ist.
///
/// Muss mit den Bedingungen in `GamificationService.calculateAndSync()`
/// uebereinstimmen — die Werte kommen aus demselben `GamificationResult`.
/// Badges ohne messbaren Fortschritt (Gruendungszeit, Startklar) liefern null.
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
}) {
  BadgeFortschritt p(double a, double z, String e, String t) =>
      BadgeFortschritt(aktuell: a, ziel: z, einheit: e, anleitung: t);
  switch (badgeId) {
    case 'badge_01':
      return p(level.toDouble(), 10, 'Level', 'Sammle XP bis Level 10.');
    case 'badge_03':
      return p(level.toDouble(), 25, 'Level', 'Sammle XP bis Level 25.');
    case 'badge_08':
      return p(level.toDouble(), 50, 'Level', 'Sammle XP bis Level 50.');
    case 'badge_14':
      return p(level.toDouble(), 100, 'Level', 'Erreiche Level 100.');
    case 'badge_02':
      return p(completedRides.toDouble(), 1, 'Fahrten',
          'Fahre eine Route bis zum Ende.');
    case 'badge_17':
      return p(completedRides.toDouble(), 10, 'Fahrten',
          'Bringe zehn Fahrten bis zum Ende.');
    case 'badge_18':
      return p(completedRides.toDouble(), 50, 'Fahrten',
          'Bringe fuenfzig Fahrten bis zum Ende.');
    case 'badge_04':
      return p(completedGroupRides.toDouble(), 1, 'Gruppenfahrten',
          'Beende eine Gruppenfahrt gemeinsam.');
    case 'badge_19':
      return p(completedGroupRides.toDouble(), 5, 'Gruppenfahrten',
          'Beende fuenf Gruppenfahrten gemeinsam.');
    case 'badge_05':
      return p(routePosts.toDouble(), 1, 'Routen', 'Teile eine Route.');
    case 'badge_21':
      return p(routePosts.toDouble(), 5, 'Routen',
          'Teile fuenf Routen mit der Community.');
    case 'badge_07':
      return p(createdGroups.toDouble(), 1, 'Gruppen',
          'Erstelle eine Gruppe.');
    case 'badge_09':
      return p(savedRoutes.toDouble(), 5, 'Routen',
          'Speichere fuenf verschiedene Routen.');
    case 'badge_06':
      return p(totalKm, 500, 'km', 'Fahre insgesamt 500 Kilometer.');
    case 'badge_10':
      return p(totalKm, 2500, 'km', 'Fahre insgesamt 2.500 Kilometer.');
    case 'badge_13':
      return p(totalKm, 10000, 'km', 'Fahre insgesamt 10.000 Kilometer.');
    case 'badge_20':
      return p(longestRideKm, 100, 'km',
          'Fahre einmal ueber 100 Kilometer am Stueck.');
    case 'badge_22':
      return p(totalHours, 25, 'Std', 'Fahre insgesamt 25 Stunden.');
    default:
      return null;
  }
}
