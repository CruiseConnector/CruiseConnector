import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cruise_connect/core/legal_documents.dart';

/// Ein einzelner Startversuch. Ausgelagert, damit Tests den Fehlschlag
/// nachstellen koennen, ohne echte Plattform-Kanaele zu brauchen.
typedef LegalUrlOpener = Future<bool> Function(Uri uri, LaunchMode mode);

/// 2026-08-24 (Vorfall „Nutzer sitzt im Rechts-Tor fest"): Hier stand genau
/// EIN Startversuch mit `LaunchMode.externalApplication`. Lieferte der false —
/// gesperrter Browser (Bildschirmzeit, verwaltetes Geraet), kein Standard-
/// browser gesetzt, Web-Inhalte gesperrt —, blieb im Rechts-Tor das Haekchen
/// fuer immer gesperrt und damit die ganze App unbenutzbar.
///
/// Jetzt drei Wege in dieser Reihenfolge:
///  1. `externalApplication` — der eigene Browser des Nutzers, beste Lesbarkeit.
///  2. `inAppBrowserView` — Custom Tabs (Android) / SFSafariViewController
///     (iOS). Greift, wenn gar kein Standardbrowser gesetzt ist.
///  3. `platformDefault` — was das System sonst noch anbietet.
///
/// Jeder Versuch hat eine eigene Frist. Antwortet der Plattform-Kanal gar
/// nicht (haengendes System, deaktivierte Komponente), laeuft die Frist ab
/// statt den Aufrufer ewig warten zu lassen.
const List<LaunchMode> legalLaunchModes = <LaunchMode>[
  LaunchMode.externalApplication,
  LaunchMode.inAppBrowserView,
  LaunchMode.platformDefault,
];

/// Frist je Startversuch. Kurz genug, dass der Nutzer nicht glaubt, die App
/// haenge; lang genug fuer langsame Geraete.
const Duration legalLaunchTimeout = Duration(seconds: 5);

/// Testhaken. Nur in Tests setzen, in `addTearDown` wieder auf null.
@visibleForTesting
LegalUrlOpener? debugLegalUrlOpener;

Future<bool> _standardOpener(Uri uri, LaunchMode mode) =>
    launchUrl(uri, mode: mode);

/// Versucht, das Rechtsdokument zum Lesen zu oeffnen.
///
/// Liefert true, sobald EIN Weg funktioniert hat. Liefert false erst, wenn
/// ALLE Wege fehlgeschlagen sind — dann muss der Aufrufer dem Nutzer einen
/// Ersatzweg anbieten (siehe `legal_acceptance_page.dart`). Wirft nie.
Future<bool> launchLegalDocument(LegalDocument document) async {
  final opener = debugLegalUrlOpener ?? _standardOpener;
  for (final mode in legalLaunchModes) {
    try {
      final ok = await opener(
        document.uri,
        mode,
      ).timeout(legalLaunchTimeout, onTimeout: () => false);
      if (ok) return true;
      debugPrint('[LegalLink] ${document.url} via $mode: kein Erfolg.');
    } catch (e) {
      debugPrint('[LegalLink] ${document.url} via $mode fehlgeschlagen: $e');
    }
  }
  return false;
}
