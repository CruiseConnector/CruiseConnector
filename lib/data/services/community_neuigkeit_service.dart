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

  /// Meldet, was die Home-Kacheln gerade geladen haben.
  Future<void> melde({
    required int gruppen,
    required int vorschlaege,
  }) async {
    _letzteGruppen = gruppen;
    _letzteVorschlaege = vorschlaege;
    try {
      final p = await SharedPreferences.getInstance();
      final gesehenG = p.getInt(_kGesehenGruppen);
      final gesehenV = p.getInt(_kGesehenVorschlaege);
      // Noch nie geoeffnet: alles ist neu — genau dann soll der Punkt locken.
      final neu = gesehenG == null || gesehenV == null
          ? gruppen > 0 || vorschlaege > 0
          : gruppen > gesehenG || vorschlaege > gesehenV;
      hatNeues.value = neu;
    } catch (e) {
      debugPrint('[CommunityNeuigkeit] Stand nicht lesbar: $e');
      // Im Zweifel NICHT leuchten — ein Punkt ohne Grund ist schlimmer als
      // ein fehlender.
      hatNeues.value = false;
    }
  }

  /// Der Nutzer hat die Community geoeffnet: Punkt aus, Stand merken.
  Future<void> alsGesehenMarkieren() async {
    hatNeues.value = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kGesehenGruppen, _letzteGruppen ?? 0);
      await p.setInt(_kGesehenVorschlaege, _letzteVorschlaege ?? 0);
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
