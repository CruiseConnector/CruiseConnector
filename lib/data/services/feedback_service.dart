import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kategorien der Rueckmeldung. Die Werte muessen zu der Pruefung
/// `app_feedback_kategorie` in der Datenbank passen.
enum FeedbackKategorie { fehler, idee, lob, sonstiges }

extension FeedbackKategorieX on FeedbackKategorie {
  String get wert => name;

  String get titel => switch (this) {
    FeedbackKategorie.fehler => 'Etwas funktioniert nicht',
    FeedbackKategorie.idee => 'Ich habe eine Idee',
    FeedbackKategorie.lob => 'Lob',
    FeedbackKategorie.sonstiges => 'Sonstiges',
  };

  /// Die vorgefertigte Vorlage im Textfeld.
  ///
  /// 2026-08-09 (vucko): „mit einem vorgefertigten Layout". Eine leere Box
  /// bringt Rueckmeldungen wie „geht nicht" — mit diesen drei Zeilen kommt
  /// etwas an, mit dem man wirklich arbeiten kann.
  String get vorlage => switch (this) {
    FeedbackKategorie.fehler =>
      'Was ist passiert?\n\n\n'
          'Was haettest du erwartet?\n\n\n'
          'Wann ist es passiert (z. B. waehrend der Fahrt, beim Start)?\n',
    FeedbackKategorie.idee =>
      'Was fehlt dir?\n\n\n'
          'Wobei wuerde es dir helfen?\n',
    FeedbackKategorie.lob =>
      'Was gefaellt dir besonders?\n\n\n'
          'Was sollen wir auf keinen Fall aendern?\n',
    FeedbackKategorie.sonstiges => '',
  };
}

class FeedbackFehler implements Exception {
  const FeedbackFehler(this.nachricht);
  final String nachricht;
  @override
  String toString() => nachricht;
}

/// Rueckmeldungen aus den Einstellungen — inklusive Foto.
///
/// 2026-08-09 (vucko): „Feedback-Funktion in den Einstellungen mit einem
/// vorgefertigten Layout und der Moeglichkeit, ein Foto anzuhaengen."
class FeedbackService {
  FeedbackService._();

  static const String _bucket = 'feedback';

  static SupabaseClient get _db => Supabase.instance.client;

  /// Laedt das Foto hoch und liefert den Speicherpfad im Bucket.
  ///
  /// Der Bucket ist privat und nach Nutzer-Ordner getrennt (RLS), deshalb wird
  /// bewusst der PFAD gespeichert und keine oeffentliche URL: Screenshots
  /// enthalten oft Standort, Namen oder Chatinhalte.
  static Future<String?> _fotoHochladen(Uint8List bytes, String userId) async {
    final pfad = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from(_bucket)
        .uploadBinary(
          pfad,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    return pfad;
  }

  static Future<String> _geraeteInfo() async {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unbekannt';
    }
  }

  static Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  /// Schickt die Rueckmeldung ab.
  ///
  /// Wirft [FeedbackFehler] mit einem Text, der dem Nutzer direkt gezeigt
  /// werden kann — im Gegensatz zur Sterne-Abfrage nach der Fahrt darf hier
  /// nichts still verloren gehen: Wer ein Formular ausfuellt, will wissen, ob
  /// es angekommen ist.
  static Future<void> senden({
    required FeedbackKategorie kategorie,
    required String titel,
    required String text,
    Uint8List? foto,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw const FeedbackFehler('Bitte melde dich an, um uns zu schreiben.');
    }
    if (text.trim().isEmpty) {
      throw const FeedbackFehler('Bitte schreib uns ein paar Zeilen.');
    }

    String? fotoPfad;
    if (foto != null) {
      try {
        fotoPfad = await _fotoHochladen(foto, user.id);
      } catch (e) {
        debugPrint('[Feedback] Foto-Upload fehlgeschlagen: $e');
        // Bewusst abbrechen statt still ohne Bild zu senden: Wer ein Foto
        // anhaengt, haelt es fuer den wichtigsten Teil. Er soll selbst
        // entscheiden, ob er es ohne abschickt.
        throw const FeedbackFehler(
          'Das Foto konnte nicht hochgeladen werden. Schick die Rueckmeldung '
          'gern ohne Foto ab — der Text hilft uns schon weiter.',
        );
      }
    }

    try {
      await _db.from('app_feedback').insert({
        'user_id': user.id,
        'source': 'einstellungen',
        'category': kategorie.wert,
        'title': titel.trim().isEmpty ? null : titel.trim(),
        'comment': text.trim(),
        'screenshot_url': fotoPfad,
        'app_version': await _appVersion(),
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
        'device_info': await _geraeteInfo(),
      });
    } on PostgrestException catch (e) {
      // Das Stundenlimit aus dem Trigger kommt als check_violation zurueck.
      if (e.message.contains('Zu viele Rueckmeldungen')) {
        throw const FeedbackFehler(
          'Du hast uns gerade schon mehrfach geschrieben. Bitte versuch es in '
          'einer Stunde noch einmal — wir lesen alles.',
        );
      }
      throw FeedbackFehler('Konnte nicht gesendet werden: ${e.message}');
    }
  }
}
