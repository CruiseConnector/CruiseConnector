import 'package:flutter/material.dart';

import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/pages/community_chat_detail_page.dart';
import 'package:cruise_connect/presentation/pages/group_join_gate.dart';
import 'package:cruise_connect/presentation/widgets/community/community_vorschau_blatt.dart';

/// 2026-08-31 (Auftrag Vucko, Sprachnachricht: „dass wenn man die App hat,
/// dass man direkt zur App weitergeleitet wird und dann in den Vorschau
/// screen, wo man halt so sieht okay ja da was ist das fuer eine Gruppe [...]
/// mit kurzer Beschreibung und dem Titel und dass man auf beitreten klicken
/// kann oder nicht").
///
/// EIN Weg in eine Community von aussen. Gebaut nach dem Vorbild von
/// [GruppenEinstieg], weil dort am 23.08. genau dieselben vier Fallen schon
/// einmal aufgeraeumt wurden:
///
///   • Nicht angemeldet. Der haeufigste Fall bei einem Link, den jemand auf
///     Instagram gesehen hat. Ohne Gedaechtnis waere der Link nach dem ersten
///     Antippen verbrannt.
///   • Kaltstart. Beim Start aus einem Link steht der Wurzel-Navigator im
///     ersten Moment noch nicht. Ohne Warten verschwindet der Einstieg still.
///   • Kein Netz. Darf NICHT als „gibt es nicht mehr" erscheinen. Siehe
///     [CommunityVorschauArt].
///   • Wirklich weg. Muss ehrlich so heissen, sonst haetten wir den Fehler
///     nur umgedreht.
///
/// Der Beitritt selbst passiert NIE hier, sondern ausschliesslich ueber den
/// Knopf im [CommunityVorschauBlatt]. Das ist dieselbe Regel wie in der Liste
/// seit dem 24.08.: ein Fingertipp auf einen Link darf niemanden zum Mitglied
/// machen, weil ein Beitritt im Chat als Systemnachricht sichtbar wird.
class CommunityEinstieg {
  CommunityEinstieg._();

  /// Der einzige erlaubte Weg in eine Community von aussen.
  ///
  /// [ziel] ist das, was im Link stand: normalerweise ein Einladungscode
  /// (`CCC-ABC234`), zur Not auch eine Kennung. Was davon es ist, entscheidet
  /// [_zielArt].
  static Future<void> oeffnen(String ziel, {BuildContext? context}) async {
    final roh = ziel.trim();
    if (roh.isEmpty) return;

    // Den Navigator VOR dem ersten await festhalten. Aus einem angetippten
    // Link gibt es keinen Kontext, dann warten wir kurz auf den
    // Wurzel-Navigator (der Link kann die App aus dem toten Zustand starten).
    NavigatorState? nav = (context != null && context.mounted)
        ? Navigator.of(context, rootNavigator: true)
        : null;
    nav ??= await GruppenEinstieg.wurzelNavigator();
    if (nav == null) return;

    final art = _zielArt(roh);
    if (art == _ZielArt.unbrauchbar) {
      _meldung(
        nav,
        titel: 'Link stimmt nicht',
        text: 'Dieser Link gehört zu keiner Community. '
            'Bitte lass ihn dir noch einmal schicken.',
      );
      return;
    }

    // Der wichtigste Fall zuerst, VOR jeder Abfrage: Ein geteilter Link soll
    // neue Leute holen. Genau die sind hier nicht angemeldet.
    if (!CommunityChatService.istAngemeldet) {
      await OffenerCommunityLink.merkeCode(roh);
      if (!nav.mounted) return;
      _meldung(
        nav,
        titel: 'Erst anmelden',
        text: 'Melde dich an oder erstelle ein Konto. '
            'Wir bringen dich danach direkt zu dieser Community.',
      );
      return;
    }

    final vorschau = art == _ZielArt.code
        ? await CommunityChatService.vorschauZuCode(roh)
        : await CommunityChatService.vorschauZuId(roh);
    if (!nav.mounted) return;

    switch (vorschau.art) {
      case CommunityVorschauArt.netzfehler:
        _meldung(
          nav,
          titel: 'Keine Verbindung',
          text: 'Wir konnten die Community gerade nicht laden. '
              'Das liegt an der Verbindung, nicht an der Community.',
          wiederholen: () => oeffnen(roh, context: context),
        );
        return;

      case CommunityVorschauArt.codeUngueltig:
        _meldung(
          nav,
          titel: 'Link stimmt nicht',
          text: 'Dieser Link gehört zu keiner Community. '
              'Bitte lass ihn dir noch einmal schicken.',
        );
        return;

      case CommunityVorschauArt.unbekannt:
        // Ehrlich bleiben. Hier ist die Community wirklich zu Ende, oder der
        // Link trug eine Kennung statt eines Codes und zeigt auf eine private
        // Community. Beides endet fuer den Betrachter gleich.
        _meldung(
          nav,
          titel: 'Nicht mehr verfügbar',
          text: 'Diese Community gibt es nicht mehr, oder der Link ist '
              'abgelaufen. Frag am besten kurz nach einem neuen Link.',
        );
        return;

      case CommunityVorschauArt.gefunden:
        break;
    }

    final zeile = vorschau.zeile!;
    final id = zeile['id']?.toString() ?? '';
    // Die RPC liefert `member_count`, aber KEINE Mitgliederliste. Ohne diese
    // zweite Frage stuende einem langjaehrigen Mitglied ein Beitreten-Knopf
    // im Weg. Begruendung steht bei `CommunityChatService.istMitglied`.
    final istMitglied = id.isEmpty
        ? false
        : await CommunityChatService.istMitglied(id);
    if (!nav.mounted) return;

    final ergebnis = await CommunityVorschauBlatt.zeigen(
      nav.context,
      community: zeile,
      istMitglied: istMitglied,
      onBeitreten: () => communityBeitrittAusfuehren(
        communityId: id,
        inviteCode: art == _ZielArt.code ? roh : null,
      ),
    );
    if (ergebnis == null || !ergebnis.oeffnetChat || !nav.mounted) return;

    final zielId = ergebnis.communityId.isNotEmpty ? ergebnis.communityId : id;
    if (zielId.isEmpty) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityChatDetailPage(communityId: zielId),
      ),
    );
  }

  /// Holt einen gemerkten Community-Link nach der Anmeldung nach.
  /// Liefert true, wenn einer eingelöst wurde.
  static Future<bool> holeGemerktenLinkNach() async {
    final code = await OffenerCommunityLink.holeUndLoescheCode();
    if (code == null || code.isEmpty) return false;
    await oeffnen(code);
    return true;
  }

  static void _meldung(
    NavigatorState nav, {
    required String titel,
    required String text,
    VoidCallback? wiederholen,
  }) {
    showDialog<void>(
      context: nav.context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E28),
        title: Text(
          titel,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          text,
          style: const TextStyle(color: Color(0xFFB6BDC9), height: 1.35),
        ),
        actions: [
          if (wiederholen != null)
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                wiederholen();
              },
              child: const Text('Erneut versuchen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  /// Nur fuer den Test sichtbar gemacht: welche Art Ziel in einem Link steht.
  @visibleForTesting
  static bool istEinladungscode(String ziel) =>
      _zielArt(ziel) == _ZielArt.code;

  @visibleForTesting
  static bool istKennung(String ziel) => _zielArt(ziel) == _ZielArt.kennung;

  static _ZielArt _zielArt(String roh) {
    if (CommunityChatService.normalizeInviteCode(roh) != null) {
      return _ZielArt.code;
    }
    if (_kennungsMuster.hasMatch(roh)) return _ZielArt.kennung;
    return _ZielArt.unbrauchbar;
  }

  /// Eine Community-Kennung ist eine UUID. Ohne diese Pruefung wuerde jeder
  /// Tippfehler im Link als Kennung durchgehen und in einer nichtssagenden
  /// Datenbankmeldung enden statt in einem Satz.
  static final RegExp _kennungsMuster = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}

enum _ZielArt { code, kennung, unbrauchbar }

/// Der EINE Weg in eine Mitgliedschaft, den es in der Oberflaeche noch gibt.
/// Wird ausschliesslich vom Knopf im [CommunityVorschauBlatt] gerufen, aus dem
/// Link-Einstieg wie aus der Liste im Reiter „Chats".
///
/// Zwei Wege, ein Ergebnis:
///  • mit Einladungscode: die RPC `join_community_with_code_v2` entscheidet.
///    Bei einer privaten Community wird daraus eine Beitrittsanfrage beim
///    Admin (bindende Entscheidung Vucko vom 23.08.2026), kein Beitritt.
///  • ohne Code (Entdecken-Liste): direkter Eintrag. Geht nur bei
///    oeffentlichen Communities; bei einer privaten antwortet die Datenbank
///    mit 42501 und der Dienst mit dem passenden Satz.
///
/// 2026-08-31: Lag vorher als private Methode `_beitrittAusfuehren` in
/// community_chats_tab.dart. Der Link-Einstieg braucht dieselbe Entscheidung
/// Wort fuer Wort; zwei Abschriften waeren im ersten Monat auseinandergelaufen.
Future<CommunityBeitrittsErgebnis> communityBeitrittAusfuehren({
  required String communityId,
  String? inviteCode,
}) async {
  final id = communityId.trim();
  try {
    final code = inviteCode?.trim();
    if (code != null && code.isNotEmpty) {
      final result = await CommunityChatService.joinCommunityByCode(code);
      final ausgang = switch (result.status) {
        CommunityJoinStatus.joined => CommunityBeitrittAusgang.beigetreten,
        CommunityJoinStatus.alreadyMember =>
          CommunityBeitrittAusgang.schonMitglied,
        _ => CommunityBeitrittAusgang.angefragt,
      };
      return CommunityBeitrittsErgebnis(
        ausgang,
        communityId: result.communityId.isNotEmpty ? result.communityId : id,
        meldung: result.userMessage,
      );
    }
    if (id.isEmpty) {
      return const CommunityBeitrittsErgebnis(
        CommunityBeitrittAusgang.fehler,
        meldung: 'Diese Community gibt es nicht mehr.',
      );
    }
    await CommunityChatService.joinCommunity(id);
    return CommunityBeitrittsErgebnis(
      CommunityBeitrittAusgang.beigetreten,
      communityId: id,
    );
  } catch (e) {
    return CommunityBeitrittsErgebnis(
      CommunityBeitrittAusgang.fehler,
      communityId: id,
      meldung: beitrittsFehlerText(e),
    );
  }
}
