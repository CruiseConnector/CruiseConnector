import 'package:cruise_connect/presentation/pages/community_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-11 (vucko): „wenn ich auf Kontakte klicke, moechte ich auf das
/// Community-Entdecken-Feld kommen wo mir Leute oder Freunde von Freunden
/// vorgeschlagen werden."
///
/// Vorher riefen alle Home-Kacheln nur `onTabChange(1)` — das oeffnet den
/// Community-Tab, sagt aber nicht, WELCHER der vier Reiter gemeint ist. Man
/// landete deshalb immer auf Feed.
void main() {
  group('Community-Reiter-Signal', () {
    tearDown(() => CommunityPage.pendingTabFocus.value = null);

    test('Reiter-Indizes sind die erwarteten', () {
      // Schutz gegen ein spaeteres Umsortieren der TabBar: wer die Reihenfolge
      // aendert, muss auch hier vorbeikommen.
      expect(CommunityPage.tabFeed, 0);
      expect(CommunityPage.tabGruppen, 1);
      expect(CommunityPage.tabChats, 2);
      expect(CommunityPage.tabEntdecken, 3);
    });

    test('Signal traegt den gewuenschten Reiter', () {
      CommunityPage.pendingTabFocus.value = CommunityPage.tabEntdecken;
      expect(CommunityPage.pendingTabFocus.value, 3);
    });

    // Der eigentliche Grund fuer den ValueNotifier statt eines Konstruktor-
    // Parameters: Ein Parameter wirkt nur, wenn sich sein Wert AENDERT. Zweimal
    // hintereinander „Kontakte" waere derselbe Wert — beim zweiten Mal wuerde
    // nichts passieren. Der Notifier meldet jedes Setzen.
    test('zweimal derselbe Reiter loest zweimal aus', () {
      var meldungen = 0;
      void horcher() => meldungen++;
      CommunityPage.pendingTabFocus.addListener(horcher);
      try {
        CommunityPage.pendingTabFocus.value = CommunityPage.tabEntdecken;
        // Die Seite setzt nach dem Anspringen auf null zurueck.
        CommunityPage.pendingTabFocus.value = null;
        CommunityPage.pendingTabFocus.value = CommunityPage.tabEntdecken;
        expect(
          meldungen,
          3,
          reason: 'jedes Setzen muss ankommen, auch derselbe Reiter erneut',
        );
      } finally {
        CommunityPage.pendingTabFocus.removeListener(horcher);
      }
    });
  });
}
