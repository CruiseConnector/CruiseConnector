import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/monetization_config.dart';
import '../../../data/services/ad_service.dart';

/// Native AdMob-Anzeige im Look der Feed-Karten („Posts") bzw. als kompaktes
/// Widget fürs Home-Dashboard.
///
/// 2026-07-22 (vucko „auch als Widgets/Posts überall"): Nutzt Googles
/// NativeTemplateStyle (medium/small) — rein Dart-seitig, KEINE nativen
/// Factories nötig (google_mobile_ads >=5 rendert das Template inkl.
/// automatisch lokalisiertem „Anzeige"-Badge selbst; das Badge darf laut
/// Policy nie überdeckt werden). Verhalten wie House-Ads: Werbung ist nie
/// ein Fehlerfall — lädt die Ad nicht, verschwindet der Slot einfach
/// (SizedBox.shrink), kein Spinner, kein Fehltext. Der Aufrufer gated auf
/// SubscriptionProvider.showsAds — Paid-Nutzer bekommen dieses Widget gar
/// nicht erst gebaut.
class AdPostCard extends StatefulWidget {
  const AdPostCard({
    super.key,
    required this.placementKey,
    this.compact = false,
  });

  /// Debug-/Tracking-Schlüssel, z.B. 'discover_3' oder 'home_dashboard'.
  final String placementKey;

  /// true = kleines Template (Home-Dashboard), false = Feed-Post-Größe.
  final bool compact;

  @override
  State<AdPostCard> createState() => _AdPostCardState();
}

class _AdPostCardState extends State<AdPostCard> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // 2026-07-25 (Werbe-Audit): NICHT sofort laden. Auf dem Kaltstart baut das
    // Dashboard diese Karte im ERSTEN Frame — der UMP-Consent-Flow startet aber
    // erst im postFrameCallback danach. Ohne dieses await ging die allererste
    // Native-Anfrage ohne Einwilligung raus (DSGVO/AdMob-Policy-Verstoß).
    unawaited(_loadWhenAllowed());
  }

  Future<void> _loadWhenAllowed() async {
    final allowed = await AdService.instance.awaitNativeAdAllowed();
    if (!allowed || !mounted) return;
    _ad = NativeAd(
      adUnitId: MonetizationConfig.nativeUnit,
      request: const AdRequest(),
      // 2026-07-23 (vucko AdMob-Validator „MediaView too small"): TemplateType
      // .small hatte AUCH bei 160pt Container-Höhe noch eine zu kleine interne
      // MediaView für Video-Creatives (small ist auf eine kompakte
      // Icon-Anzeige ausgelegt, nicht auf Video). .medium garantiert
      // durchgängig eine großzügige MediaView — deshalb jetzt IMMER medium,
      // nur die AUSSEN-Höhe unterscheidet noch kompakt/normal.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF12151C),
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFFFF4438),
        ),
        primaryTextStyle: NativeTemplateTextStyle(textColor: Colors.white),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white.withValues(alpha: 0.55),
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white.withValues(alpha: 0.35),
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      // 2026-07-23 (vucko AdMob-Validator „Advertiser assets outside native
      // ad view"): Googles eigene Doku (developers.google.com/ad-manager/
      // mobile-ads-sdk/flutter/native/templates) nennt für TemplateType
      // .medium eine Mindesthöhe von 320pt (max. 400pt) — 240pt lag DARUNTER,
      // dadurch ragten interne Assets (z.B. der CTA-Button) über den
      // Container hinaus. 320pt ist jetzt exakt Googles Mindestwert.
      height: widget.compact ? 320 : 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AdWidget(ad: ad),
    );
  }
}
