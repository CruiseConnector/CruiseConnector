import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        final id = OfflineFahrtenWarteschlange.neueZeilenId();
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

  group('Verstopfte Warteschlange', () {
    test('eine fachliche Ablehnung des Servers zaehlt mit', () {
      expect(
        OfflineFahrtenWarteschlange.istServerAblehnung(
          const PostgrestException(message: 'null value', code: '23502'),
        ),
        isTrue,
        reason: 'das geht beim naechsten Versuch genauso aus',
      );
    });

    test('ein Funkloch zaehlt NICHT mit', () {
      expect(
        OfflineFahrtenWarteschlange.istServerAblehnung(
          const SocketException('kein Netz'),
        ),
        isFalse,
        reason:
            'sonst verbraucht eine lange Fahrt ohne Empfang die Versuche, '
            'obwohl mit der Zeile alles in Ordnung ist',
      );
      expect(
        OfflineFahrtenWarteschlange.istServerAblehnung(
          const PostgrestException(message: 'keine Antwort'),
        ),
        isFalse,
        reason: 'ohne Fehlercode hat der Server nichts entschieden',
      );
    });

    test('die schon gebuchte Zeile ist keine Ablehnung', () {
      expect(
        OfflineFahrtenWarteschlange.istServerAblehnung(
          const PostgrestException(message: 'duplicate key', code: '23505'),
        ),
        isFalse,
        reason: '23505 ist ein Erfolg und faellt vorher schon raus',
      );
    });

    test('nach drei Ablehnungen fliegt der Eintrag raus', () {
      expect(OfflineFahrtenWarteschlange.maxVersuche, 3);
      final wq = File(
        'lib/data/services/offline_fahrten_warteschlange.dart',
      ).readAsStringSync();
      expect(
        wq.contains('if (versuche >= maxVersuche) {'),
        isTrue,
        reason:
            'eine verlorene Fahrt ist schlimm, eine dauerhaft verstopfte '
            'Warteschlange blockiert ALLE spaeteren',
      );
    });
  });

  group('Offline-Grenze von einem Kilometer', () {
    test('die Grenze ist genau ein Kilometer', () {
      expect(OfflineFahrtenWarteschlange.mindestKmOffline, 1.0);
    });

    test('Fahrt und Strecke werden beide gemessen', () {
      expect(
        OfflineFahrtenWarteschlange.kilometer({'distance_km': 12.4}),
        12.4,
      );
      expect(OfflineFahrtenWarteschlange.kilometer({'driven_km': 3.2}), 3.2);
      expect(
        OfflineFahrtenWarteschlange.kilometer({'distance_actual': 7}),
        7.0,
        reason: 'die Strecke fuehrt die Kilometer unter einem anderen Namen',
      );
    });

    test('eine Zeile ohne Kilometerangabe zaehlt als null', () {
      expect(OfflineFahrtenWarteschlange.kilometer({'user_id': 'u'}), 0.0);
    });

    test('Kilometer als Text (numeric aus Postgres) werden gelesen', () {
      expect(
        OfflineFahrtenWarteschlange.kilometer({'distance_km': '10.5'}),
        10.5,
        reason: 'numeric kommt aus PostgREST je nach Weg als String zurueck',
      );
    });
  });

  group('Verdrahtung', () {
    String quelle(String pfad) => File(pfad).readAsStringSync();

    test('unter einem Kilometer wird offline nichts angestellt', () {
      final wq = quelle('lib/data/services/offline_fahrten_warteschlange.dart');
      expect(
        wq.contains('if (km <= mindestKmOffline) {'),
        isTrue,
        reason:
            'Vucko: "es sollte mehr wie ein kilometer sein wenn du offline "\n'
            '"bist" — die Grenze gehoert an die Warteschlange, nicht an den '
            'Abschluss, sonst gaelte sie auch online',
      );
    });

    test('auch die STRECKE wandert in die Warteschlange', () {
      final sr = quelle('lib/data/services/saved_routes_service.dart');
      expect(
        sr.contains('tabelle: OfflineFahrtenWarteschlange.tabelleStrecke'),
        isTrue,
        reason:
            'sonst kommt die Fahrt zwar in den Statistiken an, "Meine '
            'Strecken" bleibt aber leer',
      );
      expect(
        sr.contains("row['id'] = OfflineFahrtenWarteschlange.neueZeilenId();"),
        isTrue,
        reason: 'ohne Client-id ist auch die Strecke nicht doppelsicher',
      );
    });

    test('das Nachtragen schreibt in die Tabelle des Eintrags', () {
      final wq = quelle('lib/data/services/offline_fahrten_warteschlange.dart');
      expect(
        wq.contains('await _db.from(tabelle).insert(zeile);'),
        isTrue,
        reason:
            'fest verdrahtet auf user_drive_sessions ginge die Strecke ins '
            'falsche Ziel',
      );
    });

    test('die Strecke wird auch dann versucht, wenn die Buchung scheitert', () {
      final cm = quelle('lib/presentation/pages/cruise_mode_page.dart');
      final i = cm.indexOf('Object? buchungsFehler;');
      expect(
        i,
        greaterThan(0),
        reason:
            'flog der Fehler direkt nach oben, wurde saveRoute offline nie '
            'erreicht und die Strecke kam nicht in die Warteschlange',
      );
      final rumpf = cm.substring(i, i + 2500);
      expect(
        rumpf.contains('savedRouteId = await SavedRoutesService.saveRoute('),
        isTrue,
        reason: 'das Speichern der Strecke muss NACH dem Fang stehen',
      );
      expect(
        rumpf.contains('if (buchungsFehler != null) throw buchungsFehler;'),
        isTrue,
        reason:
            'verschluckt darf der Fehler nicht werden — sonst faende der '
            'Fahrer nie heraus, dass seine Fahrt noch wartet',
      );
    });

    test('die Aufzeichnung wartet nicht ewig auf die Serien-Abfrage', () {
      final cm = quelle('lib/presentation/pages/cruise_mode_page.dart');
      expect(
        cm.contains('.timeout(const Duration(seconds: 4), onTimeout: () => 1)'),
        isTrue,
        reason:
            'die Abfrage laeuft vor dem Scharfschalten der Aufzeichnung; '
            'haengt sie, passiert nach dem Tipp sichtbar nichts',
      );
    });

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
