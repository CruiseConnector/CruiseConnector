import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';

class LegalGatePage extends StatefulWidget {
  const LegalGatePage({
    super.key,
    required this.child,
    this.source = 'app_onboarding',
  });

  final Widget child;
  final String source;

  @override
  State<LegalGatePage> createState() => _LegalGatePageState();
}

class _LegalGatePageState extends State<LegalGatePage> {
  late Future<bool> _acceptedFuture;

  @override
  void initState() {
    super.initState();
    _acceptedFuture = _loadAcceptanceState();
  }

  Future<bool> _loadAcceptanceState() async {
    if (await LegalAcceptanceService.hasCurrentAcceptance()) {
      await LegalAcceptanceService.clearPendingPreAuthAcceptance();
      return true;
    }

    final pending = await LegalAcceptanceService.pendingPreAuthAcceptance();
    if (pending != null) {
      try {
        await LegalAcceptanceService.recordCurrentAcceptance(
          source: widget.source,
          snapshot: pending,
        );
        await LegalAcceptanceService.clearPendingPreAuthAcceptance();
        return true;
      } catch (e) {
        debugPrint('[LegalGate] Pending Acceptance konnte nicht speichern: $e');
      }
    }

    return false;
  }

  void _markAccepted() {
    setState(() {
      _acceptedFuture = Future<bool>.value(true);
    });
  }

  void _retry() {
    setState(() {
      _acceptedFuture = _loadAcceptanceState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _acceptedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B0E14),
            body: Center(
              child: CircularProgressIndicator(color: AppAccentColors.accent),
            ),
          );
        }

        if (snapshot.hasError) {
          return _LegalGateError(onRetry: _retry);
        }

        if (snapshot.data == true) {
          return widget.child;
        }

        return LegalAcceptancePage(
          source: widget.source,
          persistAcceptance: true,
          canGoBack: false,
          onAccepted: _markAccepted,
        );
      },
    );
  }
}

class _LegalGateError extends StatelessWidget {
  const _LegalGateError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFFB4B4),
                  size: 42,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Rechtliches konnte nicht geprüft werden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bitte prüfe die Verbindung oder ob die Legal-Migration bereits in Supabase deployed ist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB6BECC), height: 1.35),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
