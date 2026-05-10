import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Routensuche-Status zeigt keine internen Begriffe', () {
    final source = File(
      'lib/presentation/pages/cruise_mode_page.dart',
    ).readAsStringSync();
    final loadingPhases =
        RegExp(
          r'_roundTripLoadingPhases\s*=\s*\[(.*?)\];',
          dotAll: true,
        ).firstMatch(source)?.group(1) ??
        '';
    final statusNotice =
        RegExp(
          r'void _showRoundTripRouteStatusNotice\(.*?\n  \}',
          dotAll: true,
        ).firstMatch(source)?.group(0) ??
        '';
    final userFacingStatusText = '$loadingPhases\n$statusNotice';

    for (final forbidden in [
      'Routenpool',
      'Candidate',
      'Worker',
      'Cron',
      'Live-Routen',
    ]) {
      expect(userFacingStatusText, isNot(contains(forbidden)));
    }
  });
}
