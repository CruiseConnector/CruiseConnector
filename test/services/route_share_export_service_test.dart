import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('externer Route-Export bleibt PNG-Flow ohne Community-Post', () {
    final source = File(
      'lib/data/services/route_share_export_service.dart',
    ).readAsStringSync();

    expect(source, contains('ui.PictureRecorder'));
    expect(source, contains('ui.ImageByteFormat.png'));
    expect(source, isNot(contains('XFile')));
    expect(source, isNot(contains('CreatePostPage')));
    expect(source, isNot(contains('SocialService')));
    expect(source, isNot(contains('CommunityProvider')));
  });
}
