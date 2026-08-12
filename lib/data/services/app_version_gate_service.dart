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
    this.installierterBuild,
    this.benoetigterBuild,
  });

  const AppVersionGateResult.erlaubt() : this._(blockiert: false);

  const AppVersionGateResult.gesperrt({
    String? storeUrl,
    String? nachricht,
    int? installierterBuild,
    int? benoetigterBuild,
  }) : this._(
         blockiert: true,
         storeUrl: storeUrl,
         nachricht: nachricht,
         installierterBuild: installierterBuild,
         benoetigterBuild: benoetigterBuild,
       );

  final bool blockiert;
  final String? storeUrl;
  final String? nachricht;

  /// Was auf dem Gerät läuft — für „Deine Version … benötigt …".
  final int? installierterBuild;
  final int? benoetigterBuild;
}

/// Zwangs-Update-Gate.
///
/// 2026-08-10 (vucko): „in Zukunft wenn die App ein Update hat, dass die Leute
/// es herunterladen muessen, bevor sie in die App reingehen koennen."
///
/// 2026-08-12 (vucko, geschärft): „wenn die app eine alte version hat, man
/// benachrichtigt wird und die app neuinstallieren MUSS um reinzukommen."
///
/// Beim Start liest die App den Mindest-Build für ihre Plattform aus
/// `app_min_version`. Ist der installierte Build kleiner, wird der Zugang
/// blockiert. Um später ein Update zu erzwingen, wird serverseitig einfach
/// `min_build_number` hochgesetzt — kein neuer App-Build nötig.
///
/// GRUNDSATZ: fail-open. Jeder Fehler (offline, Zeitüberschreitung, kaputte
/// Antwort) lässt den Nutzer REIN.
///
/// Das ist eine bewusste Entscheidung und keine Bequemlichkeit. Die
/// naheliegende Härtung — die zuletzt bekannte Schwelle lokal merken und
/// offline darauf zurückfallen — wurde geprüft und VERWORFEN: Ein Zahlendreher
/// beim Setzen der Schwelle (995 statt 95) würde sich damit auf jedem Gerät
/// festsetzen, das danach offline startet. Die Korrektur am Server erreicht
/// genau diese Geräte nie mehr — aus einem Konfigurationsfehler von Minuten
/// würde ein dauerhaft unbrauchbares Handy, und zwar bei Leuten, die die
/// neueste Version haben. Der Preis des fail-open sind ein paar Starts mit
/// alter Version während eines Ausfalls. Das ist der kleinere Schaden.
///
/// Die Sperre wird stattdessen dort scharf gemacht, wo sie hingehört: Sie
/// liegt als Deckel ÜBER dem gesamten Navigator (siehe ForceUpdateGate), damit
/// kein `push` und kein Deeplink sie unterlaufen kann, und sie wird bei der
/// Rückkehr in den Vordergrund erneut geprüft.
class AppVersionGateService {
  AppVersionGateService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Der zuletzt bekannte Stand. Die Oberfläche hängt sich hier dran, damit
  /// eine später erkannte Sperre ohne Neustart greift.
  static final ValueNotifier<AppVersionGateResult> zustand =
      ValueNotifier<AppVersionGateResult>(const AppVersionGateResult.erlaubt());

  /// Wann zuletzt erfolgreich geprüft wurde — für die Drosselung.
  static DateTime? letzteErfolgreichePruefung;

  /// Nur für Tests: ersetzt die Abfrage.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(String plattform)? abfrage;

  /// Nur für Tests: ersetzt die Build-Nummer des Geräts.
  @visibleForTesting
  static Future<String> Function()? buildNummerLeser;

  /// Liest die Build-Nummer robust.
  ///
  /// `int.tryParse` scheitert an allem, was nicht rein numerisch ist — etwa
  /// „95.1" oder „95 (release)". Vorher fiel der Code in diesem Fall auf 0
  /// zurück und hätte damit AUSNAHMSLOS JEDEN gesperrt. Jetzt wird die erste
  /// Ziffernfolge genommen, und wenn es die nicht gibt, wird durchgelassen.
  static int? _leseBuild(String roh) {
    final treffer = RegExp(r'\d+').firstMatch(roh);
    if (treffer == null) return null;
    return int.tryParse(treffer.group(0)!);
  }

  static Future<AppVersionGateResult> pruefe() async {
    final ergebnis = await _pruefeIntern();
    zustand.value = ergebnis;
    return ergebnis;
  }

  static Future<AppVersionGateResult> _pruefeIntern() async {
    try {
      if (kIsWeb) return const AppVersionGateResult.erlaubt();
      final plattform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : null;
      if (plattform == null) return const AppVersionGateResult.erlaubt();

      final rohBuild = buildNummerLeser != null
          ? await buildNummerLeser!()
          : (await PackageInfo.fromPlatform()).buildNumber;
      final installiert = _leseBuild(rohBuild);
      if (installiert == null) {
        // Unlesbare Build-Nummer: REINLASSEN. Ein Formatwechsel in der
        // Info.plist darf nicht die ganze Nutzerschaft aussperren.
        debugPrint('[Versions-Gate] Build "$rohBuild" unlesbar → lasse rein');
        return const AppVersionGateResult.erlaubt();
      }

      final row = abfrage != null
          ? await abfrage!(plattform)
          : await _db
                .from('app_min_version')
                .select('min_build_number, store_url, message')
                .eq('platform', plattform)
                .maybeSingle()
                .timeout(const Duration(seconds: 5));

      letzteErfolgreichePruefung = DateTime.now();
      if (row == null) return const AppVersionGateResult.erlaubt();

      final mindest = (row['min_build_number'] as num?)?.toInt();
      if (mindest == null) return const AppVersionGateResult.erlaubt();
      if (installiert >= mindest) return const AppVersionGateResult.erlaubt();

      debugPrint(
        '[Versions-Gate] Build $installiert < Mindest $mindest → blockiert',
      );
      return AppVersionGateResult.gesperrt(
        storeUrl: row['store_url'] as String?,
        nachricht: row['message'] as String?,
        installierterBuild: installiert,
        benoetigterBuild: mindest,
      );
    } catch (e) {
      // Fail-open: im Zweifel REIN lassen. Siehe Klassenkommentar — die
      // Alternative wäre gefährlicher als das Problem.
      debugPrint('[Versions-Gate] Pruefung fehlgeschlagen, lasse rein: $e');
      return const AppVersionGateResult.erlaubt();
    }
  }

  /// Nur für Tests.
  @visibleForTesting
  static void resetForTests() {
    zustand.value = const AppVersionGateResult.erlaubt();
    letzteErfolgreichePruefung = null;
    abfrage = null;
    buildNummerLeser = null;
  }
}
