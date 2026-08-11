import 'package:cruise_connect/data/services/social_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „ich moechte, dass man nicht zwingend eine Uhrzeit bzw.
/// ein Datum einstellen muss. Das soll zusaetzlich sein."
///
/// Seit die Startzeit optional ist, gibt es Gruppen ohne Zeit. Die alte
/// Sortierung schob sie ans ENDE der Liste — und weil die Entdecken-Abfrage bei
/// `.limit(80)` / `.take(40)` abschneidet, waeren spontane Gruppen faktisch nie
/// sichtbar geworden. Das Feature waere still tot gewesen. Diese Tests halten
/// die Reihenfolge fest.
void main() {
  String iso(Duration versatz) =>
      DateTime.now().add(versatz).toIso8601String();

  Map<String, dynamic> gruppe(
    String name, {
    String? start,
    Duration angelegtVor = Duration.zero,
  }) => {
    'name': name,
    if (start != null) 'start_time': start,
    'created_at': DateTime.now().subtract(angelegtVor).toIso8601String(),
  };

  List<String> namen(List<Map<String, dynamic>> l) =>
      l.map((g) => g['name'] as String).toList();

  test('spontane Gruppen stehen vor abgelaufenen', () {
    final liste = [
      gruppe('vorbei', start: iso(const Duration(hours: -5))),
      gruppe('spontan'),
      gruppe('bald', start: iso(const Duration(hours: 3))),
    ];
    SocialService.sortiereFuerTest(liste);
    expect(namen(liste), ['bald', 'spontan', 'vorbei']);
  });

  test('bevorstehende Termine: der naechste zuerst', () {
    final liste = [
      gruppe('spaeter', start: iso(const Duration(hours: 9))),
      gruppe('gleich', start: iso(const Duration(hours: 1))),
      gruppe('mittig', start: iso(const Duration(hours: 4))),
    ];
    SocialService.sortiereFuerTest(liste);
    expect(namen(liste), ['gleich', 'mittig', 'spaeter']);
  });

  test('spontane Gruppen: die neueste zuerst', () {
    final liste = [
      gruppe('alt', angelegtVor: const Duration(days: 3)),
      gruppe('frisch', angelegtVor: const Duration(minutes: 5)),
      gruppe('mittel', angelegtVor: const Duration(hours: 6)),
    ];
    SocialService.sortiereFuerTest(liste);
    expect(namen(liste), ['frisch', 'mittel', 'alt']);
  });

  // Der eigentliche Sinn der Aenderung: Eine spontane Gruppe darf nicht hinter
  // lauter abgelaufenen Terminen landen und dadurch aus der Liste fallen.
  test('spontane Gruppe faellt nicht aus einer abgeschnittenen Liste', () {
    final liste = <Map<String, dynamic>>[
      for (var i = 0; i < 40; i++)
        gruppe('vorbei$i', start: iso(Duration(hours: -1 - i))),
      gruppe('spontan'),
    ];
    SocialService.sortiereFuerTest(liste);
    final ersteVierzig = namen(liste).take(40);
    expect(
      ersteVierzig,
      contains('spontan'),
      reason: 'sonst waere sie in Entdecken unsichtbar',
    );
  });

  test('leere Liste und fehlende Felder stuerzen nicht ab', () {
    final leer = <Map<String, dynamic>>[];
    SocialService.sortiereFuerTest(leer);
    expect(leer, isEmpty);

    final kaputt = <Map<String, dynamic>>[
      {'name': 'ohne alles'},
      {'name': 'muell', 'start_time': 'kein datum'},
    ];
    SocialService.sortiereFuerTest(kaputt);
    expect(kaputt, hasLength(2));
  });
}
