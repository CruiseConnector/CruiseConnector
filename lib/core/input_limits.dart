import 'package:flutter/services.dart';

class AppInputLimits {
  AppInputLimits._();

  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 20;
  static const int postContentMaxLength = 1000;
  static const int commentMaxLength = 1000;
  static const int groupNameMaxLength = 25;
  static const int groupDescriptionMaxLength = 300;
  static const int communityNameMaxLength = 40;
  static const int communityDescriptionMaxLength = 300;
  static const int communityMessageMaxLength = 2000;
  static const int groupRouteNameMaxLength = 80;
  static const int groupStatsMaxLength = 120;
  static const int groupTimeLocationMaxLength = 160;
  static const int bioTitleMaxLength = 40;
  static const int bioMaxLength = 500;
  static const int linkMaxLength = 200;
  static const int routeNameMaxLength = 60;
  static const int shortTextMaxLength = 32;
  static const int addressMaxLength = 160;
  static const int searchQueryMaxLength = 64;
  static const int emailMaxLength = 254;
  static const int passwordMaxLength = 128;
  // Supabase erzwingt serverseitig min. 6 Zeichen — die App prüft das vorher,
  // damit der Nutzer keinen englischen GoTrue-Fehler zu sehen bekommt.
  static const int passwordMinLength = 6;
  static const int reportDetailsMaxLength = 280;
  static const int vehicleDescriptionMaxLength = 500;
  static const int vehicleTuningMaxLength = 500;

  // ── @-Name: erlaubte Zeichen ────────────────────────────────────────────
  //
  // 2026-08-25 (Vucko): „schau auch noch das man beim benutzernamen aeoeue
  // verwenden kann das ist bis jetzt nicht gegangen". Erlaubt sind ab jetzt
  // die DEUTSCHEN Umlaute und das ß — sonst nichts Neues.
  //
  // Warum nicht einfach „alle Buchstaben der Welt"? Weil das kyrillische „а"
  // aussieht wie das lateinische „a". Damit könnte jemand einen fremden
  // @-Namen zeichengenau nachbauen und in seinem Namen schreiben. Genau
  // deshalb lassen Instagram und X nur ASCII zu. Sieben Zeichen mehr sind
  // überschaubar; ein ganzes Alphabet mehr wäre eine Einladung.
  //
  // Diese Klasse muss zeichengleich mit dem CHECK `profiles_username_format`
  // und `public.is_valid_username_format(text)` aus der Migration
  // `20260825100000_benutzername_umlaute_und_verwechslungsschutz.sql` sein.
  // Sagt die App „frei" und die Datenbank lehnt danach ab, ärgert sich der
  // Nutzer zweimal. `test/core/benutzername_umlaute_test.dart` vergleicht
  // beide Seiten und wird rot, wenn sie auseinanderlaufen.
  static const String usernameAllowedChars = r'A-Za-z0-9_äöüÄÖÜß';

  static final RegExp usernameRegExp = RegExp(
    '^[$usernameAllowedChars]{$usernameMinLength,$usernameMaxLength}\$',
  );

  static final List<TextInputFormatter> usernameFormatters = [
    FilteringTextInputFormatter.allow(RegExp('[$usernameAllowedChars]')),
    LengthLimitingTextInputFormatter(usernameMaxLength),
  ];

  /// Faltung fuer den VERGLEICH zweier @-Namen — nie fuer die Anzeige.
  ///
  /// Angezeigt wird immer, was der Nutzer getippt hat. Verglichen wird über
  /// diesen Schlüssel: klein geschrieben, ae/oe/ue/ss ausgeschrieben. Damit
  /// ist „müller" nicht mehr frei, wenn „Mueller" schon vergeben ist — sonst
  /// stehen zwei praktisch gleich aussehende @-Namen nebeneinander und eine
  /// Nachricht von „@müller" wird für eine von „@mueller" gehalten.
  ///
  /// Das ist die Dart-Entsprechung von
  /// `public.benutzername_schluessel(text)` aus der Migration
  /// `20260825100000_benutzername_umlaute_und_verwechslungsschutz.sql`.
  /// `test/core/benutzername_umlaute_test.dart` liest diese Migration und
  /// wird rot, sobald die beiden auseinanderlaufen.
  ///
  /// Hier wird NICHT entschieden, ob ein Name frei ist — das macht
  /// ausschliesslich die Datenbank (`username_available`, dahinter der
  /// UNIQUE-Index über dieselbe Faltung). Der Schlüssel dient nur der
  /// ERKLAERUNG in der Oberfläche („müller zählt wie mueller").
  static String usernameKey(String value) {
    var key = value.trim().toLowerCase();
    for (final entry in usernameKeyReplacements.entries) {
      key = key.replaceAll(entry.key, entry.value);
    }
    return key;
  }

  /// Ausgeschriebene Paare, zeichengleich mit `benutzername_schluessel`.
  ///
  /// Bewusst NUR die sieben deutschen Sonderzeichen — nicht die längere
  /// Tabelle aus `hashtag_schluessel`. Alles andere kann in einem @-Namen
  /// gar nicht vorkommen, und die Faltung der Benutzernamen steckt in einem
  /// UNIQUE-Index: sie darf sich nicht mitverändern, wenn die Hashtags ihre
  /// Faltung erweitern.
  static const Map<String, String> usernameKeyReplacements = {
    'ä': 'ae',
    'ö': 'oe',
    'ü': 'ue',
    'ß': 'ss',
  };

  /// True, wenn sich der @-Name durch die Faltung veraendert — also wenn dem
  /// Nutzer erklaert werden muss, warum sein Name mit einem anderen kollidiert.
  static bool usernameNeedsFoldingHint(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && usernameKey(trimmed) != trimmed;
  }

  /// Der Zusatz zur Meldung „schon vergeben". Leer, wenn es nichts zu
  /// erklaeren gibt (dann kollidiert der Name zeichengenau).
  ///
  /// „Name schon vergeben" allein verwirrt, seit Umlaute erlaubt sind: wer
  /// „müller" tippt und „mueller" nie gesehen hat, versteht nicht, womit sein
  /// Name kollidiert. Der Text steht hier und nicht in einer einzelnen Seite,
  /// damit @-Name-Onboarding und Profil-Bearbeiten dieselbe Erklaerung geben.
  static String usernameFoldingHint(String value) {
    final trimmed = value.trim();
    if (!usernameNeedsFoldingHint(trimmed)) return '';
    return ' „$trimmed" zählt dabei wie „${usernameKey(trimmed)}". Groß- und '
        'Kleinschreibung sowie ä ö ü ß werden beim Vergleich gleich behandelt.';
  }

  static List<TextInputFormatter> lengthFormatters(int maxLength) {
    return [LengthLimitingTextInputFormatter(maxLength)];
  }

  /// Formatregel des @-Namens — zeichengleich mit
  /// `public.is_valid_username_format(text)` in der Datenbank.
  ///
  /// Die Datenbank verbietet zusaetzlich zum Zeichenvorrat doppelte
  /// Unterstriche und Unterstriche am Anfang oder Ende. Das stand bisher nur
  /// im Hinweistext der Oberfläche, wurde aber nicht geprüft: die App sagte
  /// „frei", der Server lehnte beim Speichern mit `invalid_format` ab.
  static bool isValidUsername(String value) {
    final trimmed = value.trim();
    return usernameRegExp.hasMatch(trimmed) &&
        !trimmed.contains('__') &&
        !trimmed.startsWith('_') &&
        !trimmed.endsWith('_');
  }

  /// Macht aus einem beliebigen Namen (Apple/Google-Anzeigename, E-Mail-Teil)
  /// einen @-Namen-Kandidaten: Umlaute BLEIBEN, alles andere Fremde wird zu
  /// `_`, Unterstriche werden zusammengezogen und aussen abgeschnitten.
  ///
  /// Das Ergebnis kann trotzdem ungueltig sein (zu kurz, leer) — das prueft
  /// der Aufrufer mit [isValidUsername] und weicht dann auf einen
  /// Ersatznamen aus.
  static String sanitizeUsername(String value) {
    var cleaned = value
        .trim()
        .replaceAll(RegExp('[^$usernameAllowedChars]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (cleaned.length > usernameMaxLength) {
      cleaned = cleaned.substring(0, usernameMaxLength);
    }
    // Nach dem Abschneiden kann wieder ein `_` am Ende stehen — das lehnt die
    // Datenbank ab, also nochmal wegnehmen.
    return cleaned.replaceAll(RegExp(r'_+$'), '');
  }

  /// Passwort-Regel der App (bewusst NICHT trimmen — Leerzeichen sind erlaubt).
  static bool isValidPassword(String value) {
    return value.length >= passwordMinLength &&
        value.length <= passwordMaxLength;
  }

  /// Grobe E-Mail-Plausibilitaet fuer Formulare (kein RFC-Parser).
  static bool looksLikeEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > emailMaxLength) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(trimmed);
  }

  static String normalizeUsernameFallback(String value) {
    final normalized = sanitizeUsername(value);
    final fallback = normalized.isEmpty
        ? 'Cruiser'
        : normalized.length < usernameMinLength
        ? 'Cruiser_$normalized'
        : normalized;
    return sanitizeUsername(fallback);
  }
}
