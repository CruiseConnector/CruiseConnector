import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../application/providers/subscription_provider.dart';
import '../../core/monetization_config.dart';

/// Zentraler AdMob-Service (App-Open, Interstitial, Rewarded).
///
/// 2026-07-22 (vucko „Werbung wirklich gut geschaltet"): Bisher war
/// google_mobile_ads nur eine Dependency — nirgends initialisiert, keine
/// einzige Ad-Instanz. Dieser Service kapselt ALLES Werbe-Verhalten nach
/// festen Grundregeln:
///
/// 1. ZAHLENDE NUTZER SEHEN NIE WERBUNG. Das Tier wird bei JEDEM Lade- und
///    Zeige-Versuch FRISCH über den [SubscriptionProvider] geprüft (nie als
///    einmaliger bool-Snapshot — der Provider startet als „free", bis der
///    Server-Tier asynchron geladen ist, und kann sich mitten in der Session
///    durch einen Kauf ändern).
/// 2. WERBUNG BLOCKIERT NIE EINE AKTION. Alle Show-Methoden sind best-effort:
///    ist keine Ad geladen, geht es sofort ohne Wartezeit weiter. Nur das
///    Vor-Fahrt-Video wartet bewusst auf das Ende der Wiedergabe — mit
///    Sicherheitsnetz-Timeout, falls das SDK hängt.
/// 3. NIE WÄHREND DER FAHRT. [navigationActive] wird von der Navigation
///    gesetzt; solange es true ist, zeigt der Service nichts (AdMob-Policy +
///    Sicherheit in einer Fahr-App — Store-Ablehnungs-Historie!).
/// 4. EWR-CONSENT ZUERST. Vor dem allerersten Ad-Request läuft der
///    UMP-Consent-Flow (DSGVO-Pflicht im DACH-Markt); geladen wird nur, wenn
///    canRequestAds() true liefert.
/// 5. NIE ZWEI VOLLBILD-ADS KURZ HINTEREINANDER. Globaler Mindestabstand
///    zwischen JEGLICHEN Vollbild-Anzeigen (App-Open/Interstitial/Rewarded),
///    zusätzlich zu den pro-Placement-Cooldowns.
class AdService with WidgetsBindingObserver {
  AdService._();
  static final AdService instance = AdService._();

  /// Von der Navigation gesetzt (Fahrt läuft) — unterdrückt ALLE Anzeigen.
  bool navigationActive = false;

  SubscriptionProvider? _subscription;
  bool _sdkInitStarted = false;
  bool _sdkReady = false;
  bool _consentFlowDone = false;
  bool _consentFormWasShown = false;
  bool _homeReached = false;
  bool _fullscreenAdShowingNow = false;
  DateTime? _lastFullscreenAdAt;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadedAt;
  bool _appOpenShownThisLaunch = false;

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  final Map<String, DateTime> _lastShownPerPlacement = {};

  // ── Gates ─────────────────────────────────────────────────────────────────

  bool get _showsAds => _subscription?.showsAds ?? false;

  /// Grund-Voraussetzungen für JEDE Vollbild-Ad (ohne den globalen Abstand).
  bool get _fullscreenBaseAllowed =>
      _showsAds && !navigationActive && !_fullscreenAdShowingNow;

  /// Wie [_fullscreenBaseAllowed], zusätzlich der globale Mindestabstand
  /// zwischen JEGLICHEN Vollbild-Ads (App-Open + Interstitials). Das
  /// Vor-Fahrt-Video ist davon bewusst AUSGENOMMEN (siehe
  /// [showRewardedBeforeRide]) — es ist das von Vucko priorisierte, vor jeder
  /// Fahrt erwartete Format und wird nur durch seinen eigenen 15-min-Cooldown
  /// begrenzt, nicht durch eine kurz zuvor gezeigte Such-Interstitial.
  bool get _fullscreenAllowedNow {
    if (!_fullscreenBaseAllowed) return false;
    final last = _lastFullscreenAdAt;
    if (last != null &&
        DateTime.now().difference(last).inSeconds <
            MonetizationConfig.fullscreenAdMinGapSec) {
      return false;
    }
    return true;
  }

  bool _placementCooldownOk(String placement, int cooldownSec) {
    final last = _lastShownPerPlacement[placement];
    return last == null ||
        DateTime.now().difference(last).inSeconds >= cooldownSec;
  }

  void _markShown(String placement) {
    final now = DateTime.now();
    _lastFullscreenAdAt = now;
    _lastShownPerPlacement[placement] = now;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Fire-and-forget aus main() — darf den Kaltstart NICHT verzögern
  /// (Gray-Screen-Fix 2026-07-22 nicht regressieren, deshalb kein await
  /// im Startpfad).
  Future<void> initializeSdkOnly() async {
    if (_sdkInitStarted || kIsWeb) return;
    _sdkInitStarted = true;
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
    } catch (e) {
      debugPrint('[AdService] SDK-Init fehlgeschlagen: $e');
    }
  }

  /// Einmalig vom ersten HomePage-Aufbau (postFrameCallback, UNBEDINGT — nicht
  /// hinter irgendeinem Permission-Prompt verkettet). Übergibt den Provider
  /// selbst, damit jeder spätere Check den LIVE-Tier sieht.
  ///
  /// 2026-07-22 (vucko): Das Consent-Formular kommt GENAU EINMAL — egal ob der
  /// Nutzer die App zum ersten Mal öffnet, schon eingeloggt ist oder sie
  /// bereits benutzt hat. Es läuft für JEDEN (auch Paid — es ist eine
  /// rechtliche Einwilligung, keine Werbung), und ERST DANACH darf überhaupt
  /// eine Ad geladen/gezeigt werden. UMP selbst merkt sich die Entscheidung
  /// persistent (`isConsentFormAvailable`/`getConsentStatus`) → beim nächsten
  /// App-Start erscheint es nicht erneut.
  Future<void> onHomeReached(SubscriptionProvider subscription) async {
    _subscription = subscription;
    if (_homeReached || kIsWeb) return;
    _homeReached = true;
    WidgetsBinding.instance.addObserver(this);
    // Consent ZUERST für alle (rechtlich), genau einmal. UMP zeigt das
    // Formular nur, wenn es erforderlich und noch nicht beantwortet ist.
    await _ensureConsent();
    // Ab hier ist Werbung freigegeben — aber nur für Free-Tier laden.
    if (!_showsAds) return;
    if (!await _canRequestAds()) return;
    unawaited(_preloadInterstitial());
    unawaited(_preloadRewarded());
    // Vuckos Wunsch „direkt nach dem Öffnen der App": App-Open laden und —
    // sobald da — EINMAL pro Kaltstart kurz nach Home-Ankunft zeigen. Wurde
    // gerade erst das Consent-Formular gezeigt, überspringen wir das (keine
    // zwei Vollbild-Overlays direkt hintereinander in der ersten Minute).
    await _loadAppOpenAd();
    if (!_consentFormWasShown && _appOpenAd != null) {
      unawaited(maybeShowAppOpenAd(initialLaunch: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_homeReached) return;
    if (!_showsAds) return; // Tier LIVE prüfen — Kauf in der Session zählt.
    unawaited(() async {
      await _ensureConsent();
      if (!await _canRequestAds()) return;
      // Falls der Nutzer erst in dieser Session zu Free wurde (Abo abgelaufen),
      // die Interstitial/Rewarded-Vorräte nachladen.
      unawaited(_preloadInterstitial());
      unawaited(_preloadRewarded());
      if (_appOpenAd == null) {
        await _loadAppOpenAd();
        return; // dieser Resume geht leer aus, der nächste zeigt.
      }
      await maybeShowAppOpenAd();
    }());
  }

  // ── UMP-Consent (EWR-Pflicht) ─────────────────────────────────────────────

  Future<void> _ensureConsent() async {
    if (_consentFlowDone || kIsWeb) return;
    _consentFlowDone = true;
    final completer = Completer<void>();
    // Debug-Builds erzwingen EWR-Geografie (Googles offizieller Test-Weg,
    // Simulatoren sind automatisch Testgeräte): so ist das Consent-Formular
    // beim Entwickeln IMMER prüfbar, unabhängig davon, ob Googles Serving die
    // veröffentlichte Meldung schon propagiert hat. Release nutzt die echte
    // Geo-Erkennung.
    final params = kDebugMode
        ? ConsentRequestParameters(
            consentDebugSettings: ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
            ),
          )
        : ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            final status =
                await ConsentInformation.instance.getConsentStatus();
            if (status == ConsentStatus.required) _consentFormWasShown = true;
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (error != null) {
                debugPrint('[AdService] Consent-Form: ${error.message}');
              }
            });
          }
        } catch (e) {
          debugPrint('[AdService] Consent-Check: $e');
        }
        if (!completer.isCompleted) completer.complete();
      },
      (error) {
        debugPrint('[AdService] Consent-Update: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    // Sicherheitsnetz: der Consent-Flow darf die App nie dauerhaft aufhalten.
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
  }

  Future<bool> _canRequestAds() async {
    if (kIsWeb || !_sdkReady) return false;
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  // ── App-Open ──────────────────────────────────────────────────────────────

  bool get _appOpenStale =>
      _appOpenLoadedAt == null ||
      DateTime.now().difference(_appOpenLoadedAt!) > const Duration(hours: 4);

  Future<void> _loadAppOpenAd() async {
    if (_appOpenAd != null && !_appOpenStale) return;
    if (!await _canRequestAds()) return;
    final completer = Completer<void>();
    await AppOpenAd.load(
      adUnitId: MonetizationConfig.appOpenUnit,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd?.dispose();
          _appOpenAd = ad;
          _appOpenLoadedAt = DateTime.now();
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdService] AppOpen-Load: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  Future<void> maybeShowAppOpenAd({bool initialLaunch = false}) async {
    if (initialLaunch && _appOpenShownThisLaunch) return;
    if (!_fullscreenAllowedNow) return;
    final ad = _appOpenAd;
    if (ad == null || _appOpenStale) {
      unawaited(_loadAppOpenAd());
      return;
    }
    _appOpenAd = null;
    _fullscreenAdShowingNow = true;
    if (initialLaunch) _appOpenShownThisLaunch = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_loadAppOpenAd());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _fullscreenAdShowingNow = false;
      },
    );
    _markShown('app_open');
    try {
      await ad.show();
    } catch (e) {
      _fullscreenAdShowingNow = false;
      debugPrint('[AdService] AppOpen-Show: $e');
    }
  }

  // ── Interstitial (schnell wegdrückbar) ────────────────────────────────────

  Future<void> _preloadInterstitial() async {
    if (_interstitialAd != null) return;
    if (!await _canRequestAds()) return;
    await InterstitialAd.load(
      adUnitId: MonetizationConfig.interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) =>
            debugPrint('[AdService] Interstitial-Load: ${error.message}'),
      ),
    );
  }

  /// Best-effort: zeigt NUR, wenn bereits geladen + alle Gates offen —
  /// blockiert nie. Für Neusuche, Gruppen-Beitritt, Seitenwechsel.
  Future<void> showInterstitialIfReady({
    required String placement,
    int cooldownSec = 0,
  }) async {
    if (!_fullscreenAllowedNow) return;
    if (cooldownSec > 0 && !_placementCooldownOk(placement, cooldownSec)) {
      return;
    }
    final ad = _interstitialAd;
    if (ad == null) {
      unawaited(_preloadInterstitial());
      return;
    }
    _interstitialAd = null;
    _fullscreenAdShowingNow = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_preloadInterstitial());
      },
    );
    _markShown(placement);
    try {
      await ad.show();
    } catch (e) {
      _fullscreenAdShowingNow = false;
      debugPrint('[AdService] Interstitial-Show ($placement): $e');
    }
  }

  // ── Rewarded (Vor-Fahrt-Video, 30-60s) ────────────────────────────────────

  Future<void> _preloadRewarded() async {
    if (_rewardedAd != null) return;
    if (!await _canRequestAds()) return;
    await RewardedAd.load(
      adUnitId: MonetizationConfig.rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) =>
            debugPrint('[AdService] Rewarded-Load: ${error.message}'),
      ),
    );
  }

  /// Vor-Fahrt-Video: wartet auf das ENDE der Wiedergabe (das ist hier
  /// gewollt — Vuckos 30-60s-Werbung vor der Fahrt), aber mit hartem
  /// Sicherheitsnetz: keine geladene Ad / Gates zu / SDK hängt → die Fahrt
  /// startet SOFORT bzw. nach [maxWait]. Die Fahrt ist NIE dauerhaft blockiert.
  Future<void> showRewardedBeforeRide({
    Duration maxWait = const Duration(minutes: 2),
  }) async {
    // BEWUSST _fullscreenBaseAllowed (ohne globalen 90s-Abstand): das
    // Vor-Fahrt-Video soll vor JEDER Fahrt kommen, auch kurz nach einer
    // Such-Interstitial — begrenzt nur durch seinen eigenen 15-min-Cooldown.
    if (!_fullscreenBaseAllowed) return;
    if (!_placementCooldownOk(
      'pre_ride',
      MonetizationConfig.preRideRewardedCooldownSec,
    )) {
      return;
    }
    final ad = _rewardedAd;
    if (ad == null) {
      unawaited(_preloadRewarded());
      return; // nichts geladen → Fahrt startet sofort, nächstes Mal dann.
    }
    _rewardedAd = null;
    _fullscreenAdShowingNow = true;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _fullscreenAdShowingNow = false;
        if (!done.isCompleted) done.complete();
        unawaited(_preloadRewarded());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _fullscreenAdShowingNow = false;
        if (!done.isCompleted) done.complete();
        unawaited(_preloadRewarded());
      },
    );
    _markShown('pre_ride');
    try {
      await ad.show(onUserEarnedReward: (ad, reward) {});
      await done.future.timeout(maxWait, onTimeout: () {
        _fullscreenAdShowingNow = false;
      });
    } catch (e) {
      _fullscreenAdShowingNow = false;
      debugPrint('[AdService] Rewarded-Show: $e');
    }
  }
}
