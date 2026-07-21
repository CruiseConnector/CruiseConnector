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
      _tier = subTierFromString(map['tier'] as String?);
    } catch (_) {/* offline / nicht eingeloggt → free */}
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
      _tier = SubTier.premium;
    } else if (active.containsKey(MonetizationConfig.entitlementBasic)) {
      _tier = SubTier.basic;
    } else {
      _tier = SubTier.free;
    }
  }

  /// Kauft ein Paket. Gibt true zurück, wenn danach ein bezahlter Tier aktiv ist.
  Future<bool> purchasePackage(Package package) async {
    if (!_purchasesReady) return false;
    try {
      final info = await Purchases.purchasePackage(package);
      _applyCustomerInfo(info);
      notifyListeners();
      return isPaid;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code != PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('[Subscription] purchase error: $code');
      }
      return false;
    } catch (e) {
      debugPrint('[Subscription] purchase failed: $e');
      return false;
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
    if (_purchasesReady) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    super.dispose();
  }
}
