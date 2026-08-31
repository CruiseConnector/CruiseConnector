import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/utils/share_helper.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';

/// 2026-08-31 (Auftrag Vucko, Sprachnachricht: „Auch moechte ich, dass man
/// Communities auch ausserhalb von Cruise connect teilen kann. Also dass man
/// sagen kann entweder dass man die community als Post teilt [...] und auch,
/// dass man die community auch auf anderen Seiten verlinken kann wie Instagram
/// Snapchat und so weiter mit deinem Link").
///
/// Zwei Wege, ein Blatt:
///
///  1. NACH AUSSEN. Der Systemdialog zum Teilen (share_plus). Damit geht der
///     Link in jede App, die der Nutzer installiert hat, ohne dass wir je eine
///     davon einbauen muessten. Instagram und Snapchat waren namentlich
///     genannt, WhatsApp und Nachrichten kommen so gratis mit.
///  2. NACH INNEN. Ein Beitrag im eigenen Feed („wir haben jetzt eine
///     Community, komm gern rein"). Erreicht die Leute, die ohnehin schon in
///     der App sind.
///
/// Was in beiden Faellen mitgeht, ist derselbe Link mit demselben
/// Einladungscode. Warum der Code und nicht die Kennung, steht ausfuehrlich
/// bei [CruiseDeepLinks.communityUri].
///
/// EHRLICH DAZUGESAGT, Stand 31.08.2026: Der Link oeffnet die App noch NICHT
/// von aussen. `/.well-known/apple-app-site-association` und
/// `/.well-known/assetlinks.json` antworten auf cruiseconnector.at beide mit
/// 404, und `/c/<code>` gibt es auf der Webseite noch nicht. Bis das steht,
/// landet der Empfaenger im Browser. In der App selbst funktioniert der Weg
/// vollstaendig (Vorschau, Beitreten, Chat), siehe community_einstieg.dart.

/// Der Satz, der mit dem Link nach aussen geht.
///
/// Reine Funktion, damit der Wortlaut pruefbar ist und nicht in einem
/// Widget-Baum versteckt liegt. Kein Binde- und kein Gedankenstrich, echte
/// Umlaute.
String communityTeilenText({required String name, required String linkUrl}) {
  final sauber = name.trim();
  if (sauber.isEmpty) {
    return 'Komm in unsere Community auf Cruise Connect: $linkUrl';
  }
  return 'Wir haben jetzt eine Community auf Cruise Connect: $sauber. '
      'Komm gern rein: $linkUrl';
}

/// Der Vorschlag fuer den Beitrag im eigenen Feed.
///
/// Bewusst ein anderer Wortlaut als [communityTeilenText]: Wer den Feed liest,
/// hat die App schon. Ihm muss man nicht erklaeren, was Cruise Connect ist.
String communityBeitragText({required String name, required String linkUrl}) {
  final sauber = name.trim();
  if (sauber.isEmpty) {
    return 'Wir haben jetzt eine Community. Komm gern rein: $linkUrl';
  }
  return 'Wir haben jetzt eine Community: $sauber. '
      'Komm gern rein: $linkUrl';
}

/// Welchen der beiden Wege der Nutzer gewaehlt hat.
enum CommunityTeilenWahl {
  /// Systemdialog zum Teilen (Instagram, Snapchat, WhatsApp, alles andere).
  link,

  /// Beitrag im eigenen Feed.
  beitrag,
}

/// Das Blatt mit den beiden Wegen.
///
/// Es ENTSCHEIDET nur und fuehrt nichts aus. Grund: Beide Wege oeffnen selbst
/// wieder etwas (Systemdialog, Schreibkasten), und das Blatt ist zu diesem
/// Zeitpunkt schon weggewischt. Ein `Navigator.of(sheetContext)` nach dem
/// eigenen `pop` zeigt ins Leere. Deshalb faellt die Wahl hier und die
/// Ausfuehrung passiert im Kontext des Aufrufers, siehe
/// [CommunityTeilenBlatt.zeigenUndAusfuehren].
class CommunityTeilenBlatt extends StatelessWidget {
  const CommunityTeilenBlatt({
    super.key,
    required this.community,
    required this.einladungsCode,
  });

  final Map<String, dynamic> community;

  /// Kommt aus der RPC `get_community_invite_code` und damit nur fuer
  /// Mitglieder. Ohne Code kein Blatt: der Aufrufer zeigt den Eintrag gar
  /// nicht erst an.
  final String einladungsCode;

  static Future<CommunityTeilenWahl?> zeigen(
    BuildContext context, {
    required Map<String, dynamic> community,
    required String einladungsCode,
  }) {
    return showModalBottomSheet<CommunityTeilenWahl>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityTeilenBlatt(
        community: community,
        einladungsCode: einladungsCode,
      ),
    );
  }

  /// Der eine Aufruf, den die Oberflaeche braucht: Blatt zeigen, Wahl
  /// abwarten, Wahl ausfuehren. [context] ist der des Aufrufers und lebt
  /// laenger als das Blatt.
  static Future<void> zeigenUndAusfuehren(
    BuildContext context, {
    required Map<String, dynamic> community,
    required String einladungsCode,
  }) async {
    final wahl = await zeigen(
      context,
      community: community,
      einladungsCode: einladungsCode,
    );
    if (wahl == null || !context.mounted) return;

    final name = community['name']?.toString().trim() ?? '';
    final linkUrl = CruiseDeepLinks.communityUrl(einladungsCode);

    switch (wahl) {
      case CommunityTeilenWahl.link:
        await shareText(
          context,
          text: communityTeilenText(name: name, linkUrl: linkUrl),
        );
      case CommunityTeilenWahl.beitrag:
        await CommunityBeitragBlatt.zeigen(
          context,
          vorschlag: communityBeitragText(name: name, linkUrl: linkUrl),
        );
    }
  }

  String get _name => community['name']?.toString().trim() ?? '';

  String get _linkUrl => CruiseDeepLinks.communityUrl(einladungsCode);

  @override
  Widget build(BuildContext context) {
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
              children: [
                CommunityAvatar.fromCommunity(
                  community,
                  size: 46,
                  borderRadius: 14,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.isEmpty ? 'Community' : _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Teilen',
                        style: TextStyle(color: Colors.grey, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _LinkFeld(linkUrl: _linkUrl),
            const SizedBox(height: 16),
            _TeilenZeile(
              icon: Icons.ios_share,
              titel: 'Link teilen',
              text: 'Instagram, Snapchat, WhatsApp und alles andere, was du '
                  'auf dem Handy hast.',
              onTap: () =>
                  Navigator.of(context).pop(CommunityTeilenWahl.link),
            ),
            const SizedBox(height: 10),
            _TeilenZeile(
              icon: Icons.post_add_rounded,
              titel: 'Als Beitrag teilen',
              text: 'Im eigenen Feed, für alle, die die App schon haben.',
              onTap: () =>
                  Navigator.of(context).pop(CommunityTeilenWahl.beitrag),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _LinkFeld extends StatelessWidget {
  const _LinkFeld({required this.linkUrl});

  final String linkUrl;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: linkUrl));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link kopiert.'),
            backgroundColor: Color(0xFF171B24),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1250),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppAccentColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppAccentColors.accent.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.link, color: AppAccentColors.accent, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                linkUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.copy, color: Colors.white70, size: 17),
          ],
        ),
      ),
    );
  }
}

class _TeilenZeile extends StatelessWidget {
  const _TeilenZeile({
    required this.icon,
    required this.titel,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String titel;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Color(0xFF8A93A6),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Der kleine Schreibkasten fuer den Beitrag im eigenen Feed.
///
/// Bewusst NICHT die grosse Seite `create_post_page.dart`: Die kennt Bilder,
/// Routenanhaenge, Sichtbarkeit und Erwaehnungen, und nichts davon gehoert
/// hierher. Hier soll man den Vorschlag lesen, zwei Woerter aendern und
/// abschicken koennen. Der Text ist vorausgefuellt, aber vollstaendig
/// aenderbar, weil der Satz zur Community passen muss und nicht zu uns.
class CommunityBeitragBlatt extends StatefulWidget {
  const CommunityBeitragBlatt({super.key, required this.vorschlag});

  final String vorschlag;

  static Future<void> zeigen(
    BuildContext context, {
    required String vorschlag,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityBeitragBlatt(vorschlag: vorschlag),
    );
  }

  @override
  State<CommunityBeitragBlatt> createState() => _CommunityBeitragBlattState();
}

class _CommunityBeitragBlattState extends State<CommunityBeitragBlatt> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.vorschlag,
  );
  bool _laeuft = false;
  String? _fehler;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _veroeffentlichen() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _laeuft) return;

    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    // Beide VOR dem Schliessen festhalten: nach dem `pop` gehoert dieser
    // Kontext zu einem Blatt, das es nicht mehr gibt, und `ScaffoldMessenger`
    // findet von dort aus nichts mehr.
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final id = await SocialService.createPost(text);
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _laeuft = false;
          _fehler = 'Der Beitrag konnte nicht angelegt werden. '
              'Bitte versuch es gleich noch einmal.';
        });
        return;
      }
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Beitrag ist im Feed.'),
          backgroundColor: Color(0xFF171B24),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        _fehler = e is SocialServiceException
            ? e.message
            : 'Der Beitrag konnte nicht angelegt werden. '
                  'Bitte versuch es gleich noch einmal.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
              const Text(
                'Als Beitrag teilen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                maxLength: AppInputLimits.postContentMaxLength,
                style: const TextStyle(color: Colors.white, height: 1.35),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1C1F26),
                  counterStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_fehler != null) ...[
                const SizedBox(height: 6),
                Text(
                  _fehler!,
                  style: const TextStyle(
                    color: Color(0xFFFFB4B4),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _laeuft ? null : _veroeffentlichen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppAccentColors.accent.withValues(
                      alpha: 0.45,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _laeuft
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Beitrag veröffentlichen',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
