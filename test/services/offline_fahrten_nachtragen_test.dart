import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/offline_fahrten_warteschlange.dart';

/// 2026-08-26 (Nutzerbericht: „die App nimmt 50 % der Fahrten nicht wahr,
/// obwohl sie ueber 10 km lang waren — es koennte daran liegen, dass ich nicht
/// mit dem Internet verbunden war").
///
/// Die Wache gegen den Rueckfall: Eine Fahrt, die nicht gebucht werden kann,
/// muss liegen bleiben und nachgetragen werden — und dabei GENAU EINE Zeile
/// erzeugen, nicht zwei.
void main() {
  group('Doppelbuchungs-Schutz', () {
    test('eine schon gebuchte Fahrt erkennt man an 23505', () {
      expect(
        OfflineFahrtenWarteschlange.istSchonGebucht(
          const PostgrestException(message: 'duplicate key', code: '23505'),
        ),
        isTrue,
        reason:
            'derselbe Schluessel ein zweites Mal = die Zeile steht bereits; '
            'das ist ein Erfolg, kein Fehlschlag',
      );
    });

    test('jeder andere Fehler bleibt ein Fehlschlag', () {
      expect(
        OfflineFahrtenWarteschlange.istSchonGebucht(
          const PostgrestException(
            message: 'row-level security',
            code: '42501',
          ),
        ),
        isFalse,
      );
      expect(
        OfflineFahrtenWarteschlange.istSchonGebucht(
          const SocketException('kein Netz'),
        ),
        isFalse,
        reason:
            'ein Funkloch darf die Fahrt nicht aus der Warteschlange werfen',
      );
    });

    test('die Fahrt-id kommt vom Client und ist eine echte UUID v4', () {
      final ids = <String>{};
      for (var i = 0; i < 500; i++) {
        final id = GamificationService.neueSessionId();
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(id),
          isTrue,
          reason: 'Postgres nimmt nur eine gueltige uuid an: $id',
        );
        ids.add(id);
      }
      expect(
        ids.length,
        500,
        reason: 'zwei gleiche ids hiessen: eine Fahrt ueberschreibt die andere',
      );
    });
  });

  group('Warteschlange', () {
    Map<String, dynamic> fahrt(int nr) => {
      'id': 'id-$nr',
      'user_id': 'u',
      'distance_km': nr.toDouble(),
    };

    test('unter der Grenze bleibt alles liegen', () {
      final eintraege = [for (var i = 0; i < 10; i++) fahrt(i)];
      expect(OfflineFahrtenWarteschlange.begrenze(eintraege).length, 10);
    });

    test('ueber der Grenze fallen die AELTESTEN raus', () {
      final eintraege = [
        for (var i = 0; i < OfflineFahrtenWarteschlange.maxEintraege + 5; i++)
          fahrt(i),
      ];
      final begrenzt = OfflineFahrtenWarteschlange.begrenze(eintraege);
      expect(begrenzt.length, OfflineFahrtenWarteschlange.maxEintraege);
      expect(
        begrenzt.last['id'],
        'id-${OfflineFahrtenWarteschlange.maxEintraege + 4}',
        reason: 'die zuletzt gefahrene Fahrt ist die wichtigste',
      );
      expect(
        begrenzt.first['id'],
        'id-5',
        reason: 'die fuenf aeltesten sind gewichen, nicht die fuenf neuesten',
      );
    });
  });

  group('Verdrahtung', () {
    String quelle(String pfad) => File(pfad).readAsStringSync();

    test('die Buchung vergibt die id selbst', () {
      final gs = quelle('lib/data/services/gamification_service.dart');
      expect(
        gs.contains("row['id'] = sessionId;"),
        isTrue,
        reason:
            'ohne client-seitige id ist das Nachtragen nach verlorener '
            'Antwort nicht doppelsicher',
      );
    });

    test('ein Fehlschlag stellt die Fahrt an, statt sie zu verlieren', () {
      final gs = quelle('lib/data/services/gamification_service.dart');
      expect(
        gs.contains('await OfflineFahrtenWarteschlange.stelleAn(row);'),
        isTrue,
        reason: 'genau hier ging die Fahrt bisher verloren',
      );
    });

    test('die unterbrochene Fahrt stellt sich NICHT zusaetzlich an', () {
      final uv = quelle(
        'lib/data/services/unterbrochene_fahrt_verbuchung.dart',
      );
      expect(
        uv.contains('beiFehlerNachtragen: false'),
        isTrue,
        reason:
            'sie hat ihren eigenen zweiten Versuch; zwei Mechanismen fuer '
            'eine Fahrt koennen zwei Zeilen anlegen',
      );
    });

    test(
      'das Nachtragen laeuft beim App-Start, nicht erst in der Fahransicht',
      () {
        final main = quelle('lib/main.dart');
        expect(
          main.contains('OfflineFahrtenWarteschlange.starteNetzWache();'),
          isTrue,
          reason:
              'wer die App nach der Fahrt schliesst, sieht die Fahransicht nie '
              'wieder — die Startseite ist der Weg zurueck',
        );
      },
    );

    test('nach dem Nachtragen werden XP, Level und Badges nachgezogen', () {
      final wq = quelle('lib/data/services/offline_fahrten_warteschlange.dart');
      expect(
        wq.contains('await GamificationService.calculateAndSync();'),
        isTrue,
        reason:
            'die Zeile allein reicht nicht — profiles.total_xp und die Badges '
            'haengen sonst bis zur naechsten Fahrt hinterher',
      );
    });

    test('der Fahrer erfaehrt, dass seine Fahrt gesichert ist', () {
      final cm = quelle('lib/presentation/pages/cruise_mode_page.dart');
      expect(
        cm.contains('OfflineFahrtenWarteschlange.offeneFahrten.value > 0'),
        isTrue,
      );
      expect(
        cm.contains('wird nachgetragen, '),
        isTrue,
        reason:
            '„konnte nicht gespeichert werden" waere falsch — die Fahrt liegt '
            'auf der Platte',
      );
    });
  });
}
