import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entscheidet, ob am Community-Symbol ein Hinweispunkt leuchtet.
///
/// 2026-08-11 (vucko): „vorallem moechte ich, dass die Leute eher sehen, dass
/// es auch das Gruppenfeature oder das Community-Feature gibt."
///
/// KOSTET KEINE EINZIGE ZUSAETZLICHE ABFRAGE. Die Home-Kacheln laden Gruppen
/// und Vorschlaege ohnehin — sie melden ihre Anzahl hierher. Verglichen wird
/// mit dem Stand vom letzten Community-Besuch.
///
/// Die Regel, damit der Punkt nicht nervt:
///   * Er erscheint, wenn es MEHR Gruppen oder Vorschlaege gibt als beim
///     letzten Besuch — beim allerersten Mal also auch, und das ist gewollt:
///     genau dann soll jemand die Community ueberhaupt entdecken.
///   * Er verschwindet, sobald der Community-Tab geoeffnet wird.
///   * Er blinkt NICHT bei jedem App-Start: Der gesehene Stand liegt auf dem
///     Geraet und ueberlebt Neustarts.
///   * Er leuchtet nicht dauerhaft: Weniger oder gleich viel wie beim letzten
///     Besuch heisst „nichts Neues".
class CommunityNeuigkeitService {
  CommunityNeuigkeitService._();

  static final CommunityNeuigkeitService instance =
      CommunityNeuigkeitService._();

  static const _kGesehenGruppen = 'community_gesehen_gruppen_v1';
  static const _kGesehenVorschlaege = 'community_gesehen_vorschlaege_v1';

  /// Die Oberflaeche haengt sich hier dran — kein Polling.
  final ValueNotifier<bool> hatNeues = ValueNotifier<bool>(false);

  int? _letzteGruppen;
  int? _letzteVorschlaege;

  /// Meldet, was eine Home-Kachel gerade geladen hat.
  ///
  /// BEIDE Werte sind ABSICHTLICH optional, und nur uebergebene Werte
  /// ueberschreiben den Stand.
  ///
  /// 2026-08-11: Vorher waren beide Pflicht — und genau daran ist der Punkt
  /// gestorben. Auf dem Startbildschirm liegen ZWEI unabhaengige Kacheln
  /// („Kontakte" und „Gruppen"). Jede laedt nur ihre eigene Haelfte und setzte
  /// fuer die andere den Cache des Nachbarn ein. Beim Kaltstart ist dieser
  /// Cache noch leer, also meldete jede Kachel fuer die fremde Haelfte eine 0.
  /// Wer zuletzt fertig wurde, gewann — und ueberschrieb den korrekten Wert
  /// des anderen mit 0. Die Vorschlaege-Abfrage ist die langsamere, sie kam
  /// typischerweise zuletzt: Neue Gruppen wurden dadurch regelmaessig auf 0
  /// zurueckgesetzt und der Punkt blieb aus, obwohl es echt Neues gab. Und das
  /// fuer die ganze Sitzung, denn melde() laeuft je Kachel nur einmal.
  Future<void> melde({int? gruppen, int? vorschlaege}) async {
    if (gruppen != null) _letzteGruppen = gruppen;
    if (vorschlaege != null) _letzteVorschlaege = vorschlaege;
    try {
      final p = await SharedPreferences.getInstance();
      final gesehenG = p.getInt(_kGesehenGruppen);
      final gesehenV = p.getInt(_kGesehenVorschlaege);

      // Nur Haelften bewerten, zu denen es ueberhaupt eine Zahl gibt. Eine
      // noch nicht geladene Haelfte darf weder leuchten lassen noch loeschen.
      final g = _letzteGruppen;
      final v = _letzteVorschlaege;

      final gruppenNeu = g != null && (gesehenG == null ? g > 0 : g > gesehenG);
      final vorschlaegeNeu =
          v != null && (gesehenV == null ? v > 0 : v > gesehenV);

      // Einmal an bleibt an, bis der Community-Tab geoeffnet wird. Sonst
      // koennte die zweite, langsamere Kachel den Punkt wieder ausknipsen,
      // den die erste zu Recht angeschaltet hat.
      if (gruppenNeu || vorschlaegeNeu) hatNeues.value = true;
    } catch (e) {
      debugPrint('[CommunityNeuigkeit] Stand nicht lesbar: $e');
      // Im Zweifel den bestehenden Zustand lassen — ein Fehler beim Lesen ist
      // kein Beleg dafuer, dass es nichts Neues gibt.
    }
  }

  /// Der Nutzer hat die Community geoeffnet: Punkt aus, Stand merken.
  Future<void> alsGesehenMarkieren() async {
    hatNeues.value = false;
    try {
      final p = await SharedPreferences.getInstance();
      // Nur schreiben, was wirklich bekannt ist. Wer sofort nach dem App-Start
      // auf Community tippt, waehrend die Kacheln noch laden, wuerde sonst 0
      // als „gesehen" festschreiben — und danach leuchtet der Punkt bei jedem
      // einzelnen Vorschlag wieder.
      final g = _letzteGruppen;
      final v = _letzteVorschlaege;
      if (g != null) await p.setInt(_kGesehenGruppen, g);
      if (v != null) await p.setInt(_kGesehenVorschlaege, v);
    } catch (e) {
      debugPrint('[CommunityNeuigkeit] Stand nicht speicherbar: $e');
    }
  }

  /// Nur fuer Tests.
  @visibleForTesting
  void zuruecksetzenFuerTest() {
    _letzteGruppen = null;
    _letzteVorschlaege = null;
    hatNeues.value = false;
  }
}
