import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/monetization_config.dart';

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
    _ad = NativeAd(
      adUnitId: MonetizationConfig.nativeUnit,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType:
            widget.compact ? TemplateType.small : TemplateType.medium,
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
      // 2026-07-22 (vucko Werbe-Test): AdMob-Native-Validator meldete bei 120pt
      // "MediaView is too small for video" (Google verlangt >=120x120pt NUR für
      // die MediaView selbst — bei TemplateType.small frisst Padding/Text um
      // die MediaView herum vom Gesamt-Container etwas ab). 160pt gibt genug
      // Reserve, ohne im Dashboard sperrig zu wirken.
      height: widget.compact ? 160 : 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AdWidget(ad: ad),
    );
  }
}
