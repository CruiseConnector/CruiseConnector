import 'dart:math';

/// Level-System mit exponentieller Kurve.
/// Anfangs schnell (10 km für Level 2), dann immer schwerer.
class UserLevel {
  const UserLevel._({
    required this.level,
    required this.name,
    required this.totalKmRequired,
    required this.currentKm,
    required this.kmToNextLevel,
    required this.progress,
  });

  final int level;
  final String name;
  final double totalKmRequired;
  final double currentKm;
  final int kmToNextLevel;
  final double progress; // 0.0 - 1.0

  static const _names = [
    'Street Rookie',     // 1
    'City Cruiser',      // 2
    'Road Explorer',     // 3
    'Highway Hero',      // 4
    'Mountain Rider',    // 5
    'Canyon Racer',      // 6
    'Alpine Master',     // 7
    'Storm Chaser',      // 8
    'Night Legend',      // 9
    'Road King',         // 10
    'Cruise Titan',      // 11
    'Eternal Driver',    // 12
  ];

  /// Berechnet die benötigten km für ein bestimmtes Level.
  /// Level 1: 0 km, Level 2: 10 km, Level 3: 30 km, Level 4: 60 km, ...
  /// Formel: km = 5 * level * (level - 1) → quadratische Kurve
  static double kmForLevel(int level) {
    if (level <= 1) return 0;
    return 5.0 * level * (level - 1);
  }

  /// Berechnet das Level und den Fortschritt aus den gefahrenen km.
  factory UserLevel.fromKm(double totalKm) {
    // Finde das aktuelle Level
    int level = 1;
    while (kmForLevel(level + 1) <= totalKm) {
      level++;
    }

    final currentLevelKm = kmForLevel(level);
    final nextLevelKm = kmForLevel(level + 1);
    final kmInLevel = totalKm - currentLevelKm;
    final kmNeeded = nextLevelKm - currentLevelKm;
    final progress = kmNeeded > 0 ? (kmInLevel / kmNeeded).clamp(0.0, 1.0) : 1.0;
    final kmToNext = max(0, (nextLevelKm - totalKm).ceil());

    final nameIndex = (level - 1).clamp(0, _names.length - 1);

    return UserLevel._(
      level: level,
      name: _names[nameIndex],
      totalKmRequired: nextLevelKm,
      currentKm: totalKm,
      kmToNextLevel: kmToNext,
      progress: progress,
    );
  }
}
