import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/community_chat_message.dart';

void main() {
  group('CommunityChatMessage', () {
    test('round-trips selected Supabase fields used by the chat UI', () {
      final message = CommunityChatMessage.fromJson({
        'id': 'm1',
        'community_id': 'c1',
        'user_id': 'u1',
        'body': 'Servus',
        'created_at': '2026-06-26T10:00:00Z',
        'updated_at': null,
        'deleted_at': null,
        'reply_to_message_id': 'm0',
        'route_attachment': {'route_id': 'r1'},
        'pinned_at': '2026-06-26T10:01:00Z',
        'pinned_by': 'u2',
        'profiles': {'username': 'vucko'},
      });

      expect(message.id, 'm1');
      expect(message.routeAttachment?['route_id'], 'r1');
      expect(message.profile?['username'], 'vucko');

      final json = message.toJson();
      expect(json['reply_to_message_id'], 'm0');
      expect(json['pinned_by'], 'u2');
      expect(json['profiles'], containsPair('username', 'vucko'));
    });

    test('normalizes missing optional maps to null instead of throwing', () {
      final message = CommunityChatMessage.fromJson({
        'id': 'm1',
        'community_id': 'c1',
        'user_id': 'u1',
        'body': 'Servus',
      });

      expect(message.routeAttachment, isNull);
      expect(message.profile, isNull);
      expect(message.toJson()['route_attachment'], isNull);
    });
  });
}
