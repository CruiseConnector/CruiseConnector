import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ein Bereich, für den es einen eigenen Lesestand gibt.
///
/// Die Namen sind zeichengleich mit dem, was die RPC
/// `community_als_gesehen_markieren` erlaubt (Migration 20260824102000):
/// feed, gruppen, chats, entdecken, community. Ein Tippfehler hier wäre in
/// der Datenbank ein `raise exception`, kein stiller Fehlschlag.
enum CommunityBereich {
  feed('feed'),
  gruppen('gruppen'),
  chats('chats'),
  entdecken('entdecken'),
  community('community');

  const CommunityBereich(this.schluessel);

  final String schluessel;

  /// Reiter-Index in [CommunityPage]: 0 Feed, 1 Gruppen & Fahrten,
  /// 2 Chats, 3 Entdecken. `community` hat keinen eigenen Reiter, sie liegt
  /// INNERHALB von Chats.
  static CommunityBereich? vonReiter(int index) {
    switch (index) {
      case 0:
        return CommunityBereich.feed;
      case 1:
        return CommunityBereich.gruppen;
      case 2:
        return CommunityBereich.chats;
      case 3:
        return CommunityBereich.entdecken;
    }
    return null;
  }
}

/// Ein Punkt mit der Anzahl dahinter.
@immutable
class CommunityHinweis {
  const CommunityHinweis({required this.neu, required this.anzahl});

  const CommunityHinweis.leer() : neu = false, anzahl = 0;

  factory CommunityHinweis.ausJson(Object? roh) {
    if (roh is! Map) return const CommunityHinweis.leer();
    return CommunityHinweis(
      neu: roh['neu'] == true,
      anzahl: (roh['anzahl'] as num?)?.toInt() ?? 0,
    );
  }

  final bool neu;
  final int anzahl;
}

/// Der vollständige Stand aller drei Ebenen.
@immutable
class CommunityHinweisStand {
  const CommunityHinweisStand({
    required this.reiter,
    required this.communities,
  });

  const CommunityHinweisStand.leer()
    : reiter = const <CommunityBereich, CommunityHinweis>{},
      communities = const <String, CommunityHinweis>{};

  final Map<CommunityBereich, CommunityHinweis> reiter;
  final Map<String, CommunityHinweis> communities;

  CommunityHinweis fuerReiter(CommunityBereich bereich) =>
      reiter[bereich] ?? const CommunityHinweis.leer();

  CommunityHinweis fuerCommunity(String? communityId) {
    if (communityId == null) return const CommunityHinweis.leer();
    return communities[communityId] ?? const CommunityHinweis.leer();
  }

  /// Ebene 1. BERECHNET, nicht gespeichert.
  ///
  /// Damit erfüllt sich Akzeptanzkriterium 3 von selbst: „Sind alle
  /// Unterbereiche gelesen, verschwindet auch der Punkt am Community-Tab."
  bool get punkt => reiter.values.any((h) => h.neu);

  /// Ohne diesen Bereich, sofort. Für die Anzeige, während der Server noch
  /// antwortet.
  CommunityHinweisStand ohneReiter(CommunityBereich bereich) {
    final neueReiter = Map<CommunityBereich, CommunityHinweis>.from(reiter);
    neueReiter[bereich] = const CommunityHinweis.leer();
    // Der Chats-Punkt ist die Summe aus „neue öffentliche Community" und den
    // einzelnen Community-Punkten. Ein Tipp auf den Reiter löscht nur den
    // Entdecken-Teil; die einzelnen Communities bleiben stehen, bis man sie
    // wirklich öffnet (WhatsApp-Verhalten). Deshalb wird beim Chats-Reiter
    // der Punkt nur dann gelöscht, wenn keine einzelne Community mehr
    // leuchtet — sonst würde die Oberfläche etwas versprechen, das der
    // nächste Serverabgleich sofort zurücknimmt.
    if (bereich == CommunityBereich.chats &&
        communities.values.any((h) => h.neu)) {
      neueReiter[bereich] = reiter[bereich] ?? const CommunityHinweis.leer();
    }
    return CommunityHinweisStand(
      reiter: neueReiter,
      communities: communities,
    );
  }

  CommunityHinweisStand ohneCommunity(String communityId) {
    final neueCommunities = Map<String, CommunityHinweis>.from(communities);
    neueCommunities[communityId] = const CommunityHinweis.leer();
    final neueReiter = Map<CommunityBereich, CommunityHinweis>.from(reiter);
    if (!neueCommunities.values.any((h) => h.neu)) {
      // War das die letzte ungelesene Community, kann auch der Chats-Punkt
      // ausgehen — es sei denn, es gibt noch neue öffentliche Communities.
      // Das weiß nur der Server; er korrigiert beim nächsten Abgleich.
      neueReiter[CommunityBereich.chats] = const CommunityHinweis.leer();
    }
    return CommunityHinweisStand(
      reiter: neueReiter,
      communities: neueCommunities,
    );
  }
}

/// Entscheidet, wo im Community-Bereich ein Hinweispunkt leuchtet.
///
/// 2026-08-24 — Aufgabe 1.1 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 1: „dass da halt einfach so ein kleiner Punkt ist, im Sinne
/// von, wie in den ganzen Apps halt eine Benachrichtigung aussieht" … „wenn
/// man auf das Community draufdrückt, dass man dann oben entweder im Feed oder
/// im Entdecker oder bei den Gruppenfahrten oder in der Community sieht: okay,
/// ja, da sind neue Sachen passiert" … „Wenn man in der Community draufdrückt,
/// dann halt das nochmal benachrichtigungsmäßig — wie, in welcher Community
/// das jetzt genau war."
///
/// WAS SICH GEGENÜBER DEM 11.08. GEÄNDERT HAT, und warum:
///
///   * Vorher lag der Stand als ZWEI ZÄHLER in SharedPreferences
///     (`community_gesehen_gruppen_v1`, `community_gesehen_vorschlaege_v1`)
///     und wurde mit den Anzahlen verglichen, die die Home-Kacheln meldeten.
///     Drei Fehler steckten darin, alle nicht reparierbar:
///       1. Ein Gerätewechsel setzte alles zurück — der Punkt leuchtete auf
///          dem neuen Handy für Dinge, die man längst gelesen hatte.
///       2. Wer eine Gruppe LÖSCHT, senkt den Zähler. Danach war die neue
///          Zahl kleiner als der gespeicherte Stand, und der Punkt blieb
///          dauerhaft aus, egal wie viel Neues dazukam.
///       3. Eine Anzahl kann grundsätzlich nicht sagen, WO etwas neu ist.
///          Vuckos Ebenen 2 und 3 waren damit unmöglich.
///
///   * Jetzt liefert die RPC `community_hinweispunkte()` alle drei Ebenen in
///     EINER Abfrage, verglichen werden ZEITSTEMPEL, und der Lesestand liegt
///     serverseitig in `community_lesestand`. Akzeptanzkriterium 4 („Nach
///     App-Neustart ist der Gelesen-Status noch korrekt, serverseitig, nicht
///     nur lokal") ist damit erfüllt.
///
/// Ebene 1 hat KEINEN eigenen Zustand mehr. Sie ist die Oder-Verknüpfung der
/// vier Reiter, siehe [CommunityHinweisStand.punkt]. Deshalb gibt es auch
/// kein „Community geöffnet, alles gelesen" mehr: Wer nur hineinschaut und
/// wieder geht, hat nichts gelesen, und der Punkt bleibt zu Recht stehen.
class CommunityNeuigkeitService {
  CommunityNeuigkeitService._();

  static final CommunityNeuigkeitService instance =
      CommunityNeuigkeitService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Ebene 1 für die Navigationsleiste. Bleibt ein `ValueNotifier<bool>`,
  /// weil `home_page.dart` seit dem 11.08. genau daran hängt.
  final ValueNotifier<bool> hatNeues = ValueNotifier<bool>(false);

  /// Ebene 2 und 3 für die Reiter und die Community-Kacheln.
  final ValueNotifier<CommunityHinweisStand> stand =
      ValueNotifier<CommunityHinweisStand>(
        const CommunityHinweisStand.leer(),
      );

  bool _laeuft = false;
  DateTime? _letzterAbgleich;

  /// Holt alle Punkte in EINER Abfrage.
  ///
  /// [erzwingen] überspringt die Sperrfrist. Ohne sie würde jeder
  /// Reiterwechsel eine Abfrage auslösen; die Sperrfrist von 5 Sekunden hält
  /// das im Rahmen, ohne dass jemand auf einen Punkt wartet.
  Future<void> aktualisieren({bool erzwingen = false}) async {
    if (_laeuft) return;
    final zuletzt = _letzterAbgleich;
    if (!erzwingen &&
        zuletzt != null &&
        DateTime.now().difference(zuletzt) < const Duration(seconds: 5)) {
      return;
    }
    if (_db.auth.currentUser == null) {
      hatNeues.value = false;
      stand.value = const CommunityHinweisStand.leer();
      return;
    }

    _laeuft = true;
    try {
      final antwort = await _db.rpc('community_hinweispunkte');
      if (antwort is! Map) return;
      final neuerStand = _ausJson(Map<String, dynamic>.from(antwort));
      stand.value = neuerStand;
      hatNeues.value = neuerStand.punkt;
      _letzterAbgleich = DateTime.now();
    } catch (e) {
      // Im Zweifel den bestehenden Zustand lassen. Ein Netzfehler ist kein
      // Beleg dafür, dass es nichts Neues gibt — und ein Punkt, der bei
      // jedem Funkloch verschwindet, ist schlimmer als gar keiner.
      debugPrint('[CommunityNeuigkeit] Punkte nicht lesbar: $e');
    } finally {
      _laeuft = false;
    }
  }

  static CommunityHinweisStand _ausJson(Map<String, dynamic> json) {
    final reiterRoh = json['reiter'];
    final reiter = <CommunityBereich, CommunityHinweis>{};
    if (reiterRoh is Map) {
      for (final bereich in CommunityBereich.values) {
        if (bereich == CommunityBereich.community) continue;
        reiter[bereich] = CommunityHinweis.ausJson(
          reiterRoh[bereich.schluessel],
        );
      }
    }

    final communitiesRoh = json['communities'];
    final communities = <String, CommunityHinweis>{};
    if (communitiesRoh is Map) {
      communitiesRoh.forEach((schluessel, wert) {
        communities[schluessel.toString()] = CommunityHinweis.ausJson(wert);
      });
    }

    return CommunityHinweisStand(reiter: reiter, communities: communities);
  }

  /// Markiert GENAU den geöffneten Bereich als gelesen.
  ///
  /// Kein Durchreichen nach oben und keines nach unten — das ist Vuckos
  /// Akzeptanzkriterium 2: „Nutzer öffnet den Feed → nur der Feed-Punkt
  /// verschwindet, die anderen bleiben."
  ///
  /// Die Oberfläche wird SOFORT umgestellt und der Server zieht nach
  /// (Optimistic-UI-Grundsatz). Schlägt der Aufruf fehl, korrigiert der
  /// nächste Abgleich.
  Future<void> alsGesehenMarkieren(
    CommunityBereich bereich, {
    String? communityId,
  }) async {
    if (_db.auth.currentUser == null) return;
    if (bereich == CommunityBereich.community && communityId == null) {
      debugPrint('[CommunityNeuigkeit] community ohne ID, wird übersprungen.');
      return;
    }

    final vorher = stand.value;
    final nachher = bereich == CommunityBereich.community
        ? vorher.ohneCommunity(communityId!)
        : vorher.ohneReiter(bereich);
    stand.value = nachher;
    hatNeues.value = nachher.punkt;

    try {
      await _db.rpc(
        'community_als_gesehen_markieren',
        params: {
          'p_bereich': bereich.schluessel,
          'p_community_id': communityId,
        },
      );
      // Sperrfrist aufheben: Nach einem Schreiben will man den echten Stand
      // sehen, nicht den geratenen.
      _letzterAbgleich = null;
      await aktualisieren(erzwingen: true);
    } catch (e) {
      debugPrint('[CommunityNeuigkeit] Lesestand nicht schreibbar: $e');
      // Zurückdrehen wäre falsch: der Nutzer HAT hingeschaut. Der nächste
      // Abgleich holt den Serverstand und korrigiert, falls nötig.
    }
  }

  /// 2026-08-24: Bleibt als leerer Durchgang bestehen.
  ///
  /// `community_carousel_card.dart` meldet hier seit dem 11.08. die Anzahl
  /// geladener Gruppen und Vorschläge. Diese Zählerei ist seit heute die
  /// falsche Grundlage (siehe Klassenkommentar), die Datei gehört aber einer
  /// anderen Baustelle. Statt sie anzufassen, nimmt der Dienst die Meldung
  /// entgegen und tut nichts damit — der Punkt kommt jetzt vom Server.
  ///
  /// Die Meldung löst allerdings einen Abgleich aus: Die Kachel lädt genau
  /// dann, wenn der Startbildschirm aufgebaut wird, und das ist ein guter
  /// Zeitpunkt für frische Punkte.
  Future<void> melde({int? gruppen, int? vorschlaege}) async {
    await aktualisieren();
  }

  /// Nur für Tests.
  @visibleForTesting
  void zuruecksetzenFuerTest() {
    hatNeues.value = false;
    stand.value = const CommunityHinweisStand.leer();
    _letzterAbgleich = null;
    _laeuft = false;
  }

  /// Nur für Tests: setzt einen Stand, als käme er vom Server.
  @visibleForTesting
  void standAusJsonFuerTest(Map<String, dynamic> json) {
    final neuerStand = _ausJson(json);
    stand.value = neuerStand;
    hatNeues.value = neuerStand.punkt;
  }
}
