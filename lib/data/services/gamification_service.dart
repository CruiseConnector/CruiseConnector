import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

/// Ergebnis der Gamification-Berechnung.
class GamificationResult {
  const GamificationResult({
    required this.level,
    required this.earnedBadgeIds,
    required this.newBadgeIds,
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalHours,
    required this.totalXp,
  });

  final UserLevel level;
  final List<String> earnedBadgeIds;
  final List<String> newBadgeIds;
  final int totalRoutes;
  final double totalDistanceKm;
  final double totalHours;
  final int totalXp;

  List<Badge> get earnedBadges =>
      earnedBadgeIds.map(Badge.getById).whereType<Badge>().toList();

  List<Badge> get newBadges =>
      newBadgeIds.map(Badge.getById).whereType<Badge>().toList();
}

class RouteXpBreakdown {
  const RouteXpBreakdown({
    required this.distanceXp,
    required this.curveXp,
    required this.styleBonus,
    required this.baseXp,
    required this.streakDays,
    required this.multiplier,
    required this.totalXp,
  });

  final int distanceXp;
  final int curveXp;
  final int styleBonus;
  final int baseXp;
  final int streakDays;
  final double multiplier;
  final int totalXp;

  String get multiplierLabel => 'x${multiplier.toStringAsFixed(2)}';
}

class DriveSessionTotals {
  const DriveSessionTotals({
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalSeconds,
    required this.totalXp,
  });

  final int totalRoutes;
  final double totalDistanceKm;
  final double totalSeconds;
  final int totalXp;
}

/// Service für XP-, Level- und Badge-System mit Supabase-Backend.
class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  static const int xpPerDrivenKm = 10;
  static const double minRouteProgressForXp = 0.20;
  static const double minRouteProgressForFullXp = 0.95;
  static const Map<String, String> _legacyBadgeIds = {'route_1': 'badge_02'};

  @visibleForTesting
  static List<String> normalizeBadgeIds(Iterable<dynamic> badgeIds) {
    final activeBadgeIds = Badge.all.map((badge) => badge.id).toSet();
    final normalized = <String>{};

    for (final raw in badgeIds) {
      final id = raw?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final mappedId = _legacyBadgeIds[id] ?? id;
      if (activeBadgeIds.contains(mappedId)) {
        normalized.add(mappedId);
      }
    }

    return [
      for (final badge in Badge.all)
        if (normalized.contains(badge.id)) badge.id,
    ];
  }

  @visibleForTesting
  static List<String> mergeBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    return normalizeBadgeIds([...previousBadgeIds, ...currentBadgeIds]);
  }

  @visibleForTesting
  static List<String> newlyQualifiedBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    final previousBadgeSet = normalizeBadgeIds(previousBadgeIds).toSet();
    return normalizeBadgeIds(
      currentBadgeIds,
    ).where((badgeId) => !previousBadgeSet.contains(badgeId)).toList();
  }

  /// Berechnet XP für eine einzelne Fahrt.
  /// Quelle ist ausschließlich die tatsächlich gefahrene Distanz: 10 XP/km.
  static int calculateRouteXp({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 1,
  }) {
    return calculateRouteXpBreakdown(
      distanceKm: distanceKm,
      curves: curves,
      style: style,
      streakDays: streakDays,
    ).totalXp;
  }

  static RouteXpBreakdown calculateRouteXpBreakdown({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 1,
  }) {
    final distanceXp = calculateDriveXp(distanceKm);
    final safeStreakDays = math.max(1, streakDays);
    // 2026-06-15 (vucko): Streak-Multiplikator JETZT echt auf die Distanz-XP
    // anwenden (vorher hart 1.0 = wirkungslos). Aufgerundet, damit der Bonus
    // nie verschluckt wird.
    final multiplier = streakMultiplierForDays(safeStreakDays);
    final totalXp = (distanceXp * multiplier).round();
    return RouteXpBreakdown(
      distanceXp: distanceXp,
      curveXp: 0,
      styleBonus: 0,
      baseXp: distanceXp,
      streakDays: safeStreakDays,
      multiplier: multiplier,
      totalXp: totalXp,
    );
  }

  static int calculateDriveXp(double distanceKm) {
    return (math.max(0, distanceKm) * xpPerDrivenKm).round();
  }

  static double routeProgressRatio({
    required double plannedDistanceKm,
    required double drivenDistanceKm,
  }) {
    if (plannedDistanceKm <= 0 || drivenDistanceKm <= 0) return 0;
    return (drivenDistanceKm / plannedDistanceKm).clamp(0.0, 1.0).toDouble();
  }

  static double completionCreditProgressStep(
    double progressRatio, {
    bool completed = false,
  }) {
    final progress = progressRatio.clamp(0.0, 1.0).toDouble();
    if (completed && progress >= minRouteProgressForFullXp) return 1.0;
    return progress;
  }

  static double creditedDistanceKmForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    bool completed = false,
  }) {
    if (plannedDistanceKm <= 0) return 0;
    final progress = completionCreditProgressStep(
      progressRatio,
      completed: completed,
    );
    if (progress < minRouteProgressForXp) return 0;
    return plannedDistanceKm * progress;
  }

  static RouteXpBreakdown calculateRouteXpBreakdownForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    required int curves,
    required String style,
    bool completed = false,
    int streakDays = 1,
  }) {
    final creditedDistanceKm = creditedDistanceKmForProgress(
      plannedDistanceKm: plannedDistanceKm,
      progressRatio: progressRatio,
      completed: completed,
    );
    return calculateRouteXpBreakdown(
      distanceKm: creditedDistanceKm,
      curves: creditedDistanceKm > 0 ? curves : 0,
      style: style,
      streakDays: streakDays,
    );
  }

  /// 2026-06-15 (vucko): XP-Streak-Multiplikator. Pro aktivem Tag +0,1, KEIN Cap:
  /// 1 Tag→1,1 · 2→1,2 · 3→1,3 · … · 10→2,0 · 11→2,1 … Wird auf die Distanz-XP
  /// jeder Fahrt angewandt UND fix in user_drive_sessions.xp_awarded geschrieben
  /// (konto-relevant, siehe [calculateRouteXpBreakdown] + recordDriveSession),
  /// nicht nur im Frontend.
  static double streakMultiplierForDays(int streakDays) {
    return 1.0 + math.max(0, streakDays) * 0.1;
  }

  static int calculateDrivingStreakDays(
    Iterable<UserDriveSession> sessions, {
    DateTime? now,
  }) {
    final today = _dateOnly((now ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(sessions);
    if (driveDays.isEmpty) return 0;

    var checkDay = today;
    if (!driveDays.contains(checkDay)) {
      checkDay = checkDay.subtract(const Duration(days: 1));
    }

    var streak = 0;
    while (driveDays.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int calculateStreakDaysForRide(
    Iterable<UserDriveSession> existingSessions, {
    DateTime? rideDate,
  }) {
    final rideDay = _dateOnly((rideDate ?? DateTime.now()).toLocal());
    final driveDays = _driveDays(existingSessions)..add(rideDay);

    var streak = 0;
    var checkDay = rideDay;
    while (driveDays.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return math.max(1, streak);
  }

  static Future<int> getStreakDaysForNextRide({DateTime? rideDate}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return 1;

    try {
      final data = await _db
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final sessions = (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
      return calculateStreakDaysForRide(sessions, rideDate: rideDate);
    } catch (e) {
      debugPrint('[Gamification] Streak-Abfrage fehlgeschlagen: $e');
      return 1;
    }
  }

  static Set<DateTime> _driveDays(Iterable<UserDriveSession> sessions) {
    return sessions
        .where((session) => session.distanceKm > 0)
        .map((session) => _dateOnly(session.createdAt.toLocal()))
        .toSet();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Zaehlt echte Kurven — dichte-unabhaengig + akkurat.
  ///
  /// 2026-08-09 (vucko): Das Verfahren liegt jetzt in [KurvenZaehler], damit
  /// ANZEIGE und ROUTEN-AUSWAHL dieselbe Zahl benutzen. Vorher entschied die
  /// Kurvenjagd-Auswahl mit einem eigenen, groben Index-Zaehler — die App zeigte
  /// also eine ehrliche Kurvenzahl an, waehlte die Route aber nach einer anderen.
  static int countCurves(List<List<double>> coords) =>
      KurvenZaehler.zaehle(coords);

  /// Async-Version: Zählt Kurven in einem separaten Isolate (Main-Thread bleibt frei).
  static Future<int> countCurvesAsync(List<List<double>> coords) {
    if (coords.length < 100) return Future.value(countCurves(coords));
    return compute(_countCurvesIsolate, coords);
  }

  static int _countCurvesIsolate(List<List<double>> coords) =>
      countCurves(coords);

  @visibleForTesting
  static DriveSessionTotals summarizeDriveSessions(
    Iterable<UserDriveSession> sessions,
  ) {
    double totalKm = 0;
    double totalSecs = 0;
    int totalXp = 0;
    int totalRoutes = 0;

    for (final session in sessions) {
      if (session.distanceKm <= 0 && session.xpAwarded <= 0) continue;
      totalRoutes++;
      totalKm += math.max(0, session.distanceKm);
      totalSecs += math.max(0, session.durationSeconds);
      totalXp += math.max(0, session.xpAwarded);
    }

    return DriveSessionTotals(
      totalRoutes: totalRoutes,
      totalDistanceKm: totalKm,
      totalSeconds: totalSecs,
      totalXp: totalXp,
    );
  }

  @visibleForTesting
  static int completedGroupRideCount(Iterable<UserDriveSession> sessions) {
    return sessions
        .where(
          (session) =>
              session.completedAtEnd &&
              (session.groupId?.trim().isNotEmpty ?? false),
        )
        .length;
  }

  @visibleForTesting
  static Map<String, dynamic> buildDriveSessionInsert({
    required String userId,
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
    int? xpAwarded,
    String? groupId,
    double? topSpeedKmh,
    List<List<double>>? trackGeometry,
    String? photoUrl,
  }) {
    final safeDistanceKm = math.max(0.0, distanceKm);
    return {
      'user_id': userId,
      if (routeId?.trim().isNotEmpty == true) 'route_id': routeId!.trim(),
      'distance_km': double.parse(safeDistanceKm.toStringAsFixed(3)),
      'duration_seconds': math.max(0, durationSeconds),
      'xp_awarded': math.max(0, xpAwarded ?? calculateDriveXp(safeDistanceKm)),
      'completed_at_end': completedAtEnd,
      if (routeStyle?.trim().isNotEmpty == true)
        'route_style': routeStyle!.trim(),
      if (routeType?.trim().isNotEmpty == true) 'route_type': routeType!.trim(),
      if (routeFingerprint?.trim().isNotEmpty == true)
        'route_fingerprint': routeFingerprint!.trim(),
      'source': source,
      // 2026-06-23 (vucko X3 Gruppen-Rangliste): Fahrt der Gruppe zuordnen +
      // erreichte Top-Speed mitschreiben, damit die deterministische Rangliste
      // (get_group_leaderboard) je Mitglied aggregieren kann.
      if (groupId?.trim().isNotEmpty == true) 'group_id': groupId!.trim(),
      if (topSpeedKmh != null && topSpeedKmh > 0)
        'top_speed_kmh': double.parse(topSpeedKmh.toStringAsFixed(1)),
      // 2026-06-25 (vucko Routen-Detail-Page): gefahrenen Track (für akkurate
      // Karten-Darstellung) + optionales Foto persistieren. Track auf ~400 Punkte
      // gedünnt → kompakt genug für jsonb, akkurat genug für die Skizze/Karte.
      if (trackGeometry != null && trackGeometry.length >= 2)
        'track_geometry': _downsampleTrack(trackGeometry, 400),
      if (photoUrl?.trim().isNotEmpty == true) 'photo_url': photoUrl!.trim(),
    };
  }

  static List<List<double>> _downsampleTrack(
    List<List<double>> pts,
    int maxPoints,
  ) {
    if (pts.length <= maxPoints) return pts;
    final step = pts.length / maxPoints;
    final out = <List<double>>[];
    for (var i = 0; i < maxPoints; i++) {
      out.add(pts[(i * step).floor()]);
    }
    out.add(pts.last);
    return out;
  }

  static Future<UserDriveSession?> recordDriveSession({
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
    int? xpAwarded,
    String? groupId,
    double? topSpeedKmh,
    List<List<double>>? trackGeometry,
    String? photoUrl,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    if (distanceKm <= 0 && (xpAwarded ?? 0) <= 0) return null;

    final row = buildDriveSessionInsert(
      userId: userId,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      completedAtEnd: completedAtEnd,
      routeId: routeId,
      routeStyle: routeStyle,
      routeType: routeType,
      routeFingerprint: routeFingerprint,
      source: source,
      xpAwarded: xpAwarded,
      groupId: groupId,
      topSpeedKmh: topSpeedKmh,
      trackGeometry: trackGeometry,
      photoUrl: photoUrl,
    );

    try {
      final data = await _db
          .from('user_drive_sessions')
          .insert(row)
          .select()
          .single();
      // Neue Fahrt ist jetzt #1 → ältere Foto-Sessions aus der Top-5 räumen
      // (außer gespeicherte Routen). Fire-and-forget, blockt den Flow nicht.
      unawaited(pruneRecentRidePhotos());
      return UserDriveSession.fromJson(data);
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Session konnte nicht gespeichert werden: $e',
      );
      rethrow;
    }
  }

  /// 2026-06-25 (vucko Routen-Detail-Page): Foto einer Fahrt nachträglich setzen
  /// oder entfernen (null). Detailseite ruft das nach dem Upload auf.
  static Future<bool> updateDriveSessionPhoto(
    String sessionId,
    String? photoUrl,
  ) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      // .select() zurückholen → ein leeres Ergebnis bedeutet 0 geänderte Zeilen
      // (z.B. RLS blockiert / falsche id), damit ein stiller Fehlschlag NICHT
      // fälschlich Erfolg meldet (das war die Wurzel des „Foto verschwindet").
      final rows = await _db
          .from('user_drive_sessions')
          .update({'photo_url': photoUrl})
          .eq('id', sessionId)
          .eq('user_id', userId)
          .select('id');
      if (rows.isEmpty) {
        debugPrint('[Gamification] Foto-Update: 0 Zeilen geändert (RLS/id?).');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Gamification] Foto-Update fehlgeschlagen: $e');
      return false;
    }
  }

  /// Sucht die jüngste EIGENE Drive-Session mit gegebenem route_fingerprint, die
  /// ein Foto trägt. So kann eine GESPEICHERTE Route das Foto der zugehörigen
  /// gefahrenen Fahrt anzeigen (eine Quelle = user_drive_sessions.photo_url),
  /// ohne das Foto doppelt zu speichern. RLS-konform (nur eigene Zeilen).
  static Future<String?> photoUrlForRouteFingerprint(String fingerprint) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null || fingerprint.trim().isEmpty) return null;
    try {
      final data = await _db
          .from('user_drive_sessions')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('route_fingerprint', fingerprint)
          .not('photo_url', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final url = data?['photo_url'] as String?;
      return (url != null && url.trim().isNotEmpty) ? url : null;
    } catch (e) {
      debugPrint(
        '[Gamification] photoUrlForRouteFingerprint fehlgeschlagen: $e',
      );
      return null;
    }
  }

  /// 2026-06-25 (vucko #178): Fotos „zuletzt gefahrener" Fahrten, die aus der
  /// Top-[keep]-Liste herausfallen, wieder entfernen — ES SEI DENN, die Route
  /// wurde GESPEICHERT (dann lebt das Foto an der gespeicherten Route weiter).
  ///
  /// „Gespeichert" = es existiert eine eigene Route mit gleichem
  /// route_fingerprint ODER eine gespeicherte Route referenziert exakt dieselbe
  /// Foto-URL (Foto wurde beim Speichern mitkopiert). Nur in diesem Fall bleibt
  /// die Storage-Datei erhalten; sonst wird sie gelöscht (kein verwaister Müll).
  ///
  /// Läuft fire-and-forget nach dem Aufzeichnen einer neuen Fahrt — blockt also
  /// nie den Abschluss-Flow und schluckt Fehler still.
  static Future<void> pruneRecentRidePhotos({int keep = 5}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // Alle eigenen Sessions MIT Foto, neueste zuerst.
      final withPhoto = await _db
          .from('user_drive_sessions')
          .select('id, photo_url, route_fingerprint')
          .eq('user_id', userId)
          .not('photo_url', 'is', null)
          .order('created_at', ascending: false);
      final rows = (withPhoto as List).cast<Map<String, dynamic>>();
      if (rows.length <= keep) return;

      // Schutzschild: Fingerprints + Foto-URLs der eigenen GESPEICHERTEN Routen.
      final savedRows = await _db
          .from('routes')
          .select('route_fingerprint, photo_url')
          .eq('user_id', userId);
      final savedFingerprints = <String>{};
      final savedPhotoUrls = <String>{};
      for (final r in (savedRows as List).cast<Map<String, dynamic>>()) {
        final fp = (r['route_fingerprint'] as String?)?.trim();
        if (fp != null && fp.isNotEmpty) savedFingerprints.add(fp);
        final pu = (r['photo_url'] as String?)?.trim();
        if (pu != null && pu.isNotEmpty) savedPhotoUrls.add(pu);
      }

      // Alles JENSEITS der Top-[keep]: Foto entfernen, wenn nicht geschützt.
      for (final row in rows.skip(keep)) {
        final id = row['id'] as String?;
        final url = (row['photo_url'] as String?)?.trim();
        final fp = (row['route_fingerprint'] as String?)?.trim();
        if (id == null || url == null || url.isEmpty) continue;

        final isSaved =
            (fp != null && fp.isNotEmpty && savedFingerprints.contains(fp)) ||
            savedPhotoUrls.contains(url);
        if (isSaved) continue; // Foto bleibt — Route ist gespeichert.

        // Foto-Spalte der Session leeren …
        await _db
            .from('user_drive_sessions')
            .update({'photo_url': null})
            .eq('id', id)
            .eq('user_id', userId);
        // … und die Datei löschen, sofern KEINE gespeicherte Route sie nutzt.
        if (!savedPhotoUrls.contains(url)) {
          await SocialService.deleteUserAsset(
            bucket: 'ride-photos',
            publicUrl: url,
          );
        }
      }
    } catch (e) {
      debugPrint('[Gamification] pruneRecentRidePhotos fehlgeschlagen: $e');
    }
  }

  static Future<List<UserDriveSession>> getDriveSessions({int? limit}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      var query = _db
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (limit != null) {
        query = query.limit(limit);
      }
      final data = await query;
      return (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Sessions konnten nicht geladen werden: $e',
      );
      return const [];
    }
  }

  /// Berechnet Level und Badges basierend auf immutable Drive-Sessions.
  /// Speichert den Fortschritt in der `profiles`-Tabelle.
  static Future<GamificationResult> calculateAndSync() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    // 1. Alle Drive-Sessions laden. Gespeicherte Routen sind nicht XP-Quelle.
    List<UserDriveSession> sessions;
    try {
      sessions = await getDriveSessions();
    } catch (e) {
      debugPrint('[Gamification] Drive-Session-Abfrage fehlgeschlagen: $e');
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    // 2. Statistiken berechnen
    final totals = summarizeDriveSessions(sessions);
    final totalKm = totals.totalDistanceKm;
    final totalSecs = totals.totalSeconds;
    final totalXp = totals.totalXp;
    final totalRoutes = totals.totalRoutes;
    final completedSessions = sessions
        .where((session) => session.completedAtEnd)
        .toList();
    final completedGroupRides = completedGroupRideCount(sessions);

    // 3. Level aus XP berechnen
    final level = UserLevel.fromXp(totalXp.toDouble());

    final extraCounts = await Future.wait<int>([
      _countCreatedGroups(userId),
      _countRoutePosts(userId),
      _countSavedRouteReferences(userId),
    ]);
    final createdGroupCount = extraCounts[0];
    final routePostCount = extraCounts[1];
    final savedRouteReferenceCount = extraCounts[2];

    // 4. Badges prüfen
    final currentlyQualifiedBadges = <String>[];

    // Level-Badges
    if (level.level >= 10) currentlyQualifiedBadges.add('badge_01');
    if (level.level >= 25) currentlyQualifiedBadges.add('badge_03');
    if (level.level >= 50) currentlyQualifiedBadges.add('badge_08');
    if (level.level >= UserLevel.maxLevel) {
      currentlyQualifiedBadges.add('badge_14');
    }

    // Routen- und Gruppen-Badges
    if (completedSessions.isNotEmpty) currentlyQualifiedBadges.add('badge_02');
    if (completedGroupRides >= 1) currentlyQualifiedBadges.add('badge_04');
    if (routePostCount >= 1) currentlyQualifiedBadges.add('badge_05');
    if (createdGroupCount >= 1) currentlyQualifiedBadges.add('badge_07');
    if (savedRouteReferenceCount >= 5) {
      currentlyQualifiedBadges.add('badge_09');
    }

    // 2026-08-15 (vucko): sechs neue Stufen — alle aus Daten, die hier
    // ohnehin schon liegen. Keine einzige zusaetzliche Abfrage.
    if (completedSessions.length >= 10) {
      currentlyQualifiedBadges.add('badge_17');
    }
    if (completedSessions.length >= 50) {
      currentlyQualifiedBadges.add('badge_18');
    }
    if (completedGroupRides >= 5) currentlyQualifiedBadges.add('badge_19');
    if (completedSessions.any((s) => s.distanceKm >= 100)) {
      currentlyQualifiedBadges.add('badge_20');
    }
    if (routePostCount >= 5) currentlyQualifiedBadges.add('badge_21');
    if (totalSecs >= 25 * 3600) currentlyQualifiedBadges.add('badge_22');

    // Distanz-Badges
    if (totalKm >= 500) currentlyQualifiedBadges.add('badge_06');
    if (totalKm >= 2500) currentlyQualifiedBadges.add('badge_10');
    if (totalKm >= 10000) currentlyQualifiedBadges.add('badge_13');

    // 2026-08-14 (vucko Tutorial-Badge): „Gründungszeit" (badge_15) bekommt
    // JEDER registrierte Nutzer — bewusst OHNE Bedingung. Bestandsnutzer
    // erhalten es dadurch beim ersten Sync nach dem Update automatisch als
    // newBadgeId → das Unlock-Popup (Verleih-Animation) feuert von selbst.
    currentlyQualifiedBadges.add(Badge.membershipBadgeId);

    // 5. Bisherige Badges laden und neue bestimmen
    List<String> previousBadges = [];
    try {
      final profile = await _db
          .from('profiles')
          .select('badges')
          .eq('id', userId)
          .maybeSingle();

      final rawBadges = profile?['badges'];
      if (rawBadges is Iterable) {
        previousBadges = normalizeBadgeIds(rawBadges);
      }
    } catch (e) {
      debugPrint('[Gamification] Badges-Abfrage fehlgeschlagen: $e');
    }

    final qualifiedBadges = normalizeBadgeIds(currentlyQualifiedBadges);
    final unlockedBadges = mergeBadgeIds(previousBadges, qualifiedBadges);
    final newBadges = newlyQualifiedBadgeIds(previousBadges, qualifiedBadges);

    // 6. Fortschritt im Backend speichern
    try {
      await _db
          .from('profiles')
          .update({
            'level': level.level,
            'total_km': totalKm,
            'total_xp': totalXp,
            'total_routes': totalRoutes,
            'badges': unlockedBadges,
          })
          .eq('id', userId);
    } catch (e) {
      debugPrint('[Gamification] Profil-Update fehlgeschlagen: $e');
    }

    return GamificationResult(
      level: level,
      earnedBadgeIds: unlockedBadges,
      newBadgeIds: newBadges,
      totalRoutes: totalRoutes,
      totalDistanceKm: totalKm,
      totalHours: totalSecs / 3600,
      totalXp: totalXp,
    );
  }

  static Future<int> _countCreatedGroups(String userId) async {
    try {
      final rows = await _db
          .from('groups')
          .select('id')
          .eq('created_by', userId)
          .limit(2);
      return (rows as List).length;
    } catch (e) {
      debugPrint('[Gamification] Gruppen-Zähler fehlgeschlagen: $e');
      return 0;
    }
  }

  static Future<int> _countRoutePosts(String userId) async {
    try {
      final rows = await _db
          .from('posts')
          .select('shared_route_id')
          .eq('user_id', userId);
      return (rows as List)
          .whereType<Map>()
          .where((row) => row['shared_route_id'] != null)
          .length;
    } catch (e) {
      debugPrint('[Gamification] Routenpost-Zähler fehlgeschlagen: $e');
      return 0;
    }
  }

  static Future<int> _countSavedRouteReferences(String userId) async {
    final routeIds = <String>{};

    try {
      final rows = await _db
          .from('routes')
          .select('id, source_route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final sourceRouteId = row['source_route_id'] as String?;
        final routeId = sourceRouteId?.trim().isNotEmpty == true
            ? sourceRouteId!.trim()
            : row['id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint(
        '[Gamification] Gespeicherte Routen-Zähler fehlgeschlagen: $e',
      );
    }

    try {
      final rows = await _db
          .from('route_bookmarks')
          .select('route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final routeId = row['route_id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint('[Gamification] Routen-Speicher-Zähler fehlgeschlagen: $e');
    }

    return routeIds.length;
  }
}
