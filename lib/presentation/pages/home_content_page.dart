import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_bookmark_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/application/providers/subscription_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/presentation/widgets/ads/ad_post_card.dart';
import 'package:cruise_connect/data/services/home_route_recommendation_service.dart';
import 'package:cruise_connect/data/services/route_elevation_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app_badges;
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_level.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';
import 'package:cruise_connect/presentation/pages/subscription_tier_page.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/widgets/community_carousel_card.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:cruise_connect/presentation/widgets/top_toast.dart';
import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/trip_service.dart';
import 'package:cruise_connect/presentation/pages/saved_route_bookmarks_page.dart';
import 'package:cruise_connect/presentation/widgets/notification_bell_button.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

enum _HomeWidgetId {
  xp,
  todayRoute,
  community,
  communityContacts,
  communityGroups,
  communityEvents,
  weekly,
  streak,
  quickStart,
  savedRoutes,
  profile,
  monthly,
  badgeHunt,
  totals,
}

enum _DashboardWidgetSize { small, large }

enum _DashboardDropIntent { before, after, merge }

class _HomeWidgetMeta {
  const _HomeWidgetMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.defaultSize,
    this.canBeSmall = true,
    this.canBeLarge = true,
  });

  final _HomeWidgetId id;
  final String title;
  final String subtitle;
  final IconData icon;
  final _DashboardWidgetSize defaultSize;
  final bool canBeSmall;
  final bool canBeLarge;
}

class _HomeDashboardItem {
  const _HomeDashboardItem({
    required this.key,
    required this.widgetIds,
    required this.size,
    this.title,
  });

  static const Object _titleSentinel = Object();

  final String key;
  final List<_HomeWidgetId> widgetIds;
  final _DashboardWidgetSize size;
  final String? title;

  bool get isFolder => widgetIds.length > 1;

  _HomeDashboardItem copyWith({
    String? key,
    List<_HomeWidgetId>? widgetIds,
    _DashboardWidgetSize? size,
    Object? title = _titleSentinel,
  }) {
    return _HomeDashboardItem(
      key: key ?? this.key,
      widgetIds: widgetIds ?? this.widgetIds,
      size: size ?? this.size,
      title: identical(title, _titleSentinel) ? this.title : title as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'widgetIds': widgetIds.map((id) => id.name).toList(),
    'size': size.name,
    if (title?.trim().isNotEmpty ?? false) 'title': title!.trim(),
  };

  static _HomeDashboardItem? fromJson(Map<String, dynamic> json) {
    final rawKey = json['key'];
    final rawIds = json['widgetIds'];
    if (rawKey is! String || rawIds is! List) return null;

    final ids = <_HomeWidgetId>[];
    for (final rawId in rawIds) {
      if (rawId is! String) continue;
      for (final id in _HomeWidgetId.values) {
        if (id.name == rawId) {
          ids.add(id);
          break;
        }
      }
    }
    if (ids.isEmpty) return null;

    var size = _DashboardWidgetSize.large;
    final rawSize = json['size'];
    if (rawSize is String) {
      for (final candidate in _DashboardWidgetSize.values) {
        if (candidate.name == rawSize) {
          size = candidate;
          break;
        }
      }
    }

    final rawTitle = json['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? rawTitle.trim()
        : null;

    return _HomeDashboardItem(
      key: rawKey,
      widgetIds: ids,
      size: size,
      title: title,
    );
  }
}

class _HomeWidgetDragPayload {
  const _HomeWidgetDragPayload.existing(this.itemKey) : childId = null;
  const _HomeWidgetDragPayload.fromFolder({
    required String folderKey,
    required _HomeWidgetId this.childId,
  }) : itemKey = folderKey;

  final String itemKey;
  final _HomeWidgetId? childId;

  bool get isFolderChild => childId != null;
  String get identityKey =>
      childId == null ? itemKey : '$itemKey:${childId!.name}';

  bool matches(_HomeWidgetDragPayload other) =>
      itemKey == other.itemKey && childId == other.childId;
}

class _DashboardDropPreview {
  const _DashboardDropPreview({
    required this.payload,
    required this.targetKey,
    required this.intent,
  });

  final _HomeWidgetDragPayload payload;
  final String targetKey;
  final _DashboardDropIntent intent;

  String get sourceKey => payload.itemKey;

  bool matches(_DashboardDropPreview other) {
    return payload.matches(other.payload) &&
        targetKey == other.targetKey &&
        intent == other.intent;
  }
}

class _DashboardLayoutEntry {
  const _DashboardLayoutEntry.item(this.item) : preview = null;
  const _DashboardLayoutEntry.preview(this.item, this.preview);

  final _HomeDashboardItem item;
  final _DashboardDropPreview? preview;

  bool get isPreview => preview != null;
}

class _BadgeGoal {
  const _BadgeGoal({
    required this.badge,
    required this.current,
    required this.target,
    required this.unit,
    required this.action,
    required this.icon,
  });

  final app_badges.Badge badge;
  final double current;
  final double target;
  final String unit;
  final String action;
  final IconData icon;

  double get progress => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);
  bool get complete => progress >= 1.0;
}

class HomeContentPage extends StatefulWidget {
  final Function(int)? onTabChange;
  final int refreshKey;
  const HomeContentPage({super.key, this.onTabChange, this.refreshKey = 0});

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage>
    with TickerProviderStateMixin {
  @override
  void didUpdateWidget(HomeContentPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _loadStats();
    }
  }

  int userLevel = 1;
  double levelProgress = 0;
  String levelName = 'Street Rookie';
  int xpToNextLevel = 100;
  int totalXp = 0;
  int totalRoutes = 0;
  double totalDistanceKm = 0;
  int badgeCount = 0;
  int _savedRouteCount = 0;
  String? _profileUserId;
  String? _avatarUrl;
  String? _profileUsername;
  bool _loading = true;
  List<double> _weeklyChartData = List.filled(7, 0);
  List<double> _weeklyKmData = List.filled(7, 0);
  List<double> _monthlyWeekKmData = List.filled(5, 0);
  double _monthDistanceKm = 0;
  int _monthRoutes = 0;
  int _monthActiveDays = 0;
  List<String> _earnedBadgeIds = const [];
  String? _selectedBadgeHuntId;
  int _streakDays = 0;
  TripSummary? _activeTrip; // 2026-05-24 (vucko Task #53): Resume-Card
  // 2026-07-06 (vucko Fahrt-Resume): unterbrochene Solo-Fahrt (App wurde vom
  // System beendet) → „Fahrt fortsetzen"-Card.
  ActiveRideSnapshot? _resumableRide;
  HomeRouteRecommendation? _todayRecommendation;
  bool _isRouteSaved = false;
  // 2026-06-09 (vucko Audit T3-B): Re-Entry-Guard gegen Doppel-Tap auf Speichern
  // → sonst nebenläufige saveExistingRoute-Calls = doppelte DB-Inserts.
  bool _isSavingRoute = false;
  bool _isClosingTrip = false;
  final Map<String, _HeroRouteInsights> _heroInsightsByRouteId = {};
  final Set<String> _heroInsightsLoading = <String>{};
  late final AnimationController _shimmerController;
  StreamSubscription<void>? _downgradeSub;
  static const String _dashboardPrefsKey = 'home_dashboard_layout_v1';
  static const String _badgeHuntPrefsKey = 'home_badge_hunt_id_v1';
  static const double _dashboardGap = 12;
  static const double _dashboardHalfTileHeight = 184;
  static const double _dashboardFolderFullHeight = 300;
  final Map<String, int> _folderPages = {};
  final Map<String, int> _folderTargetPages = {};
  final Map<String, AnimationController> _folderSlideControllers = {};
  List<_HomeDashboardItem> _dashboardItems = _defaultDashboardItems();
  bool _customizingDashboard = false;
  // ignore: prefer_final_fields
  bool _showLegacyHomeBodyForDebug = false;
  String? _recentlyChangedItemKey;
  String? _activeDropTargetKey;
  String? _draggingDashboardItemKey;
  _DashboardDropPreview? _dropPreview;
  int _dashboardItemSerial = 0;

  static List<_HomeDashboardItem> _defaultDashboardItems() => const [
    _HomeDashboardItem(
      key: 'xp',
      widgetIds: [_HomeWidgetId.xp],
      size: _DashboardWidgetSize.large,
    ),
    _HomeDashboardItem(
      key: 'todayRoute',
      widgetIds: [_HomeWidgetId.todayRoute],
      size: _DashboardWidgetSize.large,
    ),
    _HomeDashboardItem(
      key: 'communityContacts',
      widgetIds: [_HomeWidgetId.communityContacts],
      size: _DashboardWidgetSize.small,
    ),
    _HomeDashboardItem(
      key: 'communityGroups',
      widgetIds: [_HomeWidgetId.communityGroups],
      size: _DashboardWidgetSize.small,
    ),
    _HomeDashboardItem(
      key: 'weekly',
      widgetIds: [_HomeWidgetId.weekly],
      size: _DashboardWidgetSize.small,
    ),
    _HomeDashboardItem(
      key: 'streak',
      widgetIds: [_HomeWidgetId.streak],
      size: _DashboardWidgetSize.large,
    ),
  ];

  static const List<_HomeWidgetMeta> _widgetCatalog = [
    _HomeWidgetMeta(
      id: _HomeWidgetId.xp,
      title: 'XP Anzeige',
      subtitle: 'Level, Fortschritt und Gesamtwerte',
      icon: Icons.bolt_rounded,
      defaultSize: _DashboardWidgetSize.large,
      canBeSmall: false,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.todayRoute,
      title: 'Heute für dich',
      subtitle: 'Route, Trip-Fortsetzung und Fahren-CTA',
      icon: Icons.explore_rounded,
      defaultSize: _DashboardWidgetSize.large,
      canBeSmall: false,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.communityContacts,
      title: 'Kontakte',
      subtitle: 'Neue Fahrer separat anzeigen',
      icon: Icons.person_add_alt_1_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.communityGroups,
      title: 'Gruppen',
      subtitle: 'Öffentliche Gruppen separat anzeigen',
      icon: Icons.groups_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.communityEvents,
      title: 'Events',
      subtitle: 'Events separat anzeigen',
      icon: Icons.event_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.weekly,
      title: 'Letzte 7 Tage',
      subtitle: 'Wochenkilometer und aktive Tage',
      icon: Icons.bar_chart_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.streak,
      title: 'Streak',
      subtitle: 'XP-Multiplikator für heute',
      icon: Icons.local_fire_department_rounded,
      defaultSize: _DashboardWidgetSize.large,
      canBeSmall: false,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.quickStart,
      title: 'Schnellstart',
      subtitle: 'Direkt in den Fahrmodus',
      icon: Icons.directions_car_filled_rounded,
      defaultSize: _DashboardWidgetSize.small,
      canBeLarge: false,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.savedRoutes,
      title: 'Gespeicherte Routen',
      subtitle: 'Deine gemerkten Strecken',
      icon: Icons.bookmarks_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.profile,
      title: 'Profil',
      subtitle: 'Account, Badges und Garage',
      icon: Icons.person_rounded,
      defaultSize: _DashboardWidgetSize.small,
      canBeLarge: false,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.monthly,
      title: 'Monatsansicht',
      subtitle: 'Kilometer, Fahrten und Wochen im Monat',
      icon: Icons.calendar_month_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.badgeHunt,
      title: 'Badge-Jagd',
      subtitle: 'Wähle ein Badge, das du aktiv jagen willst',
      icon: Icons.emoji_events_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
    _HomeWidgetMeta(
      id: _HomeWidgetId.totals,
      title: 'Gesamtwerte',
      subtitle: 'KM, Strecken, Badges und XP kompakt',
      icon: Icons.query_stats_rounded,
      defaultSize: _DashboardWidgetSize.small,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    unawaited(_loadDashboardLayout());
    unawaited(_loadBadgeHuntPreference());
    // 2026-07-23 (vucko "Downgrade auf Free setzt Widgets zurück"): Basic/
    // Premium → Free (Abo abgelaufen/gekündigt) verwirft ein individuell
    // angepasstes Dashboard-Layout automatisch zurück auf den Standard-Satz.
    _downgradeSub = context
        .read<SubscriptionProvider>()
        .downgradeToFreeEvents
        .listen((_) => unawaited(_resetDashboardToDefaultOnDowngrade()));
    // 2026-05-28 (vucko Task #68): Cached Home-Snapshot ASYNC laden damit
    // beim App-Start Level + Wochen-Chart + Lite-Recommendation sofort
    // sichtbar sind statt Skeleton — der Refresh läuft im Hintergrund.
    unawaited(_hydrateFromHomeSnapshot());
    _loadStats();
  }

  bool _initialTierSanitizeDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 2026-07-23 (vucko "Free-Reset auch bei bereits gespeichertem
    // Custom-Layout"): SubscriptionProvider lädt async (init() wird in
    // main.dart NICHT awaitet) — erst wenn `initialized` true ist, ist der
    // Tier-Wert vertrauenswürdig. Erst dann EINMALIG prüfen: falls der
    // Nutzer schon beim allerersten Laden (nicht erst bei einem Downgrade
    // WÄHREND der Session) Free ist, aber noch ein Custom-Layout aus einer
    // früheren Basic/Premium-Zeit gespeichert war, wird es hier bereinigt.
    final subscription = context.watch<SubscriptionProvider>();
    if (!_initialTierSanitizeDone && subscription.initialized) {
      _initialTierSanitizeDone = true;
      if (!subscription.isPaid) {
        unawaited(_resetDashboardToDefaultOnDowngrade());
      }
    }
  }

  /// 2026-05-28 (vucko Task #68): Schneller initial-Render aus dem letzten
  /// gespeicherten Home-Snapshot — User sieht Level, XP-Bar, Wochen-Chart
  /// und eine Lite-Version der Empfehlung sofort beim App-Start. Sobald der
  /// Hintergrund-Refresh (_loadStats) durch ist, wird animiert auf die
  /// frischen Werte umgestellt.
  Future<void> _hydrateFromHomeSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('home_snapshot_v1');
      if (raw == null || !mounted) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      setState(() {
        userLevel = (map['userLevel'] as num?)?.toInt() ?? userLevel;
        levelProgress =
            (map['levelProgress'] as num?)?.toDouble() ?? levelProgress;
        levelName = (map['levelName'] as String?) ?? levelName;
        xpToNextLevel =
            (map['xpToNextLevel'] as num?)?.toInt() ?? xpToNextLevel;
        totalXp = (map['totalXp'] as num?)?.toInt() ?? totalXp;
        totalRoutes = (map['totalRoutes'] as num?)?.toInt() ?? totalRoutes;
        totalDistanceKm =
            (map['totalDistanceKm'] as num?)?.toDouble() ?? totalDistanceKm;
        badgeCount = (map['badgeCount'] as num?)?.toInt() ?? badgeCount;
        _savedRouteCount =
            (map['savedRouteCount'] as num?)?.toInt() ?? _savedRouteCount;
        _monthDistanceKm =
            (map['monthDistanceKm'] as num?)?.toDouble() ?? _monthDistanceKm;
        _monthRoutes = (map['monthRoutes'] as num?)?.toInt() ?? _monthRoutes;
        _monthActiveDays =
            (map['monthActiveDays'] as num?)?.toInt() ?? _monthActiveDays;
        final earned = map['earnedBadgeIds'];
        if (earned is List) {
          _earnedBadgeIds = earned.map((id) => id.toString()).toList();
        }
        _streakDays = (map['streakDays'] as num?)?.toInt() ?? _streakDays;
        final weekly = map['weeklyKm'];
        if (weekly is List && weekly.length == 7) {
          _weeklyKmData = weekly
              .map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList(growable: false);
          final maxKm = _weeklyKmData.fold<double>(0, (a, b) => a > b ? a : b);
          _weeklyChartData = _weeklyKmData
              .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
              .toList(growable: false);
        }
        final monthly = map['monthlyWeekKm'];
        if (monthly is List && monthly.length == 5) {
          _monthlyWeekKmData = monthly
              .map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList(growable: false);
        }
        _profileUsername =
            map['profileUsername'] as String? ?? _profileUsername;
        _avatarUrl = map['avatarUrl'] as String? ?? _avatarUrl;
        // 2026-05-28 (vucko Task #72): Cached Recommendation hydraten
        // damit die "Heute für dich"-Card beim 2.+ App-Start direkt sichtbar
        // ist (statt "Starte deine erste Route" Empty-State).
        final recoRaw = map['recommendation'];
        if (recoRaw is Map) {
          try {
            _todayRecommendation = HomeRouteRecommendation.fromJson(
              Map<String, dynamic>.from(recoRaw),
            );
          } catch (e) {
            debugPrint('[Home] Cached recommendation parse failed: $e');
          }
        }
        // Loading-Flag bleibt true — Card wird sofort gerendert mit cached
        // Daten, im Hintergrund läuft der echte Refresh weiter.
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Home] Snapshot-Hydration fehlgeschlagen: $e');
    }
  }

  Future<void> _persistHomeSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reco = _todayRecommendation;
      await prefs.setString(
        'home_snapshot_v1',
        jsonEncode(<String, dynamic>{
          'userLevel': userLevel,
          'levelProgress': levelProgress,
          'levelName': levelName,
          'xpToNextLevel': xpToNextLevel,
          'totalXp': totalXp,
          'totalRoutes': totalRoutes,
          'totalDistanceKm': totalDistanceKm,
          'badgeCount': badgeCount,
          'savedRouteCount': _savedRouteCount,
          'earnedBadgeIds': _earnedBadgeIds,
          'streakDays': _streakDays,
          'weeklyKm': _weeklyKmData,
          'monthlyWeekKm': _monthlyWeekKmData,
          'monthDistanceKm': _monthDistanceKm,
          'monthRoutes': _monthRoutes,
          'monthActiveDays': _monthActiveDays,
          'profileUsername': _profileUsername,
          'avatarUrl': _avatarUrl,
          // 2026-05-28 (vucko Task #72): Recommendation mit serialisieren
          // damit beim 2.+ App-Start sofort die Card sichtbar ist.
          if (reco != null) 'recommendation': reco.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('[Home] Snapshot persistieren fehlgeschlagen: $e');
    }
  }

  Future<void> _loadDashboardLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dashboardPrefsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .whereType<Map>()
          .map(
            (entry) =>
                _HomeDashboardItem.fromJson(Map<String, dynamic>.from(entry)),
          )
          .whereType<_HomeDashboardItem>()
          .toList();
      final sanitized = _sanitizeDashboardItems(parsed);
      if (!mounted) return;
      setState(() {
        _dashboardItems = sanitized;
      });
    } catch (e) {
      debugPrint('[Home] Dashboard-Layout laden fehlgeschlagen: $e');
    }
  }

  Future<void> _persistDashboardLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _dashboardPrefsKey,
        jsonEncode(_dashboardItems.map((item) => item.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[Home] Dashboard-Layout speichern fehlgeschlagen: $e');
    }
  }

  Future<void> _loadBadgeHuntPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_badgeHuntPrefsKey);
      if (!mounted || id == null || id.isEmpty) return;
      setState(() => _selectedBadgeHuntId = id);
    } catch (e) {
      debugPrint('[Home] Badge-Ziel laden fehlgeschlagen: $e');
    }
  }

  Future<void> _persistBadgeHuntPreference(String? badgeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (badgeId == null || badgeId.isEmpty) {
        await prefs.remove(_badgeHuntPrefsKey);
      } else {
        await prefs.setString(_badgeHuntPrefsKey, badgeId);
      }
    } catch (e) {
      debugPrint('[Home] Badge-Ziel speichern fehlgeschlagen: $e');
    }
  }

  List<_HomeDashboardItem> _sanitizeDashboardItems(
    List<_HomeDashboardItem> items,
  ) {
    final seen = <_HomeWidgetId>{};
    final sanitized = <_HomeDashboardItem>[];
    for (final item in items) {
      final ids = <_HomeWidgetId>[];
      for (final id in item.widgetIds) {
        for (final normalizedId in _normalizedDashboardWidgetIds(id)) {
          if (!_widgetCatalog.any((meta) => meta.id == normalizedId)) continue;
          if (seen.add(normalizedId)) ids.add(normalizedId);
        }
      }
      if (ids.isEmpty) continue;
      final size = _validSizeFor(ids, item.size);
      final title = ids.length > 1
          ? (item.title?.trim().isNotEmpty ?? false
                ? item.title!.trim()
                : _defaultFolderTitle(ids))
          : null;
      sanitized.add(item.copyWith(widgetIds: ids, size: size, title: title));
    }
    return sanitized;
  }

  List<_HomeWidgetId> _normalizedDashboardWidgetIds(_HomeWidgetId id) {
    if (id == _HomeWidgetId.community) {
      return const [
        _HomeWidgetId.communityContacts,
        _HomeWidgetId.communityGroups,
        _HomeWidgetId.communityEvents,
      ];
    }
    return [id];
  }

  _HomeWidgetMeta _metaFor(_HomeWidgetId id) =>
      _widgetCatalog.firstWhere((meta) => meta.id == id);

  Set<_HomeWidgetId> get _visibleWidgetIds =>
      _dashboardItems.expand((item) => item.widgetIds).toSet();

  _DashboardWidgetSize _validSizeFor(
    List<_HomeWidgetId> ids,
    _DashboardWidgetSize requested,
  ) {
    final metas = ids.map(_metaFor).toList();
    if (requested == _DashboardWidgetSize.small &&
        metas.every((meta) => meta.canBeSmall)) {
      return _DashboardWidgetSize.small;
    }
    if (requested == _DashboardWidgetSize.large &&
        metas.every((meta) => meta.canBeLarge)) {
      return _DashboardWidgetSize.large;
    }
    if (metas.every((meta) => meta.canBeLarge)) {
      return _DashboardWidgetSize.large;
    }
    return _DashboardWidgetSize.small;
  }

  bool _canResize(_HomeDashboardItem item) {
    final metas = item.widgetIds.map(_metaFor);
    return metas.every((meta) => meta.canBeSmall) &&
        metas.every((meta) => meta.canBeLarge);
  }

  void _addDashboardWidget(_HomeWidgetId id) {
    if (_visibleWidgetIds.contains(id)) return;
    final meta = _metaFor(id);
    final key =
        '${id.name}_${DateTime.now().millisecondsSinceEpoch}_${_dashboardItemSerial++}';
    final item = _HomeDashboardItem(
      key: key,
      widgetIds: [id],
      size: meta.defaultSize,
    );
    HapticFeedback.mediumImpact();
    setState(() {
      _dashboardItems = [..._dashboardItems, item];
      _recentlyChangedItemKey = key;
    });
    unawaited(_persistDashboardLayout());
    _clearRecentDashboardHighlight(key);
  }

  void _removeDashboardItem(String key, [_HomeWidgetId? childId]) {
    HapticFeedback.selectionClick();
    int? pageToShow;
    setState(() {
      final next = <_HomeDashboardItem>[];
      for (final item in _dashboardItems) {
        if (item.key != key) {
          next.add(item);
          continue;
        }
        if (childId == null || !item.isFolder) {
          _disposeFolderController(key);
          continue;
        }
        final remaining = item.widgetIds.where((id) => id != childId).toList();
        if (remaining.isEmpty) {
          _disposeFolderController(key);
        } else if (remaining.length == 1) {
          _disposeFolderController(key);
          next.add(
            item.copyWith(
              widgetIds: remaining,
              size: _validSizeFor(remaining, item.size),
              title: null,
            ),
          );
        } else {
          final page = (_folderPages[key] ?? 0)
              .clamp(0, math.max(0, remaining.length - 1))
              .toInt();
          _folderPages[key] = page;
          pageToShow = page;
          next.add(
            item.copyWith(
              widgetIds: remaining,
              size: _validSizeFor(remaining, item.size),
            ),
          );
        }
      }
      _dashboardItems = next;
    });
    if (pageToShow != null) _animateFolderToPage(key, pageToShow!);
    unawaited(_persistDashboardLayout());
  }

  void _toggleDashboardItemSize(String key) {
    final index = _dashboardItems.indexWhere((item) => item.key == key);
    if (index < 0) return;
    final item = _dashboardItems[index];
    if (!_canResize(item)) return;
    final nextSize = item.size == _DashboardWidgetSize.large
        ? _DashboardWidgetSize.small
        : _DashboardWidgetSize.large;
    final next = [..._dashboardItems];
    next[index] = item.copyWith(size: nextSize);
    HapticFeedback.selectionClick();
    setState(() => _dashboardItems = next);
    unawaited(_persistDashboardLayout());
  }

  void _handleDropOnDashboardItem(
    _HomeWidgetDragPayload payload,
    _HomeDashboardItem target, {
    Offset? localOffset,
    Size? size,
  }) {
    final sourceKey = payload.itemKey;
    if (sourceKey == target.key) {
      _clearDashboardDragState();
      return;
    }

    final intent = _resolveDashboardDropIntent(
      payload,
      target,
      localOffset: localOffset,
      size: size,
    );
    if (intent == null) {
      _clearDashboardDragState();
      return;
    }

    if (intent == _DashboardDropIntent.before) {
      _moveDashboardPayloadBeside(payload, target.key, after: false);
    } else if (intent == _DashboardDropIntent.after) {
      _moveDashboardPayloadBeside(payload, target.key, after: true);
    } else if (intent == _DashboardDropIntent.merge) {
      final merged = _mergeDashboardPayloadIntoTarget(payload, target.key);
      if (!merged) {
        _moveDashboardPayloadBeside(payload, target.key, after: true);
      }
    }
  }

  _DashboardDropIntent? _resolveDashboardDropIntent(
    _HomeWidgetDragPayload payload,
    _HomeDashboardItem target, {
    Offset? localOffset,
    Size? size,
  }) {
    if (!_canAcceptOnItem(payload, target)) return null;
    if (_dashboardItemForDragPayload(payload) == null) return null;
    if (localOffset != null && size != null) {
      final canMerge = _canMergeOnItem(payload, target);
      if (canMerge) {
        return localOffset.dx >= size.width * 0.50
            ? _DashboardDropIntent.merge
            : _DashboardDropIntent.before;
      }

      final edgeX = size.width * 0.28;
      final edgeY = size.height * 0.18;
      final useVerticalEdges = size.width > size.height * 1.35;
      final compactVerticalEdge = math.max(28.0, size.height * 0.22);
      if (target.size == _DashboardWidgetSize.small) {
        if (localOffset.dy <= compactVerticalEdge) {
          return _DashboardDropIntent.before;
        }
        if (localOffset.dy >= size.height - compactVerticalEdge) {
          return _DashboardDropIntent.after;
        }
      }
      final before =
          localOffset.dx <= edgeX ||
          (useVerticalEdges && localOffset.dy <= math.max(24, edgeY));
      final after =
          localOffset.dx >= size.width - edgeX ||
          (useVerticalEdges &&
              localOffset.dy >= size.height - math.max(24, edgeY));
      if (before) return _DashboardDropIntent.before;
      if (after) return _DashboardDropIntent.after;
    }
    if (_canMergeOnItem(payload, target)) return _DashboardDropIntent.merge;
    final after = localOffset != null && size != null
        ? localOffset.dx >= size.width / 2
        : true;
    return after ? _DashboardDropIntent.after : _DashboardDropIntent.before;
  }

  void _updateDashboardDropPreview(
    _HomeWidgetDragPayload payload,
    _HomeDashboardItem target, {
    Offset? localOffset,
    Size? size,
  }) {
    final intent = _resolveDashboardDropIntent(
      payload,
      target,
      localOffset: localOffset,
      size: size,
    );
    if (intent == null) {
      if (_activeDropTargetKey == target.key ||
          _dropPreview?.targetKey == target.key) {
        setState(() {
          _activeDropTargetKey = null;
          _dropPreview = null;
        });
      }
      return;
    }
    _setDashboardDropPreview(
      _DashboardDropPreview(
        payload: payload,
        targetKey: target.key,
        intent: intent,
      ),
    );
  }

  void _updateDashboardSlotDropPreview(
    _HomeWidgetDragPayload payload,
    String afterKey,
  ) {
    if (!_canAcceptInEmptySlot(payload, afterKey)) return;
    _setDashboardDropPreview(
      _DashboardDropPreview(
        payload: payload,
        targetKey: afterKey,
        intent: _DashboardDropIntent.after,
      ),
    );
  }

  void _setDashboardDropPreview(_DashboardDropPreview preview) {
    final current = _dropPreview;
    if (current != null &&
        current.matches(preview) &&
        _activeDropTargetKey == preview.targetKey) {
      return;
    }
    setState(() {
      _dropPreview = preview;
      _activeDropTargetKey = preview.targetKey;
    });
  }

  void _clearDashboardDragState() {
    if (_draggingDashboardItemKey == null &&
        _activeDropTargetKey == null &&
        _dropPreview == null) {
      return;
    }
    setState(() {
      _draggingDashboardItemKey = null;
      _activeDropTargetKey = null;
      _dropPreview = null;
    });
  }

  void _commitDashboardDropPreview(_DashboardDropPreview preview) {
    if (mounted) {
      setState(() {
        _draggingDashboardItemKey = null;
        _activeDropTargetKey = null;
        _dropPreview = null;
      });
    }
    if (preview.intent == _DashboardDropIntent.before) {
      _moveDashboardPayloadBeside(
        preview.payload,
        preview.targetKey,
        after: false,
      );
    } else if (preview.intent == _DashboardDropIntent.after) {
      _moveDashboardPayloadBeside(
        preview.payload,
        preview.targetKey,
        after: true,
      );
    } else {
      _mergeDashboardPayloadIntoTarget(preview.payload, preview.targetKey);
    }
  }

  bool _canAcceptInEmptySlot(_HomeWidgetDragPayload? payload, String afterKey) {
    if (payload == null) return false;
    if (!payload.isFolderChild && payload.itemKey == afterKey) return false;
    return _dashboardItemForDragPayload(payload) != null &&
        _dashboardItemByKey(afterKey) != null;
  }

  bool _mergeDashboardItems(String sourceKey, String targetKey) {
    _HomeDashboardItem? source;
    _HomeDashboardItem? target;
    for (final item in _dashboardItems) {
      if (item.key == sourceKey) source = item;
      if (item.key == targetKey) target = item;
    }
    final sourceItem = source;
    final targetItem = target;
    if (sourceItem == null || targetItem == null) return false;
    if (!_canMergeDashboardItems(targetItem, sourceItem)) return false;

    final mergedIds = <_HomeWidgetId>[
      ...targetItem.widgetIds,
      ...sourceItem.widgetIds.where((id) => !targetItem.widgetIds.contains(id)),
    ];
    final mergedSize = _validSizeFor(
      mergedIds,
      targetItem.size == _DashboardWidgetSize.large ||
              sourceItem.size == _DashboardWidgetSize.large
          ? _DashboardWidgetSize.large
          : _DashboardWidgetSize.small,
    );
    final startPage = (_folderPages[targetKey] ?? 0)
        .clamp(0, math.max(0, targetItem.widgetIds.length - 1))
        .toInt();
    final mergedPage = math.max(0, mergedIds.length - 1);

    final next = <_HomeDashboardItem>[];
    for (final item in _dashboardItems) {
      if (item.key == sourceKey) {
        _disposeFolderController(sourceKey);
        continue;
      }
      if (item.key == targetKey) {
        final title = (targetItem.title?.trim().isNotEmpty ?? false)
            ? targetItem.title!.trim()
            : _defaultFolderTitle(mergedIds);
        next.add(
          item.copyWith(widgetIds: mergedIds, size: mergedSize, title: title),
        );
        continue;
      }
      next.add(item);
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _dashboardItems = next;
      _folderPages[targetKey] = startPage;
      _recentlyChangedItemKey = targetKey;
    });
    _animateFolderToPage(targetKey, mergedPage);
    unawaited(_persistDashboardLayout());
    _clearRecentDashboardHighlight(targetKey);
    return true;
  }

  bool _mergeDashboardPayloadIntoTarget(
    _HomeWidgetDragPayload payload,
    String targetKey,
  ) {
    final childId = payload.childId;
    if (childId == null) {
      return _mergeDashboardItems(payload.itemKey, targetKey);
    }
    if (payload.itemKey == targetKey) return false;

    final sourceItem = _dashboardItemForDragPayload(payload);
    final targetItem = _dashboardItemByKey(targetKey);
    if (sourceItem == null || targetItem == null) return false;
    if (!_canMergeDashboardItems(targetItem, sourceItem)) return false;

    final mergedIds = <_HomeWidgetId>[
      ...targetItem.widgetIds,
      ...sourceItem.widgetIds.where((id) => !targetItem.widgetIds.contains(id)),
    ];
    final mergedSize = _validSizeFor(
      mergedIds,
      targetItem.size == _DashboardWidgetSize.large ||
              sourceItem.size == _DashboardWidgetSize.large
          ? _DashboardWidgetSize.large
          : _DashboardWidgetSize.small,
    );
    final startPage = (_folderPages[targetKey] ?? 0)
        .clamp(0, math.max(0, targetItem.widgetIds.length - 1))
        .toInt();
    final mergedPage = math.max(0, mergedIds.length - 1);

    final next = _dashboardItemsWithoutDragPayloadSource(
      payload,
      updateFolderState: true,
    );
    final targetIndex = next.indexWhere((item) => item.key == targetKey);
    if (targetIndex < 0) return false;
    final targetAfterRemoval = next[targetIndex];
    final title = (targetAfterRemoval.title?.trim().isNotEmpty ?? false)
        ? targetAfterRemoval.title!.trim()
        : _defaultFolderTitle(mergedIds);
    next[targetIndex] = targetAfterRemoval.copyWith(
      widgetIds: mergedIds,
      size: mergedSize,
      title: title,
    );

    HapticFeedback.mediumImpact();
    setState(() {
      _dashboardItems = next;
      _folderPages[targetKey] = startPage;
      _recentlyChangedItemKey = targetKey;
    });
    _animateFolderToPage(targetKey, mergedPage);
    unawaited(_persistDashboardLayout());
    _clearRecentDashboardHighlight(targetKey);
    return true;
  }

  bool _canFolder(
    List<_HomeWidgetId> targetIds,
    List<_HomeWidgetId> sourceIds,
  ) {
    final combined = [...targetIds, ...sourceIds];
    return combined.toSet().length == combined.length;
  }

  bool _canMergeDashboardItems(
    _HomeDashboardItem target,
    _HomeDashboardItem source,
  ) {
    if (!_canFolder(target.widgetIds, source.widgetIds)) return false;

    final mergedIds = <_HomeWidgetId>[
      ...target.widgetIds,
      ...source.widgetIds.where((id) => !target.widgetIds.contains(id)),
    ];
    return _validSizeFor(mergedIds, target.size) == target.size;
  }

  String _defaultFolderTitle(List<_HomeWidgetId> ids) {
    const communityIds = {
      _HomeWidgetId.communityContacts,
      _HomeWidgetId.communityGroups,
      _HomeWidgetId.communityEvents,
    };
    final uniqueIds = ids.toSet();
    if (uniqueIds.length >= 2 && uniqueIds.difference(communityIds).isEmpty) {
      return 'Community';
    }
    if (ids.length == 2) {
      return '${_metaFor(ids.first).title} + ${_metaFor(ids.last).title}';
    }
    return 'Widget-Gruppe';
  }

  void _disposeFolderController(String key) {
    _folderPages.remove(key);
    _folderTargetPages.remove(key);
    _folderSlideControllers.remove(key)?.dispose();
  }

  void _animateFolderToPage(String key, int page) {
    final item = _dashboardItemByKey(key);
    final count = item?.widgetIds.length ?? 0;
    unawaited(_animateFolderCarouselToPage(key, page, count));
  }

  void _setFolderPage(String key, int page, int count) {
    unawaited(_animateFolderCarouselToPage(key, page, count));
  }

  AnimationController _folderSlideControllerFor(String key) {
    return _folderSlideControllers.putIfAbsent(
      key,
      () => AnimationController(
        vsync: this,
        value: 0,
        lowerBound: -1,
        upperBound: 1,
        duration: const Duration(milliseconds: 230),
      ),
    );
  }

  Future<void> _animateFolderCarouselToPage(
    String key,
    int page,
    int count,
  ) async {
    if (!mounted || count <= 0) return;
    final currentPage = (_folderPages[key] ?? 0).clamp(0, count - 1).toInt();
    final nextPage = page.clamp(0, count - 1).toInt();
    final controller = _folderSlideControllerFor(key);
    controller.stop();

    if (currentPage == nextPage) {
      _folderTargetPages.remove(key);
      await _snapFolderCarouselBack(key);
      return;
    }

    _folderTargetPages[key] = nextPage;
    final targetOffset = nextPage > currentPage ? -1.0 : 1.0;
    final remaining = (targetOffset - controller.value).abs().clamp(0.0, 1.0);
    final duration = Duration(milliseconds: 100 + (130 * remaining).round());

    HapticFeedback.selectionClick();
    try {
      await controller.animateTo(
        targetOffset,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() {
      _folderPages[key] = nextPage;
      _folderTargetPages.remove(key);
    });
    controller.value = 0;
  }

  Future<void> _snapFolderCarouselBack(String key) async {
    final controller = _folderSlideControllers[key];
    if (controller == null || controller.value == 0) return;
    final distance = controller.value.abs().clamp(0.0, 1.0);
    try {
      await controller.animateTo(
        0,
        duration: Duration(milliseconds: 90 + (120 * distance).round()),
        curve: Curves.easeOutCubic,
      );
    } on TickerCanceled {
      return;
    }
  }

  void _clearRecentDashboardHighlight(String key) {
    Future<void>.delayed(const Duration(milliseconds: 700)).then((_) {
      if (!mounted || _recentlyChangedItemKey != key) return;
      setState(() => _recentlyChangedItemKey = null);
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _carouselController.dispose();
    for (final controller in _folderSlideControllers.values) {
      controller.dispose();
    }
    _folderSlideControllers.clear();
    _downgradeSub?.cancel();
    super.dispose();
  }

  /// 2026-07-23 (vucko "Downgrade auf Free setzt Widgets zurück"): Basic/
  /// Premium → Free — gespeichertes Dashboard-Layout verwerfen, zurück auf
  /// den Standard-Satz an Widgets (Ads erscheinen automatisch wieder, das
  /// steuert showsAds live in _buildDashboard() — kein Extra-Code nötig).
  Future<void> _resetDashboardToDefaultOnDowngrade() async {
    if (!mounted) return;
    setState(() => _dashboardItems = _defaultDashboardItems());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dashboardPrefsKey);
    } catch (e) {
      debugPrint('[Home] Dashboard-Reset bei Downgrade fehlgeschlagen: $e');
    }
  }

  /// 2026-05-22 (vucko): Schneller GPS-Resolve für Home-Recommendation.
  /// Strategie: lastKnownPosition zuerst (instant), parallel currentPosition
  /// mit 3s timeout. Wenn lastKnown da ist → sofort zurück. Sonst warte
  /// auf current. Fallback Frankfurt nach 3s total.
  Future<({double lat, double lng})> _resolveUserPosition() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      if (permission != geo.LocationPermission.always &&
          permission != geo.LocationPermission.whileInUse) {
        return (lat: 47.5031, lng: 9.7471);
      }
    } catch (_) {}
    // lastKnownPosition ist instant (gecached) — meistens genau genug
    try {
      final last = await geo.Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 1),
      );
      if (last != null) return (lat: last.latitude, lng: last.longitude);
    } catch (_) {}
    // Sonst: kurzes currentPosition mit medium accuracy + 3s timeout
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {}
    // Fallback Vorarlberg-Bodensee (besser als Frankfurt für DACH-User)
    return (lat: 47.5031, lng: 9.7471);
  }

  Future<void> _loadStats() async {
    try {
      // 2026-05-22 (vucko): PARALLEL loading — vorher seriell:
      // gamification → drive → profile → weekly → GPS(10s!) → recommendation → saved
      // Jetzt: alle unabhängigen calls gleichzeitig, GPS startet sofort.
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final gamificationFuture = GamificationService.calculateAndSync();
      final driveSessionsFuture = GamificationService.getDriveSessions();
      final profileFuture = userId != null
          ? Supabase.instance.client
                .from('profiles')
                .select('id, username, avatar_url')
                .eq('id', userId)
                .maybeSingle()
                .then<Map<String, dynamic>?>((v) => v)
                .catchError((_) => null)
          : Future<Map<String, dynamic>?>.value(null);
      final userPosFuture = _resolveUserPosition();
      final savedRoutesFuture = SavedRoutesService.getSavedRouteLibrary()
          .catchError((_) => <SavedRoute>[]);

      final result = await gamificationFuture;
      final driveSessions = await driveSessionsFuture;
      final profile = await profileFuture;
      final userPos = await userPosFuture;
      final savedRoutes = await savedRoutesFuture;
      // Wöchentliche Daten berechnen
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final weeklyKm = List<double>.filled(7, 0);
      final monthStart = DateTime(now.year, now.month);
      final monthlyWeekKm = List<double>.filled(5, 0);
      final monthActiveDays = <DateTime>{};
      var monthDistanceKm = 0.0;
      var monthRoutes = 0;
      for (final session in driveSessions) {
        final localCreatedAt = session.createdAt.toLocal();
        final routeDay = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
        );
        if (!routeDay.isBefore(weekStart)) {
          final dayIndex = routeDay.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weeklyKm[dayIndex] += session.distanceKm;
          }
        }
        if (!routeDay.isBefore(monthStart) &&
            localCreatedAt.year == now.year &&
            localCreatedAt.month == now.month) {
          final weekIndex = ((routeDay.day - 1) ~/ 7).clamp(0, 4).toInt();
          monthlyWeekKm[weekIndex] += session.distanceKm;
          if (session.distanceKm > 0.05) {
            monthDistanceKm += session.distanceKm;
            monthRoutes++;
            monthActiveDays.add(routeDay);
          }
        }
      }
      final maxKm = weeklyKm.fold<double>(0, (a, b) => a > b ? a : b);
      final normalized = weeklyKm
          .map((km) => maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0)
          .toList();

      final streak = GamificationService.calculateDrivingStreakDays(
        driveSessions,
      );

      // Recommendation aus dem verified Routenpool — GPS schon parallel oben gelaufen.
      HomeRouteRecommendation? recommendation;
      bool routeSaved = false;
      try {
        recommendation = await HomeRouteRecommendationService.getTodayRoute(
          userLat: userPos.lat,
          userLng: userPos.lng,
        );
        if (recommendation != null) {
          routeSaved = SavedRoutesService.hasEquivalentSavedRoute(
            recommendation.route,
            savedRoutes,
          );
        }
      } catch (e) {
        debugPrint('[Home] Routepool-Empfehlung laden fehlgeschlagen: $e');
      }

      // 2026-05-24 (vucko Task #53): Aktive/pausierte Trip checken für Resume-Card
      // 2026-06-10 (vucko Trip-Resume): AUCH Solo-Trips (User-Wunsch geändert:
      // Trips sollen zwischenspeicherbar sein und von egal wo fortsetzbar).
      TripSummary? activeTrip;
      try {
        activeTrip = await TripService.instance
            .activeOrPausedTripForCurrentUser(groupOnly: false);
      } catch (e) {
        debugPrint('[Home] Trip-Status laden fehlgeschlagen: $e');
      }

      // 2026-07-06 (vucko Fahrt-Resume): Unterbrochene Solo-Fahrt checken —
      // existiert ein lokaler Snapshot (App wurde mitten in der Fahrt vom
      // System beendet), bieten wir „Fahrt fortsetzen" als Home-Card an.
      ActiveRideSnapshot? resumableRide;
      try {
        resumableRide = await ActiveRideSnapshotService.load();
      } catch (e) {
        debugPrint('[Home] Fahrt-Snapshot laden fehlgeschlagen: $e');
      }

      if (mounted) {
        setState(() {
          userLevel = result.level.level;
          levelProgress = result.level.progress;
          levelName = result.level.name;
          xpToNextLevel = result.level.xpToNextLevel;
          totalXp = result.totalXp;
          totalRoutes = result.totalRoutes;
          totalDistanceKm = result.totalDistanceKm;
          badgeCount = result.earnedBadgeIds.length;
          _earnedBadgeIds = result.earnedBadgeIds;
          _savedRouteCount = savedRoutes.length;
          _profileUserId = userId;
          _profileUsername = (profile?['username'] as String?)?.trim();
          _avatarUrl = profile?['avatar_url'] as String?;
          _weeklyChartData = normalized;
          _weeklyKmData = weeklyKm;
          _monthlyWeekKmData = monthlyWeekKm;
          _monthDistanceKm = monthDistanceKm;
          _monthRoutes = monthRoutes;
          _monthActiveDays = monthActiveDays.length;
          _streakDays = streak;
          _activeTrip = activeTrip;
          _resumableRide = resumableRide;
          _todayRecommendation = recommendation;
          _isRouteSaved = routeSaved;
          _loading = false;
        });
      }

      if (recommendation != null) {
        unawaited(_ensureHeroRouteInsights(recommendation.route));
      }
      if (mounted && profile != null) {
        context.read<CommunityProvider>().seedProfile(profile);
      }
      // 2026-05-28 (vucko Task #68): Persistiere Home-Snapshot damit der
      // nächste App-Start sofort die Card mit cached Werten rendert statt
      // Skeleton.
      unawaited(_persistHomeSnapshot());
    } catch (e) {
      debugPrint('[Home] Daten laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureHeroRouteInsights(SavedRoute route) async {
    if (_heroInsightsByRouteId.containsKey(route.id) ||
        _heroInsightsLoading.contains(route.id)) {
      return;
    }

    final coordinates = _extractCoordinates(route.geometry);
    if (coordinates.length < 2) return;

    if (mounted) {
      setState(() {
        _heroInsightsLoading.add(route.id);
      });
    } else {
      _heroInsightsLoading.add(route.id);
    }

    try {
      final curves = await GamificationService.countCurvesAsync(coordinates);
      final xp = GamificationService.calculateRouteXp(
        distanceKm: route.distanceKm,
        curves: curves,
        style: route.style,
        // 2026-06-16 (vucko): Streak-Bonus in der Empfehlungs-XP mitzeigen
        // (N6-Feature beim Merge wieder eingebaut).
        streakDays: _streakDays,
      );
      final elevationSummary = await const RouteElevationService().getSummary(
        routeKey: route.id,
        coordinates: coordinates,
      );

      if (!mounted) return;
      setState(() {
        _heroInsightsByRouteId[route.id] = _HeroRouteInsights(
          curves: curves,
          xp: xp,
          elevation: elevationSummary,
        );
        _heroInsightsLoading.remove(route.id);
      });
    } catch (e) {
      debugPrint('[Home] Hero-Insights fehlgeschlagen: $e');
      if (!mounted) return;
      setState(() {
        _heroInsightsLoading.remove(route.id);
      });
    }
  }

  List<List<double>> _extractCoordinates(Map<String, dynamic> geometry) {
    final extracted = <List<double>>[];
    try {
      final coords = geometry['coordinates'];
      if (coords is List) {
        for (final point in coords) {
          if (point is List && point.length >= 2) {
            extracted.add([
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]);
          }
        }
      }
    } catch (_) {
      return [];
    }
    return extracted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppAccentProvider>().color;
    final community = context.watch<CommunityProvider>();
    final user = Supabase.instance.client.auth.currentUser;
    final profileBelongsToUser = _profileUserId == user?.id;
    final cachedProfile = user?.id == null
        ? null
        : community.cachedProfile(user!.id);
    final profileUsername =
        (cachedProfile?['username'] as String?) ??
        (profileBelongsToUser ? _profileUsername : null);
    final avatarUrl =
        (cachedProfile?['avatar_url'] as String?) ??
        (profileBelongsToUser ? _avatarUrl : null);
    final String userName = (profileUsername?.isNotEmpty ?? false)
        ? profileUsername!
        : (user?.userMetadata?['username'] as String?) ??
              user?.email?.split('@')[0] ??
              'User';

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RefreshIndicator(
            color: accent,
            backgroundColor: const Color(0xFF1A1E28),
            onRefresh: () async {
              // Re-fetch alle Home-Daten parallel
              await Future.wait([
                GamificationService.calculateAndSync(),
                context.read<SavedRoutesProvider>().loadRoutes().catchError(
                  (_) {},
                ),
                context
                    .read<RouteBookmarkProvider>()
                    .loadSavedRoutes()
                    .catchError((_) {}),
              ]);
              await _loadStats();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Willkommen zurück',
                                style: TextStyle(
                                  color: Color(0xFFA0AEC0),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '$userName!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                                // 2026-06-09 (vucko Audit T3-C): maxLines:1 — ohne das war
                                // ellipsis in der unbeschränkten Column wirkungslos (Overflow
                                // bei langen Namen auf schmalen Screens).
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        _buildHeaderCustomizeButton(),
                        const SizedBox(width: 8),
                        // 2026-05-23 (vucko): Bell-Icon mit Unread-Badge links
                        // vom Avatar — führt zur Notifications-Inbox.
                        NotificationBellButton(accent: accent),
                        const SizedBox(width: 8),
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 2),
                              child: UserAvatar(
                                name: userName,
                                avatarUrl: avatarUrl,
                                radius: 28,
                                backgroundColor: accent,
                                onTap: () => widget.onTabChange?.call(4),
                              ),
                            ),
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.blue[700],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$userLevel',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildDashboardEditHint(),
                    // 2026-07-23 (vucko „zwei feste Werbe-Widgets"): die
                    // beiden Ad-Blöcke sitzen jetzt FEST innerhalb von
                    // _buildDashboard() selbst (oben + an der Lücken-Stelle),
                    // das vorherige lose Ad-Widget hier drunter ist entfallen
                    // (sonst wären es drei Ad-Flächen statt zwei).
                    _buildDashboard(),
                    if (_showLegacyHomeBodyForDebug) ...[
                      // 2026-05-24 (vucko Task #42): Hero-Streak-Banner (nur sichtbar
                      // wenn 2+ Tage). Prominent, animiert, sofort sichtbar im
                      // Above-the-fold-Bereich für Daily-Retention.
                      if (_streakDays >= 2) ...[
                        _buildHeroStreakBanner(),
                        const SizedBox(height: 14),
                      ],

                      // Fortschritt Section
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onTabChange?.call(3),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1F26),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(
                                0xFFFFFFFF,
                              ).withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Fortschritt',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFFA0AEC0),
                                    size: 22,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _loading
                                  // 2026-06-24 (vucko Skeleton-Loading): 2×2-
                                  // Kachel-Skelett statt Kreis-Spinner.
                                  ? const SkeletonShimmer(
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: SkeletonBox(
                                                  height: 56,
                                                  radius: 14,
                                                ),
                                              ),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: SkeletonBox(
                                                  height: 56,
                                                  radius: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: SkeletonBox(
                                                  height: 56,
                                                  radius: 14,
                                                ),
                                              ),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: SkeletonBox(
                                                  height: 56,
                                                  radius: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 2026-06-08 (vucko Homescreen-Redesign): 2×2-Raster
                                        // aus Icon-Kacheln statt Emoji-Liste → sofortiger
                                        // Überblick, crisp Material-Icons statt Emojis.
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _statTile(
                                                Icons.bolt,
                                                _formatThousands(totalXp),
                                                'XP GESAMT',
                                                isAccent: true,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _statTile(
                                                Icons.speed,
                                                totalDistanceKm.toStringAsFixed(
                                                  0,
                                                ),
                                                'KM GEFAHREN',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _statTile(
                                                Icons.route,
                                                '$totalRoutes',
                                                'STRECKEN',
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _statTile(
                                                Icons.workspace_premium,
                                                '$badgeCount',
                                                'BADGES',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Level $userLevel - $levelName',
                                          style: const TextStyle(
                                            color: Color(0xFFA0AEC0),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${(levelProgress * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // 2026-06-08 (vucko Homescreen-Redesign): akzent-getönte
                                  // Spur (statt flachem Grau) → der Balken wirkt integriert;
                                  // Mindest-Nub, damit kleiner Fortschritt sichtbar bleibt.
                                  Container(
                                    height: 8,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: levelProgress.clamp(
                                        0.02,
                                        1.0,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          gradient: LinearGradient(
                                            colors: [
                                              accent,
                                              AppAccentColors.accentStrong,
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                userLevel >= UserLevel.maxLevel
                                    ? 'Maximallevel erreicht'
                                    : 'Noch $xpToNextLevel XP bis Level ${userLevel + 1}',
                                style: const TextStyle(
                                  color: Color(0xFFA0AEC0),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Top-Strecke dieser Woche
                      _buildSuggestedRouteSection(),
                      const SizedBox(height: 16),

                      // Community + Chart Section
                      SizedBox(
                        height: 244,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CommunityCarouselCard(
                                onOpenCommunity: () =>
                                    widget.onTabChange?.call(1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildWeeklyActivityCard()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Streak Widget
                      _buildStreakWidget(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardFloatingControls() {
    if (!_customizingDashboard) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dashboardToolbarButton(
          tooltip: 'Widgets hinzufügen',
          icon: Icons.add_rounded,
          label: 'Widgets',
          onTap: _openDashboardEditor,
        ),
        const SizedBox(width: 8),
        _dashboardToolbarButton(
          tooltip: 'Fertig',
          icon: Icons.check_rounded,
          emphasized: true,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _customizingDashboard = false);
          },
        ),
      ],
    );
  }

  Widget _buildHeaderCustomizeButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tooltip(
        message: 'Home anpassen',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openDashboardEditor,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _customizingDashboard
                      ? AppAccentColors.accent.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _customizingDashboard
                        ? AppAccentColors.accent.withValues(alpha: 0.48)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: _customizingDashboard
                      ? AppAccentColors.accent
                      : Colors.white.withValues(alpha: 0.86),
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboardToolbarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    bool emphasized = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: label == null ? 42 : 104,
          height: 42,
          padding: label == null
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: emphasized
                ? AppAccentColors.accent
                : const Color(0xFF151922).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: emphasized
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: label == null
              ? Icon(icon, color: Colors.white, size: 22)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 19),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showDashboardEditUpsell() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF202733), Color(0xFF151A23)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: Colors.white38, size: 40),
            const SizedBox(height: 14),
            const Text(
              'Dashboard anpassen ist ab Basic',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Widgets verschieben, hinzufügen und entfernen geht mit Basic oder Premium.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionTierPage()),
                  );
                },
                icon: const Icon(Icons.workspace_premium, size: 20),
                label: const Text(
                  'Jetzt freischalten',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppAccentColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2026-07-23 (vucko „nur mit Basic bearbeiten"): Dashboard-Anpassung ist
  /// ab Basic — Free sieht direkt das Abo-Popup statt des Editors.
  void _openDashboardEditor() {
    if (!context.read<SubscriptionProvider>().isPaid) {
      _showDashboardEditUpsell();
      return;
    }
    HapticFeedback.selectionClick();
    if (!_customizingDashboard) {
      setState(() => _customizingDashboard = true);
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF11151D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.25,
          maxChildSize: 0.94,
          snap: true,
          snapSizes: const [0.55, 0.92],
          shouldCloseOnMinExtent: true,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final hidden = _widgetCatalog
                    .where((meta) => !_visibleWidgetIds.contains(meta.id))
                    .toList();
                final active = _dashboardItems
                    .expand((item) => item.widgetIds)
                    .map(_metaFor)
                    .toList();

                void refresh(VoidCallback action) {
                  action();
                  setSheetState(() {});
                }

                return SafeArea(
                  top: true,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      18 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  gradient: AppAccentColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.widgets_rounded,
                                  color: Colors.white,
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Home bearbeiten',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Die Home ist deine Live-Vorschau. Ziehe Kacheln links auf ein Widget zum Verschieben oder rechts auf ein passendes Widget, um es in einen Ordner oder ein Carousel zu legen. Community gibt es jetzt als Kontakte, Gruppen und Events einzeln.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Auf der Home',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Column(
                            children: [
                              for (
                                var index = 0;
                                index < active.length;
                                index++
                              ) ...[
                                Builder(
                                  builder: (_) {
                                    final meta = active[index];
                                    return _buildSheetWidgetChip(
                                      meta: meta,
                                      icon: Icons.remove_rounded,
                                      onTap: () => refresh(() {
                                        _removeWidgetIdFromDashboard(meta.id);
                                      }),
                                    );
                                  },
                                ),
                                if (index < active.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Widget-Bibliothek',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (hidden.isEmpty)
                            Text(
                              'Alle Widgets sind gerade auf der Home Page.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.58),
                                fontSize: 12,
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < hidden.length;
                                  index++
                                ) ...[
                                  Builder(
                                    builder: (_) {
                                      final meta = hidden[index];
                                      return _buildSheetWidgetChip(
                                        meta: meta,
                                        icon: Icons.add_rounded,
                                        onTap: () => refresh(() {
                                          _addDashboardWidget(meta.id);
                                        }),
                                      );
                                    },
                                  ),
                                  if (index < hidden.length - 1)
                                    const SizedBox(height: 10),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSheetWidgetChip({
    required _HomeWidgetMeta meta,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(meta.icon, color: AppAccentColors.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta.subtitle,
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.54),
                      fontSize: 11.5,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppAccentColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  void _removeWidgetIdFromDashboard(_HomeWidgetId id) {
    String? key;
    for (final item in _dashboardItems) {
      if (item.widgetIds.contains(id)) {
        key = item.key;
        break;
      }
    }
    if (key == null) return;
    _removeDashboardItem(key, id);
  }

  List<_DashboardLayoutEntry> _normalDashboardEntries() {
    return [
      for (final item in _dashboardItems) _DashboardLayoutEntry.item(item),
    ];
  }

  _HomeDashboardItem? _dashboardItemByKey(String key) {
    for (final item in _dashboardItems) {
      if (item.key == key) return item;
    }
    return null;
  }

  String _newDashboardItemKeyFor(_HomeWidgetId id) =>
      '${id.name}_${DateTime.now().millisecondsSinceEpoch}_${_dashboardItemSerial++}';

  _HomeDashboardItem? _dashboardItemForDragPayload(
    _HomeWidgetDragPayload payload,
  ) {
    final childId = payload.childId;
    if (childId == null) return _dashboardItemByKey(payload.itemKey);

    final folder = _dashboardItemByKey(payload.itemKey);
    if (folder == null || !folder.widgetIds.contains(childId)) return null;
    return _HomeDashboardItem(
      key: payload.identityKey,
      widgetIds: [childId],
      size: _validSizeFor([childId], folder.size),
    );
  }

  List<_HomeDashboardItem> _dashboardItemsWithoutDragPayloadSource(
    _HomeWidgetDragPayload payload, {
    bool updateFolderState = false,
  }) {
    final childId = payload.childId;
    final next = <_HomeDashboardItem>[];

    for (final item in _dashboardItems) {
      if (childId == null) {
        if (item.key == payload.itemKey) {
          if (updateFolderState) _disposeFolderController(item.key);
          continue;
        }
        next.add(item);
        continue;
      }

      if (item.key != payload.itemKey) {
        next.add(item);
        continue;
      }

      final removedIndex = item.widgetIds.indexOf(childId);
      if (removedIndex < 0) {
        next.add(item);
        continue;
      }

      final remaining = item.widgetIds.where((id) => id != childId).toList();
      if (remaining.isEmpty) {
        if (updateFolderState) _disposeFolderController(item.key);
        continue;
      }

      if (remaining.length == 1) {
        if (updateFolderState) _disposeFolderController(item.key);
        next.add(
          item.copyWith(
            widgetIds: remaining,
            size: _validSizeFor(remaining, item.size),
            title: null,
          ),
        );
        continue;
      }

      if (updateFolderState) {
        final currentPage = (_folderPages[item.key] ?? 0)
            .clamp(0, item.widgetIds.length - 1)
            .toInt();
        final adjustedPage = (removedIndex <= currentPage && currentPage > 0)
            ? currentPage - 1
            : currentPage;
        _folderPages[item.key] = adjustedPage
            .clamp(0, remaining.length - 1)
            .toInt();
      }

      next.add(
        item.copyWith(
          widgetIds: remaining,
          size: _validSizeFor(remaining, item.size),
          title: (item.title?.trim().isNotEmpty ?? false)
              ? item.title!.trim()
              : _defaultFolderTitle(remaining),
        ),
      );
    }

    return next;
  }

  List<_DashboardLayoutEntry> _dashboardLayoutEntries() {
    final preview = _dropPreview;
    if (preview == null) return _normalDashboardEntries();

    final source = _dashboardItemForDragPayload(preview.payload);
    if (source == null) return _normalDashboardEntries();

    final targetIndex = _dashboardItems.indexWhere(
      (item) => item.key == preview.targetKey,
    );
    if (targetIndex < 0 ||
        (!preview.payload.isFolderChild &&
            preview.sourceKey == preview.targetKey)) {
      return _normalDashboardEntries();
    }

    final target = _dashboardItems[targetIndex];
    final targetCanMerge = _canMergeDashboardItems(target, source);

    if (targetCanMerge &&
        (preview.intent == _DashboardDropIntent.before ||
            preview.intent == _DashboardDropIntent.merge)) {
      return _normalDashboardEntries();
    }

    if (preview.intent == _DashboardDropIntent.merge) {
      if (!targetCanMerge) {
        return _normalDashboardEntries();
      }
      final mergedIds = <_HomeWidgetId>[
        ...target.widgetIds,
        ...source.widgetIds.where((id) => !target.widgetIds.contains(id)),
      ];
      final mergedSize = _validSizeFor(
        mergedIds,
        target.size == _DashboardWidgetSize.large ||
                source.size == _DashboardWidgetSize.large
            ? _DashboardWidgetSize.large
            : _DashboardWidgetSize.small,
      );
      final entries = <_DashboardLayoutEntry>[];
      final itemsWithoutSource = _dashboardItemsWithoutDragPayloadSource(
        preview.payload,
      );
      for (final item in itemsWithoutSource) {
        if (item.key == preview.targetKey) {
          entries.add(
            _DashboardLayoutEntry.preview(
              item.copyWith(
                widgetIds: mergedIds,
                size: mergedSize,
                title: (item.title?.trim().isNotEmpty ?? false)
                    ? item.title!.trim()
                    : _defaultFolderTitle(mergedIds),
              ),
              preview,
            ),
          );
          continue;
        }
        entries.add(_DashboardLayoutEntry.item(item));
      }
      return entries;
    }

    final itemsWithoutSource = _dashboardItemsWithoutDragPayloadSource(
      preview.payload,
    );
    final insertIndex = _resolvedDashboardInsertIndexForPayload(
      preview.payload,
      preview.targetKey,
      after: preview.intent == _DashboardDropIntent.after,
    );
    if (insertIndex == null) return _normalDashboardEntries();

    final entries = <_DashboardLayoutEntry>[];
    for (var index = 0; index <= itemsWithoutSource.length; index++) {
      if (index == insertIndex) {
        entries.add(_DashboardLayoutEntry.preview(source, preview));
      }
      if (index < itemsWithoutSource.length) {
        entries.add(_DashboardLayoutEntry.item(itemsWithoutSource[index]));
      }
    }
    return entries;
  }

  Widget _buildDashboard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final useOneColumn = maxWidth < 300;
        final entries = _dashboardLayoutEntries();

        if (_dashboardItems.isEmpty) {
          return _buildEmptyDashboard();
        }

        // 2026-07-23 (vucko „zwei feste Werbe-Widgets"): NUR Free-Tier sieht
        // sie, sie liegen AUSSERHALB von _dashboardItems — also nicht
        // verschiebbar, nicht entfernbar, nicht persistiert.
        final showAds = context.watch<SubscriptionProvider>().showsAds;

        final blocks = <Widget>[];
        final pendingSmall = <_DashboardLayoutEntry>[];

        if (showAds) {
          // Widget 1: ganz oben, garantiert ohne Scrollen sichtbar.
          blocks.add(
            const AdPostCard(
              placementKey: 'home_dashboard_top',
              compact: true,
            ),
          );
        }

        var gapAdPlaced = false;
        void flushSmall() {
          if (pendingSmall.isEmpty) return;
          blocks.add(
            _buildDashboardSmallCluster(
              List<_DashboardLayoutEntry>.from(pendingSmall),
              useOneColumn: useOneColumn,
            ),
          );
          pendingSmall.clear();
          // Widget 2: direkt nach der ersten Small-Cluster-Reihe — genau da,
          // wo bei ungerader Anzahl sonst die leere Lücken-Kachel wäre.
          if (showAds && !gapAdPlaced) {
            blocks.add(
              const AdPostCard(
                placementKey: 'home_dashboard_gap',
                compact: true,
              ),
            );
            gapAdPlaced = true;
          }
        }

        for (final entry in entries) {
          final item = entry.item;
          if (useOneColumn || item.size == _DashboardWidgetSize.large) {
            flushSmall();
            blocks.add(_buildDashboardEntry(entry));
            continue;
          }
          pendingSmall.add(entry);
        }
        flushSmall();
        if (showAds && !gapAdPlaced) {
          blocks.add(
            const AdPostCard(
              placementKey: 'home_dashboard_gap',
              compact: true,
            ),
          );
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < blocks.length; index++) ...[
                blocks[index],
                if (index < blocks.length - 1)
                  const SizedBox(height: _dashboardGap),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardSmallCluster(
    List<_DashboardLayoutEntry> entries, {
    required bool useOneColumn,
  }) {
    if (useOneColumn) {
      return Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _buildDashboardEntry(entries[index]),
            if (index < entries.length - 1)
              const SizedBox(height: _dashboardGap),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (var index = 0; index < entries.length; index += 2) ...[
          _buildDashboardHalfRow(
            first: entries[index],
            second: index + 1 < entries.length ? entries[index + 1] : null,
          ),
          if (index + 2 < entries.length) const SizedBox(height: _dashboardGap),
        ],
      ],
    );
  }

  Widget _buildDashboardHalfRow({
    required _DashboardLayoutEntry first,
    _DashboardLayoutEntry? second,
  }) {
    return SizedBox(
      height: _dashboardHalfTileHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildDashboardEntry(first)),
          const SizedBox(width: _dashboardGap),
          Expanded(
            child: second == null
                ? _buildDashboardEmptyHalfSlot(afterKey: first.item.key)
                : _buildDashboardEntry(second),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardEntry(_DashboardLayoutEntry entry) {
    final preview = entry.preview;
    if (preview != null) {
      return _buildDashboardPreviewCell(entry.item, preview);
    }
    return _buildDashboardCell(entry.item);
  }

  Widget _buildDashboardEditHint() {
    if (!_customizingDashboard) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF151922).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_rounded,
              color: AppAccentColors.accent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Live-Vorschau: links verschiebt, rechts fügt hinzu.',
                maxLines: 3,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildDashboardFloatingControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDashboard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _openDashboardEditor,
      onTap: _customizingDashboard ? _openDashboardEditor : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _customizingDashboard
              ? AppAccentColors.accent.withValues(alpha: 0.10)
              : const Color(0xFF151922),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _customizingDashboard
                ? AppAccentColors.accent.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.add_box_rounded,
              color: _customizingDashboard
                  ? AppAccentColors.accent
                  : Colors.white.withValues(alpha: 0.52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _customizingDashboard
                    ? 'Widgets aus der Auswahl hinzufügen.'
                    : 'Dashboard ist leer.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveDashboardItemToResolvedIndex(String sourceKey, int insertIndex) {
    final index = _dashboardItems.indexWhere((item) => item.key == sourceKey);
    if (index < 0) return;
    final next = [..._dashboardItems];
    final item = next.removeAt(index);
    final targetIndex = insertIndex.clamp(0, next.length).toInt();
    if (targetIndex == index) return;
    next.insert(targetIndex, item);
    HapticFeedback.selectionClick();
    setState(() => _dashboardItems = next);
    unawaited(_persistDashboardLayout());
  }

  void _moveDashboardPayloadBeside(
    _HomeWidgetDragPayload payload,
    String targetKey, {
    required bool after,
  }) {
    final insertIndex = _resolvedDashboardInsertIndexForPayload(
      payload,
      targetKey,
      after: after,
    );
    if (insertIndex == null) return;

    final childId = payload.childId;
    if (childId == null) {
      _moveDashboardItemToResolvedIndex(payload.itemKey, insertIndex);
      return;
    }

    final source = _dashboardItemForDragPayload(payload);
    if (source == null) return;
    final next = _dashboardItemsWithoutDragPayloadSource(
      payload,
      updateFolderState: true,
    );
    final targetIndex = insertIndex.clamp(0, next.length).toInt();
    final newKey = _newDashboardItemKeyFor(childId);
    next.insert(targetIndex, source.copyWith(key: newKey));
    HapticFeedback.selectionClick();
    setState(() {
      _dashboardItems = next;
      _recentlyChangedItemKey = newKey;
    });
    unawaited(_persistDashboardLayout());
    _clearRecentDashboardHighlight(newKey);
  }

  int? _resolvedDashboardInsertIndexForPayload(
    _HomeWidgetDragPayload payload,
    String targetKey, {
    required bool after,
  }) {
    final source = _dashboardItemForDragPayload(payload);
    if (source == null) return null;
    final itemsWithoutSource = _dashboardItemsWithoutDragPayloadSource(payload);
    final targetIndex = itemsWithoutSource.indexWhere(
      (item) => item.key == targetKey,
    );
    if (targetIndex < 0) return null;

    var insertIndex = targetIndex + (after ? 1 : 0);
    final target = itemsWithoutSource[targetIndex];
    if (source.size == _DashboardWidgetSize.large &&
        target.size == _DashboardWidgetSize.small) {
      final pairBounds = _smallPairBounds(itemsWithoutSource, targetIndex);
      if (pairBounds != null) {
        final pairStart = pairBounds.$1;
        final pairEnd = pairBounds.$2;
        final wouldSplitPair =
            insertIndex > pairStart && insertIndex <= pairEnd;
        insertIndex = wouldSplitPair || after ? pairEnd + 1 : pairStart;
      }
    }

    return insertIndex.clamp(0, itemsWithoutSource.length).toInt();
  }

  (int, int)? _smallPairBounds(List<_HomeDashboardItem> items, int itemIndex) {
    if (itemIndex < 0 ||
        itemIndex >= items.length ||
        items[itemIndex].size != _DashboardWidgetSize.small) {
      return null;
    }

    var runStart = itemIndex;
    while (runStart > 0 &&
        items[runStart - 1].size == _DashboardWidgetSize.small) {
      runStart -= 1;
    }

    var runEnd = itemIndex;
    while (runEnd + 1 < items.length &&
        items[runEnd + 1].size == _DashboardWidgetSize.small) {
      runEnd += 1;
    }

    final pairStart = runStart + (((itemIndex - runStart) ~/ 2) * 2);
    final pairEnd = math.min(pairStart + 1, runEnd);
    if (pairEnd <= pairStart) return null;
    return (pairStart, pairEnd);
  }

  double _dashboardItemHeight(_HomeDashboardItem item) {
    if (item.size == _DashboardWidgetSize.small) {
      return _dashboardHalfTileHeight;
    }
    return item.isFolder ? _dashboardFolderFullHeight : 0;
  }

  Widget _buildDashboardSizedContent(_HomeDashboardItem item) {
    final content = item.isFolder
        ? _buildFolderCard(item)
        : _buildSingleDashboardWidget(item.widgetIds.first, item.size);
    final height = _dashboardItemHeight(item);
    return height > 0
        ? SizedBox(
            height: height,
            child: SizedBox.expand(child: content),
          )
        : content;
  }

  Widget _buildDashboardPreviewCell(
    _HomeDashboardItem item,
    _DashboardDropPreview preview,
  ) {
    final content = _buildDashboardSizedContent(item);
    final label = _dashboardDropPreviewLabel(item, preview);

    return DragTarget<_HomeWidgetDragPayload>(
      onWillAcceptWithDetails: (details) {
        return details.data.matches(preview.payload);
      },
      onMove: (_) => _setDashboardDropPreview(preview),
      onAcceptWithDetails: (_) => _commitDashboardDropPreview(preview),
      builder: (context, candidates, rejected) {
        final active =
            candidates.isNotEmpty || (_dropPreview?.matches(preview) ?? false);
        return AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: active ? 1.015 : 1.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppAccentColors.accent.withValues(alpha: 0.72),
                    width: 1.7,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppAccentColors.accent.withValues(alpha: 0.20),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: preview.intent == _DashboardDropIntent.merge
                        ? 0.88
                        : 0.68,
                    child: content,
                  ),
                ),
              ),
              if (label != null)
                Positioned(
                  right: 10,
                  top: -10,
                  child: _buildDropPreviewBadge(label),
                ),
            ],
          ),
        );
      },
    );
  }

  String? _dashboardDropPreviewLabel(
    _HomeDashboardItem item,
    _DashboardDropPreview preview,
  ) {
    final target = _dashboardItemByKey(preview.targetKey) ?? item;
    final source = _dashboardItemForDragPayload(preview.payload);
    final canMerge = source != null && _canMergeDashboardItems(target, source);
    if (!canMerge) return null;
    if (preview.intent == _DashboardDropIntent.before) {
      return 'Links: verschieben';
    }
    if (preview.intent != _DashboardDropIntent.merge) return null;
    return target.isFolder ? 'Rechts: ins Carousel' : 'Rechts: Ordner';
  }

  Widget _buildDashboardEmptyHalfSlot({required String afterKey}) {
    final visible = _customizingDashboard || _draggingDashboardItemKey != null;
    final active =
        _dropPreview?.targetKey == afterKey &&
        _dropPreview?.intent == _DashboardDropIntent.after;

    return DragTarget<_HomeWidgetDragPayload>(
      onWillAcceptWithDetails: (details) {
        final canAccept = _canAcceptInEmptySlot(details.data, afterKey);
        if (canAccept) {
          setState(() => _activeDropTargetKey = afterKey);
        }
        return canAccept;
      },
      onMove: (details) =>
          _updateDashboardSlotDropPreview(details.data, afterKey),
      onLeave: (_) {
        if (_activeDropTargetKey == afterKey) {
          setState(() => _activeDropTargetKey = null);
        }
      },
      onAcceptWithDetails: (details) {
        final preview = _DashboardDropPreview(
          payload: details.data,
          targetKey: afterKey,
          intent: _DashboardDropIntent.after,
        );
        _commitDashboardDropPreview(preview);
      },
      builder: (context, candidates, rejected) {
        final isHighlighted = active || candidates.isNotEmpty;
        final interactive = visible || isHighlighted;
        return IgnorePointer(
          ignoring: !interactive,
          child: GestureDetector(
            onTap: _openDashboardEditor,
            behavior: HitTestBehavior.opaque,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: interactive ? 1 : 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? AppAccentColors.accent.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.025),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isHighlighted
                        ? AppAccentColors.accent.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    key: const ValueKey('empty-slot-icon'),
                    color: Colors.white.withValues(
                      alpha: isHighlighted ? 0.58 : 0.34,
                    ),
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropPreviewBadge(String label) {
    return Container(
      key: ValueKey(label),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF090B10).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildDashboardDropZoneGuide({
    required _HomeDashboardItem item,
    required _DashboardDropIntent? intent,
  }) {
    final rightLabel = item.isFolder ? 'Carousel' : 'Ordner';
    final leftActive = intent == _DashboardDropIntent.before;
    final rightActive = intent == _DashboardDropIntent.merge;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF05070B).withValues(alpha: 0.34),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: _buildDashboardDropZoneHalf(
                icon: Icons.swap_horiz_rounded,
                title: 'Links',
                label: 'verschieben',
                active: leftActive,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDashboardDropZoneHalf(
                icon: item.isFolder
                    ? Icons.view_carousel_rounded
                    : Icons.create_new_folder_rounded,
                title: 'Rechts',
                label: rightLabel,
                active: rightActive,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardDropZoneHalf({
    required IconData icon,
    required String title,
    required String label,
    required bool active,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? AppAccentColors.accent.withValues(alpha: 0.82)
            : const Color(0xFF0B0E14).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: active ? 0.92 : 0.72),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCell(_HomeDashboardItem item) {
    final recentlyChanged = _recentlyChangedItemKey == item.key;
    final content = _buildDashboardSizedContent(item);
    final targetKey = GlobalKey();

    final target = DragTarget<_HomeWidgetDragPayload>(
      onWillAcceptWithDetails: (details) {
        final canAccept = _canAcceptOnItem(details.data, item);
        if (canAccept) setState(() => _activeDropTargetKey = item.key);
        return canAccept;
      },
      onMove: (details) {
        final renderBox =
            targetKey.currentContext?.findRenderObject() as RenderBox?;
        final localOffset = renderBox?.globalToLocal(details.offset);
        final size = renderBox?.size;
        _updateDashboardDropPreview(
          details.data,
          item,
          localOffset: localOffset,
          size: size,
        );
      },
      onLeave: (_) {
        if (_activeDropTargetKey == item.key) {
          setState(() => _activeDropTargetKey = null);
        }
      },
      onAcceptWithDetails: (details) {
        final renderBox =
            targetKey.currentContext?.findRenderObject() as RenderBox?;
        final localOffset = renderBox?.globalToLocal(details.offset);
        final size = renderBox?.size;
        setState(() {
          _activeDropTargetKey = null;
          _dropPreview = null;
        });
        _handleDropOnDashboardItem(
          details.data,
          item,
          localOffset: localOffset,
          size: size,
        );
      },
      builder: (context, candidates, rejected) {
        final active =
            candidates.isNotEmpty ||
            _activeDropTargetKey == item.key ||
            _dropPreview?.targetKey == item.key;
        final previewPayload = _dropPreview?.targetKey == item.key
            ? _dropPreview?.payload
            : null;
        final activePayload = candidates.isNotEmpty
            ? candidates.first
            : previewPayload;
        final canMergeHere = _canMergeOnItem(activePayload, item);
        final previewIntent = _dropPreview?.targetKey == item.key
            ? _dropPreview?.intent
            : null;
        final showDropGuide = active && _customizingDashboard && canMergeHere;
        return AnimatedScale(
          key: targetKey,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: active ? 1.025 : (recentlyChanged ? 1.018 : 1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: active
                        ? AppAccentColors.accent.withValues(alpha: 0.62)
                        : recentlyChanged
                        ? AppAccentColors.accent.withValues(alpha: 0.34)
                        : Colors.transparent,
                    width: active ? 1.8 : 1,
                  ),
                  boxShadow: active || recentlyChanged
                      ? [
                          BoxShadow(
                            color: AppAccentColors.accent.withValues(
                              alpha: active ? 0.22 : 0.14,
                            ),
                            blurRadius: active ? 24 : 16,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : const [],
                ),
                child: content,
              ),
              if (showDropGuide)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _buildDashboardDropZoneGuide(
                      item: item,
                      intent: previewIntent,
                    ),
                  ),
                ),
              if (_customizingDashboard)
                Positioned(
                  right: 8,
                  top: -12,
                  child: _buildDashboardCardControls(item),
                ),
            ],
          ),
        );
      },
    );

    // 2026-07-23 (vucko „nur mit Basic bearbeiten"): Free-Nutzer können
    // Widgets nicht per Drag verschieben — maxSimultaneousDrags: 0 verhindert
    // den Drag komplett (kein Pop-up nötig, es ist einfach kein Ziehen
    // möglich), das Editor-Pop-up kommt weiterhin über den oberen Button.
    final canEditDashboard = context.watch<SubscriptionProvider>().isPaid;
    return LongPressDraggable<_HomeWidgetDragPayload>(
      data: _HomeWidgetDragPayload.existing(item.key),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      maxSimultaneousDrags: canEditDashboard ? null : 0,
      feedback: _buildDragFeedback(_dashboardItemTitle(item), Icons.widgets),
      childWhenDragging: Opacity(opacity: 0.38, child: target),
      onDragStarted: () {
        HapticFeedback.selectionClick();
        setState(() {
          _draggingDashboardItemKey = item.key;
          _dropPreview = null;
          if (!_customizingDashboard) {
            _customizingDashboard = true;
          }
        });
      },
      onDragEnd: (_) {
        if (mounted) _clearDashboardDragState();
      },
      onDraggableCanceled: (_, _) {
        if (mounted) _clearDashboardDragState();
      },
      onDragCompleted: () {
        if (mounted) _clearDashboardDragState();
      },
      child: target,
    );
  }

  bool _canAcceptOnItem(
    _HomeWidgetDragPayload? payload,
    _HomeDashboardItem target,
  ) {
    if (payload == null) return false;
    if (payload.itemKey == target.key) return false;
    return _dashboardItemForDragPayload(payload) != null;
  }

  bool _canMergeOnItem(
    _HomeWidgetDragPayload? payload,
    _HomeDashboardItem target,
  ) {
    if (payload == null || payload.itemKey == target.key) return false;
    final currentTarget = _dashboardItemByKey(target.key);
    if (currentTarget == null) return false;
    final source = _dashboardItemForDragPayload(payload);
    if (source == null) return false;
    return _canMergeDashboardItems(currentTarget, source);
  }

  Widget _buildDashboardCardControls(_HomeDashboardItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canResize(item)) ...[
          _miniControlButton(
            tooltip: item.size == _DashboardWidgetSize.large ? 'Klein' : 'Groß',
            icon: item.size == _DashboardWidgetSize.large
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            onTap: () => _toggleDashboardItemSize(item.key),
          ),
          const SizedBox(width: 6),
        ],
        _miniControlButton(
          tooltip: 'Entfernen',
          icon: Icons.close_rounded,
          onTap: () => _removeDashboardItem(item.key),
        ),
      ],
    );
  }

  Widget _miniControlButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF090B10).withValues(alpha: 0.90),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 15),
        ),
      ),
    );
  }

  Widget _buildDragFeedback(String title, IconData icon) {
    return Material(
      color: Colors.transparent,
      child: Transform.translate(
        offset: const Offset(-95, -44),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Transform.rotate(
            angle: -0.035,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF202530),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppAccentColors.accent.withValues(alpha: 0.38),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.36),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppAccentColors.accent, size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _dashboardItemTitle(_HomeDashboardItem item) {
    if (!item.isFolder) return _metaFor(item.widgetIds.first).title;
    if (item.title?.trim().isNotEmpty ?? false) {
      return item.title!.trim();
    }
    return item.widgetIds.map((id) => _metaFor(id).title).join(' + ');
  }

  Future<void> _renameDashboardFolder(_HomeDashboardItem item) async {
    if (!item.isFolder) return;
    final controller = TextEditingController(text: _dashboardItemTitle(item));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151922),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Gruppe benennen',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            maxLength: 28,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              counterStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.46),
              ),
              hintText: 'z.B. Community',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppAccentColors.accent),
              ),
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Abbrechen',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(
                'Speichern',
                style: TextStyle(
                  color: AppAccentColors.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    if (!mounted) return;

    final nextTitle = result.trim().isEmpty
        ? _defaultFolderTitle(item.widgetIds)
        : result.trim();
    final index = _dashboardItems.indexWhere(
      (current) => current.key == item.key,
    );
    if (index < 0) return;
    final next = [..._dashboardItems];
    next[index] = next[index].copyWith(title: nextTitle);
    HapticFeedback.selectionClick();
    setState(() => _dashboardItems = next);
    unawaited(_persistDashboardLayout());
  }

  Widget _buildSingleDashboardWidget(
    _HomeWidgetId id,
    _DashboardWidgetSize size, {
    bool embedded = false,
  }) {
    switch (id) {
      case _HomeWidgetId.xp:
        return _buildXpDashboardWidget(size);
      case _HomeWidgetId.todayRoute:
        return _buildSuggestedRouteSection();
      case _HomeWidgetId.community:
        return SizedBox(
          height: 288,
          child: CommunityCarouselCard(
            compact: embedded,
            framed: !embedded,
            showHeader: !embedded,
            onOpenCommunity: () => widget.onTabChange?.call(1),
          ),
        );
      case _HomeWidgetId.communityContacts:
        return SizedBox(
          height: size == _DashboardWidgetSize.large
              ? 288
              : _dashboardHalfTileHeight,
          child: CommunityCarouselCard(
            section: CommunityDashboardSection.contacts,
            compact: size == _DashboardWidgetSize.small || embedded,
            framed: !embedded,
            showHeader: !embedded,
            onOpenCommunity: () => widget.onTabChange?.call(1),
          ),
        );
      case _HomeWidgetId.communityGroups:
        return SizedBox(
          height: size == _DashboardWidgetSize.large
              ? 288
              : _dashboardHalfTileHeight,
          child: CommunityCarouselCard(
            section: CommunityDashboardSection.groups,
            compact: size == _DashboardWidgetSize.small || embedded,
            framed: !embedded,
            showHeader: !embedded,
            onOpenCommunity: () => widget.onTabChange?.call(1),
          ),
        );
      case _HomeWidgetId.communityEvents:
        return SizedBox(
          height: size == _DashboardWidgetSize.large
              ? 288
              : _dashboardHalfTileHeight,
          child: CommunityCarouselCard(
            section: CommunityDashboardSection.events,
            compact: size == _DashboardWidgetSize.small || embedded,
            framed: !embedded,
            showHeader: !embedded,
            onOpenCommunity: () => widget.onTabChange?.call(1),
          ),
        );
      case _HomeWidgetId.weekly:
        if (embedded) return _buildWeeklyFolderSlide();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTabChange?.call(3),
          child: SizedBox(
            height: size == _DashboardWidgetSize.large
                ? 280
                : _dashboardHalfTileHeight,
            child: _buildWeeklyActivityCard(),
          ),
        );
      case _HomeWidgetId.streak:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTabChange?.call(3),
          child: _buildStreakWidget(),
        );
      case _HomeWidgetId.quickStart:
        return _buildQuickStartWidget();
      case _HomeWidgetId.savedRoutes:
        return _buildSavedRoutesWidget(size);
      case _HomeWidgetId.profile:
        return _buildProfileShortcutWidget(size);
      case _HomeWidgetId.monthly:
        return _buildMonthlyActivityWidget(size);
      case _HomeWidgetId.badgeHunt:
        return _buildBadgeHuntWidget(size);
      case _HomeWidgetId.totals:
        return _buildTotalsWidget(size);
    }
  }

  Widget _buildFolderCard(_HomeDashboardItem item) {
    final maxPage = math.max(0, item.widgetIds.length - 1);
    final currentPage = ((_folderPages[item.key] ?? 0).clamp(
      0,
      maxPage,
    )).toInt();
    _folderPages[item.key] = currentPage;
    final height = item.size == _DashboardWidgetSize.large
        ? _dashboardFolderFullHeight
        : _dashboardHalfTileHeight;
    final controller = _folderSlideControllerFor(item.key);
    return Container(
      height: height,
      decoration: _dashboardCardDecoration(),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              12,
              _customizingDashboard ? 48 : 14,
              4,
            ),
            child: GestureDetector(
              onTap: _customizingDashboard
                  ? () => _renameDashboardFolder(item)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _dashboardItemTitle(item),
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: item.size == _DashboardWidgetSize.small
                          ? 14.5
                          : 16,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth
                    ? math.max(1.0, constraints.maxWidth)
                    : math.max(1.0, MediaQuery.sizeOf(context).width);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    controller.stop();
                    _folderTargetPages.remove(item.key);
                    if (controller.value.abs() > 0.01) {
                      controller.value = 0;
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (item.widgetIds.length < 2) return;
                    final delta = (details.primaryDelta ?? 0) / width;
                    final proposed = controller.value + delta;
                    final draggingBeforeStart =
                        currentPage == 0 && proposed > 0;
                    final draggingAfterEnd =
                        currentPage == maxPage && proposed < 0;

                    if (draggingBeforeStart) {
                      controller.value = (controller.value + delta * 0.28)
                          .clamp(0.0, 0.18)
                          .toDouble();
                    } else if (draggingAfterEnd) {
                      controller.value = (controller.value + delta * 0.28)
                          .clamp(-0.18, 0.0)
                          .toDouble();
                    } else {
                      controller.value = proposed.clamp(-1.0, 1.0).toDouble();
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (item.widgetIds.length < 2) return;
                    final velocity = details.primaryVelocity ?? 0;
                    final offset = controller.value;
                    final goNext = velocity < -260 || offset < -0.28;
                    final goPrevious = velocity > 260 || offset > 0.28;

                    if (goNext && currentPage < maxPage) {
                      _setFolderPage(
                        item.key,
                        currentPage + 1,
                        item.widgetIds.length,
                      );
                    } else if (goPrevious && currentPage > 0) {
                      _setFolderPage(
                        item.key,
                        currentPage - 1,
                        item.widgetIds.length,
                      );
                    } else {
                      _folderTargetPages.remove(item.key);
                      unawaited(_snapFolderCarouselBack(item.key));
                    }
                  },
                  onHorizontalDragCancel: () {
                    _folderTargetPages.remove(item.key);
                    unawaited(_snapFolderCarouselBack(item.key));
                  },
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final offset = controller.value;
                        var secondaryPage = _folderTargetPages[item.key];
                        if (secondaryPage == currentPage) {
                          secondaryPage = null;
                        }
                        secondaryPage ??= offset < 0 && currentPage < maxPage
                            ? currentPage + 1
                            : offset > 0 && currentPage > 0
                            ? currentPage - 1
                            : null;

                        final currentDx = offset * width;
                        final secondaryDx = secondaryPage == null
                            ? null
                            : (secondaryPage > currentPage ? width : -width) +
                                  currentDx;

                        Widget positionedSlide(int page, double dx) {
                          final id = item.widgetIds[page];
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: IgnorePointer(
                              ignoring:
                                  page != currentPage || offset.abs() > 0.02,
                              child: _buildFolderCarouselSlide(item, id),
                            ),
                          );
                        }

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (secondaryPage != null && secondaryDx != null)
                              positionedSlide(secondaryPage, secondaryDx),
                            positionedSlide(currentPage, currentDx),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildFolderDots(
              count: item.widgetIds.length,
              activeIndex: currentPage,
              onTap: (page) =>
                  _setFolderPage(item.key, page, item.widgetIds.length),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCarouselSlide(_HomeDashboardItem item, _HomeWidgetId id) {
    final payload = _HomeWidgetDragPayload.fromFolder(
      folderKey: item.key,
      childId: id,
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _buildSingleDashboardWidget(id, item.size, embedded: true),
            ),
          ),
          if (_customizingDashboard)
            Positioned(
              right: 6,
              bottom: 6,
              child: _miniControlButton(
                tooltip: 'Aus Ordner entfernen',
                icon: Icons.remove_circle_outline_rounded,
                onTap: () => _removeDashboardItem(item.key, id),
              ),
            ),
        ],
      ),
    );

    // 2026-07-23 (vucko „nur mit Basic bearbeiten"): siehe _buildDashboardCell.
    final canEditDashboard = context.watch<SubscriptionProvider>().isPaid;
    return KeyedSubtree(
      key: ValueKey('folder_content_${item.key}_${id.name}'),
      child: LongPressDraggable<_HomeWidgetDragPayload>(
        data: payload,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        maxSimultaneousDrags: canEditDashboard ? null : 0,
        feedback: _buildDragFeedback(_metaFor(id).title, _metaFor(id).icon),
        childWhenDragging: Opacity(opacity: 0.36, child: content),
        onDragStarted: () {
          HapticFeedback.selectionClick();
          _folderSlideControllerFor(item.key).stop();
          setState(() {
            _draggingDashboardItemKey = payload.identityKey;
            _dropPreview = null;
            if (!_customizingDashboard) {
              _customizingDashboard = true;
            }
          });
        },
        onDragEnd: (_) {
          if (mounted) _clearDashboardDragState();
        },
        onDraggableCanceled: (_, _) {
          if (mounted) _clearDashboardDragState();
        },
        onDragCompleted: () {
          if (mounted) _clearDashboardDragState();
        },
        child: content,
      ),
    );
  }

  Widget _buildFolderDots({
    required int count,
    required int activeIndex,
    ValueChanged<int>? onTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return GestureDetector(
          onTap: onTap == null ? null : () => onTap(index),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? AppAccentColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildWeeklyFolderSlide() {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final totalKm = _weeklyKmData.fold<double>(0, (sum, km) => sum + km);
    final activeDays = _weeklyKmData.where((km) => km > 0.05).length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Letzte 7 Tage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatCompactKm(totalKm),
                  maxLines: 1,
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activeDays == 0
                ? 'Noch keine Fahrten'
                : '$activeDays aktive ${activeDays == 1 ? 'Tag' : 'Tage'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 10.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (index) {
                final km = _weeklyKmData[index];
                final hasKm = km > 0.05;
                final fill = hasKm
                    ? math.max(_weeklyChartData[index], 0.12)
                    : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D3748),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: fill.clamp(0.0, 1.0),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppAccentColors.accent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          days[index],
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFFA0AEC0),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXpDashboardWidget(_DashboardWidgetSize size) {
    final accent = context.watch<AppAccentProvider>().color;
    if (size == _DashboardWidgetSize.small) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTabChange?.call(3),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _dashboardCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: accent, size: 21),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'XP Anzeige',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${(levelProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Level $userLevel - $levelName',
                maxLines: 2,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  height: 1.14,
                ),
              ),
              const SizedBox(height: 10),
              _buildLevelProgressBar(accent),
              const SizedBox(height: 10),
              Text(
                userLevel >= UserLevel.maxLevel
                    ? 'Maximallevel erreicht'
                    : 'Noch $xpToNextLevel XP bis Level ${userLevel + 1}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.56),
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_formatThousands(totalXp)} XP gesamt',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(3),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _dashboardCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Fortschritt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFA0AEC0),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _loading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              Icons.bolt,
                              _formatThousands(totalXp),
                              'XP GESAMT',
                              isAccent: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statTile(
                              Icons.speed,
                              totalDistanceKm.toStringAsFixed(0),
                              'KM GEFAHREN',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              Icons.route,
                              '$totalRoutes',
                              'STRECKEN',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statTile(
                              Icons.workspace_premium,
                              '$badgeCount',
                              'BADGES',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Level $userLevel - $levelName',
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(levelProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildLevelProgressBar(accent),
            const SizedBox(height: 8),
            Text(
              userLevel >= UserLevel.maxLevel
                  ? 'Maximallevel erreicht'
                  : 'Noch $xpToNextLevel XP bis Level ${userLevel + 1}',
              style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelProgressBar(Color accent) {
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: levelProgress.clamp(0.02, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [accent, AppAccentColors.accentStrong],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStartWidget() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(2),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppAccentColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Schnellstart',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Route planen und direkt losfahren.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedRoutesWidget(_DashboardWidgetSize size) {
    final provider = context.watch<RouteBookmarkProvider>();
    final savedCount = provider.savedRoutes.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SavedRouteBookmarksPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: size == _DashboardWidgetSize.small
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.bookmarks_rounded,
                      color: AppAccentColors.accent,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Merkliste',
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    savedCount == 1
                        ? '1 Route gemerkt'
                        : '$savedCount Routen gemerkt',
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.bookmarks_rounded,
                      color: AppAccentColors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Gespeicherte Routen',
                          maxLines: 2,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          savedCount == 1
                              ? '1 Route gemerkt'
                              : '$savedCount Routen gemerkt',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFA0AEC0),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileShortcutWidget(_DashboardWidgetSize size) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = (_profileUsername?.isNotEmpty ?? false)
        ? _profileUsername!
        : user?.email?.split('@')[0] ?? 'Profil';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: size == _DashboardWidgetSize.small
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    name: name,
                    avatarUrl: _avatarUrl,
                    radius: 22,
                    backgroundColor: AppAccentColors.accent,
                  ),
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Level $userLevel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  UserAvatar(
                    name: name,
                    avatarUrl: _avatarUrl,
                    radius: 24,
                    backgroundColor: AppAccentColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Level $userLevel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMonthlyActivityWidget(_DashboardWidgetSize size) {
    final maxKm = _monthlyWeekKmData.fold<double>(0, math.max);
    final height = size == _DashboardWidgetSize.large
        ? 254.0
        : _dashboardHalfTileHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(3),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: AppAccentColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Monat',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  _formatCompactKm(_monthDistanceKm),
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _compactMetric('Fahrten', '$_monthRoutes'),
                const SizedBox(width: 8),
                _compactMetric('Aktive Tage', '$_monthActiveDays'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(_monthlyWeekKmData.length, (index) {
                  final km = _monthlyWeekKmData[index];
                  final fill = maxKm > 0 ? (km / maxKm).clamp(0.0, 1.0) : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: km > 0.05
                                    ? math.max(fill.toDouble(), 0.12)
                                    : 0.04,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: km > 0.05
                                        ? AppAccentColors.primaryGradient
                                        : null,
                                    color: km > 0.05
                                        ? null
                                        : const Color(0xFF2D3748),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'W${index + 1}',
                            style: const TextStyle(
                              color: Color(0xFFA0AEC0),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeHuntWidget(_DashboardWidgetSize size) {
    final goal = _selectedBadgeGoal() ?? _recommendedBadgeGoal();
    final height = size == _DashboardWidgetSize.large
        ? 230.0
        : _dashboardHalfTileHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openBadgeHuntPicker,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: goal == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: AppAccentColors.accent,
                    size: 26,
                  ),
                  const Spacer(),
                  const Text(
                    'Badge-Jagd',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Alle bekannten Badge-Ziele sind geschafft.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppAccentColors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          goal.badge.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Badge-Jagd',
                              style: TextStyle(
                                color: Color(0xFFA0AEC0),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              goal.badge.name,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                height: 1.06,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    goal.action,
                    maxLines: size == _DashboardWidgetSize.large ? 3 : 2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.64),
                      fontSize: 11.5,
                      height: 1.22,
                    ),
                  ),
                  const Spacer(),
                  _progressLine(goal.progress),
                  const SizedBox(height: 7),
                  Text(
                    '${_formatGoalValue(goal.current)} / ${_formatGoalValue(goal.target)} ${goal.unit}',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTotalsWidget(_DashboardWidgetSize size) {
    final height = size == _DashboardWidgetSize.large
        ? 230.0
        : _dashboardHalfTileHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTabChange?.call(3),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        decoration: _dashboardCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.query_stats_rounded,
                  color: AppAccentColors.accent,
                  size: 21,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Gesamtwerte',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                _summaryMetric(Icons.route_rounded, '$totalRoutes', 'Touren'),
                const SizedBox(width: 8),
                _summaryMetric(
                  Icons.speed_rounded,
                  totalDistanceKm.toStringAsFixed(0),
                  'km',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _summaryMetric(
                  Icons.bolt_rounded,
                  _formatThousands(totalXp),
                  'XP',
                ),
                const SizedBox(width: 8),
                _summaryMetric(
                  Icons.workspace_premium_rounded,
                  '$badgeCount',
                  'Badges',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFA0AEC0),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(IconData icon, String value, String label) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppAccentColors.accent, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_BadgeGoal> _badgeGoals() {
    _BadgeGoal? goal(
      String id, {
      required double current,
      required double target,
      required String unit,
      required String action,
      required IconData icon,
    }) {
      final badge = app_badges.Badge.getById(id);
      if (badge == null) return null;
      return _BadgeGoal(
        badge: badge,
        current: current,
        target: target,
        unit: unit,
        action: action,
        icon: icon,
      );
    }

    return [
      goal(
        'badge_02',
        current: totalRoutes.toDouble(),
        target: 1,
        unit: 'Fahrt',
        action: 'Schließe deine erste Route ab.',
        icon: Icons.flag_rounded,
      ),
      goal(
        'badge_01',
        current: userLevel.toDouble(),
        target: 10,
        unit: 'Level',
        action: 'Sammle XP bis Level 10.',
        icon: Icons.rocket_launch_rounded,
      ),
      goal(
        'badge_06',
        current: totalDistanceKm,
        target: 500,
        unit: 'km',
        action: 'Fahre insgesamt 500 km.',
        icon: Icons.public_rounded,
      ),
      goal(
        'badge_09',
        current: _savedRouteCount.toDouble(),
        target: 5,
        unit: 'Routen',
        action: 'Speichere 5 verschiedene Routen.',
        icon: Icons.bookmarks_rounded,
      ),
      goal(
        'badge_03',
        current: userLevel.toDouble(),
        target: 25,
        unit: 'Level',
        action: 'Erreiche Level 25.',
        icon: Icons.route_rounded,
      ),
      goal(
        'badge_10',
        current: totalDistanceKm,
        target: 2500,
        unit: 'km',
        action: 'Fahre insgesamt 2.500 km.',
        icon: Icons.emoji_events_rounded,
      ),
      goal(
        'badge_08',
        current: userLevel.toDouble(),
        target: 50,
        unit: 'Level',
        action: 'Erreiche Level 50.',
        icon: Icons.sports_score_rounded,
      ),
      goal(
        'badge_13',
        current: totalDistanceKm,
        target: 10000,
        unit: 'km',
        action: 'Fahre insgesamt 10.000 km.',
        icon: Icons.workspace_premium_rounded,
      ),
      goal(
        'badge_14',
        current: userLevel.toDouble(),
        target: UserLevel.maxLevel.toDouble(),
        unit: 'Level',
        action: 'Erreiche Level ${UserLevel.maxLevel}.',
        icon: Icons.diamond_rounded,
      ),
    ].whereType<_BadgeGoal>().toList();
  }

  _BadgeGoal? _badgeGoalForId(String? badgeId) {
    if (badgeId == null) return null;
    for (final goal in _badgeGoals()) {
      if (goal.badge.id == badgeId && !_earnedBadgeIds.contains(badgeId)) {
        return goal;
      }
    }
    return null;
  }

  _BadgeGoal? _selectedBadgeGoal() => _badgeGoalForId(_selectedBadgeHuntId);

  _BadgeGoal? _recommendedBadgeGoal() {
    final goals = _badgeGoals()
        .where((goal) => !_earnedBadgeIds.contains(goal.badge.id))
        .where((goal) => !goal.complete)
        .toList();
    if (goals.isEmpty) return null;
    goals.sort((a, b) {
      final progress = b.progress.compareTo(a.progress);
      if (progress != 0) return progress;
      return a.target.compareTo(b.target);
    });
    return goals.first;
  }

  Future<void> _openBadgeHuntPicker() async {
    HapticFeedback.selectionClick();
    final goals = _badgeGoals()
        .where((goal) => !_earnedBadgeIds.contains(goal.badge.id))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11151D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Badge-Jagd wählen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dieses Ziel erscheint als Widget auf deiner Home.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        for (final goal in goals) ...[
                          _buildBadgeGoalOption(sheetContext, goal),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgeGoalOption(BuildContext sheetContext, _BadgeGoal goal) {
    final selected = _selectedBadgeHuntId == goal.badge.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selectedBadgeHuntId = goal.badge.id);
        unawaited(_persistBadgeHuntPreference(goal.badge.id));
        Navigator.of(sheetContext).pop();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent.withValues(alpha: 0.48)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                goal.badge.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.badge.name,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _progressLine(goal.progress),
                  const SizedBox(height: 5),
                  Text(
                    '${_formatGoalValue(goal.current)} / ${_formatGoalValue(goal.target)} ${goal.unit}',
                    style: const TextStyle(
                      color: Color(0xFFA0AEC0),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected
                  ? AppAccentColors.accent
                  : const Color(0xFFA0AEC0),
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressLine(double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 7,
        value: progress.clamp(0.0, 1.0),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(AppAccentColors.accent),
      ),
    );
  }

  String _formatGoalValue(double value) {
    if (value >= 1000) return _formatThousands(value.round());
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  BoxDecoration _dashboardCardDecoration() {
    return BoxDecoration(
      color: const Color(0xFF1C1F26),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildSuggestedRouteSection() {
    final recommendation = _todayRecommendation;
    final trip = _activeTrip;
    final resumableRide = _resumableRide;

    // 2026-05-24 (vucko): Mehrere Cards → swipeable Carousel.
    // 2026-07-06 (vucko Fahrt-Resume): Unterbrochene Fahrt kommt ZUERST —
    // das ist die dringendste Aktion (App wurde mitten in der Fahrt beendet).
    final cards = <Widget>[
      if (resumableRide != null) _buildRideResumeCarouselCard(resumableRide),
      if (trip != null) _buildTripResumeCarouselCard(trip),
      if (recommendation != null)
        // Heute-für-dich-Card auf gleiche Carousel-Höhe wrappen damit
        // PageView nichts streckt. Original-Card hat intrinsisch < 180px.
        SizedBox(
          height: _carouselCardHeight,
          child: _buildSuggestedRouteCard(recommendation),
        ),
    ];
    if (cards.length > 1) {
      return _buildHomeCarousel(cards: cards);
    }
    if (resumableRide != null) {
      return _buildRideResumeCarouselCard(resumableRide);
    }
    if (trip != null) {
      return _buildTripResumeCarouselCard(trip);
    }
    if (recommendation != null) {
      return _buildSuggestedRouteCard(recommendation);
    }
    if (_loading) {
      return _buildSuggestedRouteSkeleton();
    }
    return _buildEmptyRecommendation();
  }

  /// 2026-07-06 (vucko Fahrt-Resume): Card für eine unterbrochene Solo-Fahrt.
  /// Tap = Route über den bewährten pendingRoute-Pfad erneut laden; der
  /// joinNearestForward-Mechanismus schließt automatisch am nächsten
  /// Routenpunkt an — auch wenn der User inzwischen weitergefahren ist.
  Widget _buildRideResumeCarouselCard(ActiveRideSnapshot ride) {
    const statusColor = Color(0xFFFFB347);
    final ageMinutes = DateTime.now().difference(ride.savedAt).inMinutes;
    final ageLabel = ageMinutes < 60
        ? 'vor $ageMinutes Min'
        : 'vor ${(ageMinutes / 60).floor()} Std';
    final remainingKm = (ride.distanceKm - ride.drivenKm).clamp(
      0.0,
      ride.distanceKm,
    );
    final metricsLine =
        '${ride.distanceKm.toStringAsFixed(0)} km Route • '
        '${ride.drivenKm.toStringAsFixed(0)} km gefahren • ${ride.style}';
    return SizedBox(
      height: _carouselCardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'FAHRT UNTERBROCHEN',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '· $ageLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ride.isRoundTrip ? 'Rundkurs fortsetzen' : 'Fahrt fortsetzen',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                  height: 1.08,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 5),
              Text(
                metricsLine,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                'Noch ~${remainingKm.toStringAsFixed(0)} km offen — die Route '
                'wird an deiner Position wieder aufgenommen.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11.5,
                ),
                maxLines: 2,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppAccentColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => _resumeInterruptedRide(ride),
                        child: const Text(
                          'Fortsetzen',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.55),
                      ),
                      onPressed: _dismissInterruptedRide,
                      child: const Text(
                        'Verwerfen',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resumeInterruptedRide(ActiveRideSnapshot ride) {
    final route = SavedRoute(
      id: 'local-resume-${ride.startedAt.millisecondsSinceEpoch}',
      createdAt: ride.startedAt,
      style: ride.style,
      distanceKm: ride.distanceKm,
      geometry: ride.geometry,
      durationSeconds: ride.durationSeconds,
      routeType: ride.isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT',
      routeSource: 'resume',
    );
    CruiseModePage.pendingRoute.value = route;
    widget.onTabChange?.call(2);
  }

  void _dismissInterruptedRide() {
    unawaited(ActiveRideSnapshotService.clear());
    if (mounted) setState(() => _resumableRide = null);
  }

  // 2026-05-24 (vucko): Carousel-State für Trip+Heute-Slides.
  int _carouselIndex = 0;
  late final PageController _carouselController = PageController();

  /// Carousel-Höhe synchron zur Heute-für-dich-Card.
  /// "Heute für dich" braucht mit Mini-Map, nachgeladenen Hero-Insights,
  /// zwei Metric-Zeilen und 44px-CTA genug Luft, sonst overflowt sie im
  /// Trip+Route-Carousel auf schmalen iPhones.
  static const double _carouselCardHeight = 252;

  Widget _buildHomeCarousel({required List<Widget> cards}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _carouselCardHeight,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: cards.length,
            onPageChanged: (i) {
              if (mounted) setState(() => _carouselIndex = i);
            },
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: cards[i],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Pagination dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (i) {
            final active = i == _carouselIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              width: active ? 20 : 6,
              decoration: BoxDecoration(
                color: active
                    ? AppAccentColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Trip-Resume-Card im Carousel — komplett app-konforme dunkle Optik.
  /// 2026-05-24 (vucko v2): kein Gradient, kein helles Tinten, exakt das
  /// gleiche Card-Schema wie "Heute für dich". Status nur als kleiner
  /// gefärbter Pin.
  Widget _buildTripResumeCarouselCard(TripSummary trip) {
    final isPaused = trip.isPaused;
    final statusColor = isPaused
        ? const Color(0xFFFFB347)
        : AppAccentColors.accent;
    final statusLabel = isPaused ? 'Tour pausiert' : 'Tour aktiv';
    final statusSubtitle = _tripStatusSubtitle(trip);
    final title = trip.title.isEmpty ? 'Multi-Stop Tour' : trip.title;
    // Distanz nur zeigen wenn > 0 (sonst irreführend "0 km")
    final km = trip.totalDistanceKm;
    final metricsLine = km > 0
        ? '${trip.stopCount} Stopps • ${km.toStringAsFixed(0)} km • ${trip.defaultStyle}'
        : '${trip.stopCount} Stopps • ${trip.defaultStyle}';
    final canCancelTrip = _canCancelTrip(trip);
    return SizedBox(
      height: _carouselCardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header-Zeile (exakt analog "Heute für dich")
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                    ),
                  ),
                  if (statusSubtitle.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '· $statusSubtitle',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                  height: 1.08,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 5),
              Text(
                metricsLine,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
                maxLines: 2,
              ),
              const Spacer(),
              // CTA wie der Drive-Chip in der Heute-Card (orange filled)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openTrip(trip),
                      child: SizedBox(
                        height: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppAccentColors.accent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppAccentColors.accent.withValues(
                                  alpha: 0.32,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPaused ? 'Tour fortsetzen' : 'Tour öffnen',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canCancelTrip) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Tour abbrechen',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isClosingTrip
                            ? null
                            : () => _confirmCancelTrip(trip),
                        child: Container(
                          width: 44,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: _isClosingTrip
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.76),
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTrip(TripSummary trip) {
    final groupId = trip.groupId;
    if (groupId != null) {
      CruiseModePage.pendingGroupView.value = groupId;
      widget.onTabChange?.call(1);
      return;
    }
    // 2026-06-10 (vucko Resume-Crash-Fix): erst null, dann id — ein
    // ValueNotifier feuert bei GLEICHEM Wert nicht. Blieb der Intent von
    // einem fehlgeschlagenen Versuch stehen (wird seit heute erst nach
    // Erfolg konsumiert), wäre der zweite Tap sonst ein totes Event.
    CruiseModePage.pendingTripResume.value = null;
    CruiseModePage.pendingTripResume.value = trip.id;
    widget.onTabChange?.call(2);
  }

  bool _canCancelTrip(TripSummary trip) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId != null && trip.ownerId == userId;
  }

  Future<void> _confirmCancelTrip(TripSummary trip) async {
    if (_isClosingTrip) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Tour abbrechen?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Die Tour wird aus dem Fortsetzen-Bereich entfernt. Deine gefahrenen Strecken bleiben unverändert.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Zurück',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Abbrechen',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousTrip = _activeTrip;
    setState(() {
      _isClosingTrip = true;
      _activeTrip = null;
    });

    try {
      await TripService.instance.cancelTrip(trip.id);
      if (!mounted) return;
      TopToast.show(
        context,
        message: 'Tour abgebrochen',
        icon: Icons.close_rounded,
      );
      unawaited(_loadStats());
    } catch (e) {
      debugPrint('[Home] Trip abbrechen fehlgeschlagen: $e');
      if (!mounted) return;
      setState(() => _activeTrip = previousTrip);
      TopToast.show(
        context,
        message: 'Tour konnte nicht abgebrochen werden',
        icon: Icons.error_outline,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isClosingTrip = false);
    }
  }

  String _tripStatusSubtitle(TripSummary trip) {
    // 2026-05-24 (vucko Fix): negative Diff (clock skew / zukünftiger
    // started_at) als "gerade gestartet" zeigen — niemals "-X Min".
    String formatAgo(DateTime when, String prefix) {
      final mins = DateTime.now().difference(when).inMinutes;
      if (mins <= 0) return '$prefix gerade eben';
      if (mins < 60) return '$prefix seit $mins Min';
      final h = mins ~/ 60;
      if (h < 24) return '$prefix seit ${h}h';
      return '$prefix seit ${h ~/ 24}d';
    }

    if (trip.isPaused && trip.pausedAt != null) {
      return formatAgo(trip.pausedAt!, 'pausiert');
    }
    if (trip.isActive && trip.startedAt != null) {
      return formatAgo(trip.startedAt!, 'läuft');
    }
    return '';
  }

  Widget _buildSuggestedRouteCard(HomeRouteRecommendation recommendation) {
    final route = recommendation.route;
    final coordinates = _extractCoordinates(route.geometry);
    final heroInsights = _heroInsightsByRouteId[route.id];
    final ratingValue = recommendation.averageRating;
    final title = recommendation.displayName;
    final routeTypeLabel = route.isRoundTrip ? 'Rundkurs' : 'A nach B';
    final durationLabel = route.formattedDuration;
    final distanceLabel = route.formattedDistance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 430;
        final isCarouselConstrained =
            constraints.hasBoundedHeight &&
            constraints.maxHeight <= _carouselCardHeight + 1;
        // 2026-06-08 (vucko Route-Widget): quadratische Mini-Map, ~Höhe der
        // dichten Titel-/Stat-Spalte links.
        final previewSize = isCompact
            ? (isCarouselConstrained ? 88.0 : 96.0)
            : (isCarouselConstrained ? 96.0 : 104.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            CruiseModePage.pendingRoute.value = route;
            widget.onTabChange?.call(2);
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            // 2026-06-08 (vucko Route-Widget): dichteres, premium Layout. Tight-
            // Cluster (Eyebrow→Titel→Untertitel→Stat-Strip mit 2–11px) + EIN
            // bewusster 14px-Bruch vor der CTA. Stat-Chips → randlose Inline-Icon-
            // Metriken, Stil wandert in den Untertitel → kein Stil-Chip mehr.
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                isCarouselConstrained ? 12 : 13,
                14,
                isCarouselConstrained ? 12 : 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: AppAccentColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'HEUTE FÜR DICH',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              maxLines: 2,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.96),
                                fontSize: isCompact ? 16.5 : 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.25,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$routeTypeLabel · ${route.displayStyleLabel}',
                              maxLines: 2,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                              ),
                            ),
                            SizedBox(height: isCarouselConstrained ? 9 : 11),
                            Wrap(
                              spacing: 13,
                              runSpacing: 7,
                              children: [
                                _inlineMetric(
                                  Icons.straighten_rounded,
                                  distanceLabel,
                                ),
                                if (heroInsights != null)
                                  _inlineMetric(
                                    Icons.moving_rounded,
                                    '${heroInsights.curves} Kurven',
                                  ),
                                if (durationLabel.isNotEmpty &&
                                    durationLabel != '--')
                                  _inlineMetric(
                                    Icons.schedule_rounded,
                                    durationLabel,
                                  ),
                                if (ratingValue != null &&
                                    recommendation.ratingCount > 0)
                                  _inlineMetric(
                                    Icons.star_rounded,
                                    ratingValue.toStringAsFixed(1),
                                    iconColor: AppAccentColors.accent,
                                    valueColor: AppAccentColors.accent,
                                  ),
                                if (heroInsights != null)
                                  _inlineMetric(
                                    Icons.bolt_rounded,
                                    '${heroInsights.xp} XP',
                                    iconColor: Colors.white.withValues(
                                      alpha: 0.45,
                                    ),
                                    valueColor: Colors.white.withValues(
                                      alpha: 0.5,
                                    ),
                                    valueSize: 12.5,
                                    valueWeight: FontWeight.w500,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildSuggestedRoutePreview(
                        route,
                        coordinates,
                        size: previewSize,
                      ),
                    ],
                  ),
                  SizedBox(height: isCarouselConstrained ? 12 : 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDriveCta(
                          onTap: () {
                            CruiseModePage.pendingRoute.value = route;
                            widget.onTabChange?.call(2);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSaveChip(route),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 2026-06-08 (vucko Route-Widget): randlose Inline-Metrik (Icon = Label, Wert
  // daneben). Dichter + ruhiger als Pills; Icon trägt die Bedeutung.
  Widget _inlineMetric(
    IconData icon,
    String value, {
    Color? iconColor,
    Color? valueColor,
    double valueSize = 13.5,
    FontWeight valueWeight = FontWeight.w600,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white.withValues(alpha: 0.88),
            fontSize: valueSize,
            fontWeight: valueWeight,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  // Primäre CTA — füllt per Expanded die Restbreite, h44 für ein klares Tap-Ziel.
  Widget _buildDriveCta({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppAccentColors.accent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: AppAccentColors.accent.withValues(alpha: 0.34),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car_filled_rounded,
              color: Colors.white,
              size: 19,
            ),
            SizedBox(width: 7),
            Text(
              'Fahren',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedRoutePreview(
    SavedRoute route,
    List<List<double>> coordinates, {
    required double size,
  }) {
    // 2026-06-08 (vucko Route-Widget): Mini-Map mit straßen-artigem Hintergrund
    // (Land → Blöcke → an der Routenachse ausgerichtetes Straßennetz → Route mit
    // Glow/Casing/Linie/Punkten). KEINE Overlay-Icons mehr (Stil-Badge + Map-Icon
    // entfernt) — das Kästchen zeigt nur Karte + Route.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // 2026-06-08 (vucko Route-Widget): ganz leicht sichtbarer Rahmen.
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: CustomPaint(
          painter: _RouteMiniMapPainter(
            coordinates: coordinates,
            seed: route.id.hashCode,
            accent: AppAccentColors.accent,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyRecommendation() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF2A313C),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Heute für dich',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Starte deine erste Route',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sobald eine Empfehlung verfügbar ist, erscheint sie hier als kompakte Featured-Route.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 132,
              height: 132,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!,
                      AppAccentColors.accentStrong,
                    ],
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171C24),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.explore_outlined,
                    color: AppAccentColors.accent,
                    size: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedRouteSkeleton() {
    Widget shimmerCopy(double maxWidth) {
      double capped(double width) => math.min(width, maxWidth);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _shimmerBar(width: capped(112), height: 12),
          const SizedBox(height: 8),
          _shimmerBar(width: capped(220), height: 24),
          const SizedBox(height: 8),
          _shimmerBar(width: capped(230), height: 14),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _shimmerPill(width: capped(118)),
              _shimmerPill(width: capped(98)),
              _shimmerPill(width: capped(74)),
            ],
          ),
          const SizedBox(height: 10),
          _shimmerBar(width: capped(190), height: 34, radius: 12),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final previewSize = isCompact ? 92.0 : 116.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2A313C),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 150),
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, copyConstraints) {
                        return shimmerCopy(copyConstraints.maxWidth);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  _shimmerRoutePreview(size: previewSize),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveChip(SavedRoute route) {
    return GestureDetector(
      onTap: () async {
        // 2026-06-09 (vucko Audit T3-B): Doppel-Tap-Schutz — verhindert nebenläufige
        // save/unsave-Calls (doppelte DB-Inserts / Toggle-Race).
        if (_isSavingRoute) return;
        _isSavingRoute = true;
        // 2026-05-22 (vucko): Optimistic UI — setState SOFORT, dann async work.
        // Vorher: 5 sequenzielle awaits (save → reload → checkSaved → provider
        // reload → calculateAndSync) blockten UI 2-3s. Jetzt: User sieht
        // sofort den Haken, alles andere passiert im Hintergrund.
        final wasSaved = _isRouteSaved;
        try {
          if (wasSaved) {
            setState(() => _isRouteSaved = false); // optimistic
            unawaited(SavedRoutesService.unsaveRouteEverywhere(route));
            if (!mounted) return;
            unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
            unawaited(context.read<SavedRoutesProvider>().loadRoutes());
            return;
          }

          // optimistic: setState true sofort
          setState(() => _isRouteSaved = true);
          TopToast.show(
            context,
            message: 'Route gespeichert',
            icon: Icons.bookmark_added_rounded,
          );
          // Async work im Hintergrund
          await SavedRoutesService.saveExistingRoute(route);
          if (!mounted) return;
          unawaited(context.read<RouteBookmarkProvider>().loadSavedRoutes());
          unawaited(context.read<SavedRoutesProvider>().loadRoutes());
          // Gamification + Badge-Popup async (kein UI-Block)
          unawaited(() async {
            final gamResult = await GamificationService.calculateAndSync();
            if (!mounted) return;
            if (gamResult.newBadges.isNotEmpty) {
              await showBadgeUnlockPopup(
                context: context,
                badges: gamResult.newBadges,
              );
            }
          }());
        } catch (e) {
          debugPrint('[Home] Route speichern fehlgeschlagen: $e');
          if (!mounted) {
            _isSavingRoute = false;
            return;
          }
          // Rollback optimistic state
          setState(() => _isRouteSaved = wasSaved);
          TopToast.show(
            context,
            message: 'Route konnte nicht gespeichert werden',
            icon: Icons.error_outline,
            isError: true,
          );
        } finally {
          _isSavingRoute = false;
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        // 2026-06-08 (vucko Route-Widget): gleiche Höhe wie der Fahren-Button (44).
        width: 48,
        height: 44,
        decoration: BoxDecoration(
          color: _isRouteSaved
              ? const Color(0xFFFFE2A8).withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: _isRouteSaved
                ? const Color(0xFFFFE2A8).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          _isRouteSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: _isRouteSaved ? const Color(0xFFFFE2A8) : Colors.white,
          size: 17,
        ),
      ),
    );
  }

  Widget _shimmerBar({
    required double width,
    required double height,
    double radius = 12,
  }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final phase = _shimmerController.value;
        return Container(
          width: width.isFinite ? width : double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + phase * 2, -0.2),
              end: Alignment(1.0 + phase * 2, 0.2),
              colors: const [
                Color(0xFF22262F),
                Color(0xFF323844),
                Color(0xFF22262F),
              ],
              stops: const [0.2, 0.5, 0.8],
            ),
          ),
        );
      },
    );
  }

  Widget _shimmerPill({required double width}) {
    return _shimmerBar(width: width, height: 28, radius: 999);
  }

  Widget _shimmerRoutePreview({double size = 188}) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!,
              AppAccentColors.accentStrong,
            ],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF171C24),
            borderRadius: BorderRadius.circular(24),
          ),
          child: AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: CustomPaint(
                  painter: _RoutePolylinePainter(
                    accent: AppAccentColors.accent,
                    coordinates: [
                      [0.12, 0.78],
                      [0.26, 0.52],
                      [0.42, 0.60],
                      [0.58, 0.30],
                      [0.76, 0.44],
                      [0.88, 0.18],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Hero-Streak-Banner (prominent, above-the-fold) ──────────────────────

  Widget _buildHeroStreakBanner() {
    final accent = AppAccentColors.accent;
    final mul = GamificationService.streakMultiplierForDays(_streakDays);
    final mulNext = GamificationService.streakMultiplierForDays(
      _streakDays + 1,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: GestureDetector(
        onTap: () => widget.onTabChange?.call(3),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFFF6B35).withValues(alpha: 0.85),
                accent.withValues(alpha: 0.78),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: const Text('🔥', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_streakDays Tage Streak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Heute fahren: ${mulNext.toStringAsFixed(2)}× XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  '${mul.toStringAsFixed(2)}×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Streak Widget ────────────────────────────────────────────────────────

  // 2026-06-16 (vucko): Streak-Dashboard-Kachel = das ALTE orange Streak-Hero
  // (nicht mehr die schlichte dunkle Karte/N6-Dublette). Bei aktiver Streak
  // leuchtend orange mit 🔥, sonst dezent dunkel mit ❄️. OHNE „(+10%)"-Zusatz.
  Widget _buildStreakWidget() {
    final hasStreak = _streakDays > 0;
    final accent = AppAccentColors.accent;
    final mul = GamificationService.streakMultiplierForDays(_streakDays);
    final mulNext = GamificationService.streakMultiplierForDays(
      _streakDays + 1,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: hasStreak
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFF6B35).withValues(alpha: 0.92),
                    accent.withValues(alpha: 0.85),
                  ],
                )
              : null,
          color: hasStreak ? null : const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(22),
          border: hasStreak
              ? null
              : Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                ),
          boxShadow: hasStreak
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.32),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasStreak
                    ? Colors.white.withValues(alpha: 0.18)
                    : const Color(0xFF2D3748),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasStreak
                      ? Colors.white.withValues(alpha: 0.30)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                hasStreak ? '🔥' : '❄️',
                style: const TextStyle(fontSize: 26),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasStreak
                        ? '$_streakDays Tage Streak'
                        : 'Keine aktive Streak',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasStreak
                        ? 'Heute fahren: ${mulNext.toStringAsFixed(2)}× XP'
                        : 'Starte eine Fahrt und beginne deinen Streak.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasStreak
                          ? Colors.white.withValues(alpha: 0.92)
                          : const Color(0xFFA0AEC0),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (hasStreak) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  '${mul.toStringAsFixed(2)}×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────────────

  // 2026-06-08 (vucko Homescreen-Redesign): eine Stat-Kachel — Icon in dezentem
  // Squircle-Chip, große Zahl, kleines Uppercase-Label. Eine Kachel akzentuiert
  // (XP), der Rest neutral-grau → ein Fokus, kein Emoji-Wirrwarr.
  Widget _statTile(
    IconData icon,
    String value,
    String label, {
    bool isAccent = false,
  }) {
    final tint = isAccent ? AppAccentColors.accent : const Color(0xFF9AA4B2);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: isAccent ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: tint, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 2,
                style: const TextStyle(
                  color: Color(0xFFF0F0F0),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                style: const TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Tausender-Trennung (deutsch: 1.535).
  String _formatThousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return (n < 0 ? '-' : '') + buf.toString();
  }

  Widget _buildWeeklyActivityCard() {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final totalKm = _weeklyKmData.fold<double>(0, (sum, km) => sum + km);
    final activeDays = _weeklyKmData.where((km) => km > 0.05).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Letzte 7 Tage',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatCompactKm(totalKm),
                  style: TextStyle(
                    color: AppAccentColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activeDays == 0
                ? 'Noch keine Fahrten'
                : '$activeDays aktive ${activeDays == 1 ? 'Tag' : 'Tage'}',
            maxLines: 2,
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (index) {
                return Expanded(
                  child: _buildWeeklyBar(
                    day: days[index],
                    value: _weeklyChartData[index],
                    km: _weeklyKmData[index],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBar({
    required String day,
    required double value,
    required double km,
  }) {
    final hasKm = km > 0.05;
    final fill = hasKm ? math.max(value, 0.12) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: 12,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D3748),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: 12,
                        height: constraints.maxHeight * fill,
                        decoration: BoxDecoration(
                          gradient: hasKm
                              ? AppAccentColors.primaryGradient
                              : null,
                          color: hasKm ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            day,
            maxLines: 1,
            style: TextStyle(
              color: hasKm ? Colors.white : const Color(0xFFA0AEC0),
              fontSize: 10,
              fontWeight: hasKm ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompactKm(double km) {
    if (km <= 0.05) return '0 km';
    if (km >= 100) return '${km.round()} km';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
}

// ── CustomPainter für Route-Polyline auf dem Gradient-Hintergrund ──────────

class _HeroRouteInsights {
  _HeroRouteInsights({
    required this.curves,
    required this.xp,
    required this.elevation,
  });

  final int curves;
  final int xp;
  final RouteElevationSummary? elevation;
}

// 2026-06-08 (vucko Homescreen-Redesign): echte GPS-Route als premium Mini-Skizze.
// Aufbau hintereinander (Mapbox-Nav-Look): weicher Glow → Casing in BG-Farbe (hebt
// die Linie sauber vom Glow ab) → Akzent-Linie → Start/Ziel-Punkte mit Ring.
// Rundkurs (Start≈Ziel) zeigt EINEN Punkt statt zwei überlappender.
class _RoutePolylinePainter extends CustomPainter {
  final List<List<double>> coordinates;
  final Color accent;

  _RoutePolylinePainter({required this.coordinates, required this.accent});

  static const Color _bg = Color(0xFF171C24);

  @override
  void paint(Canvas canvas, Size size) {
    if (coordinates.length < 2) return;

    double minLon = double.infinity, maxLon = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    for (final c in coordinates) {
      if (c[0] < minLon) minLon = c[0];
      if (c[0] > maxLon) maxLon = c[0];
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
    }

    final lonRange = maxLon - minLon;
    final latRange = maxLat - minLat;
    if (lonRange == 0 && latRange == 0) return;

    const padding = 12.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;
    final scaleX = lonRange > 0 ? drawWidth / lonRange : 1.0;
    final scaleY = latRange > 0 ? drawHeight / latRange : 1.0;
    final scale = math.min(scaleX, scaleY);
    final offsetX = padding + (drawWidth - lonRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    final points = coordinates.map((c) {
      final x = offsetX + (c[0] - minLon) * scale;
      final y = offsetY + (maxLat - c[1]) * scale;
      return Offset(x, y);
    }).toList();

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // 1. Glow (weicher Akzent-Schein)
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.26)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );
    // 2. Casing (BG-Farbe) — hebt die Linie sauber vom Glow ab.
    canvas.drawPath(
      path,
      Paint()
        ..color = _bg
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    // 3. Hauptlinie (Akzent)
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // 4. Start/Ziel-Punkte
    final diag = math.sqrt(lonRange * lonRange + latRange * latRange);
    final startEndGeo = math.sqrt(
      math.pow(coordinates.first[0] - coordinates.last[0], 2) +
          math.pow(coordinates.first[1] - coordinates.last[1], 2),
    );
    final isLoop = diag > 0 && startEndGeo / diag < 0.08;

    void dot(Offset p, Color fill) {
      canvas.drawCircle(p, 3.6, Paint()..color = _bg);
      canvas.drawCircle(p, 2.4, Paint()..color = fill);
    }

    if (isLoop) {
      dot(points.first, accent);
    } else {
      dot(points.first, const Color(0xFF34D399)); // grün = Start
      dot(points.last, accent); // Akzent = Ziel
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePolylinePainter oldDelegate) =>
      oldDelegate.coordinates != coordinates || oldDelegate.accent != accent;
}

// 2026-06-08 (vucko Route-Widget): Offline-Mini-Map als Hintergrund der Empfehlung.
// Recherchiert (Komoot/Strava-Thumbnail-Look): gedämpfter Karten-Basemap (Land +
// Häuserblöcke + an der Routen-Hauptachse ausgerichtetes Straßennetz) in einem
// engen Grau-Wertband, darüber die Route als einziges saturiertes Element. Alles
// deterministisch aus der Route-ID geseedet (kein Flackern), keine Tiles/kein
// Live-GL-Map → performant im Scroll-Feed.
class _RouteMiniMapPainter extends CustomPainter {
  final List<List<double>> coordinates; // leer → generische Skizze
  final int seed;
  final Color accent;

  _RouteMiniMapPainter({
    required this.coordinates,
    required this.seed,
    required this.accent,
  });

  static const Color _land = Color(0xFF0E0F12);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed & 0x7fffffff);

    // 1. Land-Basis mit dezentem Vertikal-Verlauf (Tiefe statt flach).
    final baseRect = Offset.zero & size;
    canvas.drawRect(
      baseRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14171E), Color(0xFF0C0D11)],
        ).createShader(baseRect),
    );

    // Route-Punkte (echt oder generisch) — geben die Haupt-Ausrichtung des
    // Straßennetzes vor (first→Mitte ist auch bei Rundkursen stabil).
    final pts = coordinates.length >= 2
        ? _projectRoute(size)
        : _genericRoute(size, rnd);
    final mid = pts[pts.length ~/ 2];
    final theta = math.atan2(mid.dy - pts.first.dy, mid.dx - pts.first.dx);
    final perp = theta + math.pi / 2;
    final diag = size.width + size.height;

    // 2. Baufelder: leicht in Netz-Richtung gedrehte Blöcke (wie echte Häuserzeilen
    // zwischen den Straßen), nicht achsen-parallel → wirkt organischer.
    final blockPaint = Paint()
      ..color = const Color(0xFF2B313C).withValues(alpha: 0.55);
    for (var i = 0; i < 16; i++) {
      final bw = 6.0 + rnd.nextDouble() * 13;
      final bh = 6.0 + rnd.nextDouble() * 13;
      canvas.save();
      canvas.translate(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      canvas.rotate(theta + (rnd.nextDouble() - 0.5) * 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: bw, height: bh),
          const Radius.circular(1.5),
        ),
        blockPaint,
      );
      canvas.restore();
    }

    // 3. Organisches Straßennetz: sanft mäandernde Linien (keine starren Geraden),
    //    grob an theta/perp ausgerichtet mit Winkel-Jitter → wirkt wie echte Straßen.
    void windingRoad(
      double sx,
      double sy,
      double angle,
      double length,
      int steps,
      double width,
      Color color,
    ) {
      final path = Path()..moveTo(sx, sy);
      var px = sx, py = sy, a = angle;
      final seg = length / steps;
      for (var i = 0; i < steps; i++) {
        a += (rnd.nextDouble() - 0.5) * 0.34;
        px += math.cos(a) * seg;
        py += math.sin(a) * seg;
        path.lineTo(px, py);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < 8; i++) {
      final a = (i.isEven ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.6;
      windingRoad(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
        a,
        size.width * (0.45 + rnd.nextDouble() * 0.5),
        4,
        0.8,
        const Color(0xFF3C4350),
      );
    }
    for (var i = 0; i < 3; i++) {
      final a = (i.isEven ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.4;
      final cx = (0.25 + rnd.nextDouble() * 0.5) * size.width;
      final cy = (0.25 + rnd.nextDouble() * 0.5) * size.height;
      windingRoad(
        cx - math.cos(a) * diag * 0.45,
        cy - math.sin(a) * diag * 0.45,
        a,
        diag * 0.9,
        6,
        1.4,
        const Color(0xFF4A5161),
      );
    }
    for (var i = 0; i < 2; i++) {
      final a = (i == 0 ? theta : perp) + (rnd.nextDouble() - 0.5) * 0.22;
      final cx = (0.3 + rnd.nextDouble() * 0.4) * size.width;
      final cy = (0.3 + rnd.nextDouble() * 0.4) * size.height;
      windingRoad(
        cx - math.cos(a) * diag * 0.6,
        cy - math.sin(a) * diag * 0.6,
        a,
        diag * 1.25,
        7,
        2.3,
        const Color(0xFF595F71),
      );
    }

    // 4. Route: Glow → Casing → Linie → Punkte.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..strokeWidth = 4.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final isLoop =
        coordinates.length >= 2 && (pts.first - pts.last).distance < 6.0;
    void dot(Offset p, Color fill) {
      canvas.drawCircle(p, 3.4, Paint()..color = _land);
      canvas.drawCircle(p, 2.4, Paint()..color = fill);
    }

    if (isLoop) {
      dot(pts.first, accent);
    } else {
      dot(pts.first, const Color(0xFF34D399));
      dot(pts.last, accent);
    }
  }

  List<Offset> _projectRoute(Size size) {
    double minLon = double.infinity, maxLon = -double.infinity;
    double minLat = double.infinity, maxLat = -double.infinity;
    for (final c in coordinates) {
      if (c[0] < minLon) minLon = c[0];
      if (c[0] > maxLon) maxLon = c[0];
      if (c[1] < minLat) minLat = c[1];
      if (c[1] > maxLat) maxLat = c[1];
    }
    final lonRange = (maxLon - minLon).abs();
    final latRange = (maxLat - minLat).abs();
    const padding = 11.0;
    final dw = size.width - padding * 2;
    final dh = size.height - padding * 2;
    final scale = math.min(
      lonRange > 0 ? dw / lonRange : 1.0,
      latRange > 0 ? dh / latRange : 1.0,
    );
    final ox = padding + (dw - lonRange * scale) / 2;
    final oy = padding + (dh - latRange * scale) / 2;
    return coordinates
        .map(
          (c) => Offset(
            ox + (c[0] - minLon) * scale,
            oy + (maxLat - c[1]) * scale,
          ),
        )
        .toList();
  }

  List<Offset> _genericRoute(Size size, math.Random rnd) {
    const padding = 14.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    const n = 5;
    return List.generate(n, (i) {
      final t = i / (n - 1);
      return Offset(
        padding + t * w,
        padding + (0.2 + rnd.nextDouble() * 0.6) * h,
      );
    });
  }

  @override
  bool shouldRepaint(covariant _RouteMiniMapPainter old) =>
      old.seed != seed ||
      old.coordinates != coordinates ||
      old.accent != accent;
}
