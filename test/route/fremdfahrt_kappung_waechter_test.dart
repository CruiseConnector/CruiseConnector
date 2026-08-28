import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-28 (vucko Fehler 8, Stalking-Schutz): Quelltext-Waechter.
///
/// JEDER Einstieg, der `CruiseModePage.pendingRoute` mit einer Route setzt,
/// MUSS vorher durch `SavedRoute.fuerFremdfahrt` gehen — sonst startet ein
/// fremder Nutzer an der Haustuer des Besitzers. Der Waechter liest den
/// Quelltext unter lib/ und schlaegt bei jeder Zuweisung fehl, die nicht
/// nachweislich die gekappte Fassung uebergibt.
///
/// ERLAUBT sind genau drei Formen:
///  1. `pendingRoute.value = null` — Aufraeumen, keine Fahrt.
///  2. `pendingRoute.value = fahrbareRoute` in einer Datei, die die
///     Variable ueber `.fuerFremdfahrt(` erzeugt (der gemeinsame Weg).
///  3. Die Wiederaufnahme der EIGENEN unterbrochenen Fahrt in
///     home_content_page.dart — erkennbar daran, dass unmittelbar davor
///     `pendingResumeProgress.value` gesetzt wird. Diese Route ist lokal
///     gebaut (userId null) und darf ungekappt bleiben.
///
/// cruise_mode_page.dart selbst ist ausgenommen: die Seite BESITZT den
/// Notifier und setzt ihn nach dem Verbrauch zurueck; neue Fahr-Einstiege
/// gehoeren nicht dorthin.
///
/// WENN DER TEST ROT IST: die neue Stelle nicht freischalten, sondern durch
/// `route.fuerFremdfahrt(eigeneId)` schicken und das Ergebnis (mit
/// null-Pruefung und ehrlichem Hinweis bei zu kurzer Route) zuweisen —
/// Vorbild ist `_startRide` in route_attachment_card.dart.
void main() {
  final libVerzeichnis = Directory('lib');

  // 2026-08-28 (Abnahmefund): Die erste Fassung fing nur einfache
  // Bezeichner (`= route;`). Eine Zuweisung wie `= widget.route;` oder ein
  // beliebiger Ausdruck rutschte UNSICHTBAR durch — kein Rot, kein Hinweis.
  // Jetzt wird ALLES bis zum Semikolon erfasst (die negierte Klasse laeuft
  // auch ueber Zeilenumbrueche) und nur die drei bekannten Formen bestehen.
  final zuweisung = RegExp(r'pendingRoute\.value\s*=\s*([^;]+);');

  test('kein Einstieg setzt pendingRoute mit einer ungekappten Route', () {
    expect(
      libVerzeichnis.existsSync(),
      isTrue,
      reason: 'Test muss im Repo-Wurzelverzeichnis laufen (flutter test).',
    );

    final verstoesse = <String>[];

    final dateien = libVerzeichnis
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('cruise_mode_page.dart'));

    for (final datei in dateien) {
      final quelle = datei.readAsStringSync();
      for (final treffer in zuweisung.allMatches(quelle)) {
        final ziel = treffer.group(1)!.trim();
        if (ziel == 'null') continue;

        // Der gemeinsame Weg: Variable heisst fahrbareRoute und wird IN DER
        // NAEHE der Zuweisung aus fuerFremdfahrt erzeugt (Abnahmefund: die
        // dateiweite Pruefung liess jede zweite, rohe Zuweisung in derselben
        // Datei durch).
        final davor = quelle.substring(
          math.max(0, treffer.start - 800),
          treffer.start,
        );
        if (ziel == 'fahrbareRoute' && davor.contains('.fuerFremdfahrt(')) {
          continue;
        }

        // Einzige Ausnahme: Wiederaufnahme der eigenen Fahrt. Direkt vor
        // der Zuweisung wird der Fortschritts-Schnappschuss gesetzt.
        if (datei.path.endsWith('home_content_page.dart') &&
            davor.contains('pendingResumeProgress.value')) {
          continue;
        }

        final zeile =
            quelle.substring(0, treffer.start).split('\n').length;
        verstoesse.add('${datei.path}:$zeile  pendingRoute.value = $ziel');
      }
    }

    expect(
      verstoesse,
      isEmpty,
      reason:
          'Diese Stellen setzen pendingRoute ohne die Fremdfahrt-Kappung. '
          'Durch route.fuerFremdfahrt(eigeneId) schicken, null pruefen, '
          'dann fahrbareRoute zuweisen:\n${verstoesse.join('\n')}',
    );
  });

  test('route_attachment_card setzt nie die rohe fremde Route', () {
    final quelle = File(
      'lib/presentation/widgets/social/route_attachment_card.dart',
    ).readAsStringSync();

    expect(
      quelle.contains('.fuerFremdfahrt('),
      isTrue,
      reason:
          'route_attachment_card.dart muss den gemeinsamen Weg '
          'SavedRoute.fuerFremdfahrt benutzen.',
    );
    expect(
      RegExp(r'pendingRoute\.value\s*=\s*_?route\b').hasMatch(quelle),
      isFalse,
      reason:
          'route_attachment_card.dart darf die geladene Route nie direkt '
          'an pendingRoute uebergeben — nur die gekappte fahrbareRoute.',
    );
  });
}
