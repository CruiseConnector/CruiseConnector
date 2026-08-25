import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/rangliste_service.dart';
import 'package:flutter/material.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 6): „Auf der Startseite ein Widget,
/// wo man die Rangliste sieht — im kleinen Quadrat oder im großen Rechteck.
/// Innerhalb vom Widget die Top 3 und die eigene Position, wöchentlich und
/// monatlich, gut gefüllt, keine Lücken."
///
/// Zwei Formen:
///  * KLEIN (Quadrat, halbe Breite): Titel + Zeitraum-Umschalter als zwei
///    Chips, darunter drei kompakte Zeilen (Rang · Name · km) und ganz unten
///    „Du: Platz N · km". Alles auf einer Höhe von [_dashboardHalfTileHeight].
///  * GROSS (Rechteck, volle Breite): Kopf mit Woche/Monat-Segment, drei
///    Podestzeilen mit Avatar, Name, Fahrten und km-Balken, dann die eigene
///    Zeile hervorgehoben (auch wenn sie in den Top 3 ist).
/// Weniger als drei Fahrer im Zeitraum? Die freien Plätze werden als
/// „Platz frei" gezeigt — kein leerer Raum.
class RanglisteKachel extends StatefulWidget {
  const RanglisteKachel({
    super.key,
    required this.kompakt,
    this.hoehe,
    this.decoration,
    this.onTap,
    this.lader,
  });

  final bool kompakt;
  final double? hoehe;
  final BoxDecoration? decoration;
  final VoidCallback? onTap;

  /// Nur fuer Tests austauschbar (Standard: [RanglisteService.instance.lade]).
  final Future<Rangliste?> Function(RanglisteZeitraum zeitraum)? lader;

  @override
  State<RanglisteKachel> createState() => _RanglisteKachelState();
}

class _RanglisteKachelState extends State<RanglisteKachel> {
  RanglisteZeitraum _zeitraum = RanglisteZeitraum.woche;
  Rangliste? _daten;
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    unawaited(_laden());
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final lade = widget.lader ?? (z) => RanglisteService.instance.lade(z);
    final r = await lade(_zeitraum);
    if (!mounted) return;
    setState(() {
      _daten = r;
      _laedt = false;
    });
  }

  void _wechsle(RanglisteZeitraum z) {
    if (z == _zeitraum) return;
    setState(() => _zeitraum = z);
    unawaited(_laden());
  }

  static String _km(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final inhalt = widget.kompakt ? _klein(accent) : _gross(accent);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        height: widget.hoehe,
        padding: EdgeInsets.all(widget.kompakt ? 12 : 16),
        decoration: widget.decoration ??
            BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
        child: inhalt,
      ),
    );
  }

  // ── Klein ────────────────────────────────────────────────────────────────

  Widget _klein(Color accent) {
    final top = _daten?.top ?? const <RanglisteEintrag>[];
    final ich = _daten?.ich;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: accent, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Rangliste',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _MiniUmschalter(zeitraum: _zeitraum, onChanged: _wechsle, accent: accent),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _laedt && _daten == null
              ? _skelett(3)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 3; i++)
                      _kleineZeile(i + 1, i < top.length ? top[i] : null, accent),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.person_rounded, color: accent, size: 13),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  ich == null
                      ? 'Du: noch nicht dabei'
                      : 'Du: Platz ${ich.rang} · ${_km(ich.distanceKm)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kleineZeile(int platz, RanglisteEintrag? e, Color accent) {
    final frei = e == null;
    return Row(
      children: [
        _Podest(platz: platz, accent: accent, klein: true),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            frei ? 'Platz frei' : e.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: frei
                  ? Colors.white30
                  : (e.istIch ? accent : Colors.white),
              fontSize: 12.5,
              fontWeight: e?.istIch == true ? FontWeight.w800 : FontWeight.w600,
              fontStyle: frei ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        Text(
          frei ? '–' : '${_km(e.distanceKm)} km',
          style: TextStyle(
            color: frei ? Colors.white24 : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Gross ────────────────────────────────────────────────────────────────

  Widget _gross(Color accent) {
    final top = _daten?.top ?? const <RanglisteEintrag>[];
    final ich = _daten?.ich;
    final maxKm = top.isEmpty
        ? 1.0
        : top.map((e) => e.distanceKm).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emoji_events_rounded, color: accent, size: 21),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Rangliste',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _Segment(zeitraum: _zeitraum, onChanged: _wechsle, accent: accent),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _zeitraum == RanglisteZeitraum.woche
              ? 'Gefahrene Kilometer diese Woche'
              : 'Gefahrene Kilometer diesen Monat',
          style: const TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        const SizedBox(height: 10),
        if (_laedt && _daten == null)
          _skelett(3, hoch: true)
        else
          for (var i = 0; i < 3; i++) ...[
            _grosseZeile(i + 1, i < top.length ? top[i] : null, accent, maxKm),
            if (i < 2) const SizedBox(height: 8),
          ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.person_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ich == null
                      ? 'Du bist noch nicht dabei. Fahr eine Runde und steig ein.'
                      : 'Du: Platz ${ich.rang}'
                            '${ich.sessionCount > 0 ? ' · ${ich.sessionCount} ${ich.sessionCount == 1 ? 'Fahrt' : 'Fahrten'}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (ich != null)
                Text(
                  '${_km(ich.distanceKm)} km',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _grosseZeile(int platz, RanglisteEintrag? e, Color accent, double maxKm) {
    final frei = e == null;
    final anteil = frei || maxKm <= 0 ? 0.0 : (e.distanceKm / maxKm).clamp(0.05, 1.0);
    return Row(
      children: [
        _Podest(platz: platz, accent: accent, klein: false),
        const SizedBox(width: 10),
        _Avatar(url: e?.avatarUrl, name: frei ? '?' : e.username, accent: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      frei ? 'Platz frei' : e.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: frei
                            ? Colors.white30
                            : (e.istIch ? accent : Colors.white),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        fontStyle: frei ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  Text(
                    frei ? '–' : '${_km(e.distanceKm)} km',
                    style: TextStyle(
                      color: frei ? Colors.white24 : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: anteil,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    frei ? Colors.white12 : accent.withValues(alpha: platz == 1 ? 1 : 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skelett(int zeilen, {bool hoch = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < zeilen; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: hoch ? 6 : 3),
            child: Container(
              height: hoch ? 30 : 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}

class _Podest extends StatelessWidget {
  const _Podest({required this.platz, required this.accent, required this.klein});
  final int platz;
  final Color accent;
  final bool klein;

  @override
  Widget build(BuildContext context) {
    final farbe = switch (platz) {
      1 => const Color(0xFFFFC94D),
      2 => const Color(0xFFC7CDD8),
      3 => const Color(0xFFCD8B5B),
      _ => Colors.white24,
    };
    final groesse = klein ? 20.0 : 26.0;
    return Container(
      width: groesse,
      height: groesse,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: farbe.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(
        '$platz',
        style: TextStyle(
          color: farbe,
          fontSize: klein ? 11 : 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, required this.accent});
  final String? url;
  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 16,
      backgroundColor: accent.withValues(alpha: 0.18),
      backgroundImage: (url != null && url!.startsWith('http'))
          ? NetworkImage(url!)
          : null,
      child: (url != null && url!.startsWith('http'))
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.zeitraum, required this.onChanged, required this.accent});
  final RanglisteZeitraum zeitraum;
  final ValueChanged<RanglisteZeitraum> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final z in RanglisteZeitraum.values)
            GestureDetector(
              key: ValueKey('rangliste_${z.name}'),
              onTap: () => onChanged(z),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: z == zeitraum ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  z.label,
                  style: TextStyle(
                    color: z == zeitraum ? Colors.white : Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniUmschalter extends StatelessWidget {
  const _MiniUmschalter({required this.zeitraum, required this.onChanged, required this.accent});
  final RanglisteZeitraum zeitraum;
  final ValueChanged<RanglisteZeitraum> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Ein Tipp wechselt zwischen Woche und Monat — spart Platz im Quadrat.
    final naechster = zeitraum == RanglisteZeitraum.woche
        ? RanglisteZeitraum.monat
        : RanglisteZeitraum.woche;
    return GestureDetector(
      key: const ValueKey('rangliste_mini_umschalter'),
      onTap: () => onChanged(naechster),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              zeitraum.label,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.swap_horiz_rounded, color: accent, size: 12),
          ],
        ),
      ),
    );
  }
}
