import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/badge_stufen_stil.dart';
import 'package:cruise_connect/presentation/widgets/badge_uebersicht_panel.dart';
import 'package:cruise_connect/presentation/widgets/profile_badge_showcase.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';
import 'package:cruise_connect/presentation/pages/alle_fahrten_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/domain/models/user_level.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';

const List<String> _weekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const List<String> _monthLabelsShort = [
  'J',
  'F',
  'M',
  'A',
  'M',
  'J',
  'J',
  'A',
  'S',
  'O',
  'N',
  'D',
];
const List<String> _monthLabelsLong = [
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

class _AnalyticsBucket {
  const _AnalyticsBucket({
    required this.start,
    required this.label,
    this.distanceKm = 0,
    this.durationSeconds = 0,
    this.xp = 0,
    this.routes = 0,
  });

  final DateTime start;
  final String label;
  final double distanceKm;
  final double durationSeconds;
  final double xp;
  final int routes;

  bool get hasData =>
      routes > 0 || distanceKm > 0.05 || durationSeconds > 0 || xp > 0;

  _AnalyticsBucket add({
    required double distanceKm,
    required double durationSeconds,
    required double xp,
    required int routes,
  }) {
    return _AnalyticsBucket(
      start: start,
      label: label,
      distanceKm: this.distanceKm + distanceKm,
      durationSeconds: this.durationSeconds + durationSeconds,
      xp: this.xp + xp,
      routes: this.routes + routes,
    );
  }
}

enum _LeaderboardPeriod { allTime, month, week }

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.userId,
    required this.rank,
    required this.distanceKm,
    required this.routeCount,
    this.username,
    this.avatarUrl,
  });

  final String userId;
  final int rank;
  final double distanceKm;
  final int routeCount;
  final String? username;
  final String? avatarUrl;

  String get displayName {
    final clean = username?.trim();
    return clean == null || clean.isEmpty ? 'Cruiser' : clean;
  }
}

/// 2026-08-24 (Aufgabe 2.2). Vucko wörtlich: „dass man auch wirklich bei der
/// Analytics-Page dann gruppieren kann: Autos, Motorräder oder alle."
///
/// Die drei Werte gehen zeichengleich als `p_vehicle_type` an die beiden
/// RPCs `get_brand_overview` und `get_brand_members` (Migration
/// 20260824101000). Die Datenbank kennt genau `car`, `motorcycle` und `all`;
/// alles andere behandelt sie als `all`.
enum _FahrzeugFilter {
  autos('car', 'Autos'),
  motorraeder('motorcycle', 'Motorräder'),
  alle('all', 'Alle');

  const _FahrzeugFilter(this.rpcWert, this.beschriftung);

  final String rpcWert;
  final String beschriftung;
}

/// Eine Zeile der Marken-Übersicht, so wie `get_brand_overview` sie liefert.
class _MarkenEintrag {
  const _MarkenEintrag({
    required this.marke,
    required this.personen,
    required this.fahrzeuge,
    required this.ausGarage,
    required this.ausProfil,
  });

  final String marke;
  final int personen;
  final int fahrzeuge;

  /// Woher die Zeilen kommen. `profiles.car_brand` ist Freitext und zählt
  /// serverseitig nur für Personen ohne jede Garagen-Zeile; sichtbar ist
  /// diese Ebene nur im Filter „Alle", weil ihr die Fahrzeugart fehlt.
  final int ausGarage;
  final int ausProfil;
}

/// Eine Person im Drilldown, so wie `get_brand_members` sie liefert.
class _MarkenPerson {
  const _MarkenPerson({
    required this.userId,
    required this.marke,
    this.username,
    this.avatarUrl,
    this.modell,
    this.fahrzeugArt,
    this.quelle,
  });

  final String userId;
  final String marke;
  final String? username;
  final String? avatarUrl;
  final String? modell;
  final String? fahrzeugArt;
  final String? quelle;

  String get anzeigeName {
    final sauber = username?.trim();
    return sauber == null || sauber.isEmpty ? 'Cruiser' : sauber;
  }

  /// Vuckos Bild vom Ergebnis: „die und die Person hat den BMW, die und die
  /// Person hat jetzt einen Skoda". Also Marke UND Fahrzeug, nicht nur ein
  /// Name. Ohne Modell bleibt die Marke allein stehen.
  String get fahrzeugZeile {
    final m = modell?.trim();
    return m == null || m.isEmpty ? marke : '$marke $m';
  }
}

class AnalyticsPage extends StatefulWidget {
  final int refreshKey;
  const AnalyticsPage({super.key, this.refreshKey = 0});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  @override
  void didUpdateWidget(AnalyticsPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshKey != old.refreshKey && widget.refreshKey > 0) {
      _loadData();
    }
  }

  late TabController _tabController;
  bool _loading = true;

  int _totalRoutes = 0;
  double _totalDistanceKm = 0;
  double _totalHours = 0;
  int _totalXp = 0;
  UserLevel _level = UserLevel.fromXp(0);
  List<app.Badge> _earnedBadges = [];
  // 2026-08-15: fuer den Badge-Fortschritt (274 von 1000 km).
  GamificationResult? _gamResult;
  List<UserDriveSession> _driveSessions = [];
  List<_LeaderboardEntry> _leaderboardAllTime = const [];
  List<_LeaderboardEntry> _leaderboardWeek = const [];
  List<_LeaderboardEntry> _leaderboardMonth = const [];
  _LeaderboardPeriod _leaderboardPeriod = _LeaderboardPeriod.allTime;

  // ── Aufgabe 2.2: Marken-Übersicht mit Drilldown ────────────────────────
  // Der Filter gilt für BEIDE Ansichten, auch nach dem Drilldown: er steht
  // im State der Seite, nicht in der jeweiligen Ansicht. Start ist „Alle",
  // damit die Seite beim ersten Öffnen nichts wegblendet.
  _FahrzeugFilter _fahrzeugFilter = _FahrzeugFilter.alle;
  final Map<_FahrzeugFilter, List<_MarkenEintrag>> _markenCache = {};
  bool _markenLaedt = false;
  String? _markenFehler;

  /// Gesetzt = Drilldown offen. Der Wert ist die kanonische Marke aus der
  /// Übersicht; die RPC nimmt aber jede Schreibweise entgegen.
  String? _offeneMarke;
  List<_MarkenPerson> _markenPersonen = const [];
  bool _personenLaden = false;

  List<_AnalyticsBucket> _weeklyBuckets = List.generate(
    7,
    (i) => _AnalyticsBucket(
      start: DateTime(1970, 1, 5 + i),
      label: _weekdayLabels[i],
    ),
  );
  List<_AnalyticsBucket> _monthlyBuckets = const [];
  int _selectedWeekIndex = DateTime.now().weekday - 1;
  int _selectedMonthIndex = 11;

  // Streak
  int _streakDays = 0;

  // Wochendaten (neu)
  double _weeklyTotalKm = 0;
  double _weeklyTotalXp = 0;
  int _weeklyRouteCount = 0;
  double _weeklyTotalTime = 0; // Sekunden
  double _lastWeekTotalKm = 0;
  double _lastWeekTotalXp = 0;
  double _lastWeekTotalTime = 0; // Sekunden
  @override
  void initState() {
    super.initState();
    // 2026-08-24 (Aufgabe 2.2): sechster Reiter „Marken".
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() {});
        // 2026-08-24 (Aufgabe 2.2): Die Marken holen wir erst, wenn der
        // Reiter wirklich aufgeht. Die Seite ist Reiter 3 der normalen
        // Navigation und wird bei jedem Start gebaut; zwei zusätzliche RPCs
        // im Startpfad wären für alle teuer und für die meisten unnötig.
        if (_tabController.index == 5) unawaited(_ladeMarken());
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 2026-06-24 (vucko): Session-Cache der Analytics-Daten. Beim erneuten Öffnen
  // der Seite werden die letzten Daten SOFORT gezeigt (kein Skelett, kein voller
  // Reload); nur wenn der Cache älter als _cacheStaleAfter ist, wird im
  // Hintergrund still aktualisiert. So lädt die Seite gefühlt sofort und hämmert
  // nicht bei jedem Tab-Wechsel das Netz.
  static _AnalyticsCache? _cache;
  static const Duration _cacheStaleAfter = Duration(seconds: 45);

  Future<void> _loadData() async {
    final cache = _cache;
    if (cache != null) {
      // Sofort aus dem Cache rendern — kein Skelett, kein Reload-Flackern.
      _applyResults(cache.gam, cache.sessions, cache.leaderboards);
      final age = DateTime.now().difference(cache.at);
      if (age < _cacheStaleAfter) return; // frisch genug → gar kein Netz
      unawaited(_fetchAndApply(silent: true)); // still im Hintergrund frischen
      return;
    }
    // Erster Aufruf (kein Cache) → Skelett zeigen + laden.
    setState(() => _loading = true);
    await _fetchAndApply(silent: false);
  }

  /// Holt die 3 Datenquellen, aktualisiert den Cache und wendet sie an. [silent]
  /// = ohne Skelett (Hintergrund-Refresh / Pull-to-Refresh).
  Future<void> _fetchAndApply({required bool silent}) async {
    try {
      final results = await Future.wait<Object>([
        GamificationService.calculateAndSync(),
        GamificationService.getDriveSessions(),
        _loadLeaderboards(),
      ]);
      final gamResult = results[0] as GamificationResult;
      // 2026-08-26 (vucko, Aufgabe 7): Genau HIER ist seine 1000-Kilometer-
      // Marke untergegangen. Bei Fahrtende standen erst 992 km, das Abzeichen
      // war noch nicht faellig; beim Oeffnen dieser Seite lief der naechste
      // Abgleich mit 1007 km, schaltete es frei — und die Auswertung kannte
      // keine Feier. Danach galt es als „schon vorhanden" und war fuer immer
      // stumm vergeben.
      if (mounted) unawaited(zeigeOffeneAuszeichnungen(context));
      final driveSessions = results[1] as List<UserDriveSession>;
      final leaderboards =
          results[2] as Map<_LeaderboardPeriod, List<_LeaderboardEntry>>;
      driveSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _cache = _AnalyticsCache(
        gam: gamResult,
        sessions: driveSessions,
        leaderboards: leaderboards,
        at: DateTime.now(),
      );
      _applyResults(gamResult, driveSessions, leaderboards);
      // 2026-08-24 (Aufgabe 2.2): Zieht jemand die Seite herunter, sollen
      // auch die Marken frisch sein.
      // Ist der Reiter gerade offen, bleibt die alte Liste stehen, während
      // im Hintergrund neu geholt wird — sonst blitzt bei jedem stillen
      // Auffrischen ein Skelett auf, obwohl schon Daten da sind. Ist er
      // zu, reicht das Leeren; geholt wird beim nächsten Öffnen.
      if (mounted && _tabController.index == 5) {
        _markenCache.removeWhere((filter, _) => filter != _fahrzeugFilter);
        unawaited(_ladeMarken(erzwingen: true));
      } else {
        _markenCache.clear();
      }
    } catch (e) {
      debugPrint('[Analytics] Daten laden fehlgeschlagen: $e');
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _applyResults(
    GamificationResult gamResult,
    List<UserDriveSession> driveSessions,
    Map<_LeaderboardPeriod, List<_LeaderboardEntry>> leaderboards,
  ) {
    if (!mounted) return;
    {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      final nextWeekStart = weekStart.add(const Duration(days: 7));
      final weekBuckets = List<_AnalyticsBucket>.generate(
        7,
        (i) => _AnalyticsBucket(
          start: weekStart.add(Duration(days: i)),
          label: _weekdayLabels[i],
        ),
      );

      // Monats-/Jahresberechnung
      final rollingMonthStart = DateTime(now.year, now.month - 11);
      final nextMonthStart = DateTime(now.year, now.month + 1);
      final monthBuckets = List<_AnalyticsBucket>.generate(12, (i) {
        final start = DateTime(
          rollingMonthStart.year,
          rollingMonthStart.month + i,
        );
        return _AnalyticsBucket(
          start: start,
          label: _monthLabelsShort[start.month - 1],
        );
      });

      // Neue Tracking-Variablen
      double weeklyTotalTime = 0, lastWeekTotalTime = 0;
      double lastWeekKm = 0, lastWeekXp = 0;
      int weekRouteCount = 0;
      final lastWeekStart = weekStart.subtract(const Duration(days: 7));

      for (final session in driveSessions) {
        final createdAt = session.createdAt.toLocal();
        final routeDay = DateTime(
          createdAt.year,
          createdAt.month,
          createdAt.day,
        );
        final actualDistanceKm = session.distanceKm;
        final routeDuration = session.durationSeconds.toDouble();
        final routeXp = session.xpAwarded.toDouble();

        // Wöchentliche Daten
        if (!routeDay.isBefore(weekStart) && routeDay.isBefore(nextWeekStart)) {
          final dayIndex = createdAt.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) {
            weekBuckets[dayIndex] = weekBuckets[dayIndex].add(
              distanceKm: actualDistanceKm,
              durationSeconds: routeDuration,
              xp: routeXp.toDouble(),
              routes: 1,
            );
          }
          weekRouteCount++;
          weeklyTotalTime += routeDuration;
        } else if (!routeDay.isBefore(lastWeekStart) &&
            routeDay.isBefore(weekStart)) {
          lastWeekKm += actualDistanceKm;
          lastWeekXp += routeXp;
          lastWeekTotalTime += routeDuration;
        }

        // Monatsdaten
        if (!createdAt.isBefore(rollingMonthStart) &&
            createdAt.isBefore(nextMonthStart)) {
          final monthIndex =
              (createdAt.year - rollingMonthStart.year) * 12 +
              createdAt.month -
              rollingMonthStart.month;
          if (monthIndex >= 0 && monthIndex < monthBuckets.length) {
            monthBuckets[monthIndex] = monthBuckets[monthIndex].add(
              distanceKm: actualDistanceKm,
              durationSeconds: routeDuration,
              xp: routeXp.toDouble(),
              routes: 1,
            );
          }
        }
      }

      // 2026-08-19 (vucko): „wenn man eine Streak hat und einen Tag vergisst,
      // das man die moeglichkeit hat die streak wieder zu entfachen"
      //
      // Hier stand eine ZWEITE, abgeschriebene Streak-Schleife. Sie hatte den
      // Filter `distance_km > 0` nicht, den der Dienst hat: eine 0-km-Zeile
      // (abgebrochene Fahrt) hielt die Serie in der Auswertung am Leben,
      // waehrend Startseite und Gutschrift sie schon gerissen sahen. Zwei
      // Wahrheiten fuer dieselbe Zahl. Jetzt rechnet nur noch der Dienst —
      // inklusive der neuen Schonfrist.
      final streak = GamificationService.calculateDrivingStreakDays(
        driveSessions,
        now: now,
      );

      if (mounted) {
        setState(() {
          _totalRoutes = gamResult.totalRoutes;
          _totalDistanceKm = gamResult.totalDistanceKm;
          _totalHours = gamResult.totalHours;
          _totalXp = gamResult.totalXp;
          _level = gamResult.level;
          _earnedBadges = gamResult.earnedBadges;
          _gamResult = gamResult;
          _driveSessions = driveSessions;
          _leaderboardAllTime =
              leaderboards[_LeaderboardPeriod.allTime] ?? const [];
          _leaderboardWeek = leaderboards[_LeaderboardPeriod.week] ?? const [];
          _leaderboardMonth =
              leaderboards[_LeaderboardPeriod.month] ?? const [];
          _weeklyBuckets = weekBuckets;
          _streakDays = streak;
          _monthlyBuckets = monthBuckets;
          _selectedWeekIndex = _selectedWeekIndex.clamp(0, 6).toInt();
          _selectedMonthIndex = _selectedMonthIndex.clamp(0, 11).toInt();
          _weeklyTotalKm = weekBuckets.fold(
            0.0,
            (total, bucket) => total + bucket.distanceKm,
          );
          _weeklyTotalXp = weekBuckets.fold(
            0.0,
            (total, bucket) => total + bucket.xp,
          );
          _weeklyRouteCount = weekRouteCount;
          _weeklyTotalTime = weeklyTotalTime;
          _lastWeekTotalKm = lastWeekKm;
          _lastWeekTotalXp = lastWeekXp;
          _lastWeekTotalTime = lastWeekTotalTime;
          _loading = false;
        });
      }
    }
  }

  Future<Map<_LeaderboardPeriod, List<_LeaderboardEntry>>>
  _loadLeaderboards() async {
    try {
      final allTimeFuture = _loadLeaderboardForColumn(column: 'all_time_km');
      final monthFuture = _loadLeaderboardForColumn(
        column: 'month_km',
        periodColumn: 'month_start',
        periodStart: _currentMonthStartIso(),
      );
      final weekFuture = _loadLeaderboardForColumn(
        column: 'week_km',
        periodColumn: 'week_start',
        periodStart: _currentWeekStartIso(),
      );
      return {
        _LeaderboardPeriod.allTime: await allTimeFuture,
        _LeaderboardPeriod.month: await monthFuture,
        _LeaderboardPeriod.week: await weekFuture,
      };
    } catch (e) {
      debugPrint('[Analytics] Leaderboard-Rollup nicht verfügbar: $e');
      return {
        _LeaderboardPeriod.allTime: await _loadAllTimeProfileFallback(),
        _LeaderboardPeriod.week: const [],
        _LeaderboardPeriod.month: const [],
      };
    }
  }

  Future<List<_LeaderboardEntry>> _loadLeaderboardForColumn({
    required String column,
    String? periodColumn,
    String? periodStart,
  }) async {
    var query = Supabase.instance.client
        .from('user_distance_leaderboard')
        .select(
          'user_id, all_time_km, week_km, month_km, route_count, '
          'profiles(id, username, avatar_url)',
        );
    if (periodColumn != null && periodStart != null) {
      query = query.eq(periodColumn, periodStart);
    }
    final data = await query.order(column, ascending: false).limit(25);
    return _parseLeaderboardRows(data as List, distanceColumn: column);
  }

  String _currentMonthStartIso() {
    final now = DateTime.now();
    return _dateOnlyIso(DateTime(now.year, now.month));
  }

  String _currentWeekStartIso() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _dateOnlyIso(today.subtract(Duration(days: now.weekday - 1)));
  }

  String _dateOnlyIso(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<List<_LeaderboardEntry>> _loadAllTimeProfileFallback() async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url, total_km, total_routes')
          .order('total_km', ascending: false)
          .limit(25);
      return [
        for (var i = 0; i < (data as List).length; i++)
          _leaderboardEntryFromProfileRow(
            Map<String, dynamic>.from(data[i] as Map),
            i + 1,
          ),
      ].where((entry) => entry.distanceKm > 0.05).toList();
    } catch (e) {
      debugPrint('[Analytics] All-time-Fallback fehlgeschlagen: $e');
      return const [];
    }
  }

  List<_LeaderboardEntry> _parseLeaderboardRows(
    List rows, {
    required String distanceColumn,
  }) {
    final entries = <_LeaderboardEntry>[];
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final profile = map['profiles'] is Map
          ? Map<String, dynamic>.from(map['profiles'] as Map)
          : const <String, dynamic>{};
      final distance = (map[distanceColumn] as num?)?.toDouble() ?? 0;
      if (distance <= 0.05) continue;
      entries.add(
        _LeaderboardEntry(
          userId: (map['user_id'] ?? profile['id']).toString(),
          rank: entries.length + 1,
          distanceKm: distance,
          routeCount: (map['route_count'] as num?)?.toInt() ?? 0,
          username: profile['username'] as String?,
          avatarUrl: profile['avatar_url'] as String?,
        ),
      );
    }
    return entries;
  }

  _LeaderboardEntry _leaderboardEntryFromProfileRow(
    Map<String, dynamic> row,
    int rank,
  ) {
    return _LeaderboardEntry(
      userId: row['id'].toString(),
      rank: rank,
      distanceKm: (row['total_km'] as num?)?.toDouble() ?? 0,
      routeCount: (row['total_routes'] as num?)?.toInt() ?? 0,
      username: row['username'] as String?,
      avatarUrl: row['avatar_url'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: _loading
            // 2026-06-24 (vucko Skeleton-Loading): Skelett von Hero + Tabs statt
            // Kreis-Spinner — die Struktur ist sofort sichtbar.
            ? const _AnalyticsSkeleton()
            : RefreshIndicator(
                onRefresh: () => _fetchAndApply(silent: true),
                color: AppAccentColors.accent,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 10.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 18),
                        _buildAnalyticsHero(),
                        const SizedBox(height: 18),
                        _buildTabSection(),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analytics',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _totalRoutes == 0
                    ? 'Starte deine erste Fahrt und fülle dein Dashboard.'
                    : 'Dein Fahrprofil, Fortschritt und deine besten Momente.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFA0AEC0),
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyticsHero() {
    final nextMultiplier = GamificationService.streakMultiplierForDays(
      _streakDays > 0 ? _streakDays + 1 : 1,
    );
    final progressPercent = (_level.progress * 100).round();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: _showLevelDetailsSheet,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFF202733), Color(0xFF121721)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: AppAccentColors.accent.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLevelProgressBadge(size: 70),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppAccentColors.accent.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Level ${_level.level}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  color: AppAccentColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 2026-06-24 (vucko): Prozent darf nie über die Zeile
                            // hinauslaufen → ellipsis + Flexible teilt mit dem Pill.
                            Flexible(
                              child: Text(
                                '$progressPercent%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _level.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _level.level >= UserLevel.maxLevel
                              ? '$_totalXp XP gesamt · Maximallevel'
                              : '$_totalXp XP gesamt · noch ${_level.xpToNextLevel} XP',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA0AEC0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Icon(
                      Icons.north_east_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: _level.progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.11),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppAccentColors.accent,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildHeroStat(
                      icon: Icons.route_rounded,
                      label: 'Fahrten',
                      value: '$_totalRoutes',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHeroStat(
                      icon: Icons.map_rounded,
                      label: 'Distanz',
                      value: _formatDistanceShort(_totalDistanceKm),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildHeroStat(
                      icon: Icons.timer_rounded,
                      label: 'Fahrzeit',
                      value: _formatDurationShort(_totalHours * 3600),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHeroStat(
                      icon: Icons.bolt_rounded,
                      label: 'XP',
                      value: _formatNumberCompact(_totalXp.toDouble()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E14).withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color:
                            (_streakDays > 0
                                    ? const Color(0xFFFFD166)
                                    : AppAccentColors.accent)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        _streakDays > 0
                            ? Icons.local_fire_department_rounded
                            : Icons.flag_rounded,
                        color: _streakDays > 0
                            ? const Color(0xFFFFD166)
                            : AppAccentColors.accent,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _streakDays > 0
                                ? (_streakDays == 1
                                      ? '1 Tag Streak'
                                      : '$_streakDays Tage Streak')
                                : 'Noch kein aktiver Streak',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _streakDays > 0
                                ? 'Nächste Fahrt bringt ${nextMultiplier.toStringAsFixed(2)}x XP.'
                                : 'Eine Fahrt startet deine Serie.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA0AEC0),
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppAccentColors.primaryGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _streakDays > 0
                            ? '${nextMultiplier.toStringAsFixed(2)}x'
                            : 'Start',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelProgressBadge({required double size}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: _level.progress,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(AppAccentColors.accent),
            ),
          ),
          Container(
            width: size - 13,
            height: size - 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppAccentColors.primaryGradient,
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Center(
              child: Text(
                '${_level.level}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.045)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppAccentColors.accent, size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLevelDetailsSheet() {
    final currentLevelXp = UserLevel.xpForLevel(_level.level).round();
    final nextLevelXp = _level.level >= UserLevel.maxLevel
        ? currentLevelXp
        : UserLevel.xpForLevel(_level.level + 1).round();
    final xpSpan = (nextLevelXp - currentLevelXp).clamp(0, 1 << 31);
    final xpInLevel = (_totalXp - currentLevelXp).clamp(0, xpSpan).toInt();
    final levelProgressLabel = _level.level >= UserLevel.maxLevel
        ? 'Maximallevel'
        : '$xpInLevel / $xpSpan XP in Level ${_level.level}';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final topGap = media.padding.top + 118;
        final bottomGap = media.padding.bottom + 8;
        final maxHeight = media.size.height - topGap - bottomGap;

        return Padding(
          padding: EdgeInsets.fromLTRB(10, topGap, 10, bottomGap),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF171C25),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.38),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    10,
                    18,
                    18 + media.viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Level Fortschritt',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF202733), Color(0xFF111722)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildLevelProgressBadge(size: 76),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _level.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '$_totalXp XP gesamt',
                                        style: const TextStyle(
                                          color: Color(0xFFA0AEC0),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${(_level.progress * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: _level.progress,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppAccentColors.accent,
                                ),
                                minHeight: 9,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              _level.level >= UserLevel.maxLevel
                                  ? levelProgressLabel
                                  : '$levelProgressLabel · noch ${_level.xpToNextLevel} XP bis Level ${_level.level + 1}',
                              style: const TextStyle(
                                color: Color(0xFFA0AEC0),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildLevelDetailMetric(
                              icon: Icons.bolt_rounded,
                              label: 'Gesamt',
                              value: _formatNumberCompact(_totalXp.toDouble()),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildLevelDetailMetric(
                              icon: Icons.flag_rounded,
                              label: 'Nächstes Level',
                              value: _level.level >= UserLevel.maxLevel
                                  ? 'erreicht'
                                  : '${_level.xpToNextLevel} XP',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildLevelDetailMetric(
                              icon: Icons.route_rounded,
                              label: 'Routen',
                              value: '$_totalRoutes',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildLevelDetailMetric(
                              icon: Icons.social_distance_rounded,
                              label: 'Distanz',
                              value: _formatDistanceShort(_totalDistanceKm),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Meilensteine',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildLevelBadgeMilestone(10, 'badge_01'),
                      const SizedBox(height: 8),
                      _buildLevelBadgeMilestone(25, 'badge_03'),
                      const SizedBox(height: 8),
                      _buildLevelBadgeMilestone(50, 'badge_08'),
                      const SizedBox(height: 8),
                      _buildLevelBadgeMilestone(100, 'badge_14'),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0E14).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: const Text(
                          'Abgeschlossene Fahrten, lange Strecken und aktive Streaks bringen am meisten XP.',
                          style: TextStyle(
                            color: Color(0xFFA0AEC0),
                            fontSize: 12,
                            height: 1.3,
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
      },
    );
  }

  Widget _buildLevelDetailMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppAccentColors.accent, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadgeMilestone(int level, String badgeId) {
    final badge = app.Badge.getById(badgeId);
    final earned = _level.level >= level;
    final xpNeeded = earned
        ? 0
        : (UserLevel.xpForLevel(level).round() - _totalXp).clamp(0, 1 << 31);
    final statusLabel = earned
        ? 'Freigeschaltet'
        : xpNeeded == 0
        ? 'Bereit'
        : 'Noch $xpNeeded XP';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: earned
            ? AppAccentColors.accent.withValues(alpha: 0.10)
            : const Color(0xFF0B0E14).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: earned
              ? AppAccentColors.accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: earned
                  ? AppAccentColors.accent.withValues(alpha: 0.13)
                  : Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: badge?.assetPath != null
                  ? Opacity(
                      opacity: earned ? 1 : 0.32,
                      child: Image.asset(
                        badge!.assetPath!,
                        width: 30,
                        height: 30,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Icon(
                      Icons.emoji_events_rounded,
                      color: earned
                          ? const Color(0xFFFFD166)
                          : Colors.white.withValues(alpha: 0.26),
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge?.name ?? 'Level $level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA0AEC0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: earned
                  ? AppAccentColors.accent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  earned ? Icons.check_rounded : Icons.lock_outline_rounded,
                  color: earned ? AppAccentColors.accent : Colors.white38,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'L$level',
                  style: TextStyle(
                    color: earned ? AppAccentColors.accent : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date.toLocal());
    if (diff.inMinutes < 1) return 'Jetzt';
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    if (diff.inDays < 7) return '${diff.inDays} Tage';
    final localDate = date.toLocal();
    return '${localDate.day}.${localDate.month}.';
  }

  Widget _buildTabSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: const Color(0xFF2A303B),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: AppAccentColors.accent.withValues(alpha: 0.22),
              ),
            ),
            indicatorPadding: EdgeInsets.zero,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFA0AEC0),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
            isScrollable: false,
            labelPadding: EdgeInsets.zero,
            tabs: const [
              Tab(icon: Icon(Icons.insights_rounded, size: 17), text: 'Woche'),
              Tab(
                icon: Icon(Icons.calendar_month_rounded, size: 17),
                text: 'Monat',
              ),
              Tab(
                icon: Icon(Icons.leaderboard_rounded, size: 17),
                text: 'Rang',
              ),
              Tab(icon: Icon(Icons.route_rounded, size: 17), text: 'Routen'),
              Tab(
                icon: Icon(Icons.emoji_events_rounded, size: 17),
                text: 'Badges',
              ),
              Tab(
                icon: Icon(Icons.directions_car_filled_rounded, size: 17),
                text: 'Marken',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSelectedTabContent(),
      ],
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildMonthlyTab();
      case 2:
        return _buildLeaderboardTab();
      case 3:
        return _buildRoutesTab();
      case 4:
        return _buildBadgesTab();
      case 5:
      default:
        return _buildMarkenTab();
    }
  }

  Widget _buildOverviewTab() {
    final now = DateTime.now();
    final selectedWeek = _weeklyBuckets[_selectedWeekIndex];
    final kmDelta = _weeklyTotalKm - _lastWeekTotalKm;
    final xpDelta = _weeklyTotalXp - _lastWeekTotalXp;
    final timeDelta = _weeklyTotalTime - _lastWeekTotalTime;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF202733), Color(0xFF151A23)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Diese Woche',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _formatDayTitle(selectedWeek.start),
                style: const TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  value: _formatDistanceShort(_weeklyTotalKm),
                  label: 'Distanz',
                  delta: _formatKpiDelta(kmDelta, suffix: ''),
                  deltaPositive: kmDelta >= 0,
                  deltaZero: kmDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _formatDurationShort(_weeklyTotalTime),
                  label: 'Fahrzeit',
                  delta: _formatTimeDelta(timeDelta),
                  deltaPositive: timeDelta >= 0,
                  deltaZero: timeDelta == 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _weeklyTotalXp.toStringAsFixed(0),
                  label: 'XP',
                  delta: _formatKpiDelta(xpDelta, suffix: ''),
                  deltaPositive: xpDelta >= 0,
                  deltaZero: xpDelta == 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildBucketChart(
                  buckets: _weeklyBuckets,
                  selectedIndex: _selectedWeekIndex,
                  currentIndex: now.weekday - 1,
                  onSelected: _selectWeekBucket,
                  height: 108,
                  monthMode: false,
                ),
              ),
              const SizedBox(width: 14),
              _buildCountPill(
                value: '$_weeklyRouteCount',
                label: _weeklyRouteCount == 1 ? 'Fahrt' : 'Fahrten',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBucketStatsStrip(
            title: _formatDayTitle(selectedWeek.start),
            bucket: selectedWeek,
            accentColor: _selectedWeekIndex == now.weekday - 1
                ? AppAccentColors.accent
                : Colors.white,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _streakDays > 0
                        ? (_streakDays / 7).clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: const Color(0xFF2A2F3A),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _streakDays > 0
                          ? const Color(0xFFFFD166)
                          : AppAccentColors.accent,
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _streakDays > 0
                    ? (_streakDays == 1
                          ? '\u{1F525} 1 Tag Streak'
                          : '\u{1F525} $_streakDays Tage Streak')
                    : 'Kein Streak',
                style: TextStyle(
                  color: _streakDays > 0
                      ? Colors.white
                      : const Color(0xFF8A94A6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Monats-/Jahresübersicht Tab ──────────────────────────────────────

  Widget _buildMonthlyTab() {
    final now = DateTime.now();
    final buckets = _monthlyBuckets.length == 12
        ? _monthlyBuckets
        : _buildEmptyMonthBuckets(now);
    final selectedIndex = _selectedMonthIndex
        .clamp(0, buckets.length - 1)
        .toInt();
    final selectedMonth = buckets[selectedIndex];
    final avgKmPerRoute = selectedMonth.routes > 0
        ? selectedMonth.distanceKm / selectedMonth.routes
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF202733), Color(0xFF151A23)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: AppAccentColors.accent.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatMonthTitle(selectedMonth.start),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${selectedMonth.routes} ${selectedMonth.routes == 1 ? 'Fahrt' : 'Fahrten'}',
                style: const TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  value: _formatDistanceShort(selectedMonth.distanceKm),
                  label: 'Distanz',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _formatDurationShort(selectedMonth.durationSeconds),
                  label: 'Fahrzeit',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard(
                  value: _formatNumberCompact(selectedMonth.xp),
                  label: 'XP',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${selectedMonth.routes} ${selectedMonth.routes == 1 ? 'Fahrt' : 'Fahrten'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                '  \u00b7  ',
                style: TextStyle(color: Color(0xFF8A94A6), fontSize: 13),
              ),
              Text(
                '\u00d8 ${avgKmPerRoute.toStringAsFixed(1)} km/Fahrt',
                style: const TextStyle(color: Color(0xFF8A94A6), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBucketStatsStrip(
            title: _formatMonthTitle(selectedMonth.start),
            bucket: selectedMonth,
            accentColor:
                selectedMonth.start.year == now.year &&
                    selectedMonth.start.month == now.month
                ? AppAccentColors.accent
                : Colors.white,
          ),
          const SizedBox(height: 16),
          _buildBucketChart(
            buckets: buckets,
            selectedIndex: selectedIndex,
            currentIndex: buckets.indexWhere(
              (bucket) =>
                  bucket.start.year == now.year &&
                  bucket.start.month == now.month,
            ),
            onSelected: _selectMonthBucket,
            height: 108,
            monthMode: true,
          ),
        ],
      ),
    );
  }

  List<_AnalyticsBucket> _buildEmptyMonthBuckets(DateTime now) {
    final start = DateTime(now.year, now.month - 11);
    return List<_AnalyticsBucket>.generate(12, (i) {
      final month = DateTime(start.year, start.month + i);
      return _AnalyticsBucket(
        start: month,
        label: _monthLabelsShort[month.month - 1],
      );
    });
  }

  void _selectWeekBucket(int index) {
    final nextIndex = index.clamp(0, _weeklyBuckets.length - 1).toInt();
    if (nextIndex == _selectedWeekIndex) return;
    setState(() => _selectedWeekIndex = nextIndex);
  }

  void _selectMonthBucket(int index) {
    final bucketCount = _monthlyBuckets.length == 12
        ? _monthlyBuckets.length
        : 12;
    final nextIndex = index.clamp(0, bucketCount - 1).toInt();
    if (nextIndex == _selectedMonthIndex) return;
    setState(() => _selectedMonthIndex = nextIndex);
  }

  String _formatDayTitle(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Heute';
    if (day == today.subtract(const Duration(days: 1))) return 'Gestern';
    final label = _weekdayLabels[date.weekday - 1];
    return '$label, ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
  }

  String _formatMonthTitle(DateTime date) {
    return '${_monthLabelsLong[date.month - 1]} ${date.year}';
  }

  Widget _buildBucketChart({
    required List<_AnalyticsBucket> buckets,
    required int selectedIndex,
    required int currentIndex,
    required ValueChanged<int> onSelected,
    required double height,
    required bool monthMode,
  }) {
    if (buckets.isEmpty) return const SizedBox.shrink();

    final maxDistance = buckets.fold(
      0.0,
      (maxValue, bucket) => math.max(maxValue, bucket.distanceKm),
    );
    final maxXp = buckets.fold(
      0.0,
      (maxValue, bucket) => math.max(maxValue, bucket.xp),
    );
    final useXpAsFallback = maxDistance <= 0.05 && maxXp > 0;
    final maxValue = useXpAsFallback ? maxXp : maxDistance;

    return LayoutBuilder(
      builder: (context, constraints) {
        void selectFromX(double dx) {
          if (constraints.maxWidth <= 0) return;
          final segmentWidth = constraints.maxWidth / buckets.length;
          final index = (dx / segmentWidth)
              .floor()
              .clamp(0, buckets.length - 1)
              .toInt();
          onSelected(index);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => selectFromX(details.localPosition.dx),
          onHorizontalDragStart: (details) =>
              selectFromX(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              selectFromX(details.localPosition.dx),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(buckets.length, (i) {
                final bucket = buckets[i];
                final isSelected = i == selectedIndex;
                final isCurrent = i == currentIndex;
                final hasData = bucket.hasData;
                final rawValue = useXpAsFallback
                    ? bucket.xp
                    : bucket.distanceKm;
                final heightFactor = maxValue > 0 && rawValue > 0
                    ? math.max(monthMode ? 0.18 : 0.2, rawValue / maxValue)
                    : 0.045;
                final inactiveColor = const Color(
                  0xFF303746,
                ).withValues(alpha: hasData ? 0.92 : 0.5);
                final neutralGradient = LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: hasData ? 0.9 : 0.2),
                    const Color(
                      0xFF8793A6,
                    ).withValues(alpha: hasData ? 0.78 : 0.22),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                );

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: monthMode ? 2 : 3,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              widthFactor: monthMode ? 0.62 : 0.66,
                              heightFactor: heightFactor.clamp(0.0, 1.0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  gradient: hasData
                                      ? (isCurrent
                                            ? LinearGradient(
                                                colors: [
                                                  AppAccentColors.accent,
                                                  AppAccentColors.accentStrong,
                                                ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              )
                                            : neutralGradient)
                                      : null,
                                  color: hasData ? null : inactiveColor,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isCurrent
                                              ? Colors.white.withValues(
                                                  alpha: 0.78,
                                                )
                                              : const Color(
                                                  0xFFFFD166,
                                                ).withValues(alpha: 0.72))
                                        : Colors.transparent,
                                    width: isSelected ? 1.3 : 0,
                                  ),
                                  boxShadow: isSelected && hasData
                                      ? [
                                          BoxShadow(
                                            color:
                                                (isCurrent
                                                        ? AppAccentColors.accent
                                                        : Colors.white)
                                                    .withValues(alpha: 0.18),
                                            blurRadius: 14,
                                            offset: const Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        SizedBox(
                          height: 18,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                bucket.label,
                                softWrap: false,
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppAccentColors.accent
                                      : isSelected
                                      ? const Color(0xFFFFD166)
                                      : hasData
                                      ? Colors.white70
                                      : const Color(0xFF7B8494),
                                  fontSize: monthMode ? 10 : 11,
                                  fontWeight: isSelected || isCurrent
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCountPill({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBucketStatsStrip({
    required String title,
    required _AnalyticsBucket bucket,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${bucket.routes} ${bucket.routes == 1 ? 'Fahrt' : 'Fahrten'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _buildBucketMetricChip(
                icon: Icons.map_rounded,
                value: _formatDistanceShort(bucket.distanceKm),
              ),
              _buildBucketMetricChip(
                icon: Icons.timer_rounded,
                value: _formatDurationShort(bucket.durationSeconds),
              ),
              _buildBucketMetricChip(
                icon: Icons.bolt_rounded,
                value: _formatNumberCompact(bucket.xp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBucketMetricChip({
    required IconData icon,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFA0AEC0), size: 13),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    final entries = switch (_leaderboardPeriod) {
      _LeaderboardPeriod.allTime => _leaderboardAllTime,
      _LeaderboardPeriod.week => _leaderboardWeek,
      _LeaderboardPeriod.month => _leaderboardMonth,
    };
    final subtitle = switch (_leaderboardPeriod) {
      _LeaderboardPeriod.allTime => 'Meiste Kilometer insgesamt.',
      _LeaderboardPeriod.week => 'Meiste Kilometer seit Montag.',
      _LeaderboardPeriod.month => 'Meiste Kilometer in diesem Monat.',
    };

    return _buildSectionCard(
      title: 'Leaderboard',
      subtitle: subtitle,
      icon: Icons.leaderboard_rounded,
      accentColor: AppAccentColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeaderboardPeriodPicker(),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Text(
                'Noch keine Fahrten in diesem Zeitraum.',
                style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              _buildLeaderboardRow(entries[i]),
              if (i < entries.length - 1) const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }

  Widget _buildLeaderboardPeriodPicker() {
    return Row(
      children: [
        Expanded(
          child: _buildLeaderboardPeriodChip(
            period: _LeaderboardPeriod.allTime,
            label: 'Gesamt',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildLeaderboardPeriodChip(
            period: _LeaderboardPeriod.month,
            label: 'Monat',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildLeaderboardPeriodChip(
            period: _LeaderboardPeriod.week,
            label: 'Woche',
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardPeriodChip({
    required _LeaderboardPeriod period,
    required String label,
  }) {
    final selected = _leaderboardPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _leaderboardPeriod = period),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: selected
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0B0E14).withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppAccentColors.accent.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFA0AEC0),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardRow(_LeaderboardEntry entry) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isMe = entry.userId == currentUserId;
    final medalColor = switch (entry.rank) {
      1 => const Color(0xFFFFD166),
      2 => const Color(0xFFCBD5E1),
      3 => const Color(0xFFD08A5B),
      _ => AppAccentColors.accent,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfilePage(
              userId: entry.userId,
              initialUsername: entry.displayName,
            ),
          ),
        ),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? AppAccentColors.accent.withValues(alpha: 0.11)
                : const Color(0xFF0B0E14).withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isMe
                  ? AppAccentColors.accent.withValues(alpha: 0.32)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: medalColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '#${entry.rank}',
                    style: TextStyle(
                      color: medalColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              UserAvatar(
                name: entry.displayName,
                avatarUrl: entry.avatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${entry.displayName} · du' : entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.routeCount} ${entry.routeCount == 1 ? 'Fahrt' : 'Fahrten'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDistanceShort(entry.distanceKm),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── KPI Card (shared by Week + Month) ──────────────────────────────

  Widget _buildKpiCard({
    required String value,
    required String label,
    String? delta,
    bool deltaPositive = true,
    bool deltaZero = true,
  }) {
    final icon = switch (label) {
      'Distanz' => Icons.map_rounded,
      'Fahrzeit' => Icons.timer_rounded,
      'XP' => Icons.bolt_rounded,
      _ => Icons.insights_rounded,
    };
    final deltaColor = deltaZero
        ? const Color(0xFF8A94A6)
        : deltaPositive
        ? const Color(0xFF4ADE80)
        : AppAccentColors.accent;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppAccentColors.accent, size: 17),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 25,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 7),
            Text(
              delta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: deltaColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Format helpers ─────────────────────────────────────────────────

  String _formatDurationShort(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '${totalMinutes}m';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String _formatDistanceShort(double km) {
    if (km <= 0.05) return '0 km';
    if (km >= 1000) {
      return '${(km / 1000).toStringAsFixed(1).replaceAll('.', ',')}k km';
    }
    if (km >= 100) return '${km.round()} km';
    final rounded = km.roundToDouble();
    if ((km - rounded).abs() < 0.05) return '${rounded.toInt()} km';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  String _formatNumberCompact(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
    }
    return value.round().toString();
  }

  String _formatKpiDelta(double delta, {String suffix = ''}) {
    if (delta == 0) return '\u00b10$suffix';
    final prefix = delta > 0 ? '+' : '';
    return '$prefix${delta.toStringAsFixed(delta.abs() >= 10 ? 0 : 1)}$suffix';
  }

  String _formatTimeDelta(double deltaSeconds) {
    if (deltaSeconds == 0) return '\u00b10:00';
    final prefix = deltaSeconds > 0 ? '+' : '-';
    final abs = deltaSeconds.abs();
    final totalMinutes = (abs / 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '$prefix$h:${m.toString().padLeft(2, '0')}';
  }

  // ── Aufgabe 2.2: Marken-Übersicht mit Drilldown ────────────────────────
  //
  // 2026-08-24. Vucko wörtlich: „dass man auch wirklich in der
  // Analytics-Page die ganzen Marken sieht, wo vertreten sind. Und dann,
  // wenn man draufklickt, die Leute sieht, wo unter diesen Marken sind.
  // [...] die und die Person hat den BMW, die und die Person hat jetzt
  // einen Skoda [...] Und dass man auch wirklich bei der Analytics-Page
  // dann gruppieren kann: Autos, Motorräder oder alle."
  //
  // ENTSCHEIDUNG „eigener Reiter oder Abschnitt in einem bestehenden"
  // (Vucko schläft, keine Rückfrage möglich): eigener sechster Reiter.
  //   * Fünf Reiter sind eng, aber Flutters `Tab` rendert seinen Text mit
  //     `softWrap: false, overflow: fade` — er wird also ausgeblendet, nicht
  //     überlaufend. Auf 360 dp bleiben je Reiter rund 52 dp, „Marken" mit
  //     sechs Zeichen passt.
  //   * Der Alternativplatz wäre der Reiter „Rang" gewesen. Dort stehen bis
  //     zu 25 Ranglistenzeilen; die Marken lägen darunter und wären nur
  //     nach langem Scrollen zu finden. Vucko sagt „wirklich in der
  //     Analytics-Page die ganzen Marken sieht" — das ist eine Forderung
  //     nach Sichtbarkeit, nicht nach Unterbringung.
  //
  // ENTSCHEIDUNG „Drilldown als eigene Seite oder im Reiter": im Reiter.
  // Eine eigene Seite wäre eine neue Datei; parallel arbeiten drei weitere
  // Agenten im Projekt. Wichtiger: der Filter Autos/Motorräder/Alle muss
  // laut Auftrag „auf beide Ansichten, auch nach dem Drilldown" wirken. Im
  // selben Reiter ist er zwangsläufig derselbe Zustand und kann gar nicht
  // auseinanderlaufen.

  /// Holt die Marken-Übersicht für den aktuellen Filter.
  ///
  /// Die Gruppierung macht die Datenbank (`get_brand_overview`, Migration
  /// 20260824101000), nicht der Client. Grund: der Client hat sie bis heute
  /// selbst geraten, und genau daran sind „BMW" und „Bmw" zu zwei Marken
  /// geworden. Gemessen am 24.08. über die RPC: BMW 30 Personen /
  /// 31 Fahrzeuge, Volkswagen 16, Audi 14, Beta 8.
  Future<void> _ladeMarken({bool erzwingen = false}) async {
    final filter = _fahrzeugFilter;
    if (!erzwingen && _markenCache.containsKey(filter)) return;
    if (mounted) {
      setState(() {
        _markenLaedt = true;
        _markenFehler = null;
      });
    }
    try {
      final daten = await Supabase.instance.client.rpc(
        'get_brand_overview',
        params: {'p_vehicle_type': filter.rpcWert},
      );
      final eintraege = <_MarkenEintrag>[
        for (final zeile in (daten as List? ?? const []))
          if (zeile is Map)
            _MarkenEintrag(
              marke: (zeile['brand'] ?? '').toString(),
              personen: (zeile['people'] as num?)?.toInt() ?? 0,
              fahrzeuge: (zeile['vehicles'] as num?)?.toInt() ?? 0,
              ausGarage: (zeile['from_garage'] as num?)?.toInt() ?? 0,
              ausProfil: (zeile['from_profile'] as num?)?.toInt() ?? 0,
            ),
      ].where((e) => e.marke.trim().isNotEmpty).toList();
      _markenCache[filter] = eintraege;
      if (mounted) setState(() => _markenLaedt = false);
    } catch (e) {
      debugPrint('[Analytics] Marken-Übersicht fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          _markenLaedt = false;
          _markenFehler = 'Die Marken konnten gerade nicht geladen werden.';
        });
      }
    }
  }

  /// Holt die Personen einer Marke. `p_brand` darf beliebig geschrieben
  /// sein, die RPC normalisiert selbst.
  Future<void> _ladeMarkenPersonen(String marke) async {
    if (mounted) {
      setState(() {
        _personenLaden = true;
        _markenPersonen = const [];
      });
    }
    try {
      final daten = await Supabase.instance.client.rpc(
        'get_brand_members',
        params: {'p_brand': marke, 'p_vehicle_type': _fahrzeugFilter.rpcWert},
      );
      final personen = <_MarkenPerson>[
        for (final zeile in (daten as List? ?? const []))
          if (zeile is Map)
            _MarkenPerson(
              userId: (zeile['user_id'] ?? '').toString(),
              marke: (zeile['brand'] ?? marke).toString(),
              username: zeile['username'] as String?,
              avatarUrl: zeile['avatar_url'] as String?,
              modell: zeile['model'] as String?,
              fahrzeugArt: zeile['vehicle_type'] as String?,
              quelle: zeile['source'] as String?,
            ),
      ];
      // Garage vor Profil, danach nach Name: die Garagen-Zeilen tragen ein
      // Modell und sind damit die Zeilen, die Vucko sehen will.
      personen.sort((a, b) {
        final qa = a.quelle == 'garage' ? 0 : 1;
        final qb = b.quelle == 'garage' ? 0 : 1;
        if (qa != qb) return qa - qb;
        return a.anzeigeName.toLowerCase().compareTo(
          b.anzeigeName.toLowerCase(),
        );
      });
      if (mounted) {
        setState(() {
          _markenPersonen = personen;
          _personenLaden = false;
        });
      }
    } catch (e) {
      debugPrint('[Analytics] Personen zur Marke fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          _personenLaden = false;
          _markenPersonen = const [];
        });
      }
    }
  }

  void _oeffneMarke(String marke) {
    setState(() => _offeneMarke = marke);
    unawaited(_ladeMarkenPersonen(marke));
  }

  void _schliesseMarke() {
    setState(() {
      _offeneMarke = null;
      _markenPersonen = const [];
    });
  }

  void _setzeFahrzeugFilter(_FahrzeugFilter filter) {
    if (_fahrzeugFilter == filter) return;
    setState(() => _fahrzeugFilter = filter);
    unawaited(_ladeMarken());
    // Der Filter wirkt auch im Drilldown. Steht die offene Marke im neuen
    // Filter gar nicht mehr, bleibt die Personenliste leer und der Text
    // darunter sagt genau das.
    final offen = _offeneMarke;
    if (offen != null) unawaited(_ladeMarkenPersonen(offen));
  }

  Widget _buildMarkenTab() {
    final offen = _offeneMarke;
    final eintraege = _markenCache[_fahrzeugFilter];
    final untertitel = offen == null
        ? switch (_fahrzeugFilter) {
            _FahrzeugFilter.autos => 'Alle Automarken in der Community.',
            _FahrzeugFilter.motorraeder =>
              'Alle Motorradmarken in der Community.',
            _FahrzeugFilter.alle => 'Alle Marken in der Community.',
          }
        : 'Wer fährt einen $offen?';

    return _buildSectionCard(
      title: offen ?? 'Marken',
      subtitle: untertitel,
      icon: offen == null
          ? Icons.directions_car_filled_rounded
          : Icons.group_rounded,
      accentColor: AppAccentColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offen != null) ...[
            _buildMarkenZurueckZeile(),
            const SizedBox(height: 12),
          ],
          _buildFahrzeugFilterPicker(),
          const SizedBox(height: 14),
          if (offen != null)
            _buildMarkenPersonenListe()
          else if (_markenFehler != null)
            _buildMarkenHinweis(_markenFehler!)
          else if (eintraege == null || (_markenLaedt && eintraege.isEmpty))
            const _MarkenSkelett()
          else if (eintraege.isEmpty)
            _buildMarkenHinweis(switch (_fahrzeugFilter) {
              _FahrzeugFilter.autos => 'Noch kein Auto in der Garage.',
              _FahrzeugFilter.motorraeder =>
                'Noch kein Motorrad in der Garage.',
              _FahrzeugFilter.alle => 'Noch kein Fahrzeug eingetragen.',
            })
          else
            for (var i = 0; i < eintraege.length; i++) ...[
              _buildMarkenZeile(eintraege[i]),
              if (i < eintraege.length - 1) const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }

  Widget _buildMarkenZurueckZeile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _schliesseMarke,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: Color(0xFFA0AEC0),
              ),
              SizedBox(width: 6),
              Text(
                'Alle Marken',
                style: TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Drei Zustände als Chip-Reihe, gebaut wie
  /// `_buildLeaderboardPeriodPicker` weiter oben. Reihenfolge wie im
  /// Auftrag: „Autos, Motorräder oder alle".
  Widget _buildFahrzeugFilterPicker() {
    return Row(
      children: [
        for (final filter in _FahrzeugFilter.values) ...[
          if (filter != _FahrzeugFilter.values.first) const SizedBox(width: 8),
          Expanded(child: _buildFahrzeugFilterChip(filter)),
        ],
      ],
    );
  }

  Widget _buildFahrzeugFilterChip(_FahrzeugFilter filter) {
    final gewaehlt = _fahrzeugFilter == filter;
    return GestureDetector(
      onTap: () => _setzeFahrzeugFilter(filter),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: gewaehlt
              ? AppAccentColors.accent.withValues(alpha: 0.18)
              : const Color(0xFF0B0E14).withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: gewaehlt
                ? AppAccentColors.accent.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Center(
          child: Text(
            filter.beschriftung,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: gewaehlt ? Colors.white : const Color(0xFFA0AEC0),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkenHinweis(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
      ),
    );
  }

  Widget _buildMarkenZeile(_MarkenEintrag eintrag) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _oeffneMarke(eintrag.marke),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${eintrag.personen}',
                    style: TextStyle(
                      color: AppAccentColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eintrag.marke,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${eintrag.personen} '
                      '${eintrag.personen == 1 ? 'Person' : 'Personen'} · '
                      '${eintrag.fahrzeuge} '
                      '${eintrag.fahrzeuge == 1 ? 'Fahrzeug' : 'Fahrzeuge'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF8A94A6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarkenPersonenListe() {
    if (_personenLaden) return const _MarkenSkelett();
    if (_markenPersonen.isEmpty) {
      return _buildMarkenHinweis(switch (_fahrzeugFilter) {
        _FahrzeugFilter.autos =>
          'Diese Marke fährt hier niemand als Auto. Stell den Filter auf '
              'Alle.',
        _FahrzeugFilter.motorraeder =>
          'Diese Marke fährt hier niemand als Motorrad. Stell den Filter '
              'auf Alle.',
        _FahrzeugFilter.alle => 'Zu dieser Marke ist niemand eingetragen.',
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _markenPersonen.length; i++) ...[
          _buildMarkenPersonZeile(_markenPersonen[i]),
          if (i < _markenPersonen.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _buildMarkenPersonZeile(_MarkenPerson person) {
    final meineId = Supabase.instance.client.auth.currentUser?.id;
    final binIch = person.userId == meineId;
    final istMotorrad = person.fahrzeugArt == 'motorcycle';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfilePage(
              userId: person.userId,
              initialUsername: person.anzeigeName,
            ),
          ),
        ),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: binIch
                ? AppAccentColors.accent.withValues(alpha: 0.11)
                : const Color(0xFF0B0E14).withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: binIch
                  ? AppAccentColors.accent.withValues(alpha: 0.32)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            children: [
              UserAvatar(
                name: person.anzeigeName,
                avatarUrl: person.avatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      binIch
                          ? '${person.anzeigeName} · du'
                          : person.anzeigeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          istMotorrad
                              ? Icons.two_wheeler_rounded
                              : Icons.directions_car_filled_rounded,
                          size: 13,
                          color: const Color(0xFF8A94A6),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            person.fahrzeugZeile,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA0AEC0),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF8A94A6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String subtitle = '',
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF202733), Color(0xFF151A23)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFA0AEC0),
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildRoutesTab() {
    final recentRoutes = _recentRouteHistory();
    if (recentRoutes.isEmpty) {
      return _buildSectionCard(
        title: 'Letzte Fahrten',
        icon: Icons.route_rounded,
        accentColor: AppAccentColors.accent,
        child: const Text(
          'Deine letzten Fahrten erscheinen hier, sobald du losgefahren bist.',
          style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Letzte Fahrten',
      icon: Icons.route_rounded,
      accentColor: AppAccentColors.accent,
      child: Column(
        children: [
          _buildRoutesOverviewStrip(recentRoutes),
          const SizedBox(height: 14),
          for (var i = 0; i < recentRoutes.length; i++) ...[
            _buildRouteSummaryRow(recentRoutes[i]),
            if (i < recentRoutes.length - 1) const SizedBox(height: 10),
          ],
          // 2026-09-01 (Vucko: nachtraeglich speichern und Fotos hinzufuegen):
          // Die Uebersicht bleibt bewusst bei fuenf Eintraegen — so wollte er
          // sie am 25.06. ausdruecklich haben. Aber alles Aeltere war dadurch
          // gar nicht mehr aufrufbar, und damit auch die Fahrten-Detailseite
          // nicht, auf der man Fotos hinzufuegt und die Strecke speichert.
          // Dieser Weg fuehrt zu allem dahinter.
          if (_driveSessions.length > recentRoutes.length) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlleFahrtenPage(fahrten: _driveSessions),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Alle ${_driveSessions.length} Fahrten ansehen',
                        style: TextStyle(
                          color: AppAccentColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppAccentColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<UserDriveSession> _recentRouteHistory() {
    // 2026-06-25 (vucko): IMMER nur die letzten 5 Fahrten zeigen (vorher: bis zu
    // 10 aus den letzten 7 Tagen). Alles darüber fällt raus → sauberer Überblick.
    final sorted = [..._driveSessions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(5).toList();
  }

  Widget _buildRoutesOverviewStrip(List<UserDriveSession> sessions) {
    final distance = sessions.fold(
      0.0,
      (total, session) => total + session.distanceKm,
    );
    final duration = sessions.fold(
      0.0,
      (total, session) => total + session.durationSeconds,
    );
    final xp = sessions.fold<int>(
      0,
      (total, session) => total + session.xpAwarded,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildRouteOverviewMetric(
              icon: Icons.map_rounded,
              value: _formatDistanceShort(distance),
              label: 'Distanz',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: Colors.white.withValues(alpha: 0.07),
          ),
          Expanded(
            child: _buildRouteOverviewMetric(
              icon: Icons.timer_rounded,
              value: _formatDurationShort(duration),
              label: 'Zeit',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: Colors.white.withValues(alpha: 0.07),
          ),
          Expanded(
            child: _buildRouteOverviewMetric(
              icon: Icons.bolt_rounded,
              value: '$xp',
              label: 'XP',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteOverviewMetric({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppAccentColors.accent, size: 17),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFA0AEC0),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildBadgesTab() {
    final progress = app.Badge.all.isEmpty
        ? 0.0
        : _earnedBadges.length / app.Badge.all.length;

    return _buildSectionCard(
      title: 'Badge Sammlung',
      subtitle:
          '${_earnedBadges.length}/${app.Badge.all.length} freigeschaltet.',
      icon: Icons.emoji_events_rounded,
      accentColor: const Color(0xFFFFD700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBadgeProgressPanel(progress),
          const SizedBox(height: 12),
          // 2026-08-19 (vucko woertlich): „und das man wirklich einen
          // ueberblick hat". Vorher musste man siebzehn Bloecke durchscrollen,
          // um zu sehen, wo man ueberall steht. Jetzt steht das oben: Legende
          // der Stufen, Raster aller Familien, die drei naechsten Ziele.
          BadgeUebersichtPanel(
            erreichteIds: _earnedBadges.map((b) => b.id).toSet(),
            metriken: _badgeMetriken(),
            onBadgeTippen: _oeffneBadge,
          ),
          const SizedBox(height: 16),
          // 2026-08-24 (vucko woertlich): „die stufen badges sollen noch
          // besser angezeigt werden man scrollt da endlos". Der Katalog liegt
          // jetzt in Schubladen, eine je Familie — Begruendung und Messung
          // stehen bei [BadgeKatalogListe].
          BadgeKatalogListe(
            erreichteIds: _earnedBadges.map((b) => b.id).toSet(),
            metriken: _badgeMetriken(),
            kachelBauer: _buildBadgeTile,
            onBadgeTippen: _oeffneBadge,
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeProgressPanel(double progress) {
    final percentage = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Color(0xFFFFD166),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_earnedBadges.length} von ${app.Badge.all.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$percentage%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.09),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFD166),
                    ),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSummaryRow(UserDriveSession session) {
    final Widget card = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111720), Color(0xFF0B0E14)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Icon(
                    session.completedAtEnd
                        ? Icons.flag_rounded
                        : Icons.route_rounded,
                    color: AppAccentColors.accent,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.completedAtEnd
                          ? 'Fahrt abgeschlossen'
                          : 'Fahrt aufgezeichnet',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.05,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          session.completedAtEnd
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: session.completedAtEnd
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFA0AEC0),
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            session.routeStyle?.trim().isNotEmpty == true
                                ? session.routeStyle!
                                : 'Cruise',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA0AEC0),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildRouteMetaPill(
                icon: Icons.schedule_rounded,
                label: _formatDateShort(session.createdAt),
              ),
              _buildRouteMetaPill(
                icon: Icons.map_rounded,
                label: _formatDistanceShort(session.distanceKm),
              ),
              _buildRouteMetaPill(
                icon: Icons.timer_rounded,
                label: _formatDurationShort(session.durationSeconds.toDouble()),
              ),
              _buildRouteMetaPill(
                icon: Icons.bolt_rounded,
                label: '${session.xpAwarded} XP',
              ),
            ],
          ),
        ],
      ),
    );
    // 2026-06-25 (vucko): Zeile ist jetzt klickbar → Strava-artige Detailansicht.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RideDetailPage(session: session)),
        ),
        child: card,
      ),
    );
  }

  Widget _buildRouteMetaPill({
    required IconData icon,
    required String label,
    Color color = const Color(0xFFA0AEC0),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Die Kennzahlen des Nutzers in der Form, die die Badge-Tabelle versteht.
  /// Dieselbe Tabelle entscheidet im GamificationService ueber die
  /// Freischaltung — Anzeige und Vergabe koennen nicht auseinanderlaufen.
  Map<app.BadgeMetrik, double>? _badgeMetriken() {
    final g = _gamResult;
    if (g == null) return null;
    return app.badgeMetriken(
      level: g.level.level,
      totalKm: g.totalDistanceKm,
      totalHours: g.totalHours,
      completedRides: g.completedRides,
      completedGroupRides: g.completedGroupRides,
      routePosts: g.routePosts,
      createdGroups: g.createdGroups,
      savedRoutes: g.savedRoutes,
      longestRideKm: g.longestRideKm,
      fruehFahrten: g.fruehFahrten,
      nachtFahrten: g.nachtFahrten,
      wochenendFahrten: g.wochenendFahrten,
      besteSerieTage: g.besteSerieTage,
      kurvenjagdFahrten: g.kurvenjagdFahrten,
      gefahreneStile: g.gefahreneStile,
      rundkurse: g.rundkurse,
      aNachBFahrten: g.aNachBFahrten,
    );
  }

  app.BadgeFortschritt? _fortschrittFuer(app.Badge badge) {
    final metriken = _badgeMetriken();
    if (metriken == null) return null;
    return app.badgeFortschrittAus(badge.id, metriken);
  }

  Future<void> _oeffneBadge(app.Badge badge) {
    final earned = _earnedBadges.any((b) => b.id == badge.id);
    return ProfileBadgeShowcase.showBadgeDetails(
      context,
      badge,
      freigeschaltet: earned,
      fortschritt: earned ? null : _fortschrittFuer(badge),
    );
  }

  /// 2026-08-25 (vucko woertlich): „nicht untereinander sondern schon
  /// nebeneinander und das es noch besser aussieht".
  ///
  /// WAS SICH GEAENDERT HAT UND WARUM:
  ///
  /// 1. GROESSE FOLGT DER BREITE. Die Kachel war fest 138 Punkte hoch, egal
  ///    ob sie 191 oder 95 Punkte breit war. Mit drei Spalten auf einem
  ///    schmalen Telefon fuellte das 52 Punkte grosse Emblem die Kachel fast
  ///    randlos und der Name wurde zur Restflaeche. Emblem, Innenabstand und
  ///    Schriftgrad kommen jetzt aus [badgeKachelMasse] — fuer alle Kacheln
  ///    der Seite dieselben Werte, also eine durchgehende Rasterkante.
  ///
  /// 2. EIN GEZEICHNETES ABZEICHEN STATT ZWEI. In der linken oberen Ecke sass
  ///    eine [BadgeStufenMarke]: die Silhouette der Stufe mit Fuellung, Rand,
  ///    Symbol und Ziffer — also GENAU dieselbe Form und Farbe, die zwei
  ///    Zentimeter darunter das Emblem noch einmal zeichnet. Bei 191 Punkten
  ///    Breite fiel das kaum auf, bei 118 sind es zwei gleiche Silhouetten in
  ///    einer Kachel. Die Ecke traegt jetzt nur noch, was das Emblem NICHT
  ///    sagt: das Stufensymbol und die roemische Ziffer, ohne zweiten Rahmen.
  ///    Die drei Merkmale aus `badge_stufen_stil.dart` bleiben damit
  ///    vollstaendig — Form und Farbe im Emblem, Symbol und Ziffer in der
  ///    Ecke; nur die Dopplung faellt weg.
  ///
  /// 3. DIE UNTERZEILE WIRD KUERZER STATT ABGESCHNITTEN. Freigeschaltet stand
  ///    dort „Stufe III · Violett" — bei 118 Punkten Breite bleibt davon
  ///    „Stufe III · V…". Die Ziffer steht jetzt oben in der Ecke, unten
  ///    reicht der Farbname. Gesperrt stand der volle Familienname
  ///    („Abgeschlossene Fahrten"); dafuer gibt es [badgeKurzTitel], das
  ///    genau aus diesem Grund schon existiert.
  ///
  /// Zeile 1 der Kachel ist die Kopfzeile (Stufe links, Zustand rechts),
  /// darunter mittig Emblem, Name und Unterzeile. Alle drei Textfelder haben
  /// eine feste Hoehe, damit die Namen aller Kacheln einer Reihe auf
  /// derselben Grundlinie sitzen.
  Widget _buildBadgeTile(app.Badge badge, BadgeKachelMasse masse) {
    final earned = _earnedBadges.any((b) => b.id == badge.id);
    // 2026-08-19 (vucko woertlich): „schau das sie andere Farben andere Formen
    // andere Symbole haben ... das die niedrigste Stufe Bronze / Rot ist, die
    // beste lila oder blau ist". Die Kachel folgt jetzt der Stufen-Skala.
    // Stufenlose Meilensteine (Gruendungszeit, 1.000 km) behalten ihre
    // Kategorie-Farbe, sonst haetten sie faelschlich einen Rang.
    final stil = badgeStufenStil(badge.stufe);
    final accent = badge.stufe > 0 ? stil.farbe : _badgeAccentColor(badge);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        // 2026-08-25: Der Grund traegt die Stufenfarbe nur noch als Hauch,
        // und beide Enden des Verlaufs sind DECKEND.
        //
        // GEMESSEN am gerenderten Bild, nicht gerechnet: Der Verlauf lief
        // vorher von einer durchscheinenden Leitfarbe (Deckkraft 0,20) zu
        // einem deckenden Dunkel. Flutter blendet zwischen den beiden Enden
        // auch die DECKKRAFT ueber — auf halber Strecke, also genau dort, wo
        // das Emblem sitzt, lag sie bei rund 0,5 statt bei 0,2. Der Grund
        // hinter dem Emblem war damit viel kraeftiger als die 0,20 vermuten
        // lassen, und zwar in DERSELBEN Farbe wie das Emblem.
        //
        // Gemessener Kontrast des Emblem-Randes gegen den Grund, an dem er
        // liegt (Bronze / Tuerkis / Violett):
        //   vorher  3,29 : 1   5,42 : 1   4,15 : 1
        //   jetzt   4,21 : 1   9,12 : 1   6,14 : 1
        // Bronze lag vorher knapp ueber den 3 : 1, die fuer grafische
        // Elemente die Untergrenze sind — bei einer Kachel, die von 191 auf
        // 118 Punkte geschrumpft ist, war das zu wenig.
        //
        // Verloren geht dabei nichts: freigeschaltet bleibt an sechs Stellen
        // erkennbar — gefuelltes Emblem, Rand in der Leitfarbe, Ziffer,
        // Haken, weisser Name und farbige Unterzeile.
        gradient: earned
            ? LinearGradient(
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: 0.18),
                    const Color(0xFF0B0E14),
                  ),
                  const Color(0xFF0D1118),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF11151C), Color(0xFF0A0D12)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        // 14 statt 18: die Kachel ist nur noch rund 118 statt 191 Punkte
        // breit, ein 18er Radius laesst sie dabei wie eine Pille wirken.
        // 14 ist derselbe Radius wie der der Schublade, in der sie liegt.
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: badgeKachelRand,
          color: earned
              ? accent.withValues(alpha: 0.48)
              : Colors.white.withValues(alpha: 0.045),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(masse.polster, 8, masse.polster, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 14,
              child: Row(
                children: [
                  // Stufensymbol und Ziffer, ohne zweiten Rahmen.
                  Icon(
                    stil.symbol,
                    size: 12,
                    color: stil.farbeHell.withValues(
                      alpha: earned ? 0.95 : 0.32,
                    ),
                  ),
                  if (stil.ziffer.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Text(
                      stil.ziffer,
                      style: TextStyle(
                        color: stil.farbeHell.withValues(
                          alpha: earned ? 0.95 : 0.32,
                        ),
                        fontSize: 9.5,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    earned ? Icons.check_circle_rounded : Icons.lock_rounded,
                    color: earned
                        ? accent
                        : Colors.white.withValues(alpha: 0.2),
                    size: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 2026-08-19 (vucko): „andere Formen" — Kreis fuer Stufe I,
            // Sechseck fuer II, Zackenkranz fuer III. Gezeichnet, nicht
            // als Bild: zwanzig weitere PNG waeren nach den gemessenen
            // 31 MB der bestehenden Serie rund 20 MB obendrauf gewesen.
            // Das vorhandene Familien-Emblem bleibt als Bild im Inneren.
            Center(
              child: BadgeStufenEmblem(
                stufe: badge.stufe,
                groesse: masse.emblem,
                freigeschaltet: earned,
                child: badge.assetPath != null
                    ? Opacity(
                        opacity: earned ? 1 : 0.26,
                        child: Image.asset(
                          badge.assetPath!,
                          width: masse.emblem * 0.65,
                          height: masse.emblem * 0.65,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Text(
                        badge.emoji,
                        style: TextStyle(
                          fontSize: masse.emblem * 0.42,
                          color: earned
                              ? null
                              : Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: masse.namenHoehe,
              child: Center(
                child: Text(
                  badge.name,
                  style: TextStyle(
                    color: earned
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.34),
                    fontSize: masse.namenGroesse,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 13,
              child: Center(
                child: Text(
                  _kachelUnterzeile(badge, stil, earned),
                  style: TextStyle(
                    color: earned
                        ? accent
                        : Colors.white.withValues(alpha: 0.24),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Die Unterzeile der Kachel: freigeschaltet der Name der Stufe, gesperrt
  /// die Familie — beide bewusst kurz, siehe [_buildBadgeTile].
  String _kachelUnterzeile(app.Badge badge, BadgeStufenStil stil, bool earned) {
    if (earned) return badge.stufe > 0 ? stil.name : 'Freigeschaltet';
    if (badge.familie == null) return badge.category;
    final familie = app.badgeFamilieVon(badge.familie!);
    return familie == null ? badge.category : badgeKurzTitel(familie.titel);
  }

  Color _badgeAccentColor(app.Badge badge) {
    return switch (badge.category) {
      'level' => AppAccentColors.accent,
      'routes' => const Color(0xFFFFB86B),
      'groups' => const Color(0xFF4ADE80),
      'social' => const Color(0xFFB06CFF),
      'distance' => const Color(0xFF38D5FF),
      'saved' => const Color(0xFFFFD166),
      _ => const Color(0xFFFFD166),
    };
  }
}

/// 2026-06-24 (vucko Skeleton-Loading): Lade-Skelett der Analytics-Seite —
/// spiegelt Header, Hero-Karte (Level-Ring + Stat-Grid + Streak) und die Tabs.
/// 2026-08-24 (Aufgabe 2.2): Skelett für die Marken-Übersicht und den
/// Drilldown. Regel aus dem Projekt: nie ein Kreis-Spinner, immer die
/// Struktur der echten Liste.
class _MarkenSkelett extends StatelessWidget {
  const _MarkenSkelett();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14171E),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  SkeletonCircle(size: 34),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 110, height: 13),
                        SizedBox(height: 6),
                        SkeletonBox(width: 150, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < 4) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  Widget _statTile() => Expanded(
    child: Container(
      height: 64,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF14171E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          SkeletonCircle(size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox(width: 50, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 36, height: 10),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const SkeletonBox(width: 190, height: 32),
            const SizedBox(height: 10),
            const SkeletonBox(width: double.infinity, height: 14),
            const SizedBox(height: 18),
            // Hero-Karte
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1F26),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      SkeletonCircle(size: 70),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 110, height: 16),
                            SizedBox(height: 10),
                            SkeletonBox(width: 200, height: 24),
                            SizedBox(height: 8),
                            SkeletonBox(width: 150, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SkeletonBox(
                    width: double.infinity,
                    height: 8,
                    radius: 999,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _statTile(),
                      const SizedBox(width: 10),
                      _statTile(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statTile(),
                      const SizedBox(width: 10),
                      _statTile(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SkeletonBox(
                    width: double.infinity,
                    height: 60,
                    radius: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Tab-Bar
            const SkeletonBox(width: double.infinity, height: 44, radius: 14),
            const SizedBox(height: 16),
            // Tab-Inhalt
            const Row(
              children: [
                Expanded(child: SkeletonBox(height: 80, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 80, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 80, radius: 16)),
              ],
            ),
            const SizedBox(height: 12),
            const SkeletonBox(width: double.infinity, height: 140, radius: 16),
          ],
        ),
      ),
    );
  }
}

/// 2026-06-24 (vucko): In-Memory-Cache der Analytics-Daten für die App-Session.
/// Lässt die Seite beim erneuten Öffnen sofort die letzten Daten zeigen, statt
/// jedes Mal Skelett + voller Netz-Reload.
class _AnalyticsCache {
  _AnalyticsCache({
    required this.gam,
    required this.sessions,
    required this.leaderboards,
    required this.at,
  });

  final GamificationResult gam;
  final List<UserDriveSession> sessions;
  final Map<_LeaderboardPeriod, List<_LeaderboardEntry>> leaderboards;
  final DateTime at;
}

// ---------------------------------------------------------------------------
// Der Katalog unter der Uebersicht — gegen das endlose Scrollen
// ---------------------------------------------------------------------------

/// 2026-08-24 (vucko woertlich): „die stufen badges sollen noch besser
/// angezeigt werden man scrollt da endlos".
///
/// GEMESSEN (Test `test/presentation/badge_katalog_schubladen_test.dart`, bei
/// 390 Punkten Breite — ein uebliches Telefon): der Katalog stand mit ALLEN
/// Kacheln untereinander, am 24.08. sind das 68 Kacheln zu je 138 Punkten in
/// 22 Bloecken. Das ergab 11.007 Punkte. Ein Telefon zeigt rund 700 davon auf
/// einmal: SECHZEHN volle Bildschirme, allein unterhalb der Uebersicht. Genau
/// das meinte „endlos". Mit den Schubladen sind es im Auslieferungszustand
/// 1.767 Punkte, also gut zweieinhalb Bildschirme — und die waechst nur noch
/// mit der Zahl der FAMILIEN (eine Zeile je Familie), nicht mehr mit der Zahl
/// der Abzeichen. Der Test rechnet diese Schranke mit und faellt, wenn wieder
/// Kacheln in zugeklappten Schubladen landen.
///
/// WARUM HIER NICHT DIESELBE EINTEILUNG WIE OBEN:
/// [badgeFamilienGruppen] teilt den Katalog nach Zustand („In Arbeit",
/// „Geschafft", „Noch nicht begonnen"). Oben im Uebersichts-Panel ist das
/// richtig, dort lautet die Frage „wo stehe ich". Hier unten lautet sie „was
/// gibt es ueberhaupt", und dafuer taugt der Zustand nicht:
///   - Die drei Ueberschriften stuenden zweimal auf derselben Seite, keine
///     zwei Bildschirme voneinander entfernt.
///   - Die Reihenfolge einer SAMMLUNG darf sich nicht bewegen. Wer weiss, wo
///     „Kilometer" liegt, soll es nach der naechsten Fahrt dort wiederfinden.
///     Nach Zustand sortiert wandert eine Familie beim Freischalten weg.
/// Der Katalog behaelt deshalb seine feste Reihenfolge
/// ([Badge.familienReihenfolge]); zur Schublade wird jede FAMILIE einzeln.
/// Wiederverwendet wird aus dem Panel, was hier wirklich passt:
/// [badgeFamilieFertig] und [badgeZielBadge] — damit „fertig" oben und unten
/// dasselbe heisst.
///
/// ES VERSCHWINDET NICHTS: Jede Familie behaelt ihre Kopfzeile mit Stufenpfad
/// und Stand, bleibt also sichtbar; ein Tipp oeffnet ihre Kacheln, und „Alle
/// aufklappen" stellt mit einem Tipp wieder den vollen Katalog her.
///
/// ES WIRD AUCH NICHTS LEER: Eine Schublade steht immer offen — die Familie,
/// der man am naechsten ist ([vorgabeOffen]). Beim Hinscrollen sieht man also
/// sofort echte Kacheln und nicht nur eine Liste von Zeilen.
///
/// KEINE DOPPLUNG MIT „Als Naechstes": Der Fortschrittsbalken einer Familie
/// steht nur in der OFFENEN Schublade. Zugeklappt traegt die Kopfzeile nur
/// Stufenpfad und Zaehler — die Zahlen zum naechsten Ziel stehen oben.
///
/// Oeffentlich, damit der Test die Hoehe messen kann, ohne die ganze Seite
/// (und damit Supabase) hochzufahren.
class BadgeKatalogListe extends StatefulWidget {
  const BadgeKatalogListe({
    super.key,
    required this.erreichteIds,
    required this.metriken,
    required this.kachelBauer,
    this.onBadgeTippen,
  });

  final Set<String> erreichteIds;

  /// null = die Kennzahlen sind noch nicht geladen. Dann entfaellt der
  /// Fortschrittsbalken, die Schubladen stehen trotzdem.
  final Map<app.BadgeMetrik, double>? metriken;

  /// Baut die Kachel eines Abzeichens. Als Rueckruf, weil die Kachel den
  /// Zustand der Seite braucht (freigeschaltet, Akzentfarbe). Die Masse
  /// kommen von hier und werden NICHT in der Kachel neu aus ihrer eigenen
  /// Breite abgeleitet: ein `Container` mit Rand gibt seinem Kind zwei Punkte
  /// weniger, und aus dieser Differenz entstuenden zwei Rechnungen mit zwei
  /// Ergebnissen.
  final Widget Function(app.Badge badge, BadgeKachelMasse masse) kachelBauer;

  final void Function(app.Badge badge)? onBadgeTippen;

  /// Die Schublade der Abzeichen ohne Familie („Weitere").
  static const String weitereSchluessel = '__weitere__';

  /// 2026-08-25 (vucko woertlich): „nicht untereinander sondern schon
  /// nebeneinander".
  ///
  /// Rand und seitlicher Innenabstand einer Schublade stehen hier EINMAL und
  /// werden von [_KatalogSchublade] gezeichnet UND von der Kachelbreite
  /// abgezogen. Genau dieses Auseinanderlaufen war der Fehler: gerechnet
  /// wurde mit der Aussenbreite der Liste (390 -> zwei Kacheln zu 191),
  /// gezeichnet wurde in der Innenbreite der Schublade (370). 191 + 8 + 191
  /// passte nicht hinein, also brach das `Wrap` nach jeder einzelnen Kachel
  /// um — auf dem Telefon stand eine Kachel je Reihe.
  static const double schubladeRand = 1.0;
  static const double schubladeInnen = 9.0;

  /// Was Rand und Innenabstand einer Schublade der Kachelreihe wegnehmen.
  static const double schubladeChrom = 2 * (schubladeRand + schubladeInnen);

  /// Welche Schublade steht ohne Zutun offen?
  ///
  /// Die Familie, der man am naechsten ist und die noch nicht durch ist. Ohne
  /// Kennzahlen die erste noch offene Familie, und wenn wirklich alles
  /// geschafft ist, die erste ueberhaupt — offen ist IMMER genau eine, damit
  /// der Abschnitt nie leer wirkt. Bei Gleichstand gewinnt die frueher im
  /// Katalog stehende, sonst spraenge die offene Schublade zwischen zwei
  /// gleich weiten Familien hin und her.
  static String vorgabeOffen({
    required Set<String> erreichteIds,
    Map<app.BadgeMetrik, double>? metriken,
  }) {
    final offene = app.badgeFamilien
        .where((f) => !badgeFamilieFertig(f, erreichteIds))
        .toList();
    if (offene.isEmpty) {
      return app.badgeFamilien.isEmpty
          ? weitereSchluessel
          : app.badgeFamilien.first.schluessel;
    }
    if (metriken != null) {
      app.BadgeFamilie? beste;
      var bester = -1.0;
      for (final familie in offene) {
        final anteil =
            app
                .badgeFamilienFortschritt(
                  familie: familie.schluessel,
                  erreichteBadgeIds: erreichteIds,
                  metriken: metriken,
                )
                ?.anteil ??
            0.0;
        if (anteil > bester) {
          bester = anteil;
          beste = familie;
        }
      }
      if (beste != null) return beste.schluessel;
    }
    return offene.first.schluessel;
  }

  /// Die Abzeichen einer Schublade. Oeffentlich, damit der Test pruefen kann,
  /// dass die Schubladen zusammen den vollen Katalog ergeben.
  static List<app.Badge> badgesVon(String schluessel) =>
      schluessel == weitereSchluessel
      ? app.Badge.all.where((b) => b.familie == null).toList()
      : app.Badge.familienBadges(schluessel);

  /// Alle Schubladen in Katalogreihenfolge; leere entfallen.
  static List<String> schubladen() => <String>[
    ...app.Badge.familienReihenfolge,
    weitereSchluessel,
  ].where((s) => badgesVon(s).isNotEmpty).toList();

  @override
  State<BadgeKatalogListe> createState() => _BadgeKatalogListeState();
}

class _BadgeKatalogListeState extends State<BadgeKatalogListe> {
  /// Nur die eigenhaendig umgeschalteten Schubladen. Die Vorgabe wird bei
  /// jedem Aufbau neu gerechnet: Kennzahlen und erreichte Abzeichen kommen
  /// nachgeladen, eingefroren stuende sonst die falsche Schublade offen.
  final Map<String, bool> _umgeschaltet = {};

  bool _offen(String schluessel, String vorgabe) =>
      _umgeschaltet[schluessel] ?? (schluessel == vorgabe);

  @override
  Widget build(BuildContext context) {
    final vorgabe = BadgeKatalogListe.vorgabeOffen(
      erreichteIds: widget.erreichteIds,
      metriken: widget.metriken,
    );
    final schubladen = BadgeKatalogListe.schubladen();
    final alleOffen = schubladen.every((s) => _offen(s, vorgabe));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Die nutzbare Breite ist die INNENbreite der Schublade, nicht die
        // der Liste. Gerechnet wird mit derselben Rasterregel wie im
        // Uebersichts-Panel darueber, damit beide Raster dieselbe Kante
        // haben — [badgeRasterSpalten].
        final nutzbar = constraints.maxWidth - BadgeKatalogListe.schubladeChrom;
        final masse = badgeKachelMasse(badgeRasterKachelBreite(nutzbar));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _katalogKopf(schubladen, alleOffen),
            const SizedBox(height: 9),
            for (var i = 0; i < schubladen.length; i++) ...[
              if (i > 0) const SizedBox(height: 7),
              _KatalogSchublade(
                schluessel: schubladen[i],
                erreichteIds: widget.erreichteIds,
                metriken: widget.metriken,
                masse: masse,
                kachelBauer: widget.kachelBauer,
                onBadgeTippen: widget.onBadgeTippen,
                offen: _offen(schubladen[i], vorgabe),
                aufTippen: () => setState(() {
                  final s = schubladen[i];
                  _umgeschaltet[s] = !_offen(s, vorgabe);
                }),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Ueberschrift des Katalogs und der Schalter fuer alles auf einmal.
  Widget _katalogKopf(List<String> schubladen, bool alleOffen) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Alle Abzeichen',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            for (final s in schubladen) {
              _umgeschaltet[s] = !alleOffen;
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  alleOffen
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  alleOffen ? 'Alle zuklappen' : 'Alle aufklappen',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Eine Familie als Schublade: Kopfzeile mit Stufenpfad und Stand, aufgeklappt
/// darunter der Fortschritt zur naechsten Stufe und die Kacheln.
class _KatalogSchublade extends StatelessWidget {
  const _KatalogSchublade({
    required this.schluessel,
    required this.erreichteIds,
    required this.metriken,
    required this.masse,
    required this.kachelBauer,
    required this.offen,
    required this.aufTippen,
    this.onBadgeTippen,
  });

  final String schluessel;
  final Set<String> erreichteIds;
  final Map<app.BadgeMetrik, double>? metriken;

  /// Breite, Hoehe und Innenmasse jeder Kachel — fuer die ganze Seite
  /// dieselben, damit das Raster eine saubere Kante behaelt.
  final BadgeKachelMasse masse;
  final Widget Function(app.Badge badge, BadgeKachelMasse masse) kachelBauer;
  final bool offen;
  final VoidCallback aufTippen;
  final void Function(app.Badge badge)? onBadgeTippen;

  @override
  Widget build(BuildContext context) {
    final istWeitere = schluessel == BadgeKatalogListe.weitereSchluessel;
    final badges = BadgeKatalogListe.badgesVon(schluessel);
    final familie = istWeitere ? null : app.badgeFamilieVon(schluessel);
    final titel = istWeitere ? 'Weitere' : (familie?.titel ?? schluessel);
    final erreicht = badges.where((b) => erreichteIds.contains(b.id)).length;
    final hoechsteStufe = istWeitere
        ? 0
        : app.Badge.hoechsteErreichteStufe(schluessel, erreichteIds);
    // „fertig" heisst hier dasselbe wie oben im Panel: kein Abzeichen der
    // Familie ist mehr offen — Meilensteine eingeschlossen.
    final fertig = familie == null
        ? erreicht == badges.length
        : badgeFamilieFertig(familie, erreichteIds);
    final zielStil = badgeStufenStil(
      familie == null ? 0 : (badgeZielBadge(familie, erreichteIds)?.stufe ?? 3),
    );
    final fortschritt = (istWeitere || metriken == null)
        ? null
        : app.badgeFamilienFortschritt(
            familie: schluessel,
            erreichteBadgeIds: erreichteIds,
            metriken: metriken!,
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: offen ? 0.03 : 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: BadgeKatalogListe.schubladeRand,
          color: fertig
              ? zielStil.farbe.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: aufTippen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 7, 9),
              child: Row(
                children: [
                  if (familie?.istGestuft ?? false) ...[
                    BadgeStufenPfadLeiste(
                      erreichteStufen: hoechsteStufe,
                      punktGroesse: 13,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$erreicht/${badges.length}',
                    style: TextStyle(
                      color: fertig
                          ? zielStil.farbeHell.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    turns: offen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (offen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BadgeKatalogListe.schubladeInnen,
                0,
                BadgeKatalogListe.schubladeInnen,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fortschritt != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: fortschritt.anteil,
                              minHeight: 4,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.07,
                              ),
                              color: zielStil.farbe,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fortschritt.zahlen,
                          style: TextStyle(
                            color: zielStil.farbeHell.withValues(alpha: 0.9),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: badgeRasterLuecke,
                    runSpacing: badgeRasterLuecke,
                    children: [
                      for (final badge in badges)
                        SizedBox(
                          width: masse.breite,
                          height: masse.hoehe,
                          // 2026-08-15 (vucko): Jede Kachel oeffnet das
                          // Overlay — freigeschaltet mit Beschreibung,
                          // gesperrt mit Bedingung und Fortschritt.
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onBadgeTippen?.call(badge),
                            child: kachelBauer(badge, masse),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
