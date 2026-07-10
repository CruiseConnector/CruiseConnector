import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/legal_documents.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/utils/legal_link_launcher.dart';

const _legalBackground = Color(0xFF0D141E);
const _legalSurface = Color(0xFF151E2A);
const _legalField = Color(0xFF1A2432);
const _legalBorder = Color(0xFF344156);
const _legalTextMuted = Color(0xFFB6BECC);

class LegalAcceptancePage extends StatefulWidget {
  const LegalAcceptancePage({
    super.key,
    required this.source,
    this.persistAcceptance = true,
    this.canGoBack = false,
    this.onAccepted,
  });

  final String source;
  final bool persistAcceptance;
  final bool canGoBack;
  final VoidCallback? onAccepted;

  static Future<LegalAcceptanceSnapshot?> requestPreAuth(
    BuildContext context, {
    required String source,
  }) {
    return Navigator.of(context).push<LegalAcceptanceSnapshot>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LegalAcceptancePage(
          source: source,
          persistAcceptance: false,
          canGoBack: true,
        ),
      ),
    );
  }

  @override
  State<LegalAcceptancePage> createState() => _LegalAcceptancePageState();
}

class _LegalAcceptancePageState extends State<LegalAcceptancePage> {
  bool _termsOpened = false;
  bool _privacyOpened = false;
  bool _termsAccepted = false;
  bool _privacyAcknowledged = false;
  bool _saving = false;
  String? _error;

  bool get _canContinue => _termsAccepted && _privacyAcknowledged && !_saving;

  Future<void> _openDocument(LegalDocument document) async {
    final ok = await launchLegalDocument(document);
    if (!mounted) return;
    if (!ok) {
      setState(
        () => _error =
            '${document.title} konnte nicht geöffnet werden. Bitte prüfe die Verbindung.',
      );
      return;
    }
    setState(() {
      _error = null;
      if (document == LegalDocuments.terms) _termsOpened = true;
      if (document == LegalDocuments.privacy) _privacyOpened = true;
    });
  }

  Future<void> _continue() async {
    if (!_canContinue) return;

    final snapshot = LegalAcceptanceSnapshot.current(source: widget.source);
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.persistAcceptance) {
        await LegalAcceptanceService.recordCurrentAcceptance(
          source: widget.source,
          snapshot: snapshot,
        );
        await LegalAcceptanceService.clearPendingPreAuthAcceptance();
        widget.onAccepted?.call();
      } else {
        await LegalAcceptanceService.savePendingPreAuthAcceptance(snapshot);
        if (!mounted) return;
        Navigator.of(context).pop(snapshot);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            'Legal-Bestätigung konnte nicht gespeichert werden. Bitte erneut versuchen.',
      );
      debugPrint('[LegalAcceptance] Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showReadFirstMessage(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Bitte zuerst $label öffnen.')));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;

    return PopScope(
      canPop: widget.canGoBack,
      child: Scaffold(
        backgroundColor: _legalBackground,
        appBar: AppBar(
          automaticallyImplyLeading: widget.canGoBack,
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Rechtliches',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Icon(Icons.verified_user_outlined, color: accent, size: 46),
                  const SizedBox(height: 18),
                  const Text(
                    'Bitte bestätige die aktuellen Rechtstexte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'AGB und Datenschutz werden getrennt behandelt. Es gibt keine Newsletter- oder Marketing-Einwilligung in diesem Schritt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _legalTextMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _LegalDocumentPanel(
                    document: LegalDocuments.terms,
                    opened: _termsOpened,
                    checked: _termsAccepted,
                    checkboxText:
                        'Ich habe die AGB / Terms of Service gelesen und akzeptiere sie.',
                    onOpen: () => _openDocument(LegalDocuments.terms),
                    onChanged: _termsOpened
                        ? (value) =>
                              setState(() => _termsAccepted = value ?? false)
                        : null,
                    onDisabledTap: () => _showReadFirstMessage('die AGB'),
                  ),
                  const SizedBox(height: 14),
                  _LegalDocumentPanel(
                    document: LegalDocuments.privacy,
                    opened: _privacyOpened,
                    checked: _privacyAcknowledged,
                    checkboxText:
                        'Ich habe die Datenschutzerklärung gelesen und zur Kenntnis genommen.',
                    onOpen: () => _openDocument(LegalDocuments.privacy),
                    onChanged: _privacyOpened
                        ? (value) => setState(
                            () => _privacyAcknowledged = value ?? false,
                          )
                        : null,
                    onDisabledTap: () =>
                        _showReadFirstMessage('die Datenschutzerklärung'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF331316),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(
                            0xFFFF6B6B,
                          ).withValues(alpha: 0.42),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFB4B4),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _canContinue ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _legalBorder,
                        disabledForegroundColor: Colors.white54,
                        shape: const StadiumBorder(),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Text(
                              widget.persistAcceptance
                                  ? 'Weiter'
                                  : 'Bestätigen und fortfahren',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalDocumentPanel extends StatelessWidget {
  const _LegalDocumentPanel({
    required this.document,
    required this.opened,
    required this.checked,
    required this.checkboxText,
    required this.onOpen,
    required this.onChanged,
    required this.onDisabledTap,
  });

  final LegalDocument document;
  final bool opened;
  final bool checked;
  final String checkboxText;
  final VoidCallback onOpen;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: _legalSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _legalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                opened
                    ? Icons.check_circle_outline
                    : Icons.description_outlined,
                color: opened ? const Color(0xFF34D399) : accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  document.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Lesen'),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ReadRequiredCheckbox(
            checked: checked,
            checkboxText: checkboxText,
            accent: accent,
            onChanged: onChanged,
            onDisabledTap: onDisabledTap,
          ),
        ],
      ),
    );
  }
}

class _ReadRequiredCheckbox extends StatelessWidget {
  const _ReadRequiredCheckbox({
    required this.checked,
    required this.checkboxText,
    required this.accent,
    required this.onChanged,
    required this.onDisabledTap,
  });

  final bool checked;
  final String checkboxText;
  final Color accent;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      decoration: BoxDecoration(
        color: _legalField,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: checked,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: accent,
        checkColor: Colors.white,
        title: Text(
          checkboxText,
          style: TextStyle(
            color: onChanged == null
                ? Colors.white.withValues(alpha: 0.45)
                : Colors.white,
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    if (onChanged != null) return tile;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onDisabledTap,
      child: tile,
    );
  }
}
