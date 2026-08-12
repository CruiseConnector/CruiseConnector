import 'dart:io' show Platform;

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Blockierender Update-Screen. Kein Weg vorbei — genau das ist der Sinn.
///
/// 2026-08-10 (vucko): „bevor sie in die App reingehen koennen."
/// 2026-08-12 (vucko): „wenn die app eine alte version hat, man benachrichtigt
/// wird und die app neuinstallieren MUSS um reinzukommen."
///
/// Die Seite liegt als Deckel über der ganzen App (siehe ForceUpdateGate), nicht
/// als Route im Navigator. Deshalb hier:
///   * ein eigener `Material`-Rahmen statt `Scaffold`-Annahmen,
///   * die Fehlermeldung INLINE statt per ScaffoldMessenger — über dem
///     Navigator ist kein Messenger garantiert erreichbar,
///   * `BackButtonListener` statt `PopScope`: Der System-Zurück-Knopf auf
///     Android geht an den Navigator DARUNTER; ein PopScope hier oben würde ihn
///     nie zu sehen bekommen.
class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({
    super.key,
    this.storeUrl,
    this.nachricht,
    this.installierterBuild,
    this.benoetigterBuild,
    this.onErneutPruefen,
  });

  final String? storeUrl;
  final String? nachricht;
  final int? installierterBuild;
  final int? benoetigterBuild;

  /// „Ich habe aktualisiert" — prüft erneut, ohne dass die App neu gestartet
  /// werden muss.
  final Future<void> Function()? onErneutPruefen;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  String? _fehler;
  bool _prueftGerade = false;

  /// Der Store-Link kommt aus der Datenbank. Der Rückfall war vorher HART der
  /// Play Store — auf einem iPhone also der falsche Laden. Jetzt je Plattform.
  String get _url {
    final ausDb = widget.storeUrl;
    if (ausDb != null && ausDb.trim().isNotEmpty) return ausDb;
    if (!kIsWeb && Platform.isIOS) {
      return 'https://apps.apple.com/app/cruise-connector/id6749841801';
    }
    return 'https://play.google.com/store/apps/details?id=com.vucko.cruiserconnect';
  }

  Future<void> _oeffneStore() async {
    setState(() => _fehler = null);
    try {
      final ok = await launchUrl(
        Uri.parse(_url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        setState(() => _fehler = 'Store konnte nicht geöffnet werden.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _fehler = 'Store konnte nicht geöffnet werden.');
      }
    }
  }

  Future<void> _erneutPruefen() async {
    final rueckruf = widget.onErneutPruefen;
    if (rueckruf == null || _prueftGerade) return;
    setState(() {
      _prueftGerade = true;
      _fehler = null;
    });
    await rueckruf();
    if (!mounted) return;
    setState(() {
      _prueftGerade = false;
      // Sind wir noch hier, hat die Prüfung nichts geändert.
      _fehler = 'Noch die alte Version. Bitte im Store aktualisieren.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final installiert = widget.installierterBuild;
    final benoetigt = widget.benoetigterBuild;

    return BackButtonListener(
      // Verschluckt den System-Zurück-Knopf, solange die Sperre liegt.
      onBackButtonPressed: () async => true,
      child: Material(
        color: const Color(0xFF0D141E),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: accent,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Neue Version verfügbar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.nachricht ??
                        'Um Cruise Connector weiter zu nutzen, aktualisiere '
                            'bitte auf die neueste Version. Es dauert nur '
                            'einen Moment.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  if (installiert != null && benoetigt != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Auf dem Gerät: Version $installiert · '
                      'benötigt: $benoetigt',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _oeffneStore,
                      child: const Text(
                        'Jetzt aktualisieren',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onErneutPruefen != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _prueftGerade ? null : _erneutPruefen,
                        child: Text(
                          _prueftGerade
                              ? 'Wird geprüft …'
                              : 'Ich habe aktualisiert',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_fehler != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _fehler!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
