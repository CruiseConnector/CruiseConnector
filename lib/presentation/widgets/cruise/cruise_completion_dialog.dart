import 'package:flutter/material.dart';

/// Dialog der nach Abschluss einer Route angezeigt wird.
/// Zeigt Statistiken und eine Sterne-Bewertung.
class CruiseCompletionDialog extends StatefulWidget {
  const CruiseCompletionDialog({
    super.key,
    required this.distanceKm,
    required this.onSave,
    required this.onDiscard,
  });

  final double? distanceKm;
  final ValueChanged<int> onSave; // rating (1-5)
  final VoidCallback onDiscard;

  @override
  State<CruiseCompletionDialog> createState() => _CruiseCompletionDialogState();
}

class _CruiseCompletionDialogState extends State<CruiseCompletionDialog> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Column(
        children: [
          Text('\u{1F3C1}', style: TextStyle(fontSize: 48)),
          SizedBox(height: 8),
          Text(
            'Route abgeschlossen!',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.distanceKm?.toStringAsFixed(1) ?? '--'} km gefahren',
            style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
          ),
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
