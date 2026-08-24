import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';

/// 2026-08-24 — Auftrag Vucko: „zudem moechte ich einen beitret button weil
/// man wenn man auf eine community klickt, dass man direkt beitritt ohne
/// beitrettbutton -> fixxen das muss noch umgehend gefixxt werden".
///
/// Gemessen am 24.08.2026 in `community_chats_tab.dart`: das `onTap` der
/// Kachel einer fremden Community war `_joinCommunity(community)`, und dieses
/// `onTap` lag als InkWell ueber der KOMPLETTEN Kachel. Wer nur nachsehen
/// wollte, wer da drin ist, war mit demselben Fingertipp Mitglied. Ein Weg
/// zurueck existierte nur ueber „Verlassen".
///
/// Das wiegt seit heute schwerer als vorher: Beitritt und Austritt werden als
/// Systemnachricht im Chat sichtbar („X ist beigetreten"). Ein Fehltipp
/// schreibt also in einen fremden Chat. Deshalb ist der Tipp auf die Kachel
/// jetzt eine reine ANSICHT, und der Beitritt haengt an genau einem Knopf,
/// den man erst sieht, nachdem man weiss, worauf man sich einlaesst.
///
/// Warum ein Blatt von unten und keine eigene Seite: Die Vorschau ist ein
/// Blick, keine Station. Sie zeigt sechs Angaben, die alle schon in der
/// geladenen Zeile stehen (Bild, Name, Besitzer, Beschreibung, Mitgliederzahl,
/// Gruendungsdatum) und braucht deshalb KEINE zusaetzliche Abfrage. Ein
/// Wisch nach unten bringt einen zurueck in die Liste, an dieselbe Stelle.
/// Eine aufklappende Kachel waere die dritte Variante gewesen, macht die
/// Liste beim Auf- und Zuklappen aber unruhig und laesst keinen Platz fuer
/// einen Knopf, den man nicht uebersehen kann.

/// Was ein Tippen auf eine Community-Kachel ausloesen darf.
///
/// Bewusst eine eigene, benannte Entscheidung statt eines `onTap`, das an der
/// Aufrufstelle irgendetwas sein kann. Genau dort ist der Fehler entstanden.
enum CommunityKachelZiel {
  /// Mitglied: der Tipp fuehrt in den Chat.
  chat,

  /// Kein Mitglied: der Tipp fuehrt in die Vorschau. NIEMALS in den Beitritt.
  vorschau,
}

/// Die eine Stelle, die ueber das Ziel eines Kacheltipps entscheidet.
CommunityKachelZiel communityKachelZiel({required bool istMitglied}) {
  return istMitglied ? CommunityKachelZiel.chat : CommunityKachelZiel.vorschau;
}

/// Wie ein Beitrittsversuch ausgegangen ist.
enum CommunityBeitrittAusgang {
  /// Jetzt Mitglied. Der Chat darf aufgehen.
  beigetreten,

  /// War schon Mitglied (zweiter Fingertipp, alter Einladungscode). Der Chat
  /// darf ebenfalls aufgehen.
  schonMitglied,

  /// Private Community: eine Anfrage liegt beim Admin. Der Chat bleibt zu,
  /// sonst landet der Nutzer in einer leeren, nicht lesbaren Seite.
  angefragt,

  /// Hat nicht geklappt. [CommunityBeitrittsErgebnis.meldung] sagt warum.
  fehler,
}

class CommunityBeitrittsErgebnis {
  const CommunityBeitrittsErgebnis(
    this.ausgang, {
    this.communityId = '',
    this.meldung,
  });

  final CommunityBeitrittAusgang ausgang;
  final String communityId;

  /// Der Satz fuer den Nutzer. Er steht IM Blatt, nicht in einem Schnipsel
  /// dahinter: eine SnackBar liegt unter dem Blatt und ist damit unsichtbar.
  final String? meldung;

  bool get oeffnetChat =>
      ausgang == CommunityBeitrittAusgang.beigetreten ||
      ausgang == CommunityBeitrittAusgang.schonMitglied;
}

/// Uebersetzt einen Fehler beim Beitreten in einen Satz, der dem Nutzer sagt,
/// was los ist.
///
/// Deckt die Faelle ab, die beim Beitreten wirklich vorkommen und vorher alle
/// als „Aktion gerade nicht moeglich." endeten:
/// - Community wurde inzwischen geloescht (Fremdschluessel greift ins Leere),
/// - kein Netz,
/// - privat (dann steht die richtige Erklaerung schon im Fehler des Dienstes).
String beitrittsFehlerText(Object fehler) {
  final roh = fehler.toString().trim();
  final klein = roh.toLowerCase();

  if (klein.contains('foreign key') ||
      klein.contains('23503') ||
      klein.contains('is not present in table')) {
    return 'Diese Community gibt es nicht mehr.';
  }

  if (klein.contains('socketexception') ||
      klein.contains('clientexception') ||
      klein.contains('failed host lookup') ||
      klein.contains('connection closed') ||
      klein.contains('connection refused') ||
      klein.contains('network is unreachable') ||
      klein.contains('timeoutexception') ||
      klein.contains('timed out')) {
    return 'Keine Verbindung. Sobald du wieder Netz hast, klappt der Beitritt.';
  }

  // Der Dienst liefert fuer „privat" und fuer die Antworten der RPC schon
  // fertige deutsche Saetze. Die bleiben, solange sie nach einem Satz fuer
  // Menschen aussehen und nicht nach Datenbank.
  final istBackendRauschen =
      klein.contains('postgrest') ||
      klein.contains('supabase') ||
      klein.contains('row-level') ||
      klein.contains('policy') ||
      klein.contains('violates') ||
      klein.contains('schema cache') ||
      klein.contains('duplicate key');
  if (roh.isEmpty || istBackendRauschen || roh.length > 110) {
    return 'Beitreten gerade nicht möglich. Versuch es gleich noch einmal.';
  }
  return roh;
}

/// Die Vorschau selbst.
///
/// Absichtlich ohne jeden Datenbankzugriff: alles kommt als [community]-Zeile
/// herein, der Beitritt geschieht ueber [onBeitreten]. Dadurch ist das Blatt
/// im Test vollstaendig fahrbar, und der Beitritt kann NUR ueber den Knopf
/// ausgeloest werden.
class CommunityVorschauBlatt extends StatefulWidget {
  const CommunityVorschauBlatt({
    super.key,
    required this.community,
    required this.istMitglied,
    required this.onBeitreten,
    required this.onFertig,
    this.jetzt,
  });

  final Map<String, dynamic> community;

  /// Ob man schon dabei ist. Dann heisst der Knopf „Chat öffnen" und
  /// [onBeitreten] wird gar nicht erst gerufen.
  final bool istMitglied;

  /// Fuehrt den Beitritt aus. Wird ausschliesslich vom Knopf gerufen.
  final Future<CommunityBeitrittsErgebnis> Function() onBeitreten;

  /// Der Chat darf aufgehen. Das Blatt navigiert selbst nicht.
  final void Function(CommunityBeitrittsErgebnis ergebnis) onFertig;

  /// Nur fuer den Test: fester Bezugspunkt fuer „Vor kurzem erstellt".
  final DateTime? jetzt;

  /// Oeffnet die Vorschau als Blatt von unten und liefert das Ergebnis.
  static Future<CommunityBeitrittsErgebnis?> zeigen(
    BuildContext context, {
    required Map<String, dynamic> community,
    required bool istMitglied,
    required Future<CommunityBeitrittsErgebnis> Function() onBeitreten,
  }) {
    return showModalBottomSheet<CommunityBeitrittsErgebnis>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => CommunityVorschauBlatt(
        community: community,
        istMitglied: istMitglied,
        onBeitreten: onBeitreten,
        onFertig: (ergebnis) => Navigator.of(sheetContext).pop(ergebnis),
      ),
    );
  }

  @override
  State<CommunityVorschauBlatt> createState() => _CommunityVorschauBlattState();
}

class _CommunityVorschauBlattState extends State<CommunityVorschauBlatt> {
  late int _mitglieder;
  late bool _istMitglied;
  bool _laeuft = false;
  bool _angefragt = false;
  String? _hinweis;
  bool _hinweisIstFehler = false;

  @override
  void initState() {
    super.initState();
    _mitglieder = CommunityChatService.memberCount(widget.community);
    _istMitglied = widget.istMitglied;
  }

  bool get _istOeffentlich => widget.community['is_public'] == true;

  String get _knopfText {
    if (_istMitglied) return 'Chat öffnen';
    if (_angefragt) return 'Anfrage liegt beim Admin';
    return _istOeffentlich ? 'Beitreten' : 'Beitritt anfragen';
  }

  Future<void> _knopfGedrueckt() async {
    if (_laeuft || _angefragt) return;

    // Schon Mitglied: kein zweiter Beitritt, nur aufmachen.
    if (_istMitglied) {
      widget.onFertig(
        CommunityBeitrittsErgebnis(
          CommunityBeitrittAusgang.schonMitglied,
          communityId: widget.community['id']?.toString() ?? '',
        ),
      );
      return;
    }

    setState(() {
      _laeuft = true;
      _hinweis = null;
      _hinweisIstFehler = false;
    });

    final ergebnis = await widget.onBeitreten();
    if (!mounted) return;

    setState(() {
      _laeuft = false;
      if (ergebnis.oeffnetChat) {
        // Vuckos Punkt „man soll sehen wer dazu gekommen ist": die Zahl im
        // Blatt zaehlt den eigenen Beitritt SOFORT mit. Die Liste dahinter
        // holt sich gleich danach den echten Stand vom Server.
        if (ergebnis.ausgang == CommunityBeitrittAusgang.beigetreten) {
          _mitglieder += 1;
        }
        _istMitglied = true;
        _hinweis = ergebnis.meldung;
        _hinweisIstFehler = false;
      } else if (ergebnis.ausgang == CommunityBeitrittAusgang.angefragt) {
        _angefragt = true;
        _hinweis = ergebnis.meldung ?? 'Deine Anfrage liegt jetzt beim Admin.';
        _hinweisIstFehler = false;
      } else {
        _hinweis = ergebnis.meldung ?? 'Beitreten gerade nicht möglich.';
        _hinweisIstFehler = true;
      }
    });

    if (ergebnis.oeffnetChat) widget.onFertig(ergebnis);
  }

  @override
  Widget build(BuildContext context) {
    final community = widget.community;
    final owner = CommunityChatService.ownerProfile(community);
    final ownerName = CommunityChatService.displayName(
      owner,
      fallbackUserId: community['owner_id'] as String?,
    );
    final beschreibung = (community['description'] as String?)?.trim();
    final gruendung = CommunityChatService.gruendungsdatumText(community);
    final istNeu = CommunityChatService.istVorKurzemErstellt(
      community,
      jetzt: widget.jetzt,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CommunityAvatar.fromCommunity(
                  community,
                  size: 62,
                  borderRadius: 16,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        community['name']?.toString() ?? 'Community',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$ownerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _plakette(
                            _istOeffentlich ? 'Öffentlich' : 'Privat',
                            _istOeffentlich
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                          if (istNeu)
                            _plakette('Vor kurzem erstellt', Colors.white70),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              beschreibung == null || beschreibung.isEmpty
                  ? 'Diese Community hat noch keine Beschreibung.'
                  : beschreibung,
              style: TextStyle(
                color: beschreibung == null || beschreibung.isEmpty
                    ? Colors.grey
                    : Colors.white70,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _angabe(
              Icons.people_outline,
              _mitglieder == 1 ? '1 Mitglied' : '$_mitglieder Mitglieder',
            ),
            if (gruendung != null) ...[
              const SizedBox(height: 9),
              _angabe(Icons.event_outlined, gruendung),
            ],
            if (!_istOeffentlich && !_istMitglied) ...[
              const SizedBox(height: 9),
              _angabe(
                Icons.lock_outline,
                'Privat. Der Admin muss deine Anfrage annehmen.',
              ),
            ],
            if (_hinweis != null) ...[
              const SizedBox(height: 14),
              _hinweisFeld(_hinweis!, istFehler: _hinweisIstFehler),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_laeuft || _angefragt) ? null : _knopfGedrueckt,
                icon: _laeuft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _istMitglied
                            ? Icons.chat_bubble_outline
                            : (_istOeffentlich
                                  ? Icons.person_add_alt_1
                                  : Icons.mark_email_unread_outlined),
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _knopfText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppAccentColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppAccentColors.accent.withValues(
                    alpha: 0.45,
                  ),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _angabe(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey[500], size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _plakette(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _hinweisFeld(String text, {required bool istFehler}) {
    final farbe = istFehler ? Colors.redAccent : AppAccentColors.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: farbe.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            istFehler ? Icons.error_outline : Icons.info_outline,
            color: farbe,
            size: 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
