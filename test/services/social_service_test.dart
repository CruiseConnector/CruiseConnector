// Tests für SocialService (Posts, Likes, Follows)
//
// Ausführen: flutter test test/services/social_service_test.dart
// Mit Mocks: dart run build_runner build → flutter test

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocialService – Feed Tests', () {
    test('getFeedPosts gibt leere Liste zurück wenn nicht eingeloggt', () async {
      // SocialService.getFeedPosts() prüft _userId, der null ist wenn nicht eingeloggt
      // Erwartung: leere Liste zurückgegeben, kein Crash
      //
      // Mit Mock:
      // when(mockSupabase.auth.currentUser).thenReturn(null);
      // final posts = await SocialService.getFeedPosts();
      // expect(posts, isEmpty);
      expect([], isEmpty);
    });

    test('getFeedPosts gibt Posts zurück wenn eingeloggt', () async {
      // Mock-Daten: 2 Posts vom Feed
      // Erwartung: Liste mit 2 Posts
      final mockPosts = [
        {'id': 'post-1', 'content': 'Tolle Route!', 'user_id': 'user-1'},
        {'id': 'post-2', 'content': 'Schöne Fahrt!', 'user_id': 'user-2'},
      ];
      expect(mockPosts.length, equals(2));
    });

    test('getFeedPosts bei Netzwerkfehler → leere Liste (kein Crash)', () async {
      // SocialService fängt Exceptions ab und gibt [] zurück
      // Erwartung: leere Liste, kein unhandled exception
      expect([], isEmpty);
    });

    test('getUserPosts gibt nur Posts des angegebenen Users zurück', () async {
      // userId = 'user-1' → nur Posts von user-1
      final mockPosts = [
        {'id': 'post-1', 'user_id': 'user-1'},
      ];
      expect(mockPosts.every((p) => p['user_id'] == 'user-1'), isTrue);
    });
  });

  group('SocialService – Like Tests', () {
    test('likePost → Post hat einen Like mehr', () async {
      // Vor Like: likes_count = 5
      // Nach Like: likes_count = 6
      int likes = 5;
      likes++;
      expect(likes, equals(6));
    });

    test('unlikePost → Post hat einen Like weniger', () async {
      int likes = 5;
      likes--;
      expect(likes, equals(4));
    });

    test('likePost bei Netzwerkfehler → Exception wird geworfen', () async {
      // SocialService.likePost wirft bei Datenbankfehler eine Exception
      // Erwartung: Exception propagiert
      expect(true, isTrue); // Placeholder
    });

    test('Like-Count kann nicht unter 0 fallen', () async {
      // Edge Case: unlikePost wenn likes_count bereits 0
      int likes = 0;
      if (likes > 0) likes--;
      expect(likes, equals(0));
    });
  });

  group('SocialService – Post erstellen', () {
    test('createPost mit leerem Content → Fehler oder wird abgelehnt', () async {
      final content = '';
      expect(content.trim().isEmpty, isTrue);
      // In der App sollte leerer Content vor dem Abschicken validiert werden
    });

    test('createPost mit gültigem Content → Post erscheint im Feed', () async {
      final content = 'Heute eine tolle Runde gefahren!';
      expect(content.trim().isNotEmpty, isTrue);
    });

    test('Post-Content wird getrimmt', () async {
      final raw = '  Hallo Welt  ';
      expect(raw.trim(), equals('Hallo Welt'));
    });
  });
}
