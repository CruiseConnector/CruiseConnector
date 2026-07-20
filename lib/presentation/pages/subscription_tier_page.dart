import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../application/providers/subscription_provider.dart';

/// Ästhetische Abo-Auswahl (Free / Basic / Premium).
///
/// Wird nach dem Onboarding gezeigt (`isOnboarding: true`) und aus den
/// Einstellungen ("Abonnement verwalten"). Preise kommen live aus dem Store
/// (RevenueCat-Offerings), sobald angebunden; sonst als Vorschau.
class SubscriptionTierPage extends StatefulWidget {
  final bool isOnboarding;
  const SubscriptionTierPage({super.key, this.isOnboarding = false});

  @override
  State<SubscriptionTierPage> createState() => _SubscriptionTierPageState();
}

class _TierSpec {
  final SubTier tier;
  final String name;
  final String tagline;
  final List<(bool, String)> features; // (enthalten?, Text)
  final String entitlement; // RevenueCat-Entitlement/Package-Hinweis
  final bool highlight;
  const _TierSpec(
    this.tier,
    this.name,
    this.tagline,
    this.features,
    this.entitlement, {
    this.highlight = false,
  });
}

// EINE gemeinsame Feature-Reihenfolge für alle drei Karten (statt pro Tier
// unterschiedlicher Texte) — macht den Unterschied zwischen den Stufen auf
// den ersten Blick vergleichbar: gleiche Zeile, mal grüner Haken, mal rotes
// X. Je höher der Tier, desto länger die grüne Haken-Kette (Value-Stacking) —
// Premium hat als einziger Tier alle Haken, das ist der eigentliche Kaufanreiz.
const _tiers = <_TierSpec>[
  _TierSpec(SubTier.free, 'Free', 'Zum Reinschnuppern – mit Werbung', [
    (true, 'Routen generieren & cruisen'),
    (true, 'Rangliste & Badges'),
    (true, 'Gruppen & Communities beitreten'),
    (false, 'Eigene Gruppen-Fahrten erstellen (bis zu 5 Mitglieder)'),
    (false, 'Fahr-Statistiken (km, Zeit, XP, Charts)'),
    (false, 'Komplett werbefrei'),
    (false, 'Prioritäts-Routing'),
    (false, 'Unbegrenzt gespeicherte Routen'),
    (false, 'Jahres-Vergleich & persönliche Bestzeiten'),
    (false, 'Bis zu 25 Mitglieder pro Gruppen-Fahrt'),
    (false, 'Eigene Communities erstellen'),
  ], 'free'),
  _TierSpec(SubTier.basic, 'Basic', 'Für echte Cruiser – komplett werbefrei', [
    (true, 'Routen generieren & cruisen'),
    (true, 'Rangliste & Badges'),
    (true, 'Gruppen & Communities beitreten'),
    (true, 'Eigene Gruppen-Fahrten erstellen (bis zu 5 Mitglieder)'),
    (true, 'Fahr-Statistiken (km, Zeit, XP, Charts)'),
    (true, 'Komplett werbefrei'),
    (true, 'Prioritäts-Routing'),
    (false, 'Unbegrenzt gespeicherte Routen'),
    (false, 'Jahres-Vergleich & persönliche Bestzeiten'),
    (false, 'Bis zu 25 Mitglieder pro Gruppen-Fahrt'),
    (false, 'Eigene Communities erstellen'),
  ], 'basic', highlight: true),
  _TierSpec(SubTier.premium, 'Premium', 'Das volle Programm', [
    (true, 'Routen generieren & cruisen'),
    (true, 'Rangliste & Badges'),
    (true, 'Gruppen & Communities beitreten'),
    (true, 'Eigene Gruppen-Fahrten erstellen (bis zu 5 Mitglieder)'),
    (true, 'Fahr-Statistiken (km, Zeit, XP, Charts)'),
    (true, 'Komplett werbefrei'),
    (true, 'Prioritäts-Routing'),
    (true, 'Unbegrenzt gespeicherte Routen'),
    (true, 'Jahres-Vergleich & persönliche Bestzeiten'),
    (true, 'Bis zu 25 Mitglieder pro Gruppen-Fahrt'),
    (true, 'Eigene Communities erstellen'),
  ], 'premium'),
];

enum _Billing { monthly, yearly }

class _SubscriptionTierPageState extends State<SubscriptionTierPage> {
  SubTier _selected = SubTier.basic;
  _Billing _billing = _Billing.monthly;
  bool _busy = false;

  Color get _accent => Theme.of(context).colorScheme.primary;

  /// Passendes Package für (Tier, Abrechnungszeitraum) finden.
  ///
  /// Primär über RevenueCats [Package.packageType] — der wird von RevenueCat
  /// direkt aus der echten Store-Laufzeit des Produkts abgeleitet, ist also
  /// unabhängig davon, wie die Produkt-/Package-IDs benannt sind. Fallback:
  /// Namens-Heuristik (falls RevenueCat den Typ mal nicht erkennt, z.B. bei
  /// rein custom benannten Packages ohne Store-Metadaten).
  Package? _packageFor(SubscriptionProvider sub, String entitlement, _Billing billing) {
    final offering = sub.offerings?.current;
    if (offering == null) return null;
    final wantType = billing == _Billing.yearly ? PackageType.annual : PackageType.monthly;
    Package? byType;
    Package? byName;
    for (final p in offering.availablePackages) {
      final id = p.identifier.toLowerCase();
      final prod = p.storeProduct.identifier.toLowerCase();
      if (!(id.contains(entitlement) || prod.contains(entitlement))) continue;
      if (p.packageType == wantType) byType ??= p;
      final nameMatch = billing == _Billing.yearly
          ? (id.contains('year') || id.contains('annual') || prod.contains('year') || prod.contains('annual'))
          : (id.contains('month') || prod.contains('month'));
      if (nameMatch) byName ??= p;
    }
    return byType ?? byName;
  }

  String _priceFor(SubscriptionProvider sub, _TierSpec spec) {
    if (spec.tier == SubTier.free) return 'Kostenlos';
    final pkg = _packageFor(sub, spec.entitlement, _billing);
    if (pkg != null) {
      final suffix = _billing == _Billing.yearly ? '/ Jahr' : '/ Monat';
      return '${pkg.storeProduct.priceString} $suffix';
    }
    return sub.purchasesAvailable ? '—' : 'Preis im Store';
  }

  /// Ersparnis-Chip fürs Jahres-Abo (z.B. "−17%"), aus den echten Store-
  /// Preisen berechnet — null wenn (noch) nicht beide Laufzeiten vorliegen.
  String? _yearlySavings(SubscriptionProvider sub, _TierSpec spec) {
    if (_billing != _Billing.yearly) return null;
    final monthly = _packageFor(sub, spec.entitlement, _Billing.monthly);
    final yearly = _packageFor(sub, spec.entitlement, _Billing.yearly);
    if (monthly == null || yearly == null) return null;
    final monthlyCost = monthly.storeProduct.price * 12;
    final yearlyCost = yearly.storeProduct.price;
    if (monthlyCost <= 0 || yearlyCost <= 0 || yearlyCost >= monthlyCost) return null;
    final pct = ((1 - (yearlyCost / monthlyCost)) * 100).round();
    return pct > 0 ? '−$pct%' : null;
  }

  Future<void> _choose(SubscriptionProvider sub, _TierSpec spec) async {
    if (spec.tier == SubTier.free) {
      _finish(false);
      return;
    }
    final pkg = _packageFor(sub, spec.entitlement, _billing);
    if (pkg == null || !sub.purchasesAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Abos werden gerade eingerichtet — schau gleich nochmal vorbei.'),
      ));
      return;
    }
    setState(() => _busy = true);
    final ok = await sub.purchasePackage(pkg);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _finish(true);
    }
  }

  void _finish(bool purchased) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(purchased);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_accent.withValues(alpha: 0.32), Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isOnboarding)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => _finish(false),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ),
                  const Text('🚀', style: TextStyle(fontSize: 30)),
                  const SizedBox(height: 10),
                  const Text('Wähle deinen Plan',
                      style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(height: 6),
                  Text('Jederzeit kündbar. Mehr Features, keine Werbung.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13.5)),
                ],
              ),
            ),
            _billingSwitch(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  for (final spec in _tiers) _tierCard(sub, spec, cs),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // Bottom actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _choose(sub, _tiers.firstWhere((t) => t.tier == _selected)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              _selected == SubTier.free
                                  ? 'Mit Free starten'
                                  : 'Weiter mit ${_tiers.firstWhere((t) => t.tier == _selected).name}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.isOnboarding)
                        TextButton(
                          onPressed: _busy ? null : () => _finish(false),
                          child: Text('Später', style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
                        ),
                      TextButton(
                        onPressed: _busy || !sub.purchasesAvailable ? null : () => sub.restore(),
                        child: Text('Käufe wiederherstellen',
                            style: TextStyle(color: Colors.white.withValues(alpha: sub.purchasesAvailable ? 0.7 : 0.3))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Monatlich/Jährlich-Umschalter — gilt für Basic UND Premium gemeinsam,
  /// damit immer nur genau 2 Karten sichtbar sind (nicht 4 einzelne Optionen).
  Widget _billingSwitch() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(child: _billingSegment(_Billing.monthly, 'Monatlich')),
          Expanded(child: _billingSegment(_Billing.yearly, 'Jährlich')),
        ],
      ),
    );
  }

  Widget _billingSegment(_Billing value, String label) {
    final selected = _billing == value;
    return GestureDetector(
      onTap: () => setState(() => _billing = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _tierCard(SubscriptionProvider sub, _TierSpec spec, ColorScheme cs) {
    final selected = _selected == spec.tier;
    final current = sub.tier == spec.tier;
    return GestureDetector(
      onTap: () => setState(() => _selected = spec.tier),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(spec.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                if (spec.tier == SubTier.premium) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.workspace_premium_rounded, size: 17, color: Color(0xFFFFC94D)),
                ],
                const SizedBox(width: 8),
                if (spec.highlight)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(999)),
                    child: const Text('BELIEBT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                if (current)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                    child: const Text('AKTIV', style: TextStyle(color: Color(0xFF3fb950), fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                const Spacer(),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? _accent : Colors.white24, size: 22),
              ],
            ),
            const SizedBox(height: 2),
            Text(spec.tagline, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(_priceFor(sub, spec),
                    style: TextStyle(color: spec.tier == SubTier.free ? Colors.white70 : _accent, fontSize: 17, fontWeight: FontWeight.w800)),
                if (_yearlySavings(sub, spec) != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3fb950).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_yearlySavings(sub, spec)!,
                        style: const TextStyle(color: Color(0xFF3fb950), fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            for (final f in spec.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Enthalten = grüner Haken; NICHT enthalten = rotes X —
                    // Verlust-Framing ("das verpasst du") wirkt stärker als
                    // ein neutrales Schloss-Icon und macht den Unterschied
                    // zwischen den Karten auf einen Blick lesbar.
                    Icon(f.$1 ? Icons.check_circle : Icons.cancel,
                        size: 17, color: f.$1 ? const Color(0xFF3fb950) : Colors.redAccent.withValues(alpha: 0.85)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.$2,
                          style: TextStyle(
                              color: f.$1 ? Colors.white.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.38),
                              fontSize: 13.5,
                              height: 1.3,
                              decoration: f.$1 ? null : TextDecoration.lineThrough,
                              decorationColor: Colors.redAccent.withValues(alpha: 0.5))),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
