import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ergebnis der Versionsprüfung beim App-Start.
class AppVersionGateResult {
  const AppVersionGateResult._({
    required this.blockiert,
    this.storeUrl,
    this.nachricht,
  });

  const AppVersionGateResult.erlaubt() : this._(blockiert: false);

  const AppVersionGateResult.gesperrt({String? storeUrl, String? nachricht})
    : this._(blockiert: true, storeUrl: storeUrl, nachricht: nachricht);

  final bool blockiert;
  final String? storeUrl;
  final String? nachricht;
}

/// Zwangs-Update-Gate.
///
/// 2026-08-10 (vucko): „in Zukunft wenn die App ein Update hat, dass die Leute
/// es herunterladen muessen, bevor sie in die App reingehen koennen."
///
/// Beim Start liest die App den Mindest-Build fuer ihre Plattform aus
/// `app_min_version`. Ist der installierte Build kleiner, wird der Zugang
/// blockiert. Um spaeter ein Update zu erzwingen, wird serverseitig einfach
/// `min_build_number` hochgesetzt — kein neuer App-Build noetig.
///
/// GRUNDSATZ: fail-open. Jeder Fehler (offline, Zeitueberschreitung, kaputte
/// Antwort) laesst den Nutzer REIN. Andernfalls wuerde ein Supabase-Ausfall
/// die ganze Nutzerschaft aussperren — das waere schlimmer als eine kurzzeitig
/// veraltete Version.
class AppVersionGateService {
  AppVersionGateService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<AppVersionGateResult> pruefe() async {
    try {
      if (kIsWeb) return const AppVersionGateResult.erlaubt();
      final plattform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : null;
      if (plattform == null) return const AppVersionGateResult.erlaubt();

      final info = await PackageInfo.fromPlatform();
      final installiert = int.tryParse(info.buildNumber) ?? 0;

      final row = await _db
          .from('app_min_version')
          .select('min_build_number, store_url, message')
          .eq('platform', plattform)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (row == null) return const AppVersionGateResult.erlaubt();

      final mindest = (row['min_build_number'] as num?)?.toInt() ?? 0;
      if (installiert >= mindest) return const AppVersionGateResult.erlaubt();

      debugPrint(
        '[Versions-Gate] Build $installiert < Mindest $mindest → blockiert',
      );
      return AppVersionGateResult.gesperrt(
        storeUrl: row['store_url'] as String?,
        nachricht: row['message'] as String?,
      );
    } catch (e) {
      // Fail-open: im Zweifel REIN lassen.
      debugPrint('[Versions-Gate] Pruefung fehlgeschlagen, lasse rein: $e');
      return const AppVersionGateResult.erlaubt();
    }
  }
}
