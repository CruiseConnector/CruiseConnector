/// Ein Badge das der Nutzer verdienen kann.
class Badge {
  const Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.category,
  });

  final String id;
  final String name;
  final String description;
  final String emoji;
  final String category; // 'distance', 'routes', 'style', 'special'

  /// Alle verfügbaren Badges im System.
  static const List<Badge> all = [
    // ── Distanz-Badges ──────────────────────────────────────────────────────
    Badge(id: 'dist_10', name: 'Erste Runde', description: '10 km gefahren', emoji: '\u{1F697}', category: 'distance'),
    Badge(id: 'dist_50', name: 'Stadtfahrer', description: '50 km gefahren', emoji: '\u{1F3D9}\uFE0F', category: 'distance'),
    Badge(id: 'dist_100', name: 'Highway Held', description: '100 km gefahren', emoji: '\u{1F6E3}\uFE0F', category: 'distance'),
    Badge(id: 'dist_500', name: 'Langstrecke', description: '500 km gefahren', emoji: '\u{1F30D}', category: 'distance'),
    Badge(id: 'dist_1000', name: 'Road Warrior', description: '1.000 km gefahren', emoji: '\u{1F3C6}', category: 'distance'),
    Badge(id: 'dist_5000', name: 'Legende', description: '5.000 km gefahren', emoji: '\u{1F451}', category: 'distance'),

    // ── Routen-Badges ───────────────────────────────────────────────────────
    Badge(id: 'route_1', name: 'Erster Start', description: '1 Route abgeschlossen', emoji: '\u{1F3C1}', category: 'routes'),
    Badge(id: 'route_5', name: 'Routensammler', description: '5 Routen abgeschlossen', emoji: '\u{1F5FA}\uFE0F', category: 'routes'),
    Badge(id: 'route_10', name: 'Entdecker', description: '10 Routen abgeschlossen', emoji: '\u{1F9ED}', category: 'routes'),
    Badge(id: 'route_25', name: 'Vielfahrer', description: '25 Routen abgeschlossen', emoji: '\u{1F698}', category: 'routes'),
    Badge(id: 'route_50', name: 'Profi', description: '50 Routen abgeschlossen', emoji: '\u{1F3CE}\uFE0F', category: 'routes'),

    // ── Stil-Badges ─────────────────────────────────────────────────────────
    Badge(id: 'style_kurven', name: 'Kurvenk\u00f6nig', description: '5 Kurvenjagd-Routen', emoji: '\u{1F3D4}\uFE0F', category: 'style'),
    Badge(id: 'style_sport', name: 'Sportfahrer', description: '5 Sport Mode-Routen', emoji: '\u{1F3CE}\uFE0F', category: 'style'),
    Badge(id: 'style_abend', name: 'Nachtfahrer', description: '5 Abendrunden', emoji: '\u{1F319}', category: 'style'),
    Badge(id: 'style_entdecker', name: 'Weltenbummler', description: '5 Entdecker-Routen', emoji: '\u{1F30E}', category: 'style'),

    // ── Spezial-Badges ──────────────────────────────────────────────────────
    Badge(id: 'special_roundtrip', name: 'Rundkurs-Fan', description: '10 Rundkurse gefahren', emoji: '\u{1F504}', category: 'special'),
    Badge(id: 'special_long', name: 'Marathon', description: 'Eine Route \u00fcber 100 km', emoji: '\u{1F3C5}', category: 'special'),
  ];

  static Badge? getById(String id) {
    try {
      return all.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }
}
