import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';

/// 2026-08-24 — Auftrag Vucko: „man soll auch community anpinnen koennen und
/// wenn man in der community oben klickt auf den namen wenn man drinnen ist,
/// soll man auch als normaler user in der gruppe die eckdaten wie mitglieder
/// usw sehen koennen aber man soll nichts aendern koennen das soll gelocked
/// sein".
///
/// GEMESSEN am 24.08.2026 vor der Aenderung: der Community-Name in
/// `community_chat_detail_page.dart` war an BEIDEN Stellen (Titel der
/// AppBar und Kopfzeile darunter) ein blosser `Row` aus [CommunityAvatar]
/// und [Text] — ohne `onTap`, ohne `InkWell`, ohne `GestureDetector`. Ein
/// normales Mitglied kam an die Eckdaten seiner eigenen Community also gar
/// nicht heran: die Einstellungs-Seite steht nur Admins offen
/// (`_amAdmin == _myRole == 'owner'`), und die Vorschau von unten ist fuer
/// NICHTMITGLIEDER gebaut und endet in einem Beitritts-Knopf.
///
/// ## Warum ein eigenes Blatt und keine Erweiterung von CommunityVorschauBlatt
///
/// Geprueft, bevor etwas Neues entstand. Die Vorschau zeigt fuenf derselben
/// Angaben (Bild, Name, Besitzer, Sichtbarkeit, Beschreibung, Mitgliederzahl,
/// Gruendungsdatum) — der Gedanke, sie einfach um einen Modus zu erweitern,
/// liegt nahe und war der erste Versuch. Dagegen sprechen drei Dinge:
///
/// 1. Die Vorschau ist ihrem ganzen Zustand nach ein BEITRITTS-Vorgang:
///    `_laeuft`, `_angefragt`, `_istMitglied`, `onBeitreten` als Pflichtfeld,
///    ein Ergebnis-Objekt als Rueckgabe. Fuer ein Mitglied ist davon nichts
///    zutreffend. Ein Modus-Schalter haette jeden dieser Zweige mit einem
///    „ausser wenn Mitglied" versehen — genau die Art Verzweigung, aus der
///    am 24.08. der Fehler „ein Tipp trat sofort bei" entstanden ist.
/// 2. Der Inhalt ist NICHT derselbe. Ein Mitglied braucht zusaetzlich den
///    Schreibmodus, seine eigene Rolle und den Weg zur Mitgliederliste;
///    umgekehrt ist der Satz „Der Admin muss deine Anfrage annehmen" fuer
///    ein Mitglied sinnlos.
/// 3. Der Auftrag zieht die Grenze der Dateien bewusst um die Chat-Seite
///    herum; die Vorschau ist seit heute im Einsatz und wird hier nicht
///    angefasst.
///
/// Damit aus zwei Ansichten keine drei auseinanderlaufenden werden, sind alle
/// Angaben aus DENSELBEN Quellen gelesen wie dort ([CommunityChatService]),
/// und das Blatt sieht bewusst gleich aus (Griff, Bild 62, Plaketten, Zeilen
/// mit Symbol). Was noch fehlt, steht im Bericht unter „offen“: die
/// gemeinsamen Anzeigebausteine gehoeren spaeter in EIN Widget, das beide
/// Blaetter benutzen.
///
/// ## Was „gelocked" hier heisst
///
/// Nicht grau und tot. Alle Angaben stehen in normaler Schrift, gut lesbar,
/// wie in der Vorschau. Gesperrt ist nur, was hier nirgends auftaucht:
/// Eingabefelder, Schalter, Speichern-Knoepfe. Ein Satz mit Schloss sagt
/// zusaetzlich, WER es aendern kann — ein Nutzer, der weiss, an wen er sich
/// wendet, fuehlt sich nicht ausgesperrt. Und ein Weg bleibt offen, den auch
/// ein normales Mitglied gehen darf: die Mitgliederliste.

/// Wohin ein Tipp auf den Community-Namen in der Kopfzeile fuehrt.
///
/// Bewusst eine eigene, benannte Entscheidung — dasselbe Muster wie
/// `communityKachelZiel` in `community_vorschau_blatt.dart`. Beide Stellen
/// (AppBar-Titel und Kopfzeile darunter) fragen dieselbe Funktion, damit sie
/// nicht auseinanderlaufen koennen.
enum CommunityKopfzeileZiel {
  /// Admin: direkt in die Einstellungen. Ein Tipp, kein Zwischenblatt.
  einstellungen,

  /// Alle anderen (Mitglied, Moderator): die Eckdaten zum Nachlesen.
  eckdaten,
}

/// Die eine Stelle, die ueber das Ziel eines Tipps auf den Namen entscheidet.
///
/// Vuckos Punkt 4: „Ein ADMIN muss von derselben Stelle aus weiterhin in die
/// Einstellungen kommen — er soll nicht erst durch eine Nur-Lesen-Ansicht
/// hindurch." Deshalb fuehrt derselbe Fingertipp je nach Rolle woanders hin:
/// Der Admin sieht in den Einstellungen ALLES, was im Eckdaten-Blatt steht,
/// und kann es zusaetzlich aendern — ein Zwischenblatt waere fuer ihn ein
/// zusaetzlicher Tipp ohne einen einzigen zusaetzlichen Wert.
///
/// [rolle] ist die eigene Rolle in dieser Community (`owner`, `moderator`,
/// `member`) oder null, solange die Mitglieder noch nicht geladen sind.
/// Unbekannt zaehlt wie „normales Mitglied": lieber die Nur-Lesen-Ansicht als
/// eine Einstellungs-Seite, die dann „Kein Zugriff" zeigt.
CommunityKopfzeileZiel communityKopfzeileZiel({required String? rolle}) {
  return rolle == 'owner'
      ? CommunityKopfzeileZiel.einstellungen
      : CommunityKopfzeileZiel.eckdaten;
}

/// Die Eckdaten einer Community, nur zum Lesen.
///
/// Absichtlich ohne jeden Datenbankzugriff: alles kommt als [community]-Zeile
/// herein, die bereits geladen ist. Dadurch ist das Blatt im Test vollstaendig
/// fahrbar — und es KANN gar nichts schreiben, weil es keinen Dienst kennt,
/// der schreibt.
class CommunityEckdatenBlatt extends StatelessWidget {
  const CommunityEckdatenBlatt({
    super.key,
    required this.community,
    required this.rolle,
    required this.onMitgliederAnzeigen,
    required this.onSchliessen,
  });

  final Map<String, dynamic> community;

  /// Eigene Rolle: `owner`, `moderator`, `member` oder null.
  final String? rolle;

  /// Fuehrt in die Mitgliederliste. Der eine Weg, der auch einem normalen
  /// Mitglied offensteht.
  final VoidCallback onMitgliederAnzeigen;

  /// Schliesst das Blatt. Es navigiert selbst nicht.
  final VoidCallback onSchliessen;

  /// Oeffnet die Eckdaten als Blatt von unten.
  static Future<void> zeigen(
    BuildContext context, {
    required Map<String, dynamic> community,
    required String? rolle,
    required VoidCallback onMitgliederAnzeigen,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => CommunityEckdatenBlatt(
        community: community,
        rolle: rolle,
        // Erst zu, dann die Liste: zwei Blaetter uebereinander verdecken
        // sich sonst gegenseitig.
        onMitgliederAnzeigen: () {
          Navigator.of(sheetContext).pop();
          onMitgliederAnzeigen();
        },
        onSchliessen: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  bool get _istOeffentlich => community['is_public'] == true;

  bool get _nurAdminsSchreiben => community['owner_only_messages'] == true;

  /// Der Satz mit dem Schloss. Er sagt WER aendern darf, nicht nur DASS es
  /// gesperrt ist — und er ist fuer einen Moderator ein anderer, weil ein
  /// Moderator sehr wohl etwas darf (Beitraege anheften, Mitglieder
  /// entfernen), nur eben nicht die Eckdaten aendern.
  String get _schlossText {
    if (rolle == 'moderator') {
      return 'Als Moderator moderierst du Beiträge und Mitglieder. '
          'Name, Bild, Sichtbarkeit und Schreibmodus ändert der Admin.';
    }
    return 'Diese Angaben legt der Admin fest. Du kannst sie hier in Ruhe '
        'nachlesen, ändern kann sie nur er.';
  }

  @override
  Widget build(BuildContext context) {
    final owner = CommunityChatService.ownerProfile(community);
    final ownerName = CommunityChatService.displayName(
      owner,
      fallbackUserId: community['owner_id'] as String?,
    );
    final beschreibung = (community['description'] as String?)?.trim();
    final gruendung = CommunityChatService.gruendungsdatumText(community);
    final mitglieder = CommunityChatService.memberCount(community);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: SingleChildScrollView(
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
                            // Die eigene Rolle steht hier, weil sie erklaert,
                            // warum manches geht und manches nicht.
                            _plakette(
                              'Du: ${CommunityChatService.roleLabel(rolle)}',
                              Colors.white70,
                            ),
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
                mitglieder == 1 ? '1 Mitglied' : '$mitglieder Mitglieder',
              ),
              if (gruendung != null) ...[
                const SizedBox(height: 9),
                _angabe(Icons.event_outlined, gruendung),
              ],
              const SizedBox(height: 9),
              _angabe(
                _istOeffentlich ? Icons.public : Icons.lock_outline,
                _istOeffentlich
                    ? 'Öffentlich, jeder findet und liest diese Community.'
                    : 'Privat, nur mit Einladung oder nach Anfrage.',
              ),
              const SizedBox(height: 9),
              _angabe(
                _nurAdminsSchreiben
                    ? Icons.admin_panel_settings_outlined
                    : Icons.edit_outlined,
                'Wer darf schreiben: '
                '${_nurAdminsSchreiben ? CommunityChatService.writeModeAdminsTitle : CommunityChatService.writeModeEveryoneTitle}',
              ),
              const SizedBox(height: 16),
              _schlossHinweis(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onMitgliederAnzeigen,
                  icon: const Icon(
                    Icons.people_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Mitglieder ansehen',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppAccentColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // Immer ein sichtbarer Ausweg, nicht nur der Wisch nach unten.
              Center(
                child: TextButton(
                  onPressed: onSchliessen,
                  child: const Text(
                    'Schließen',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
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

  /// Der Hinweis ist ABSICHTLICH in der Akzentfarbe und nicht in Grau oder
  /// Rot: Grau liest sich wie „kaputt", Rot wie „du hast etwas falsch
  /// gemacht". Hier ist beides nicht der Fall — es ist eine Auskunft.
  Widget _schlossHinweis() {
    final farbe = AppAccentColors.accent;
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
          Icon(Icons.lock_outline, color: farbe, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _schlossText,
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
