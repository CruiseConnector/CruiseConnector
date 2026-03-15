import 'package:flutter/material.dart';

/// Der Zustand der Fahrtsteuerung.
enum DriveState { stopped, started, paused }

/// Ein UI-Panel zur Steuerung einer aktiven Fahrt (Start, Pause, Stopp).
/// Wird typischerweise am unteren Bildschirmrand angezeigt.
class DriveControlPanel extends StatefulWidget {
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onStop;

  const DriveControlPanel({super.key, this.onStart, this.onPause, this.onStop});

  @override
  State<DriveControlPanel> createState() => _DriveControlPanelState();
}

class _DriveControlPanelState extends State<DriveControlPanel> {
  DriveState _driveState = DriveState.stopped;

  void _handleStart() {
    if (!mounted) return;
    setState(() => _driveState = DriveState.started);
    widget.onStart?.call();
    print('DriveControlPanel: Fahrt gestartet!');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Fahrt gestartet!')));
  }

  void _handlePause() {
    if (!mounted) return;
    setState(() => _driveState = DriveState.paused);
    widget.onPause?.call();
    print('DriveControlPanel: Fahrt pausiert!');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Fahrt pausiert!')));
  }

  void _handleStop() {
    if (!mounted) return;
    setState(() => _driveState = DriveState.stopped);
    widget.onStop?.call();
    print('DriveControlPanel: Fahrt beendet!');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Fahrt beendet!')));
    // Hier könnte später ein Callback aufgerufen werden, um den Dialog zu schließen
    // oder zur Zusammenfassung zu navigieren.
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false, // Wegen Margin nicht mehr zwingend nötig
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    switch (_driveState) {
      case DriveState.stopped:
        return SizedBox(
          key: const ValueKey('start'),
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _handleStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text(
              'Fahrt starten',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        );
      case DriveState.started:
      case DriveState.paused:
        return Row(
          key: const ValueKey('running'),
          children: [
            // Pause/Fortsetzen Button
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _driveState == DriveState.started ? _handlePause : _handleStart,
                  icon: Icon(_driveState == DriveState.started ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_driveState == DriveState.started ? 'Pausieren' : 'Fortsetzen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A3D46),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Beenden Button
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _handleStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Beenden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}