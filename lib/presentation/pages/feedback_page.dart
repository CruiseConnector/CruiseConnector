import 'dart:typed_data';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Rueckmeldung aus den Einstellungen.
///
/// 2026-08-09 (vucko): „Feedback-Funktion in den Einstellungen, sodass die
/// Leute mir schreiben koennen mit einem vorgefertigten Layout und der
/// Moeglichkeit, ein Foto anzuhaengen."
///
/// Die Vorlage im Textfeld wechselt mit der Kategorie. Sie wird nur dann
/// ersetzt, wenn der Nutzer noch nichts Eigenes geschrieben hat — sonst waere
/// ein versehentlicher Kategorie-Wechsel ein Datenverlust.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _titel = TextEditingController();
  final TextEditingController _text = TextEditingController();

  FeedbackKategorie _kategorie = FeedbackKategorie.fehler;
  Uint8List? _foto;
  bool _sendet = false;

  @override
  void initState() {
    super.initState();
    _text.text = _kategorie.vorlage;
  }

  @override
  void dispose() {
    _titel.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _textIstNochVorlage {
    final aktuell = _text.text.trim();
    if (aktuell.isEmpty) return true;
    for (final k in FeedbackKategorie.values) {
      if (aktuell == k.vorlage.trim()) return true;
    }
    return false;
  }

  void _kategorieWechseln(FeedbackKategorie k) {
    if (k == _kategorie) return;
    setState(() {
      _kategorie = k;
      if (_textIstNochVorlage) _text.text = k.vorlage;
    });
  }

  Future<void> _fotoWaehlen() async {
    try {
      final datei = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Screenshots werden bewusst nicht zugeschnitten — bei einem Fehlerbild
        // ist genau der Rand oft das Entscheidende. Nur die Groesse wird
        // gedeckelt, damit der Upload im Mobilfunknetz durchgeht.
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (datei == null) return;
      final bytes = await datei.readAsBytes();
      if (!mounted) return;
      setState(() => _foto = bytes);
    } catch (e) {
      if (!mounted) return;
      _hinweis('Foto konnte nicht geladen werden: $e');
    }
  }

  void _hinweis(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _senden() async {
    if (_sendet) return;
    if (_textIstNochVorlage) {
      _hinweis('Bitte schreib uns ein paar Zeilen.');
      return;
    }
    setState(() => _sendet = true);
    try {
      await FeedbackService.senden(
        kategorie: _kategorie,
        titel: _titel.text,
        text: _text.text,
        foto: _foto,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          title: const Text('Danke dir', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Deine Rueckmeldung ist angekommen. Wir lesen jede einzelne.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schliessen'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FeedbackFehler catch (e) {
      if (!mounted) return;
      _hinweis(e.nachricht);
    } catch (e) {
      if (!mounted) return;
      _hinweis('Konnte nicht gesendet werden: $e');
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: const Text(
          'Rueckmeldung',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Schreib uns direkt. Je konkreter, desto schneller koennen wir '
              'es abstellen oder einbauen.',
              style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in FeedbackKategorie.values)
                  _kategorieChip(k, accent),
              ],
            ),
            const SizedBox(height: 20),
            _feld(
              controller: _titel,
              label: 'Kurz auf den Punkt (optional)',
              hint: 'z. B. Karte bleibt beim Start schwarz',
              maxLines: 1,
              accent: accent,
            ),
            const SizedBox(height: 16),
            _feld(
              controller: _text,
              label: 'Deine Rueckmeldung',
              hint: null,
              maxLines: 12,
              accent: accent,
            ),
            const SizedBox(height: 20),
            _fotoBereich(accent),
            const SizedBox(height: 28),
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
                onPressed: _sendet ? null : _senden,
                child: _sendet
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Absenden',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Wir schicken die Version der App und deinen Gerätetyp mit, damit '
              'wir den Fehler nachstellen können.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kategorieChip(FeedbackKategorie k, Color accent) {
    final aktiv = k == _kategorie;
    return GestureDetector(
      onTap: () => _kategorieWechseln(k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: aktiv ? accent.withValues(alpha: 0.18) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: aktiv ? accent : Colors.white12,
            width: aktiv ? 1.4 : 1,
          ),
        ),
        child: Text(
          k.titel,
          style: TextStyle(
            color: aktiv ? accent : Colors.white70,
            fontSize: 13.5,
            fontWeight: aktiv ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _feld({
    required TextEditingController controller,
    required String label,
    required String? hint,
    required int maxLines,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 6 : 1,
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF161616),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fotoBereich(Color accent) {
    if (_foto == null) {
      return OutlinedButton.icon(
        onPressed: _fotoWaehlen,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
        label: const Text('Screenshot oder Foto anhaengen'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            _foto!,
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _fotoWaehlen,
              icon: Icon(Icons.swap_horiz, size: 18, color: accent),
              label: Text('Anderes Bild', style: TextStyle(color: accent)),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _foto = null),
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.white54,
              ),
              label: const Text(
                'Entfernen',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
