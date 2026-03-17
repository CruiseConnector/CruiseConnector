import 'package:flutter/material.dart';

/// Der Zustand der Fahrtsteuerung.
enum DriveState { stopped, started, paused }

/// Ein UI-Panel zur Steuerung einer aktiven Fahrt (Start, Pause, Stopp).
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
  }

  void _handlePause() {
    if (!mounted) return;
    setState(() => _driveState = DriveState.paused);
    widget.onPause?.call();
  }

  void _handleStop() {
    if (!mounted) return;
    setState(() => _driveState = DriveState.stopped);
    widget.onStop?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2028).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildControls(),
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
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _handleStart,
            icon: const Icon(Icons.navigation_rounded, size: 22),
            label: const Text(
              'Fahrt starten',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        );
      case DriveState.started:
      case DriveState.paused:
        return Row(
          key: const ValueKey('running'),
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _driveState == DriveState.started ? _handlePause : _handleStart,
                  icon: Icon(
                    _driveState == DriveState.started ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                  label: Text(
                    _driveState == DriveState.started ? 'Pause' : 'Weiter',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _handleStop,
                  icon: const Icon(Icons.stop_rounded, size: 22),
                  label: const Text(
                    'Beenden',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}
