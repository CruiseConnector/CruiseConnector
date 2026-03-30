import 'package:flutter/material.dart';

/// Dialog der nach Abschluss oder vorzeitigem Beenden einer Route angezeigt wird.
/// Zeigt Statistiken und eine Sterne-Bewertung.
class CruiseCompletionDialog extends StatefulWidget {
  const CruiseCompletionDialog({
    super.key,
    required this.distanceKm,
    required this.onSave,
    required this.onDiscard,
    this.isEarlyStop = false,
    this.totalRouteKm,
    this.belowMinimum = false,
  });

  final double? distanceKm;
  final ValueChanged<int> onSave; // rating (1-5)
  final VoidCallback onDiscard;
  final bool isEarlyStop;
  final double? totalRouteKm; // Gesamte geplante Route
  final bool belowMinimum; // < 10% gefahren → keine XP-Gutschrift

  @override
  State<CruiseCompletionDialog> createState() => _CruiseCompletionDialogState();
}

class _CruiseCompletionDialogState extends State<CruiseCompletionDialog> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    final drivenKm = widget.distanceKm?.toStringAsFixed(1) ?? '--';
    final progressPercent = (widget.distanceKm != null && widget.totalRouteKm != null && widget.totalRouteKm! > 0)
        ? ((widget.distanceKm! / widget.totalRouteKm!) * 100).clamp(0, 100).round()
        : null;

    // Bestimme Icon und Titel je nach Fortschrittskategorie
    final String emoji;
    final String title;
    final String? subtitleText;
    final Color progressColor;

    if (widget.belowMinimum) {
      emoji = '\u{26A0}\u{FE0F}'; // ⚠️
      title = 'Zu wenig gefahren';
      subtitleText = 'Mindestens 10% der Strecke fahren für Gutschrift';
      progressColor = const Color(0xFFFF9500); // Orange
    } else if (widget.isEarlyStop) {
      emoji = '\u{1F6D1}';
      title = 'Fahrt beendet';
      subtitleText = progressPercent != null
          ? '$progressPercent% geschafft \u{00B7} Anteilige Gutschrift'
          : null;
      progressColor = const Color(0xFFFF3B30);
    } else {
      emoji = '\u{1F3C1}';
      title = 'Route abgeschlossen!';
      subtitleText = null;
      progressColor = const Color(0xFFFF3B30);
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (subtitleText != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitleText,
              style: TextStyle(
                color: widget.belowMinimum ? const Color(0xFFFF9500) : const Color(0xFFA0AEC0),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gefahrene Distanz
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.straighten_rounded, color: Color(0xFFFF3B30), size: 20),
              const SizedBox(width: 8),
              Text(
                '$drivenKm km gefahren',
                style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (widget.isEarlyStop && progressPercent != null) ...[
            const SizedBox(height: 8),
            // Fortschrittsbalken
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (progressPercent / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$progressPercent% der Route geschafft',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Wie war die Strecke?',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < _rating ? const Color(0xFFFFD700) : Colors.grey,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onDiscard,
          child: const Text('Verwerfen', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _rating == 0 ? null : () => widget.onSave(_rating),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.belowMinimum ? Colors.grey[700] : const Color(0xFFFF3B30),
            disabledBackgroundColor: Colors.grey[800],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            widget.belowMinimum ? 'Ohne Gutschrift speichern' : 'Route speichern',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
