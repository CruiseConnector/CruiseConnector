import 'package:flutter/material.dart';

import '../../core/deep_links.dart';
import '../../data/services/social_service.dart';
import '../widgets/user_avatar.dart';
import 'group_lobby_page.dart';

/// 2026-08-23 (vucko, Sprachnachricht vom 23.08.: „wenn er eine Gruppe
/// erstellt hat und er einen anderen einlaedt [...] und er ueber die Glocke
/// bzw. ueber den Quicklink dann joinen will [...] dass ein Fehler kommt").
///
/// EIN Weg in eine Gruppe, fuer alle drei Eingaenge: Glocke, Quicklink und
/// Handy-Push. Vorher waren es drei getrennte Wege mit drei verschiedenen
/// Fehlerbildern:
///   • Glocke      → notifications_page zeigte „Diese Gruppe ist nicht mehr
///                   verfuegbar." (gemessen: dreimal getippt, dann aufgegeben)
///   • Quicklink   → main.dart brach mit einem stummen `return;` ab
///   • Handy-Push  → push_notification_service._handleTapData war ein leerer
///                   Rumpf mit TODO, der Nutzer landete auf der Startseite
///
/// Und selbst mit korrekter Lesepolitik fuehrte kein Weg zum Beitritt: die
/// Lobby ist fuer Mitglieder gebaut und hat keinen Beitreten-Knopf, und
/// `getDiscoverGroups` filtert `is_public = true`, private Gruppen tauchen
/// dort also nie auf.
class GruppenEinstieg {
  GruppenEinstieg._();

  /// Der einzige erlaubte Weg in eine Gruppe von aussen.
  ///
  /// [einladerName] und [gruppenNameAusMeldung] kommen aus der Benachrichtigung,
  /// falls vorhanden. Sie sind nur Schmuck fuer den Text; die Entscheidung
  /// trifft immer der Server ueber [SocialService.pruefeGruppenZugang].
  static Future<void> oeffnen(
    String gruppenId, {
    BuildContext? context,
    String? einladerName,
    String? gruppenNameAusMeldung,
  }) async {
    // Den Navigator VOR dem ersten await festhalten. Aus einer getippten Push
    // gibt es keinen Kontext, dann warten wir kurz auf den Wurzel-Navigator
    // (Kaltstart: die Push kann die App aus dem toten Zustand starten).
    NavigatorState? nav = (context != null && context.mounted)
        ? Navigator.of(context, rootNavigator: true)
        : null;
    nav ??= await _wurzelNavigator();
    if (nav == null) return;

    final bescheid = await SocialService.pruefeGruppenZugang(gruppenId);
    if (!nav.mounted) return;

    switch (bescheid.zugang) {
      case GruppenZugang.mitglied:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => GroupLobbyPage(groupId: gruppenId),
          ),
        );
        return;

      case GruppenZugang.einladung:
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) => GruppenEinladungSeite(
              gruppenId: gruppenId,
              gruppenName: bescheid.gruppenName ?? gruppenNameAusMeldung,
              einladerName: einladerName ?? bescheid.gastgeberName,
              mitgliederAnzahl: bescheid.mitgliederAnzahl,
            ),
          ),
        );
        return;

      case GruppenZugang.nichtAngemeldet:
        // Der wichtigste Fall: Ein Einladungslink soll NEUE Leute holen.
        await OffenerEinladungsLink.merkeGruppe(gruppenId);
        if (!nav.mounted) return;
        _meldung(
          nav,
          titel: 'Erst anmelden',
          text: 'Melde dich an oder erstelle ein Konto. '
              'Wir bringen dich danach direkt zu dieser Gruppe.',
        );
        return;

      case GruppenZugang.netzfehler:
        _meldung(
          nav,
          titel: 'Keine Verbindung',
          text: 'Wir konnten die Gruppe gerade nicht laden. '
              'Das liegt an der Verbindung, nicht an der Gruppe.',
          wiederholen: () => oeffnen(
            gruppenId,
            context: context,
            einladerName: einladerName,
            gruppenNameAusMeldung: gruppenNameAusMeldung,
          ),
        );
        return;

      case GruppenZugang.nichtVerfuegbar:
        // Ehrlich bleiben: Hier ist die Gruppe wirklich zu Ende. Diese Meldung
        // MUSS erhalten bleiben, sonst haetten wir den Fehler nur umgedreht.
        _meldung(
          nav,
          titel: 'Nicht mehr verfügbar',
          text: 'Diese Gruppe gibt es nicht mehr. '
              'Sie wurde gelöscht, beendet, oder die Fahrt läuft bereits.',
        );
        return;
    }
  }

  /// Holt einen gemerkten Einladungslink nach der Anmeldung nach.
  /// Liefert true, wenn ein Link eingelöst wurde.
  /// Laeuft immer auf dem Wurzel-Navigator: Nach der Anmeldung ist die Seite,
  /// auf der der Link angetippt wurde, laengst weg.
  static Future<bool> holeGemerktenLinkNach() async {
    final gruppenId = await OffenerEinladungsLink.holeUndLoescheGruppe();
    if (gruppenId == null || gruppenId.isEmpty) return false;
    await oeffnen(gruppenId);
    return true;
  }

  /// Wartet kurz auf den Wurzel-Navigator. Beim Kaltstart aus einer Push oder
  /// einem Link ist er im ersten Moment noch nicht gebaut; ohne dieses Warten
  /// verschwand der Einstieg still.
  static Future<NavigatorState?> _wurzelNavigator({
    Duration hoechstens = const Duration(seconds: 12),
  }) async {
    final ende = DateTime.now().add(hoechstens);
    NavigatorState? nav = rootNavigatorSchluessel?.currentState;
    while (nav == null && DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      nav = rootNavigatorSchluessel?.currentState;
    }
    return nav;
  }

  /// Wird in main.dart gesetzt. Ein eigener Zeiger statt eines Imports von
  /// main.dart, damit hier keine Ringabhaengigkeit entsteht.
  static GlobalKey<NavigatorState>? rootNavigatorSchluessel;

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
}

/// Das Einladungsblatt. Bewusst ein eigener Bildschirm MIT Knopf und nicht ein
/// stiller Beitritt: Eine Gruppenfahrt teilt die eigene Live-Position mit allen
/// Mitgliedern und belegt einen der `max_people`-Plaetze. Wer nur nachsieht,
/// wer ihn eingeladen hat, darf davon nicht ungefragt betroffen sein.
class GruppenEinladungSeite extends StatefulWidget {
  const GruppenEinladungSeite({
    super.key,
    required this.gruppenId,
    this.gruppenName,
    this.einladerName,
    this.mitgliederAnzahl = 0,
  });

  final String gruppenId;
  final String? gruppenName;
  final String? einladerName;
  final int mitgliederAnzahl;

  @override
  State<GruppenEinladungSeite> createState() => _GruppenEinladungSeiteState();
}

class _GruppenEinladungSeiteState extends State<GruppenEinladungSeite> {
  bool _laeuft = false;
  String? _fehler;

  Future<void> _beitreten() async {
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    try {
      await SocialService.joinGroup(widget.gruppenId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GroupLobbyPage(groupId: widget.gruppenId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _fehler = e is SocialServiceException
            ? e.message
            : 'Beitritt hat nicht geklappt. Bitte versuch es gleich noch einmal.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GruppenEinladungsBlatt(
      gruppenName: widget.gruppenName,
      einladerName: widget.einladerName,
      mitgliederAnzahl: widget.mitgliederAnzahl,
      laeuft: _laeuft,
      fehler: _fehler,
      onBeitreten: _beitreten,
    );
  }
}

/// Reine Darstellung, damit sie ohne Datenbank pruefbar ist.
class GruppenEinladungsBlatt extends StatelessWidget {
  const GruppenEinladungsBlatt({
    super.key,
    this.gruppenName,
    this.einladerName,
    this.mitgliederAnzahl = 0,
    this.laeuft = false,
    this.fehler,
    required this.onBeitreten,
  });

  final String? gruppenName;
  final String? einladerName;
  final int mitgliederAnzahl;
  final bool laeuft;
  final String? fehler;
  final VoidCallback onBeitreten;

  String get einladungsText {
    final gruppe = (gruppenName != null && gruppenName!.trim().isNotEmpty)
        ? gruppenName!.trim()
        : 'einer Gruppenfahrt';
    final einlader = (einladerName != null && einladerName!.trim().isNotEmpty)
        ? einladerName!.trim()
        : null;
    return einlader == null
        ? 'Du wurdest zu $gruppe eingeladen'
        : '$einlader lädt dich zu $gruppe ein';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        title: const Text(
          'Einladung',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: UserAvatar(
                  name: einladerName ?? 'Gruppe',
                  radius: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                einladungsText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                mitgliederAnzahl > 0
                    ? 'Bisher sind $mitgliederAnzahl dabei. Beim Beitreten sehen die anderen während der Fahrt deine Position.'
                    : 'Beim Beitreten sehen die anderen während der Fahrt deine Position.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8A93A6),
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (fehler != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF301B20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    fehler!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFB4B4),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: laeuft ? null : onBeitreten,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: laeuft
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text(
                        'Beitreten',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: laeuft ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'Später',
                  style: TextStyle(
                    color: Color(0xFF8A93A6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
