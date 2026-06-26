/// Shared string semantics for route modes, styles and persisted route types.
///
/// Supabase rows, Edge Functions and Flutter UI historically use a mix of
/// display labels (`Sport Mode`), DB keys (`sport_mode`) and legacy aliases
/// (`sport`). Keep those mappings in one place so routing and pool logic do
/// not drift apart again.
class RouteSemantics {
  const RouteSemantics._();

  static String normalizeStyleKey(String style) {
    final cleaned = style
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'standard' : cleaned;
  }

  static Set<String> styleKeyAliases(String style) {
    final normalized = normalizeStyleKey(style);
    if (normalized == 'sport' ||
        normalized == 'sport_mode' ||
        normalized == 'sportmode') {
      return const {'sport_mode', 'sport'};
    }
    if (normalized == 'kurvenjagd' ||
        normalized == 'kurvenreich' ||
        normalized == 'curvy' ||
        normalized == 'curves' ||
        normalized == 'alpenstrassen' ||
        normalized == 'alpenstrasse' ||
        normalized == 'alpenstra_en') {
      return const {
        'kurvenjagd',
        'kurvenreich',
        'curvy',
        'alpenstrassen',
        'alpenstrasse',
        'alpenstra_en',
      };
    }
    return {normalized};
  }

  static bool styleKeyMatches(String style, Set<String> aliases) {
    final normalized = normalizeStyleKey(style);
    return aliases.any((alias) => sameText(normalized, alias));
  }

  static List<String> normalizeStyleKeyList(List<String> styles) {
    return styles.map(normalizeStyleKey).toList(growable: false);
  }

  static String normalizeRouteType(String routeType) {
    final cleaned = routeType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned == 'round_trip' ||
        cleaned == 'roundtrip' ||
        cleaned == 'rundkurs') {
      return 'ROUND_TRIP';
    }
    if (cleaned == 'point_to_point' ||
        cleaned == 'pointtopoint' ||
        cleaned == 'a_b' ||
        cleaned == 'ab') {
      return 'POINT_TO_POINT';
    }
    return routeType.trim().toUpperCase();
  }

  static bool routeTypeMatches(String? left, String? right) {
    return normalizeRouteType(left ?? '') == normalizeRouteType(right ?? '');
  }

  static Set<String> routeTypeAliases(String routeType) {
    return switch (normalizeRouteType(routeType)) {
      'ROUND_TRIP' => const {
        'ROUND_TRIP',
        'round_trip',
        'roundtrip',
        'Rundkurs',
      },
      'POINT_TO_POINT' => const {
        'POINT_TO_POINT',
        'point_to_point',
        'pointtopoint',
      },
      final normalized => {normalized},
    };
  }

  static bool sameText(String? left, String? right) {
    return (left ?? '').trim().toLowerCase() ==
        (right ?? '').trim().toLowerCase();
  }
}
