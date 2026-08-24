// 2026-08-24 — Vucko: „bei der community page hat cozy mal was gepostet aber
// ich sehe es nicht in meinem feed obwohl ich ihm folge."
//
// Die echte Lage, gemessen in der Produktionsdatenbank am 24.08.:
//   - Vucko folgt cozy (status accepted).
//   - Cozy folgt NICHT zurueck.
//   - Cozy hat zwei Beitraege vom 21.08., beide visibility = 'followers',
//     beide nicht ausgeblendet.
// Der Feed holte 'followers'-Beitraege nur von Leuten, die zurueckfolgen
// („mutual"). Cozys Beitraege blieben deshalb unsichtbar.
//
// Ausfuehren: flutter test test/community/feed_follower_sichtbarkeit_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/social_service.dart';

void main() {
  // Die echten IDs aus der Messung — damit der Fall benennbar bleibt.
  const vucko = '1f444750-4407-45cc-8470-1161f866a628';
  const cozy = '33329d30-59fd-458f-a2be-5f0a9456a00c';

  group('Feed: „Follower" heisst Follower, nicht gegenseitig', () {
    test(
      'A folgt B, B folgt A NICHT: B\'s Follower-Beitrag steht in A\'s Feed',
      () {
        expect(
          FeedSichtbarkeit.imFeedSichtbar(
            betrachterId: vucko,
            verfasserId: cozy,
            sichtbarkeit: 'followers',
            folgeIch: const {cozy}, // einseitig: cozy folgt nicht zurueck
          ),
          isTrue,
          reason:
              'Vucko folgt cozy. Wer „Follower" waehlt, meint seine Follower.',
        );
      },
    );

    test('die Abfrage fragt fuer Gefolgte auch nach „followers"', () {
      // Nagelt die Query-Ebene fest: der Client darf die Beitraege gar nicht
      // erst aus der Anfrage ausschliessen.
      expect(
        FeedSichtbarkeit.stufenFuerVerfasser(folgeIchIhm: true),
        containsAll(<String>['public', 'followers']),
      );
      expect(
        FeedSichtbarkeit.stufenFuerVerfasser(folgeIchIhm: false),
        equals(const <String>['public']),
      );
    });

    test('oeffentliche Beitraege von Gefolgten bleiben sichtbar', () {
      expect(
        FeedSichtbarkeit.imFeedSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'public',
          folgeIch: const {cozy},
        ),
        isTrue,
      );
    });

    test('wem ich nicht folge, dessen Beitraege stehen nicht im Feed', () {
      for (final stufe in ['public', 'followers']) {
        expect(
          FeedSichtbarkeit.imFeedSichtbar(
            betrachterId: vucko,
            verfasserId: cozy,
            sichtbarkeit: stufe,
            folgeIch: const <String>{},
          ),
          isFalse,
          reason: 'Stufe $stufe ohne Folge-Beziehung',
        );
      }
    });

    test('eigene Beitraege sieht man auf jeder Stufe', () {
      expect(
        FeedSichtbarkeit.imFeedSichtbar(
          betrachterId: vucko,
          verfasserId: vucko,
          sichtbarkeit: 'followers',
          folgeIch: const <String>{},
        ),
        isTrue,
      );
    });

    test('blockiert schlaegt Folge-Beziehung', () {
      expect(
        FeedSichtbarkeit.imFeedSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIch: const {cozy},
          blockiert: const {cozy},
        ),
        isFalse,
      );
    });

    test('ausgeblendete (moderierte) Beitraege bleiben draussen', () {
      expect(
        FeedSichtbarkeit.imFeedSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIch: const {cozy},
          istAusgeblendet: true,
        ),
        isFalse,
      );
    });

    test(
      'fehlende visibility gilt als oeffentlich (Alt-Zeilen ohne Default)',
      () {
        expect(
          FeedSichtbarkeit.imFeedSichtbar(
            betrachterId: vucko,
            verfasserId: cozy,
            sichtbarkeit: null,
            folgeIch: const {cozy},
          ),
          isTrue,
        );
      },
    );
  });

  group('Fremdes Profil: dieselbe Regel, andere Richtung', () {
    test('Follower-Beitrag ist fuer Fremde NICHT sichtbar', () {
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIchIhm: false,
        ),
        isFalse,
        reason:
            'getUserPosts gab bis 24.08. jeden Beitrag heraus, auch diesen.',
      );
    });

    test('Follower-Beitrag ist fuer Follower sichtbar', () {
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIchIhm: true,
        ),
        isTrue,
      );
    });

    test('oeffentliche Beitraege sieht auch, wer nicht folgt', () {
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'public',
          folgeIchIhm: false,
        ),
        isTrue,
      );
    });

    test('ausgeblendete Beitraege sieht nur der Verfasser selbst', () {
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: vucko,
          verfasserId: cozy,
          sichtbarkeit: 'public',
          folgeIchIhm: true,
          istAusgeblendet: true,
        ),
        isFalse,
      );
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: cozy,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIchIhm: false,
          istAusgeblendet: true,
        ),
        isTrue,
      );
    });

    test('nicht angemeldet: nur Oeffentliches', () {
      expect(
        FeedSichtbarkeit.aufProfilSichtbar(
          betrachterId: null,
          verfasserId: cozy,
          sichtbarkeit: 'followers',
          folgeIchIhm: false,
        ),
        isFalse,
      );
    });
  });

  group('Ablehnung der Datenbank ist kein „RPC kaputt"', () {
    // 2026-08-24: Seit die Leseregel serverseitig gilt, lehnen
    // toggle_post_like/-repost mit 42501 ab. Der Rueckfallweg im Client ist
    // fuer eine FEHLENDE RPC gedacht. Verwechselt er beides, versucht er das
    // Liken direkt ueber die Tabelle — das scheitert an derselben Regel und
    // wirft dem Nutzer eine rohe Datenbank-Ausnahme ins Gesicht.
    test('42501 wird als Ablehnung erkannt', () {
      expect(
        SocialService.istAblehnungWegenSichtbarkeit(
          const PostgrestException(
            message: 'beitrag_nicht_sichtbar',
            code: '42501',
          ),
        ),
        isTrue,
      );
    });

    test('die Meldung allein genuegt auch', () {
      expect(
        SocialService.istAblehnungWegenSichtbarkeit(
          const PostgrestException(message: 'ERROR: beitrag_nicht_sichtbar'),
        ),
        isTrue,
      );
    });

    test('eine fehlende RPC ist KEINE Ablehnung — Rueckfall bleibt', () {
      expect(
        SocialService.istAblehnungWegenSichtbarkeit(
          const PostgrestException(
            message: 'Could not find the function public.toggle_post_like',
            code: 'PGRST202',
          ),
        ),
        isFalse,
      );
      expect(
        SocialService.istAblehnungWegenSichtbarkeit(Exception('kein Netz')),
        isFalse,
      );
    });
  });

  pruefeVerdrahtung();
}

// ─────────────────────────────────────────────────────────────────────────
// 2026-08-24 — Die Regel gilt nur, wenn sie auch ueberall GEFRAGT wird.
//
// Die Faelle oben nageln die Entscheidung fest. Ob die Abfragen sie
// benutzen, sieht man ihnen von aussen nicht an: dafuer braeuchte es eine
// laufende Datenbank. Deshalb dieselbe Bauart wie in
// `test/route/laender_klassifikation_test.dart` — der Test liest die
// Quelldatei und prueft die Verdrahtung.
//
// Ohne den Fix war dieser Test rot: `getFeedPosts` schnitt die Menge
// „mutual" (`following_id`, `eq('visibility', 'followers')`), und
// `getUserPosts`, `getUserLikes` sowie `getPostById` fragten gar nicht erst
// nach der Sichtbarkeit.

/// Schneidet den Rumpf einer Funktion ueber Klammerzaehlung heraus.
String _rumpf(String quelltext, String signaturTeil) {
  final start = quelltext.indexOf(signaturTeil);
  if (start < 0) {
    throw StateError('Nicht gefunden in social_service.dart: $signaturTeil');
  }
  final klammerAuf = quelltext.indexOf('{', start);
  var tiefe = 0;
  for (var i = klammerAuf; i < quelltext.length; i++) {
    if (quelltext[i] == '{') tiefe++;
    if (quelltext[i] == '}') {
      tiefe--;
      if (tiefe == 0) return quelltext.substring(klammerAuf, i + 1);
    }
  }
  throw StateError('Rumpf nicht geschlossen: $signaturTeil');
}

void pruefeVerdrahtung() {
  final quelle = File(
    'lib/data/services/social_service.dart',
  ).readAsStringSync();

  group('Verdrahtung: jede Beitrags-Abfrage fragt FeedSichtbarkeit', () {
    const stellen = <String, String>{
      'Feed': 'static Future<List<Map<String, dynamic>>> getFeedPosts()',
      'fremdes Profil':
          'static Future<List<Map<String, dynamic>>> getUserPosts(',
      'Reposts auf dem Profil':
          'static Future<List<Map<String, dynamic>>> getUserReposts(',
      '„Gefaellt mir"-Liste':
          'static Future<List<Map<String, dynamic>>> getUserLikes(',
      'Benachrichtigung/Deeplink':
          'static Future<Map<String, dynamic>?> getPostById(',
    };

    stellen.forEach((name, signatur) {
      test('$name fragt FeedSichtbarkeit', () {
        expect(
          _rumpf(quelle, signatur),
          contains('FeedSichtbarkeit'),
          reason:
              '$name gibt Beitraege heraus, ohne die Sichtbarkeitsregel zu '
              'fragen. Genau so blieb cozys Beitrag unsichtbar bzw. wurden '
              'fremde „Nur Follower"-Beitraege sichtbar.',
        );
      });
    });

    test('der Feed schneidet die Menge „mutual" nicht mehr', () {
      final feed = _rumpf(
        quelle,
        'static Future<List<Map<String, dynamic>>> getFeedPosts()',
      );
      expect(
        feed,
        isNot(contains("eq('following_id'")),
        reason:
            'Die Rueckwaerts-Abfrage auf follows ist die Mutual-Bedingung. '
            'Wer „Follower" waehlt, meint seine Follower.',
      );
      expect(
        feed,
        isNot(contains("eq('visibility', 'followers')")),
        reason:
            'Eine eigene Abfrage nur fuer „followers" war die Stelle, an der '
            'die Menge verengt wurde.',
      );
    });

    test('„gegenseitig" bleibt bei den Gruppen-Einladungen', () {
      // getMutualFollowIds darf es weiterhin geben — sie wird in
      // group_lobby_page.dart gebraucht, dort ist gegenseitig auch gemeint.
      expect(quelle, contains('static Future<Set<String>> getMutualFollowIds'));
      expect(
        File('lib/presentation/pages/group_lobby_page.dart').readAsStringSync(),
        contains('getMutualFollowIds'),
      );
    });
  });
}
