import 'package:cruise_connect/data/services/social_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „wo mir Leute oder Freunde von Freunden vorgeschlagen
/// werden — und ich moechte auch noch, dass das gekennzeichnet wird."
///
/// Der Satz dafuer existierte laengst, wurde aber NIRGENDS aufgerufen: Unter
/// dem Namen stand nur der @-Name, die Karte sagte also nie, WARUM jemand
/// auftaucht. Diese Tests halten die Formulierungen fest.
void main() {
  Map<String, dynamic> nutzer(List<String> namen, {int? anzahl}) => {
    'id': 'x',
    'mutual_names': namen,
    if (anzahl != null) 'mutual_count': anzahl,
  };

  test('eine gemeinsame Person', () {
    expect(
      SocialService.mutualFollowersLine(nutzer(['anna'])),
      '@anna folgt diesem Account',
    );
  });

  test('zwei gemeinsame Personen', () {
    expect(
      SocialService.mutualFollowersLine(nutzer(['anna', 'ben'])),
      '@anna und @ben folgen diesem Account',
    );
  });

  test('mehr als zwei werden zusammengefasst', () {
    expect(
      SocialService.mutualFollowersLine(
        nutzer(['anna', 'ben', 'clara'], anzahl: 7),
      ),
      '@anna, @ben und weitere Personen folgen diesem Account',
    );
  });

  // Der wichtige Fall fuer eine junge App: Bei wenigen Nutzern gibt es oft
  // keine gemeinsamen Bekannten. Dann darf die Zeile nicht leer bleiben —
  // die Oberflaeche setzt in dem Fall „Neu dabei" ein.
  test('ohne gemeinsame Bekannte kommt null zurueck', () {
    expect(SocialService.mutualFollowersLine(nutzer([])), isNull);
    expect(SocialService.mutualFollowersLine({'id': 'x'}), isNull);
    expect(
      SocialService.mutualFollowersLine(nutzer(['anna'], anzahl: 0)),
      isNull,
    );
  });
}
