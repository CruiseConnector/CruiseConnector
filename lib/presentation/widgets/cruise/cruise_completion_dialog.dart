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
  });

  final double? distanceKm;
  final ValueChanged<int> onSave; // rating (1-5)
  final VoidCallback onDiscard;
  final bool isEarlyStop;
  final double? totalRouteKm; // Gesamte geplante Route

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

    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          Text(
            widget.isEarlyStop ? '\u{1F6D1}' : '\u{1F3C1}',
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isEarlyStop ? 'Fahrt beendet' : 'Route abgeschlossen!',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
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
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
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
            backgroundColor: const Color(0xFFFF3B30),
            disabledBackgroundColor: Colors.grey[800],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Route speichern', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
