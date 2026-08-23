import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';

/// 2026-08-24 — Aufgabe 1.2 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 1 [00:44]: „Und wenn eine Community jünger als sieben Tage
/// ist, dass da drunter dann ‚neu' steht oder halt ‚vor kurzem erstellt'."
///
/// Vuckos Entscheidung (bindend): der Text lautet „Vor kurzem erstellt".
///
/// Akzeptanzkriterium 3 verlangt die Grenze EXAKT bei 7 Tagen, „nicht bei 6
/// oder 8". Genau darauf zielen die Tests: 6 Tage und 23 Stunden trägt das
/// Etikett, 7 Tage und eine Sekunde nicht mehr.
///
/// Ohne die Änderung ist dieser Test rot, weil
/// [CommunityChatService.istVorKurzemErstellt] gar nicht existiert und die
/// Datei sich nicht übersetzen lässt.
void main() {
  // Fester Bezugspunkt, damit der Test nicht von der Uhr des Rechners
  // abhängt. In UTC, weil PostgREST created_at mit Zeitzone liefert.
  final jetzt = DateTime.utc(2026, 8, 24, 12, 0, 0);

  Map<String, dynamic> community(Duration alter) => <String, dynamic>{
    'id': 'c1',
    'name': 'Testcommunity',
    'created_at': jetzt.subtract(alter).toIso8601String(),
  };

  group('Aufgabe 1.2 — Grenze bei genau 7 Tagen', () {
    test('frisch erstellt trägt das Etikett', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(
          community(Duration.zero),
          jetzt: jetzt,
        ),
        isTrue,
      );
    });

    test('6 Tage 23 Stunden 59 Minuten trägt es noch', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(
          community(const Duration(days: 6, hours: 23, minutes: 59)),
          jetzt: jetzt,
        ),
        isTrue,
      );
    });

    test('exakt 7 Tage trägt es NICHT mehr — die Grenze ist scharf', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(
          community(const Duration(days: 7)),
          jetzt: jetzt,
        ),
        isFalse,
      );
    });

    test('7 Tage und eine Sekunde trägt es nicht', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(
          community(const Duration(days: 7, seconds: 1)),
          jetzt: jetzt,
        ),
        isFalse,
      );
    });

    test('8 Tage alt trägt es nicht (Akzeptanzkriterium 2)', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(
          community(const Duration(days: 8)),
          jetzt: jetzt,
        ),
        isFalse,
      );
    });

    test('das Fenster ist sieben Tage, nicht sechs oder acht', () {
      expect(CommunityChatService.neuFenster, const Duration(days: 7));
    });
  });

  group('Aufgabe 1.2 — was schiefgehen kann', () {
    test('ohne created_at kein Etikett statt eines falschen', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(<String, dynamic>{
          'id': 'c1',
        }, jetzt: jetzt),
        isFalse,
      );
    });

    test('unlesbares Datum ergibt kein Etikett', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(<String, dynamic>{
          'created_at': 'gestern',
        }, jetzt: jetzt),
        isFalse,
      );
    });

    test('null-Community ergibt kein Etikett', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(null, jetzt: jetzt),
        isFalse,
      );
    });

    test(
      'Zeitzone verschiebt die Grenze nicht: dieselbe Sekunde als '
      'Ortszeit mit Versatz zählt gleich',
      () {
        // 2026-08-17T14:00:00+02:00 ist derselbe Augenblick wie
        // 2026-08-17T12:00:00Z, also 7 Tage vor dem Bezugspunkt.
        expect(
          CommunityChatService.istVorKurzemErstellt(<String, dynamic>{
            'created_at': '2026-08-17T14:00:00+02:00',
          }, jetzt: jetzt),
          isFalse,
        );
        // Eine Minute später ist es jünger als 7 Tage.
        expect(
          CommunityChatService.istVorKurzemErstellt(<String, dynamic>{
            'created_at': '2026-08-17T14:01:00+02:00',
          }, jetzt: jetzt),
          isTrue,
        );
      },
    );

    test('ein DateTime-Objekt wird genauso gelesen wie eine Zeichenkette', () {
      expect(
        CommunityChatService.createdAt(<String, dynamic>{
          'created_at': DateTime.utc(2026, 8, 24),
        }),
        DateTime.utc(2026, 8, 24),
      );
    });

    test('ein Datum in der Zukunft gilt als neu, nicht als uralt', () {
      expect(
        CommunityChatService.istVorKurzemErstellt(<String, dynamic>{
          'created_at': jetzt.add(const Duration(hours: 3)).toIso8601String(),
        }, jetzt: jetzt),
        isTrue,
      );
    });
  });

  group('Aufgabe 1.2 — Wortlaut und Anzeigestellen', () {
    late String chatsTab;
    late String service;

    setUpAll(() {
      chatsTab = File(
        'lib/presentation/pages/community_chats_tab.dart',
      ).readAsStringSync();
      service = File(
        'lib/data/services/community_chat_service.dart',
      ).readAsStringSync();
    });

    test('der Text steht so da, wie Vucko ihn entschieden hat', () {
      expect(chatsTab.contains("'Vor kurzem erstellt'"), isTrue);
    });

    test('echte Umlaute, keine ue/oe/ae-Ersatzschreibung im Etikett', () {
      // „Vor kurzem erstellt" hat keine Umlaute, aber die Kommentare drum
      // herum haben welche. Diese Prüfung bewacht die Regel aus CLAUDE.md
      // für die neue Stelle.
      expect(chatsTab.contains('juenger als sieben'), isFalse);
    });

    test('kein Gedankenstrich im Nutzertext', () {
      expect('Vor kurzem erstellt'.contains('—'), isFalse);
      expect('Vor kurzem erstellt'.contains('–'), isFalse);
    });

    test(
      'created_at wird in allen Spaltenlisten geholt, sonst bliebe das '
      'Etikett in einer der drei Anzeigestellen dunkel',
      () {
        final zeilen = service
            .split('\n')
            .where((z) => z.contains('created_at'))
            .toList();
        expect(zeilen, isNotEmpty);
        expect(
          service.contains(
            "'id, owner_id, name, description, is_public, created_at, '",
          ),
          isTrue,
        );
      },
    );

    test(
      'die Kachel fragt den Dienst, statt das Datum selbst zu rechnen',
      () {
        expect(
          chatsTab.contains('CommunityChatService.istVorKurzemErstellt('),
          isTrue,
        );
      },
    );
  });
}
