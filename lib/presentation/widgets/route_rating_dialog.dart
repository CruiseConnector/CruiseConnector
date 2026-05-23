import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/route_rating_service.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// Schicker Sterne-Dialog zur Bewertung einer gefahrenen Route.
/// Nutzt RouteRatingService.saveRating (existing Schema mit rating + tags).
Future<void> showRouteRatingDialog({
  required BuildContext context,
  required RouteResult result,
  required double completionPercent,
  required double? distanceKm,
  required double? durationSeconds,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => _RouteRatingDialog(
      result: result,
      completionPercent: completionPercent,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
    ),
  );
}

class _RouteRatingDialog extends StatefulWidget {
  const _RouteRatingDialog({
    required this.result,
    required this.completionPercent,
    required this.distanceKm,
    required this.durationSeconds,
  });

  final RouteResult result;
  final double completionPercent;
  final double? distanceKm;
  final double? durationSeconds;

  @override
  State<_RouteRatingDialog> createState() => _RouteRatingDialogState();
}

class _RouteRatingDialogState extends State<_RouteRatingDialog> {
  int _stars = 0;
  final Set<String> _tags = {};
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  static const _tagOptions = [
    'Schöne Aussicht',
    'Tolle Kurven',
    'Wenig Verkehr',
    'Top-Asphalt',
    'Bergpass',
    'Cafés am Weg',
    'Zu viel Stadt',
    'Schlechte Straße',
  ];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();
    final tagList = List<String>.from(_tags);
    if (_commentCtrl.text.trim().isNotEmpty) {
      tagList.add('comment:${_commentCtrl.text.trim()}');
    }
    await RouteRatingService.saveRating(
      result: widget.result,
      rating: _stars,
      tags: tagList,
      completionPercent: widget.completionPercent,
      distanceKm: widget.distanceKm,
      durationSeconds: widget.durationSeconds,
      qualityTier: null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Dialog(
      backgroundColor: const Color(0xFF13161E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.star_rate_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Wie war die Tour?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          )),
                      SizedBox(height: 2),
                      Text('Hilf der App passende Routen zu finden',
                          style: TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 12,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Sterne-Reihe mit Tap-Animation
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _stars = i + 1);
                    },
                    child: AnimatedScale(
                      scale: filled ? 1.10 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 42,
                        color: filled ? accent : Colors.white24,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tagOptions.map((tag) {
                final selected = _tags.contains(tag);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (selected) {
                        _tags.remove(tag);
                      } else {
                        _tags.add(tag);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: selected
                            ? accent.withValues(alpha: 0.70)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentCtrl,
              maxLines: 2,
              maxLength: 200,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Kurze Notiz? (optional)',
                hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Überspringen',
                      style: TextStyle(color: Color(0x88FFFFFF))),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _stars == 0 || _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
