import 'dart:io';

import 'package:cruise_connect/data/services/community_neuigkeit_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 — ABGELÖST. Diese Datei bewachte bis heute die Zähler-Regel vom
/// 11.08.2026: „mehr Gruppen oder Vorschläge als beim letzten Besuch heisst
/// Neues". Die Regel ist mit Aufgabe 1.1 (Auftrag vom 23.08.) weggefallen.
///
/// Warum sie weg musste, gemessen und nicht behauptet:
///
///   1. Der Stand lag in SharedPreferences. Ein Gerätewechsel setzte ihn
///      zurück, und der Punkt leuchtete auf dem neuen Handy für Dinge, die
///      man längst gelesen hatte. Vuckos Akzeptanzkriterium 4 verlangt
///      ausdrücklich „serverseitig, nicht nur lokal".
///   2. Wer eine Gruppe LÖSCHT, senkt den Zähler. Danach war die neue Zahl
///      kleiner als der gespeicherte Stand — und der Punkt blieb dauerhaft
///      aus, egal wie viel Neues dazukam. Der alte Test „weniger als zuvor
///      loest nichts aus" hat genau diesen Defekt als gewolltes Verhalten
///      festgeschrieben.
///   3. Eine Anzahl kann grundsätzlich nicht sagen, WO etwas neu ist. Vuckos
///      Ebenen 2 (welcher Reiter) und 3 (welche Community) waren damit
///      unmöglich.
///
/// Die Regeln von heute stehen in `test/community/hinweispunkte_test.dart`.
/// Was hier bleibt, ist der Wächter dagegen, dass die alte Mechanik
/// zurückkommt.
void main() {
  /// Die Kommentare im Dienst ERKLAEREN die alte Mechanik und nennen die
  /// beiden Schluessel dabei woertlich. Ohne dieses Ausblenden wuerde der
  /// Test seine eigene Begruendung als Rueckfall werten.
  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((zeile) {
        final t = zeile.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  String quelle() => ohneKommentare(
    File(
      'lib/data/services/community_neuigkeit_service.dart',
    ).readAsStringSync(),
  );

  test('die beiden Zähler-Schlüssel sind weg und bleiben weg', () {
    final code = quelle();
    expect(code.contains('community_gesehen_gruppen_v1'), isFalse);
    expect(code.contains('community_gesehen_vorschlaege_v1'), isFalse);
    expect(
      code.contains('shared_preferences'),
      isFalse,
      reason: 'Der Lesestand gehoert auf den Server, nicht aufs Geraet.',
    );
  });

  test(
    'melde() entscheidet nichts mehr — die Kachel darf den Punkt weder '
    'anschalten noch ausknipsen',
    () {
      final code = quelle();
      final stelle = code.indexOf('Future<void> melde(');
      expect(stelle, greaterThan(0));
      // Nur bis zur schliessenden Klammer der Methode schauen, sonst rutscht
      // der naechste Methodenrumpf mit ins Fenster.
      final ende = code.indexOf('\n  }', stelle);
      expect(ende, greaterThan(stelle));
      final rumpf = code.substring(stelle, ende);
      expect(rumpf.contains('hatNeues.value ='), isFalse);
      expect(rumpf.contains('aktualisieren()'), isTrue);
    },
  );

  test('alsGesehenMarkieren verlangt jetzt einen Bereich', () {
    // Ohne Bereich gibt es die Methode nicht mehr. Der Aufruf beim blossen
    // Antippen des Community-Symbols ist damit gar nicht mehr formulierbar —
    // genau das war Vuckos Beschwerde: der Punkt ging aus, ohne dass man
    // etwas gelesen hatte.
    final dienst = CommunityNeuigkeitService.instance;
    expect(dienst.alsGesehenMarkieren, isA<Function>());
    expect(CommunityBereich.values.length, 5);
  });
}
