import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Zentrale Monetarisierungs-Konfiguration (Abos + Werbung).
///
/// Echte Schlüssel/IDs werden beim Build per `--dart-define` gesetzt. Die
/// Defaults sind die offiziellen **Google-TEST-Ad-Units** — sie zeigen echte
/// Test-Anzeigen, ganz OHNE AdMob-Account. Vor Release die echten IDs setzen
/// (siehe docs/MONETIZATION_SETUP.md).
class MonetizationConfig {
  MonetizationConfig._();

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIos => !kIsWeb && Platform.isIOS;

  // ── RevenueCat (Abos) ────────────────────────────────────────────────────
  static const revenueCatAndroidKey =
      String.fromEnvironment('REVENUECAT_ANDROID_KEY', defaultValue: '');
  static const revenueCatIosKey =
      String.fromEnvironment('REVENUECAT_IOS_KEY', defaultValue: '');
  static String get revenueCatKey => isIos ? revenueCatIosKey : revenueCatAndroidKey;

  /// Entitlement-Bezeichner, die in RevenueCat angelegt werden.
  static const entitlementBasic = 'basic';
  static const entitlementPremium = 'premium';

  /// Wenn kein RevenueCat-Key gesetzt ist, laufen Käufe im „Vorschau"-Modus
  /// (Paywall sichtbar, Kauf deaktiviert) und der Tier kommt vom Server.
  static bool get purchasesConfigured => revenueCatKey.isNotEmpty;

  // ── AdMob Ad-Unit-IDs (Test-Defaults; echte via --dart-define) ───────────
  static const _appOpenAndroid = String.fromEnvironment('ADMOB_APPOPEN_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/9257395921');
  static const _appOpenIos = String.fromEnvironment('ADMOB_APPOPEN_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/5575463023');
  static String get appOpenUnit => isIos ? _appOpenIos : _appOpenAndroid;

  static const _interstitialAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const _interstitialIos = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/4411468910');
  static String get interstitialUnit => isIos ? _interstitialIos : _interstitialAndroid;

  static const _rewardedAndroid = String.fromEnvironment('ADMOB_REWARDED_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const _rewardedIos = String.fromEnvironment('ADMOB_REWARDED_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/1712485313');
  static String get rewardedUnit => isIos ? _rewardedIos : _rewardedAndroid;

  static const _nativeAndroid = String.fromEnvironment('ADMOB_NATIVE_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/2247696110');
  static const _nativeIos = String.fromEnvironment('ADMOB_NATIVE_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/3986624511');
  static String get nativeUnit => isIos ? _nativeIos : _nativeAndroid;

  static const _bannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID',
      defaultValue: 'ca-app-pub-3940256099942544/6300978111');
  static const _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS',
      defaultValue: 'ca-app-pub-3940256099942544/2934735716');
  static String get bannerUnit => isIos ? _bannerIos : _bannerAndroid;

  // ── Testgeräte ───────────────────────────────────────────────────────────
  /// Komma-getrennte AdMob-Testgeräte-Hashes, gesetzt per
  /// `--dart-define=ADMOB_TEST_DEVICES=...`.
  ///
  /// 2026-07-25 (Werbe-Audit): Ein Release-Build traegt die ECHTEN Ad-Units.
  /// Wird so ein Build zum Ausprobieren aufs eigene Handy installiert, wertet
  /// Google die eigenen Impressions/Klicks als ungueltigen Traffic — das ist
  /// laut AdMob-Doku eine der Hauptursachen fuer Konto-Sperren. Als Testgeraet
  /// registriert liefert dieselbe echte Ad-Unit weiterhin (Test-)Anzeigen, die
  /// aber nicht abgerechnet werden.
  ///
  /// Den Hash gibt das SDK beim ersten Ad-Request selbst im Log aus:
  /// `Use RequestConfiguration.Builder.setTestDeviceIds(Arrays.asList("ABC…"))`
  static const _testDevicesRaw =
      String.fromEnvironment('ADMOB_TEST_DEVICES', defaultValue: '');
  static List<String> get testDeviceIds => _testDevicesRaw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  // ── Werbe-Frequenz (Free-Tier) ───────────────────────────────────────────
  /// 2026-07-23 (vucko): Routensuche zeigt jetzt ein 30s-Rewarded-Video (vorher
  /// Interstitial) — Cooldown-Wert unverändert übernommen, nur der Name
  /// entspricht jetzt dem tatsächlichen Format.
  static const int routeSearchRewardedCooldownSec = 300;
  /// Native-Ad alle N Posts im Community-/Gruppen-Feed.
  static const int feedAdEveryNPosts = 6;
  // 2026-07-22 (vucko Placements): weitere Frequenzen.
  /// Globaler Mindestabstand zwischen JEGLICHEN Vollbild-Ads — verhindert
  /// z.B. Gruppen-Beitritt-Video direkt gefolgt vom Tab-Wechsel-Interstitial.
  static const int fullscreenAdMinGapSec = 90;
  /// Interstitial nach >5 Seitenwechseln höchstens alle N Sekunden.
  static const int tabSwitchInterstitialCooldownSec = 180;
  /// 2026-07-23 (vucko): Gruppen-Beitritt zeigt jetzt ein 30s-Rewarded-Video
  /// (vorher Interstitial) — Cooldown-Wert unverändert übernommen.
  static const int groupJoinRewardedCooldownSec = 240;
  /// Vor-Fahrt-Video (Rewarded) höchstens alle N Sekunden — der Fahrt-Start
  /// nach Pause/kurzem Stopp soll nicht jedes Mal ein Video kosten.
  static const int preRideRewardedCooldownSec = 900;
}
