import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/monetization_config.dart';
import '../../data/services/auth_service.dart';

/// Abo-Stufen. Reihenfolge = aufsteigende Berechtigung.
enum SubTier { free, basic, premium }

SubTier subTierFromString(String? s) {
  switch (s) {
    case 'premium':
      return SubTier.premium;
    case 'basic':
      return SubTier.basic;
    default:
      return SubTier.free;
  }
}

/// Zentrale Quelle für den Abo-Status + Feature-Freischaltung.
///
/// Reihenfolge der Wahrheit:
///   1. RevenueCat customerInfo (sofort, on-device) — wenn konfiguriert.
///   2. Server-Fallback `get_my_entitlement` (profiles.subscription_tier).
/// So funktioniert die App auch, solange RevenueCat noch nicht angebunden ist
/// (dann steht der Server-Tier, Käufe sind deaktiviert).
class SubscriptionProvider extends ChangeNotifier {
  SubTier _tier = SubTier.free;
  bool _purchasesReady = false;
  bool _initialized = false;
  Offerings? _offerings;
  StreamSubscription<AuthState>? _authSub;
  final StreamController<void> _downgradeToFreeController =
      StreamController<void>.broadcast();

  /// 2026-07-23 (vucko "Downgrade auf Free setzt Änderungen zurück"): feuert
  /// GENAU dann, wenn der Tier von Basic/Premium auf Free wechselt (Abo
  /// abgelaufen/gekündigt) — Hörer (z.B. HomeContentPage) können darauf mit
  /// einem Reset ihrer Free-inkompatiblen Anpassungen reagieren (z.B.
  /// Dashboard-Layout auf Standard zurücksetzen).
  Stream<void> get downgradeToFreeEvents => _downgradeToFreeController.stream;

  /// Zentrale Stelle für JEDE Tier-Änderung — nie direkt `_tier = ...`
  /// zuweisen, damit Downgrade-Erkennung garantiert überall greift.
  void _setTier(SubTier newTier) {
    final wasPaid = _tier != SubTier.free;
    _tier = newTier;
    if (wasPaid && newTier == SubTier.free) {
      _downgradeToFreeController.add(null);
    }
  }

  SubTier get tier => _tier;
  bool get isFree => _tier == SubTier.free;
  bool get isBasic => _tier == SubTier.basic;
  bool get isPremium => _tier == SubTier.premium;
  bool get isPaid => _tier != SubTier.free;
  bool get initialized => _initialized;

  /// Kauf möglich (RevenueCat konfiguriert + erreichbar).
  bool get purchasesAvailable => _purchasesReady;
  Offerings? get offerings => _offerings;

  // ── Feature-Capabilities (eine Stelle für die ganze App) ────────────────
  /// Werbung nur für Free-Nutzer.
  bool get showsAds => _tier == SubTier.free;

  /// Volle Fahr-Statistiken (km/Zeit/XP/Charts) erst ab Basic.
  /// Free sieht Rangliste + Badges, aber NICHT die eigenen Fahr-Zahlen.
  bool get canSeeDrivingStats => _tier != SubTier.free;

  /// Eigene Communities erstellen ist Premium-exklusiv — Free/Basic können
  /// nur beitreten. Server-seitiges Gating (Trigger, Design fertig) folgt
  /// erst nach Rollout dieser App-Version, das hier ist nur der Client-Teil.
  bool get canCreateCommunity => _tier == SubTier.premium;

  /// Max. Mitgliederzahl für eigene Gruppen-Fahrten: Free kann keine Gruppe
  /// erstellen (nur beitreten), Basic bis 5, Premium bis 25.
  int get maxGroupSize => switch (_tier) {
        SubTier.free => 0,
        SubTier.basic => 5,
        SubTier.premium => 25,
      };

  /// Rundkurs-Länge frei wählbar (75/100 km) erst ab Basic — Free ist auf
  /// 25/50 km begrenzt.
  bool get canUseAllRouteDistances => isPaid;

  /// Alle Fahrstile (Kurvenjagd/Abendrunde/Entdecker) erst ab Basic — Free
  /// bekommt nur Sport Mode.
  bool get canUseAllRouteModes => isPaid;

  /// Inlandsfilter ("Im Land bleiben") ist ein Basic-Feature.
  bool get canUseInlandsfilter => isPaid;

  /// Rangliste ist für alle sichtbar.
  bool get canSeeLeaderboard => true;

  /// Badges sind für alle sichtbar.
  bool get canSeeBadges => true;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _readServerTier();
    await _configureRevenueCat();
    // Ohne das hier bleibt RevenueCat nach einem Login innerhalb derselben
    // Session auf der anonymen appUserID (vom configure()-Aufruf ganz oben,
    // als currentUser evtl. noch null war) — Käufe direkt nach Onboarding
    // würden dann nie dem echten Supabase-User zugeordnet. Nur auf echte
    // Identitätswechsel reagieren, nicht auf jeden Token-Refresh.
    _authSub = AuthService.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.signedOut) {
        unawaited(refreshForUser());
      }
    });
    notifyListeners();
  }

  /// Nach Login/Logout erneut binden.
  Future<void> refreshForUser() async {
    await _readServerTier();
    if (_purchasesReady) {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      try {
        if (uid != null) {
          await Purchases.logIn(uid);
        } else {
          await Purchases.logOut();
        }
        _applyCustomerInfo(await Purchases.getCustomerInfo());
      } catch (_) {/* server tier bleibt */}
    }
    notifyListeners();
  }

  Future<void> _readServerTier() async {
    try {
      final res = await Supabase.instance.client.rpc('get_my_entitlement');
      final map = res is Map ? res : <String, dynamic>{};
      _setTier(subTierFromString(map['tier'] as String?));
    } catch (_) {/* offline / nicht eingeloggt → free */}
    _applyDebugTierOverride();
  }

  /// 2026-07-22 (vucko Werbe-Test): NUR Debug-Builds + explizites
  /// `--dart-define=DEBUG_FORCE_TIER=free|basic|premium` — erzwingt einen
  /// Tier, ohne echte Accounts/DB anzufassen. Zum Testen von Werbung und
  /// Abo-Sperren am Simulator/Testgerät. In Release-Builds wirkungslos.
  void _applyDebugTierOverride() {
    if (!kDebugMode) return;
    const forced = String.fromEnvironment('DEBUG_FORCE_TIER');
    if (forced.isNotEmpty) _setTier(subTierFromString(forced));
  }

  Future<void> _configureRevenueCat() async {
    if (!MonetizationConfig.purchasesConfigured) {
      _purchasesReady = false;
      return;
    }
    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(MonetizationConfig.revenueCatKey));
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Purchases.logIn(uid);
      }
      _purchasesReady = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _applyCustomerInfo(await Purchases.getCustomerInfo());
      _offerings = await Purchases.getOfferings();
    } catch (e) {
      debugPrint('[Subscription] RevenueCat init failed: $e');
      _purchasesReady = false;
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    _applyCustomerInfo(info);
    notifyListeners();
  }

  void _applyCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active;
    if (active.containsKey(MonetizationConfig.entitlementPremium)) {
      _setTier(SubTier.premium);
    } else if (active.containsKey(MonetizationConfig.entitlementBasic)) {
      _setTier(SubTier.basic);
    } else {
      _setTier(SubTier.free);
    }
  }

  /// 2026-07-23 (vucko "Kauf funktioniert nicht, keine Fehlermeldung"): vorher
  /// verschwand jeder Kauf-Fehler (außer Abbruch) nur in debugPrint — für den
  /// Nutzer sah ein z.B. wegen "erstes Abo noch nicht bei Apple freigegeben"
  /// fehlschlagender Kauf aus wie ein Hänger, ohne jeden Hinweis warum.
  String? _lastPurchaseError;
  String? get lastPurchaseError => _lastPurchaseError;

  /// Kauft ein Paket. Gibt true zurück, wenn danach ein bezahlter Tier aktiv ist.
  Future<bool> purchasePackage(Package package) async {
    if (!_purchasesReady) {
      _lastPurchaseError = 'Käufe sind noch nicht eingerichtet.';
      return false;
    }
    _lastPurchaseError = null;
    try {
      final info = await Purchases.purchasePackage(package);
      _applyCustomerInfo(info);
      notifyListeners();
      return isPaid;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return false; // Nutzer hat selbst abgebrochen — kein Fehler anzeigen.
      }
      _lastPurchaseError = _describePurchaseError(code);
      debugPrint('[Subscription] purchase error: $code');
      return false;
    } catch (e) {
      _lastPurchaseError = 'Kauf ist fehlgeschlagen. Bitte später erneut versuchen.';
      debugPrint('[Subscription] purchase failed: $e');
      return false;
    }
  }

  String _describePurchaseError(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'Dieses Abo ist im Store noch nicht verfügbar. Versuch es später nochmal.';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Käufe sind für diesen Account/dieses Gerät aktuell gesperrt.';
      case PurchasesErrorCode.networkError:
        return 'Keine Verbindung zum Store — prüf dein Internet.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Zahlung wird noch bestätigt.';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'Du hast dieses Abo bereits.';
      default:
        return 'Kauf ist fehlgeschlagen ($code). Bitte später erneut versuchen.';
    }
  }

  Future<void> restore() async {
    if (!_purchasesReady) return;
    try {
      _applyCustomerInfo(await Purchases.restorePurchases());
      notifyListeners();
    } catch (e) {
      debugPrint('[Subscription] restore failed: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _downgradeToFreeController.close();
    if (_purchasesReady) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    super.dispose();
  }
}
