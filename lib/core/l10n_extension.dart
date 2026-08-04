// Kurzer Zugriff auf die Übersetzungen (2026-08-03, vucko Sprachumschaltung).
//
// `AppLocalizations.of(context)` an ~2.000 Stellen wäre unlesbar — mit dieser
// Extension steht im Widget-Code `context.l10n.commonSave`.

import 'package:flutter/widgets.dart';

import 'package:cruise_connect/l10n/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  /// Übersetzungen für den aktuellen Kontext.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Übersetzungen für Code OHNE BuildContext (Services, Provider).
///
/// Hintergrund: Mehrere Services werfen fertige, für den Nutzer sichtbare
/// Meldungen (z. B. AuthService: „Diese E-Mail ist bereits registriert."). Die
/// sauberste Lösung wäre, dort nur Fehlercodes zu werfen und erst in der UI zu
/// übersetzen — das wäre aber ein Umbau quer durch alle Services und damit ein
/// zweites, größeres Risiko neben der Übersetzung selbst.
///
/// Diese Klasse hält deshalb die aktuell aktiven Übersetzungen bereit. Gesetzt
/// wird sie ausschliesslich vom App-Root (main.dart), sobald die Sprache steht
/// oder wechselt. Vor dem ersten Setzen ist [maybeCurrent] null — Aufrufer
/// müssen dann auf ihren bisherigen deutschen Text zurückfallen.
class L10n {
  L10n._();

  static AppLocalizations? _current;

  /// Aktive Übersetzungen oder null, solange die App noch nicht aufgebaut ist.
  static AppLocalizations? get maybeCurrent => _current;

  static void update(AppLocalizations localizations) {
    _current = localizations;
  }
}
