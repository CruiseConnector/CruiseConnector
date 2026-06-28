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

  const LegalAcceptanceSnapshot({
    required this.termsVersion,
    required this.termsAcceptedAt,
    required this.privacyVersion,
    required this.privacyAcknowledgedAt,
    required this.legalLocale,
    required this.legalSource,
    required this.appVersion,
    required this.platform,
  });

  factory LegalAcceptanceSnapshot.current({required String source}) {
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
    };
  }

  Map<String, dynamic> toAuthMetadata() => toJson();

  Map<String, dynamic> toInsertPayload(User user) {
    return {
      'user_id': user.id,
      'email': user.email,
      ...toJson(),
      'device_info': <String, dynamic>{},
    };
  }
}

class LegalAcceptanceService {
  LegalAcceptanceService._();

  static const _pendingKey = 'pending_legal_acceptance_v1';
  static SupabaseClient get _db => Supabase.instance.client;

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
