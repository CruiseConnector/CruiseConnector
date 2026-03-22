import 'dart:math';

/// XP-basiertes Level-System mit progressiver Kurve.
/// Anfangs erreichbar (Level 2 bei 100 XP), wird dann stetig anspruchsvoller.
///
/// XP-Quellen:
///   - 10 XP pro gefahrenem km
///   - 5 XP pro Kurve auf der Route
///   - Stil-Bonus: Kurvenjagd +20, Entdecker +15, Sport Mode +10
///
/// Beispiel: 50km-Route mit 8 Kurven im Sport Mode = 500 + 40 + 10 = 550 XP
class UserLevel {
  const UserLevel._({
    required this.level,
    required this.name,
    required this.totalXpRequired,
    required this.currentXp,
    required this.xpToNextLevel,
    required this.progress,
  });

  final int level;
  final String name;
  final double totalXpRequired;
  final double currentXp;
  final int xpToNextLevel;
  final double progress; // 0.0 - 1.0

  static const _names = [
    'Street Rookie',     // 1  —   0 XP
    'City Cruiser',      // 2  — 100 XP  (~1 kurze Route)
    'Road Explorer',     // 3  — 350 XP  (~3-4 Routen)
    'Highway Hero',      // 4  — 800 XP  (~8 Routen)
    'Mountain Rider',    // 5  — 1500 XP (~15 Routen)
    'Canyon Racer',      // 6  — 2500 XP (~25 Routen)
    'Alpine Master',     // 7  — 4000 XP (~40 Routen)
    'Storm Chaser',      // 8  — 6000 XP (~60 Routen)
    'Night Legend',      // 9  — 9000 XP (~90 Routen)
    'Road King',         // 10 — 13000 XP (~130 Routen)
    'Cruise Titan',      // 11 — 18000 XP (~180 Routen)
    'Eternal Driver',    // 12 — 25000 XP (~250 Routen)
  ];

  /// XP-Schwellenwerte pro Level.
  /// Progressive Kurve: Formel xp = 50 * level^2 + 50 * level - 100
  /// Level 1: 0, Level 2: 100, Level 3: 350, Level 4: 800, ...
  static double xpForLevel(int level) {
    if (level <= 1) return 0;
    // Vordefinierte Werte für exakte Kontrolle über die Kurve
    const thresholds = [
      0,      // Level 1
      100,    // Level 2
      350,    // Level 3
      800,    // Level 4
      1500,   // Level 5
      2500,   // Level 6
      4000,   // Level 7
      6000,   // Level 8
      9000,   // Level 9
      13000,  // Level 10
      18000,  // Level 11
      25000,  // Level 12
    ];
    if (level - 1 < thresholds.length) return thresholds[level - 1].toDouble();
    // Über Level 12: Exponentiell weiterwachsen
    return 25000.0 + 10000.0 * (level - 12);
  }

  /// Berechnet das Level und den Fortschritt aus den gesammelten XP.
  factory UserLevel.fromXp(double totalXp) {
    int level = 1;
    while (level < 50 && xpForLevel(level + 1) <= totalXp) {
      level++;
    }

    final currentLevelXp = xpForLevel(level);
    final nextLevelXp = xpForLevel(level + 1);
    final xpInLevel = totalXp - currentLevelXp;
    final xpNeeded = nextLevelXp - currentLevelXp;
    final progress = xpNeeded > 0 ? (xpInLevel / xpNeeded).clamp(0.0, 1.0) : 1.0;
    final xpToNext = max(0, (nextLevelXp - totalXp).ceil());

    final nameIndex = (level - 1).clamp(0, _names.length - 1);

    return UserLevel._(
      level: level,
      name: _names[nameIndex],
      totalXpRequired: nextLevelXp,
      currentXp: totalXp,
      xpToNextLevel: xpToNext,
      progress: progress,
    );
  }

  /// Backwards-compat: fromKm delegiert an fromXp (für Altdaten).
  factory UserLevel.fromKm(double totalKm) => UserLevel.fromXp(totalKm * 10);
}
