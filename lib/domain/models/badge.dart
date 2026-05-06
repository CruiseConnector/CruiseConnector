/// Ein Badge das der Nutzer verdienen kann.
class Badge {
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
      description: 'Schließe 5 gestartete Gruppenfahrten komplett ab.',
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
  ];

  static Badge? getById(String id) {
    try {
      return all.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }
}
