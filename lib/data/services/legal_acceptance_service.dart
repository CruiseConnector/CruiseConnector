import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/legal_documents.dart';

class LegalAcceptanceSnapshot {
  // 2026-06-28 (vucko): Felder fehlten im Kollegen-Commit „Add legal acceptance
  // flow" (5150b0c) -> ganze App kompilierte nicht. Aus der Verwendung
  // (Konstruktor/Factories/toJson/isCurrent) abgeleitet ergänzt.
  final String termsVersion;
  final DateTime termsAcceptedAt;
  final String privacyVersion;
  final DateTime privacyAcknowledgedAt;
  final String legalLocale;
  final String legalSource;
  final String appVersion;
  final String platform;

  /// 2026-08-24: Auf welchem Weg dem Nutzer die Texte zugaenglich gemacht
  /// wurden. `browser` = Dokument wurde geoeffnet. `ersatzweg_link` = auf
  /// diesem Geraet liess sich kein Browser starten (Bildschirmzeit,
  /// verwaltetes Geraet); der Nutzer hat stattdessen die Adresse bestaetigt.
  /// Landet in `device_info`, nicht in einer eigenen Spalte — die Zustimmung
  /// bleibt damit nachweisbar, ohne Schema-Aenderung.
  final String readPath;

  static const readPathBrowser = 'browser';
  static const readPathLinkFallback = 'ersatzweg_link';

  const LegalAcceptanceSnapshot({
    required this.termsVersion,
    required this.termsAcceptedAt,
    required this.privacyVersion,
    required this.privacyAcknowledgedAt,
    required this.legalLocale,
    required this.legalSource,
    required this.appVersion,
    required this.platform,
    this.readPath = readPathBrowser,
  });

  factory LegalAcceptanceSnapshot.current({
    required String source,
    String readPath = readPathBrowser,
  }) {
    final now = DateTime.now().toUtc();
    return LegalAcceptanceSnapshot(
      termsVersion: LegalDocuments.termsVersion,
      termsAcceptedAt: now,
      privacyVersion: LegalDocuments.privacyVersion,
      privacyAcknowledgedAt: now,
      legalLocale: LegalDocuments.locale,
      legalSource: source,
      appVersion: LegalDocuments.fallbackAppVersion,
      platform: LegalAcceptanceService.platformLabel,
      readPath: readPath,
    );
  }

  factory LegalAcceptanceSnapshot.fromJson(Map<String, dynamic> json) {
    return LegalAcceptanceSnapshot(
      termsVersion: json['terms_version'] as String,
      termsAcceptedAt: DateTime.parse(json['terms_accepted_at'] as String),
      privacyVersion: json['privacy_version'] as String,
      privacyAcknowledgedAt: DateTime.parse(
        json['privacy_acknowledged_at'] as String,
      ),
      legalLocale: json['legal_locale'] as String? ?? LegalDocuments.locale,
      legalSource: json['legal_source'] as String? ?? 'app_onboarding',
      appVersion:
          json['app_version'] as String? ?? LegalDocuments.fallbackAppVersion,
      platform:
          json['platform'] as String? ?? LegalAcceptanceService.platformLabel,
      readPath: json['legal_read_path'] as String? ?? readPathBrowser,
    );
  }

  bool get isCurrent =>
      termsVersion == LegalDocuments.termsVersion &&
      privacyVersion == LegalDocuments.privacyVersion;

  Map<String, dynamic> toJson() {
    return {
      'terms_version': termsVersion,
      'terms_accepted_at': termsAcceptedAt.toUtc().toIso8601String(),
      'privacy_version': privacyVersion,
      'privacy_acknowledged_at': privacyAcknowledgedAt
          .toUtc()
          .toIso8601String(),
      'legal_locale': legalLocale,
      'legal_source': legalSource,
      'app_version': appVersion,
      'platform': platform,
      'legal_read_path': readPath,
    };
  }

  Map<String, dynamic> toAuthMetadata() => toJson();

  Map<String, dynamic> toInsertPayload(User user) {
    // ACHTUNG: Hier duerfen nur echte Spalten der Tabelle stehen. `readPath`
    // hat keine eigene Spalte und geht deshalb in `device_info` (jsonb) —
    // ein Spread von toJson() wuerde die Insert-Anfrage zerschiessen.
    final columns = toJson()..remove('legal_read_path');
    return {
      'user_id': user.id,
      'email': user.email,
      ...columns,
      'device_info': <String, dynamic>{'legal_read_path': readPath},
    };
  }
}

class LegalAcceptanceService {
  LegalAcceptanceService._();

  static const _pendingKey = 'pending_legal_acceptance_v1';
  static SupabaseClient get _db => Supabase.instance.client;

  // ── Prozessweiter Dedup-Guard („AGB-Fenster kam zweimal") ────────────────
  // 2026-07-10 (vucko): Beim Login entstehen mehrere LegalGatePage-Instanzen
  // fast gleichzeitig (AuthPage-StreamBuilder rebuildet bei signedIn UND
  // login/welcome/main pushen ihr eigenes Gate). Beide prüften PARALLEL:
  // Instanz A recordete das Pending in die DB und löschte es, Instanz B sah
  // weder DB-Row (Insert noch nicht sichtbar) noch Pending (schon gelöscht)
  // → zeigte das Fenster ERNEUT. Ein geteiltes Future + In-Memory-Marker
  // machen den Check prozessweit deterministisch: alle Gates teilen sich
  // EIN Ergebnis. Der Key enthält die User-ID + Versionen → invalidiert
  // sich bei Logout/User-Wechsel/Versions-Bump von selbst.
  static Future<bool>? _ensureFuture;
  static String? _ensureKey;

  static String get _acceptanceKey =>
      '${_db.auth.currentUser?.id}'
      '|${LegalDocuments.termsVersion}'
      '|${LegalDocuments.privacyVersion}';

  static void _markAcceptedInMemory() {
    _ensureKey = _acceptanceKey;
    _ensureFuture = Future<bool>.value(true);
  }

  /// Einziger Einstieg für Post-Login-Gates: true = aktuell akzeptiert
  /// (direkt oder via Pre-Auth-Pending, das dabei in die DB übernommen wird),
  /// false = Fenster nötig. Parallele Aufrufer teilen sich dasselbe Future.
  static Future<bool> ensureAcceptedOrPending({required String source}) {
    final key = _acceptanceKey;
    final existing = _ensureFuture;
    if (existing != null && _ensureKey == key) return existing;
    _ensureKey = key;
    late final Future<bool> future;
    future = () async {
      try {
        final ok = await _ensureUncached(source: source);
        // false/Fehler nicht cachen — nach Accept im Fenster oder Retry
        // muss frisch geprüft werden. true bleibt gecacht.
        if (!ok && identical(_ensureFuture, future)) _ensureFuture = null;
        return ok;
      } catch (_) {
        if (identical(_ensureFuture, future)) _ensureFuture = null;
        rethrow;
      }
    }();
    _ensureFuture = future;
    return future;
  }

  static Future<bool> _ensureUncached({required String source}) async {
    if (await hasCurrentAcceptance()) {
      await clearPendingPreAuthAcceptance();
      return true;
    }
    final pending = await pendingPreAuthAcceptance();
    if (pending != null) {
      // Wirft bei DB-Fehler → Gate zeigt den Fehler-Screen mit „Erneut
      // versuchen" statt das bereits bestätigte Fenster ein zweites Mal.
      await recordCurrentAcceptance(source: source, snapshot: pending);
      await clearPendingPreAuthAcceptance();
      return true;
    }
    return false;
  }

  static String get platformLabel {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static Future<bool> hasCurrentAcceptance() async {
    final user = _db.auth.currentUser;
    if (user == null) return false;

    final row = await _db
        .from('legal_acceptances')
        .select('id')
        .eq('user_id', user.id)
        .eq('terms_version', LegalDocuments.termsVersion)
        .eq('privacy_version', LegalDocuments.privacyVersion)
        .limit(1)
        .maybeSingle();

    if (row != null) _markAcceptedInMemory();
    return row != null;
  }

  static Future<void> recordCurrentAcceptance({
    required String source,
    LegalAcceptanceSnapshot? snapshot,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw const AuthException('Kein User ist eingeloggt.');
    }

    final acceptance = snapshot?.isCurrent == true
        ? snapshot!
        : LegalAcceptanceSnapshot.current(source: source);

    if (await hasCurrentAcceptance()) return;

    await _db
        .from('legal_acceptances')
        .insert(acceptance.toInsertPayload(user));
    _markAcceptedInMemory();
  }

  static Future<void> savePendingPreAuthAcceptance(
    LegalAcceptanceSnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(snapshot.toJson()));
  }

  static Future<LegalAcceptanceSnapshot?> pendingPreAuthAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final snapshot = LegalAcceptanceSnapshot.fromJson(decoded);
      return snapshot.isCurrent ? snapshot : null;
    } catch (e) {
      debugPrint('[LegalAcceptance] Pending Acceptance unlesbar: $e');
      await prefs.remove(_pendingKey);
      return null;
    }
  }

  static Future<void> clearPendingPreAuthAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }
}
