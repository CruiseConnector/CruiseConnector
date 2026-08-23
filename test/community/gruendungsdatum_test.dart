import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';

/// 2026-08-24 — Aufgabe 10b aus dem Nachtrag vom 24.08.
///
/// Vucko: „und wie gesagt ein badge in der community wo man sieht wann es
/// gegruendet wurde."
///
/// Abgrenzung, die hier mitgeprüft wird: Das ist NICHT das Etikett „Vor
/// kurzem erstellt" aus Aufgabe 1.2 (das steht in der LISTE und sagt „jünger
/// als 7 Tage") und auch nicht das Erfolgs-Abzeichen für das Gründen einer
/// Community (das liegt in badge.dart). Dieses hier zeigt IMMER das Datum und
/// steht IN der Community.
void main() {
  group('10b — das Gründungsdatum', () {
    test('zeigt das Datum, egal wie alt die Community ist', () {
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{
          'created_at': '2026-03-09T08:15:00+00:00',
        }),
        'Gegründet am 09.03.2026',
      );
    });

    test('führende Null bei Tag und Monat', () {
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{
          'created_at': '2026-01-05T12:00:00+00:00',
        }),
        'Gegründet am 05.01.2026',
      );
    });

    test(
      'eine ganz frische Community zeigt das Datum genauso — anders als das '
      'Etikett aus Aufgabe 1.2, das nach 7 Tagen verschwindet',
      () {
        final jetzt = DateTime.now().toUtc();
        final text = CommunityChatService.gruendungsdatumText(
          <String, dynamic>{'created_at': jetzt.toIso8601String()},
        );
        expect(text, isNotNull);
        expect(text!.startsWith('Gegründet am '), isTrue);

        // Uralt, also kein „Vor kurzem erstellt" mehr, aber sehr wohl ein
        // Gründungsdatum.
        final alt = <String, dynamic>{
          'created_at': '2025-02-02T10:00:00+00:00',
        };
        expect(CommunityChatService.istVorKurzemErstellt(alt), isFalse);
        expect(
          CommunityChatService.gruendungsdatumText(alt),
          'Gegründet am 02.02.2025',
        );
      },
    );

    test('ohne Datum steht nichts da statt eines erfundenen Tages', () {
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{}),
        isNull,
      );
      expect(CommunityChatService.gruendungsdatumText(null), isNull);
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{
          'created_at': 'irgendwas',
        }),
        isNull,
      );
    });
  });

  group('10b — wo es steht', () {
    late String detail;

    setUpAll(() {
      detail = File(
        'lib/presentation/pages/community_chat_detail_page.dart',
      ).readAsStringSync();
    });

    test('es steht in der Kopfzeile der Community', () {
      final stelle = detail.indexOf('Widget _buildCommunityHeader(');
      expect(stelle, greaterThan(0));
      final block = detail.substring(stelle, stelle + 4200);
      expect(
        block.contains('CommunityChatService.gruendungsdatumText('),
        isTrue,
      );
      expect(block.contains('_buildMetaPill('), isTrue);
    });

    test('echter Umlaut, kein Gedankenstrich im Nutzertext', () {
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{
          'created_at': '2026-03-09T08:15:00Z',
        })!.contains('ü'),
        isTrue,
      );
      expect(
        CommunityChatService.gruendungsdatumText(<String, dynamic>{
          'created_at': '2026-03-09T08:15:00Z',
        })!.contains('—'),
        isFalse,
      );
    });
  });
}
