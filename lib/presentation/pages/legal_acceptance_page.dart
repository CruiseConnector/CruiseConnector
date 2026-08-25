import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/legal_documents.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/utils/legal_link_launcher.dart';

const _legalBackground = Color(0xFF0D141E);
const _legalSurface = Color(0xFF151E2A);
const _legalField = Color(0xFF1A2432);
const _legalBorder = Color(0xFF344156);
const _legalTextMuted = Color(0xFFB6BECC);

/// Standard-Ausweg aus dem Rechts-Tor: abmelden und zurueck zum Start.
///
/// 2026-08-24: Das Tor laeuft VOR der ganzen App. Wer die Bedingungen nicht
/// annehmen will oder — wie im Vorfall — die Texte auf seinem Geraet gar
/// nicht oeffnen kann, hatte bis heute keine einzige Handlungsmoeglichkeit:
/// kein Zurueck (`canPop: false`), kein Abbrechen, und Neuinstallation half
/// nicht, weil die Sperre am Konto haengt. Auch wenn das Abmelden am Server
/// scheitert (kein Netz), kommt der Nutzer hier heraus.
Future<void> abmeldenUndZumStart(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    // Eine gemerkte, noch nicht gebuchte Zustimmung gehoert zu DIESEM Konto.
    // Sie darf nicht liegen bleiben und beim naechsten Konto auf demselben
    // Geraet stillschweigend als dessen Zustimmung gebucht werden.
    await LegalAcceptanceService.clearPendingPreAuthAcceptance();
  } catch (e) {
    debugPrint('[LegalAcceptance] Gemerkte Zustimmung nicht loeschbar: $e');
  }
  try {
    await AuthService.signOut();
  } catch (e) {
    debugPrint('[LegalAcceptance] Abmelden fehlgeschlagen: $e');
  }
  await navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomePage()),
    (route) => false,
  );
}

class LegalAcceptancePage extends StatefulWidget {
  const LegalAcceptancePage({
    super.key,
    required this.source,
    this.persistAcceptance = true,
    this.canGoBack = false,
    this.onAccepted,
    this.onExit,
  });

  final String source;
  final bool persistAcceptance;
  final bool canGoBack;
  final VoidCallback? onAccepted;

  /// Der Ausweg, wenn es kein Zurueck gibt. Ohne Angabe: abmelden und zurueck
  /// zum Start. Tests reichen hier einen eigenen Weg herein.
  final Future<void> Function(BuildContext context)? onExit;

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

/// Zustand eines einzelnen Dokuments im Tor.
class _DocumentGate {
  bool opening = false;

  /// Das Dokument wurde tatsaechlich geoeffnet.
  bool opened = false;

  /// Mindestens ein Startversuch ist fehlgeschlagen — der Ersatzweg wird
  /// angeboten.
  bool launchFailed = false;

  /// Der Nutzer hat den Ersatzweg bewusst bestaetigt (Adresse notiert).
  bool linkConfirmed = false;

  /// Nur wenn einer der beiden Wege gegangen wurde, darf das Haekchen gesetzt
  /// werden. Der Knopf haengt also NIE mehr allein am Browser-Start.
  bool get unlocked => opened || linkConfirmed;
}

class _LegalAcceptancePageState extends State<LegalAcceptancePage> {
  final _terms = _DocumentGate();
  final _privacy = _DocumentGate();

  bool _termsAccepted = false;
  bool _privacyAcknowledged = false;
  bool _saving = false;
  String? _error;

  bool get _canContinue => _termsAccepted && _privacyAcknowledged && !_saving;

  _DocumentGate _gateFor(LegalDocument document) =>
      document == LegalDocuments.terms ? _terms : _privacy;

  Future<void> _openDocument(LegalDocument document) async {
    final gate = _gateFor(document);
    if (gate.opening) return; // Doppeltipp startet nicht zwei Browser.
    setState(() {
      gate.opening = true;
      _error = null;
    });

    final ok = await launchLegalDocument(document);
    if (!mounted) return;

    setState(() {
      gate.opening = false;
      if (ok) {
        gate.opened = true;
        gate.launchFailed = false;
      } else {
        gate.launchFailed = true;
      }
    });
  }

  Future<void> _copyLink(LegalDocument document) async {
    await Clipboard.setData(ClipboardData(text: document.url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adresse kopiert.')),
    );
  }

  void _confirmLinkFallback(LegalDocument document) {
    setState(() => _gateFor(document).linkConfirmed = true);
  }

  Future<void> _continue() async {
    if (!_canContinue) return;

    final usedFallback = _terms.linkConfirmed || _privacy.linkConfirmed;
    final snapshot = LegalAcceptanceSnapshot.current(
      source: widget.source,
      readPath: usedFallback
          ? LegalAcceptanceSnapshot.readPathLinkFallback
          : LegalAcceptanceSnapshot.readPathBrowser,
    );
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.persistAcceptance) {
        // 2026-08-24: Frist, damit ein haengender Server den Nutzer nicht in
        // einem ewig drehenden Knopf stehen laesst.
        await LegalAcceptanceService.recordCurrentAcceptance(
          source: widget.source,
          snapshot: snapshot,
        ).timeout(const Duration(seconds: 20));
        await LegalAcceptanceService.clearPendingPreAuthAcceptance();
        widget.onAccepted?.call();
      } else {
        await LegalAcceptanceService.savePendingPreAuthAcceptance(snapshot);
        if (!mounted) return;
        Navigator.of(context).pop(snapshot);
      }
    } catch (e) {
      // Die Zustimmung ist gegeben — sie darf nicht verloren gehen, nur weil
      // gerade kein Netz da ist. Sie wird lokal gemerkt und beim naechsten
      // erfolgreichen Start uebernommen (ensureAcceptedOrPending).
      try {
        await LegalAcceptanceService.savePendingPreAuthAcceptance(snapshot);
      } catch (inner) {
        debugPrint('[LegalAcceptance] Merken fehlgeschlagen: $inner');
      }
      if (!mounted) return;
      setState(
        () => _error =
            'Bestätigung konnte nicht gespeichert werden, vermutlich fehlt '
            'gerade die Verbindung. Sie ist gemerkt: bitte erneut versuchen '
            'oder die App später noch einmal starten.',
      );
      debugPrint('[LegalAcceptance] Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showReadFirstMessage(LegalDocument document) {
    final gate = _gateFor(document);
    final message = gate.launchFailed
        ? 'Der Text lässt sich hier nicht öffnen. Bitte nutze den Ersatzweg '
              'darunter.'
        : 'Bitte zuerst ${document.title} öffnen.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _legalSurface,
        title: const Text(
          'Abmelden?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Ohne Bestätigung der Rechtstexte kannst du die App nicht nutzen. '
          'Du kommst zurück zum Start und kannst dich jederzeit wieder '
          'anmelden.',
          style: TextStyle(color: _legalTextMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hierbleiben'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    final handler = widget.onExit ?? abmeldenUndZumStart;
    await handler(context);
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
          actions: [
            // Ohne Zurueck-Pfeil muss es hier einen Ausweg geben — sonst ist
            // die App ab dem Start gesperrt (Vorfall 24.08.).
            if (!widget.canGoBack)
              TextButton(
                onPressed: _exit,
                style: TextButton.styleFrom(foregroundColor: _legalTextMuted),
                child: const Text('Abmelden'),
              ),
          ],
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
                    'AGB und Datenschutz werden getrennt behandelt. In diesem Schritt stimmst du weder einem Newsletter noch Werbung zu.',
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
                    gate: _terms,
                    checked: _termsAccepted,
                    checkboxText:
                        'Ich habe die AGB / Terms of Service gelesen und akzeptiere sie.',
                    onOpen: () => _openDocument(LegalDocuments.terms),
                    onCopyLink: () => _copyLink(LegalDocuments.terms),
                    onConfirmLink: () =>
                        _confirmLinkFallback(LegalDocuments.terms),
                    onChanged: _terms.unlocked
                        ? (value) =>
                              setState(() => _termsAccepted = value ?? false)
                        : null,
                    onDisabledTap: () =>
                        _showReadFirstMessage(LegalDocuments.terms),
                  ),
                  const SizedBox(height: 14),
                  _LegalDocumentPanel(
                    document: LegalDocuments.privacy,
                    gate: _privacy,
                    checked: _privacyAcknowledged,
                    checkboxText:
                        'Ich habe die Datenschutzerklärung gelesen und zur Kenntnis genommen.',
                    onOpen: () => _openDocument(LegalDocuments.privacy),
                    onCopyLink: () => _copyLink(LegalDocuments.privacy),
                    onConfirmLink: () =>
                        _confirmLinkFallback(LegalDocuments.privacy),
                    onChanged: _privacy.unlocked
                        ? (value) => setState(
                            () => _privacyAcknowledged = value ?? false,
                          )
                        : null,
                    onDisabledTap: () =>
                        _showReadFirstMessage(LegalDocuments.privacy),
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
    required this.gate,
    required this.checked,
    required this.checkboxText,
    required this.onOpen,
    required this.onCopyLink,
    required this.onConfirmLink,
    required this.onChanged,
    required this.onDisabledTap,
  });

  final LegalDocument document;
  final _DocumentGate gate;
  final bool checked;
  final String checkboxText;
  final VoidCallback onOpen;
  final VoidCallback onCopyLink;
  final VoidCallback onConfirmLink;
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
                gate.unlocked
                    ? Icons.check_circle_outline
                    : Icons.description_outlined,
                color: gate.unlocked ? const Color(0xFF34D399) : accent,
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
              if (gate.opening)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: Text(gate.launchFailed ? 'Erneut' : 'Lesen'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
            ],
          ),
          if (gate.launchFailed && !gate.opened) ...[
            const SizedBox(height: 8),
            _LinkFallback(
              document: document,
              confirmed: gate.linkConfirmed,
              onCopyLink: onCopyLink,
              onConfirmLink: onConfirmLink,
              accent: accent,
            ),
          ],
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

/// Ersatzweg, wenn sich auf diesem Geraet kein Browser starten laesst.
///
/// Er entwertet die Zustimmung nicht: der Nutzer sieht die vollstaendige
/// Adresse, kann sie kopieren und bestaetigt ausdruecklich, dass er den Text
/// dort liest. Dieser Weg wird in der Zustimmung mitprotokolliert
/// (`device_info.legal_read_path`).
class _LinkFallback extends StatelessWidget {
  const _LinkFallback({
    required this.document,
    required this.confirmed,
    required this.onCopyLink,
    required this.onConfirmLink,
    required this.accent,
  });

  final LegalDocument document;
  final bool confirmed;
  final VoidCallback onCopyLink;
  final VoidCallback onConfirmLink;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _legalField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _legalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auf diesem Gerät lässt sich kein Browser öffnen, zum Beispiel '
            'weil Bildschirmzeit oder eine Geräteverwaltung Inhalte aus dem '
            'Netz sperrt. Du kommst hier trotzdem weiter:',
            style: TextStyle(
              color: _legalTextMuted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            document.url,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onCopyLink,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Adresse kopieren'),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
              if (!confirmed)
                TextButton.icon(
                  onPressed: onConfirmLink,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Adresse notiert, Häkchen freigeben'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    'Ersatzweg bestätigt.',
                    style: TextStyle(color: Color(0xFF34D399), fontSize: 12.5),
                  ),
                ),
            ],
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
    final tile = CheckboxListTile(
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
    );

    // Material statt Container: die Kachel hat einen eigenen Hintergrund UND
    // eine Tipp-Flaeche. Ein farbiger Container dazwischen laesst Flutter die
    // Tipp-Welle auf einer fremden Flaeche zeichnen und wirft im Debug-Build.
    return Material(
      color: _legalField,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: onChanged != null
          ? tile
          : InkWell(onTap: onDisabledTap, child: tile),
    );
  }
}
