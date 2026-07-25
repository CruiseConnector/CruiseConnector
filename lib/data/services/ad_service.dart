import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../application/providers/subscription_provider.dart';
import '../../core/monetization_config.dart';
import 'tts_service.dart';

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
  Future<void>? _sdkInitFuture;
  bool _sdkReady = false;
  bool _consentFlowDone = false;
  bool _consentFormWasShown = false;
  /// Wird erfüllt, sobald SDK-Init + UMP-Consent durch sind. Native Ads
  /// (Feed/Dashboard) laden sich selbst und müssen darauf warten können.
  final Completer<void> _adsUnblocked = Completer<void>();
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
  /// im Startpfad dort).
  ///
  /// 2026-07-23 (vucko „App-Open fehlt beim Kaltstart"): Das Future wird
  /// GETEILT statt nur einmal gestartet — vorher verhinderte ein simpler
  /// bool-Guard, dass ein ZWEITER Aufrufer (onHomeReached) auf den bereits
  /// laufenden Init warten konnte; er bekam sofort zurück, MobileAds sei
  /// „noch nicht bereit" und brach die komplette Ad-Lade-Kette für diesen
  /// Kaltstart ab. Der native SDK-Init läuft parallel zu Supabase-Init & Co.
  /// und ist auf einem echten Gerät oft noch nicht fertig, wenn HomePage
  /// zuerst gebaut wird — ohne echtes Warten kam die App-Open-Ad dann frühestens
  /// beim NÄCHSTEN Resume (App-Wechsel), nie beim tatsächlichen Neustart.
  Future<void> initializeSdkOnly() {
    if (kIsWeb) return Future.value();
    return _sdkInitFuture ??= _doInitializeSdk();
  }

  Future<void> _doInitializeSdk() async {
    try {
      // Testgeraete VOR dem Init registrieren (sonst greift es erst ab dem
      // naechsten Request). Leere Liste = No-Op fuer echte Nutzer.
      final testDevices = MonetizationConfig.testDeviceIds;
      if (testDevices.isNotEmpty) {
        MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: testDevices),
        );
        debugPrint(
          '[AdService] ${testDevices.length} Testgeraet(e) registriert — '
          'Impressions dieses Geraets werden NICHT abgerechnet.',
        );
      }
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
    // 2026-07-23 (vucko „App-Open fehlt beim Kaltstart"): ECHT auf den SDK-Init
    // warten (nicht nur hoffen, dass er bis hierhin schon fertig ist) — auf
    // einem echten Gerät läuft er parallel zu Supabase-Init & Co. und ist beim
    // allerersten Home-Aufbau oft noch nicht fertig.
    await initializeSdkOnly();
    // Consent ZUERST für alle (rechtlich), genau einmal. UMP zeigt das
    // Formular nur, wenn es erforderlich und noch nicht beantwortet ist.
    await _ensureConsent();
    // Apple-ATT NACH dem UMP-Formular (Googles empfohlene Reihenfolge: erst die
    // DSGVO-Einwilligung inkl. IDFA-Erklärtext, dann Apples Systemdialog).
    await _ensureAppTrackingTransparency();
    if (!_adsUnblocked.isCompleted) _adsUnblocked.complete();
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
      // Randfall: Resume feuert, WÄHREND der Kaltstart-onHomeReached-Ablauf
      // noch selbst am Warten ist (Nutzer wechselt sofort die App) — idempotent,
      // kein Schaden falls schon fertig.
      await initializeSdkOnly();
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

  /// Für selbstladende Formate (Native Ads im Feed/Dashboard): wartet auf
  /// SDK-Init + UMP-Consent und meldet dann, ob überhaupt angefragt werden darf.
  ///
  /// 2026-07-25 (Werbe-Audit): [AdPostCard] rief `NativeAd.load()` bisher direkt
  /// aus `initState()` — auf dem Kaltstart also im ERSTEN Frame und damit noch
  /// bevor [onHomeReached] (postFrameCallback) den Consent-Flow überhaupt
  /// gestartet hatte. Das verletzte Regel 4 des Service-Kontrakts (EWR-Consent
  /// ZUERST) ausgerechnet beim sichtbarsten Format.
  Future<bool> awaitNativeAdAllowed() async {
    if (kIsWeb) return false;
    await initializeSdkOnly();
    if (!_adsUnblocked.isCompleted) {
      // Sicherheitsnetz: hängt onHomeReached (kein Netz o.ä.), bleibt der Slot
      // einfach leer statt die Karte ewig zu blockieren.
      await _adsUnblocked.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {},
      );
    }
    if (!_showsAds) return false;
    return _canRequestAds();
  }

  /// Apples App-Tracking-Transparency-Dialog (nur iOS, nur einmal je Install).
  ///
  /// 2026-07-25 (Werbe-Audit): Fehlte komplett. `NSUserTrackingUsageDescription`
  /// stand zwar in der Info.plist, aber der Text allein loest keinen Dialog aus
  /// — ohne den Aufruf hier laeuft iOS dauerhaft im Zustand „Tracking nicht
  /// erlaubt", das GMA-SDK bekommt keine IDFA und liefert ausschliesslich
  /// unpersonalisierte Anzeigen. Deren eCPM liegt deutlich unter dem
  /// personalisierter Anzeigen — auf der Live-Plattform iOS war das der
  /// groesste verbliebene Umsatzverlust.
  ///
  /// Bewusst NICHT blockierend fuer die App: Antwortet der Nutzer nicht,
  /// laeuft es nach 15s weiter (dann eben unpersonalisiert).
  Future<void> _ensureAppTrackingTransparency() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) return;
      // Kurze Pause: Apple verwirft den Dialog, wenn die App im selben Moment
      // noch nicht vollstaendig im Vordergrund ist (bekannte ATT-Falle).
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await AppTrackingTransparency.requestTrackingAuthorization()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[AdService] ATT: $e');
    }
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
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_loadAppOpenAd());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
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
  ///
  /// 2026-07-25 (vucko „beim Seitenwechsel kommt keine Werbung"): Gibt jetzt
  /// zurueck, ob tatsaechlich eine Ad gezeigt wurde. Der Seitenwechsel-Zaehler
  /// setzte sich vorher auch dann zurueck, wenn hier ein Gate blockierte — der
  /// Nutzer musste dann wieder von vorn zaehlen und traf den naechsten Versuch
  /// oft erneut im Cooldown. Ergebnis: praktisch nie eine Seitenwechsel-Ad.
  Future<bool> showInterstitialIfReady({
    required String placement,
    int cooldownSec = 0,
  }) async {
    if (!_fullscreenAllowedNow) return false;
    if (cooldownSec > 0 && !_placementCooldownOk(placement, cooldownSec)) {
      return false;
    }
    final ad = _interstitialAd;
    if (ad == null) {
      unawaited(_preloadInterstitial());
      return false;
    }
    _interstitialAd = null;
    _fullscreenAdShowingNow = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
        a.dispose();
        _fullscreenAdShowingNow = false;
        unawaited(_preloadInterstitial());
      },
    );
    _markShown(placement);
    try {
      await ad.show();
      return true;
    } catch (e) {
      _fullscreenAdShowingNow = false;
      debugPrint('[AdService] Interstitial-Show ($placement): $e');
      return false;
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
  /// gewollt — Vuckos 30-60s-Werbung vor der Fahrt). BEWUSST
  /// `bypassGlobalGap: true`: das Vor-Fahrt-Video soll vor JEDER Fahrt
  /// kommen, auch kurz nach einer Such- oder Beitritts-Ad — begrenzt nur
  /// durch seinen eigenen 15-min-Cooldown, nicht durch den globalen
  /// Vollbild-Mindestabstand.
  Future<void> showRewardedBeforeRide({
    Duration maxWait = const Duration(minutes: 2),
    void Function(int secondsLeft)? onTick,
  }) {
    return showRewardedVideo(
      placement: 'pre_ride',
      cooldownSec: MonetizationConfig.preRideRewardedCooldownSec,
      maxWait: maxWait,
      bypassGlobalGap: true,
      // 2026-07-23 (vucko "immer 30-60s, nicht überspringbar beim Fahren"):
      // Google gibt uns KEINE Kontrolle über die Creative-Länge oder die
      // Skip-Button-Sperre der Ad selbst (offizielle Doku: 5-30s Countdown,
      // rein vom Creative bestimmt) — das hier erzwingt die Absicht
      // clientseitig: die Gesamtzeit (Ad-Wiedergabe + ggf. Restwartezeit
      // danach) ist IMMER mindestens 30s, egal wie früh der Nutzer die
      // (nicht entfernbare) Skip-Taste der Ad selbst drückt. Gilt nur, wenn
      // tatsächlich eine Ad geladen war — ohne Ad startet die Fahrt wie
      // gehabt sofort (Grundsatz oben: Werbung blockiert nie eine Aktion).
      minTotalDuration: const Duration(seconds: 30),
      onTick: onTick,
    );
  }

  /// 2026-07-23 (vucko): generisches 30s-Rewarded-Video für JEDE Aktion, die
  /// eins zeigen soll (Vor-Fahrt, Routensuche, Gruppen-Beitritt, ...) — wartet
  /// auf das ENDE der Wiedergabe, aber mit hartem Sicherheitsnetz: keine
  /// geladene Ad / Gates zu / SDK hängt → die Aktion läuft SOFORT bzw. nach
  /// [maxWait] weiter. Die Aktion selbst ist NIE dauerhaft blockiert.
  Future<void> showRewardedVideo({
    required String placement,
    required int cooldownSec,
    Duration maxWait = const Duration(minutes: 2),
    bool bypassGlobalGap = false,
    Duration? minTotalDuration,
    void Function(int secondsLeft)? onTick,
  }) async {
    final allowed = bypassGlobalGap ? _fullscreenBaseAllowed : _fullscreenAllowedNow;
    if (!allowed) return;
    if (!_placementCooldownOk(placement, cooldownSec)) return;
    final ad = _rewardedAd;
    if (ad == null) {
      unawaited(_preloadRewarded());
      return; // nichts geladen → Aktion läuft sofort weiter, nächstes Mal dann.
    }
    _rewardedAd = null;
    _fullscreenAdShowingNow = true;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
        a.dispose();
        _fullscreenAdShowingNow = false;
        if (!done.isCompleted) done.complete();
        unawaited(_preloadRewarded());
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        // 2026-07-25 (vucko Ducking-Fix): AdMob hat auf iOS die
        // AVAudioSession uebernommen (.ambient = kein Ducking) — sofort
        // zurueckholen, sonst duckt keine Navi-Ansage mehr bis App-Neustart.
        unawaited(TtsService.instance.reclaimAudioSession());
        a.dispose();
        _fullscreenAdShowingNow = false;
        if (!done.isCompleted) done.complete();
        unawaited(_preloadRewarded());
      },
    );
    _markShown(placement);
    final shownAt = DateTime.now();
    try {
      await ad.show(onUserEarnedReward: (ad, reward) {});
      await done.future.timeout(maxWait, onTimeout: () {
        _fullscreenAdShowingNow = false;
      });
    } catch (e) {
      _fullscreenAdShowingNow = false;
      debugPrint('[AdService] Rewarded-Show ($placement): $e');
    }
    if (minTotalDuration != null) {
      final remaining = minTotalDuration - DateTime.now().difference(shownAt);
      if (remaining > Duration.zero) {
        await _waitWithTicks(remaining, onTick);
        return;
      }
    }
    onTick?.call(0);
  }

  /// Zählt in 1s-Schritten von [remaining] auf 0 herunter und ruft dabei
  /// [onTick] auf — reine UI-Rückmeldung fürs "Startklar in Xs..."-Overlay,
  /// blockiert selbst nichts anderes als den Aufrufer, der bewusst darauf wartet.
  Future<void> _waitWithTicks(
    Duration remaining,
    void Function(int secondsLeft)? onTick,
  ) async {
    var wholeSecondsLeft = (remaining.inMilliseconds / 1000).ceil();
    onTick?.call(wholeSecondsLeft);
    while (wholeSecondsLeft > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      wholeSecondsLeft--;
      onTick?.call(wholeSecondsLeft);
    }
  }
}
