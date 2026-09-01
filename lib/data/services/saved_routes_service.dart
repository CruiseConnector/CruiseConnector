import 'dart:async';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/offline_fahrten_warteschlange.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/domain/models/route_result.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';

/// CRUD für gespeicherte Routen in der Supabase `routes` Tabelle.
class SavedRoutesService {
  static SupabaseClient get _db => Supabase.instance.client;

  // Cache für wöchentliche Top-Route (1 Stunde gültig)

  static bool areEquivalentRoutes(SavedRoute first, SavedRoute second) {
    if (first.id == second.id) return true;

    final firstFingerprint = _normalizedRouteFingerprint(first);
    final secondFingerprint = _normalizedRouteFingerprint(second);
    if (firstFingerprint != null &&
        secondFingerprint != null &&
        firstFingerprint == secondFingerprint) {
      return true;
    }

    final firstSource = first.sourceRouteId?.trim();
    final secondSource = second.sourceRouteId?.trim();
    final firstIds = <String>{
      first.id,
      if (firstSource != null && firstSource.isNotEmpty) firstSource,
    };
    final secondIds = <String>{
      second.id,
      if (secondSource != null && secondSource.isNotEmpty) secondSource,
    };

    if (firstIds.intersection(secondIds).isNotEmpty) return true;
    return first.routeSignature == second.routeSignature;
  }

  static String? _normalizedRouteFingerprint(SavedRoute route) {
    final explicit = route.routeFingerprint?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final metaFingerprint =
        route.routeMeta['route_fingerprint']?.toString().trim() ??
        route.routeMeta['fingerprint']?.toString().trim();
    if (metaFingerprint != null && metaFingerprint.isNotEmpty) {
      return metaFingerprint;
    }
    return null;
  }

  static bool hasEquivalentSavedRoute(
    SavedRoute route,
    Iterable<SavedRoute> savedRoutes,
  ) {
    for (final savedRoute in savedRoutes) {
      if (areEquivalentRoutes(route, savedRoute)) return true;
    }
    return false;
  }

  /// Fragt GEZIELT nach, ob eine gleichwertige Strecke schon in der Sammlung
  /// liegt — ohne die ganze Bibliothek zu laden.
  ///
  /// 2026-08-31 (Serverlast): Die Startseite lud dafuer bei jedem Aufbau die
  /// vollstaendige Bibliothek: gemessen im Schnitt 1315 kB, im 90. Perzentil
  /// 4139 kB, im schlimmsten Fall 7060 kB — und las daraus genau zwei Dinge,
  /// eine Anzahl und diesen einen Wahrheitswert.
  ///
  /// WARUM DAS OHNE GEOMETRIE GEHT. [areEquivalentRoutes] vergleicht in vier
  /// Stufen: Kennung, Fingerprint, Quellverweis und zuletzt die aus der
  /// Geometrie gerechnete [SavedRoute.routeSignature]. Die letzte Stufe sieht
  /// so aus, als brauche man die Geometrie aller gespeicherten Strecken — man
  /// braucht sie aber nicht: [_buildExistingRouteInsert] legt beim Speichern
  /// in `route_fingerprint` ENTWEDER den echten Fingerprint ODER genau diese
  /// Signatur ab. Der Wert steht also schon in der Datenbank, und er stammt
  /// aus demselben Dart-Code, der ihn hier fuer die zu pruefende Strecke
  /// bildet. Beide Seiten des Vergleichs kommen damit aus derselben
  /// Berechnung.
  ///
  /// Warum das wichtig ist: Ein Nachbau der Signatur in SQL waere NICHT
  /// gleichwertig. Postgres rundet die Dezimalzahl, Dart den Binaerwert; von
  /// vierzehn geprueften Faellen liefen zwei auseinander (9.00005 wird zu
  /// 9.0001 statt 9.0000). Ein einziger abweichender Stuetzpunkt genuegt,
  /// damit zwei identische Strecken einander nicht mehr erkennen.
  ///
  /// GRENZE, bewusst in Kauf genommen: 162 Zeilen tragen ueberhaupt keinen
  /// Fingerprint. Alle 162 sind aelter als 90 Tage; jede Strecke der letzten
  /// 90 Tage hat einen. Fuer so eine Altzeile kann diese Abfrage „nein" sagen,
  /// obwohl die Strecke liegt. Das ist folgenlos: Der Aufrufer zeigt dann
  /// einen leeren Haken, und tippt der Nutzer auf Speichern, faellt die
  /// Entscheidung erneut in [saveExistingRoute] — und DIE prueft weiterhin
  /// vollstaendig gegen die ganze Bibliothek. Eine doppelte Zeile kann also
  /// nicht entstehen.
  static Future<bool> liegtGleichwertigeStreckeInDerSammlung(
    SavedRoute route,
  ) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;

    // Stufe 2 und 4: Fingerprint oder Signatur. Beides steht bei gespeicherten
    // Zeilen in derselben Spalte, deshalb genuegt EINE Abfrage fuer beide.
    // Eine Signatur OHNE Koordinatenteil ist mehrdeutig: Typ, Stil und
    // gerundete Distanz teilen sich beliebig viele verschiedene Strecken. Als
    // Suchschluessel wuerde sie eine fremde Strecke als „schon gespeichert"
    // melden — und ueber den Loesch-Zweig des Umschalters echten Schaden
    // anrichten. Heute traegt keine Zeile so eine Signatur; die Tuer bleibt
    // trotzdem zu.
    final signatur = route.routeSignature;
    final schluessel = <String>{
      ?route.routeFingerprint?.trim(),
      if (route.hatVerwertbareGeometrie) signatur,
    }..removeWhere((wert) => wert.isEmpty);

    try {
      if (schluessel.isNotEmpty) {
        final treffer = await _db
            .from('routes')
            .select('id')
            .eq('user_id', userId)
            .inFilter('route_fingerprint', schluessel.toList(growable: false))
            .limit(1)
            .timeout(const Duration(seconds: 8));
        if ((treffer as List).isNotEmpty) return true;
      }

      // Stufe 1 und 3: eigene Kennung oder Quellverweis. Nur fragen, wenn die
      // Kennung ueberhaupt eine Kennung sein KANN — eine oertlich erzeugte
      // Strecke traegt etwas wie „local_17…", und ein uuid-Vergleich damit
      // wuerde serverseitig mit einem Typfehler abbrechen statt „nein" zu
      // sagen.
      final kennung = route.sourceRouteId?.trim().isNotEmpty == true
          ? route.sourceRouteId!.trim()
          : route.id.trim();
      if (_siehtWieKennungAus(kennung)) {
        final treffer = await _db
            .from('routes')
            .select('id')
            .eq('user_id', userId)
            .or('id.eq.$kennung,source_route_id.eq.$kennung')
            .limit(1)
            .timeout(const Duration(seconds: 8));
        if ((treffer as List).isNotEmpty) return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SavedRoutes] Gleichwertigkeit nicht pruefbar: $e');
      // „Weiss nicht" ist hier ein „nein": ein leerer Haken laesst den Nutzer
      // tippen, und dann entscheidet die vollstaendige Pruefung.
      return false;
    }
  }

  static final RegExp _kennungsMuster = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _siehtWieKennungAus(String wert) =>
      _kennungsMuster.hasMatch(wert);

  static List<SavedRoute> dedupeEquivalentRoutes(Iterable<SavedRoute> routes) {
    final unique = <SavedRoute>[];
    for (final route in routes) {
      if (!hasEquivalentSavedRoute(route, unique)) {
        unique.add(route);
      }
    }
    return unique;
  }

  @visibleForTesting
  static List<SavedRoute> savedRouteCopiesFromUserRoutes(
    Iterable<SavedRoute> routes,
  ) {
    return dedupeEquivalentRoutes(routes);
  }

  // ─── Speichern ────────────────────────────────────────────────────────────

  /// Fügt die Zeile ein und liefert die vergebene Routen-ID zurück.
  ///
  /// 2026-08-03 (vucko Route-Aufzeichnen): Ausgelagert, weil [saveRoute] die
  /// Zeile in mehreren Spalten-Fallbacks einfügt und jeder dieser Wege dieselbe
  /// ID liefern muss — die braucht das Veröffentlichen direkt nach dem Speichern.
  /// Schlägt das `select('id')` fehl (z. B. wegen RLS auf der Rückgabe), gilt
  /// das Speichern trotzdem als erfolgreich; nur die ID fehlt dann.
  static Future<String?> _insertRouteRow(Map<String, dynamic> row) async {
    final inserted = await _db
        .from('routes')
        .insert(row)
        .select('id')
        .maybeSingle();
    _meldeSpeichernAufgabe();
    return inserted?['id']?.toString();
  }

  /// Starter-Aufgabe „Eine Route speichern" — NACH dem erfolgreichen INSERT.
  ///
  /// 2026-08-24 (Aufgabe 4, vucko: „auch wirklich absolvieren"): Die Meldung
  /// stand bis heute als ERSTE Zeile in [saveRoute] und [saveExistingRoute] —
  /// noch vor `if (userId == null) return null;` und noch vor jedem
  /// Datenbankzugriff. Ein Speichern, das an fehlender Anmeldung, am Netz oder
  /// an einer Rechtepruefung scheiterte, hakte die Aufgabe trotzdem ab. Von
  /// den zwoelf Starter-Aufgaben war das die einzige mit diesem Fehler.
  ///
  /// Jetzt haengt sie an der Stelle, an der die Zeile wirklich steht. Alle
  /// Spalten-Rueckfaelle in [saveRoute] laufen durch [_insertRouteRow], sind
  /// also mit abgedeckt.
  static void _meldeSpeichernAufgabe() {
    unawaited(StarterAufgabenService.instance.markiere('speichern'));
  }

  /// Speichert eine Route für den eingeloggten User.
  /// Tut nichts, wenn kein User eingeloggt ist.
  ///
  /// Liefert die ID der gespeicherten Route (oder `null`, wenn nicht
  /// eingeloggt bzw. die ID nicht zurückkam).
  static Future<String?> saveRoute({
    required RouteResult result,
    required String style,
    required bool isRoundTrip,
    String? customName,
    int? rating,
    double? drivenKm,
    double? plannedDistanceKm,
    int? xpDistance,
    int? xpCurveBonus,
    int? xpStyleBonus,
    int? xpBase,
    double? xpMultiplier,
    int? xpStreakDays,
    int? xpAwarded,
    bool completedAtEnd = false,
    String? groupId,
    String? photoUrl,
    // 2026-08-28 (Fehler 8, Community-Routenkarte): Hoechsttempo der Fahrt
    // in km/h. Kommt kein Wert mit, holt sich saveRoute den der soeben
    // aufgezeichneten Fahrt aus [GamificationService], denn der Abschluss in
    // cruise_mode_page ruft erst recordDriveSession und direkt danach diese
    // Methode. Bleibt beides leer, bleibt routes.top_speed_kmh null und die
    // Anzeige laesst die Tempo-Kachel weg.
    double? topSpeedKmh,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final hoechsttempoKmh =
        topSpeedKmh ?? GamificationService.uebernimmHoechsttempoLetzterFahrt();

    final routeType = isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT';
    final name = (customName?.trim().isNotEmpty == true)
        ? customName!.trim()
        : '$style ${isRoundTrip ? 'Rundkurs' : 'Route'}';

    final actualDistanceKm =
        result.distanceKm ??
        (result.distanceMeters != null ? result.distanceMeters! / 1000 : 0.0);
    final effectiveDrivenKm = drivenKm ?? actualDistanceKm;
    final effectivePlannedKm = plannedDistanceKm ?? actualDistanceKm;

    final row = <String, dynamic>{
      'user_id': userId,
      'name': name,
      'style': style,
      'route_type': routeType,
      'distance_target': effectivePlannedKm.round(),
      'distance_actual': actualDistanceKm,
      'duration_seconds': result.durationSeconds?.round(),
      'geometry': result.geometry,
      if (photoUrl != null && photoUrl.trim().isNotEmpty)
        'photo_url': photoUrl.trim(),
      'driven_km': effectiveDrivenKm,
      'route_source':
          result.edgeMeta['route_source']?.toString() ??
          result.edgeMeta['source']?.toString(),
      'route_fingerprint':
          result.edgeMeta['route_fingerprint']?.toString() ??
          RouteQualityValidator.buildRouteFingerprint(
            _sampleCoordinatesForFingerprint(result.coordinates),
            distanceKm: result.distanceKm,
            precision: 4,
          ),
      'quality_tier': result.edgeMeta['quality_tier']?.toString(),
      'route_meta': result.edgeMeta,
      'completed_at_end': completedAtEnd,
      if (hoechsttempoKmh != null && hoechsttempoKmh > 0)
        'top_speed_kmh': double.parse(hoechsttempoKmh.toStringAsFixed(1)),
      if (groupId != null && groupId.trim().isNotEmpty)
        'group_id': groupId.trim(),
      if (xpDistance != null) 'xp_distance': xpDistance,
      if (xpCurveBonus != null) 'xp_curve_bonus': xpCurveBonus,
      if (xpStyleBonus != null) 'xp_style_bonus': xpStyleBonus,
      if (xpBase != null) 'xp_base': xpBase,
      if (xpMultiplier != null) 'xp_multiplier': xpMultiplier,
      if (xpStreakDays != null) 'xp_streak_days': xpStreakDays,
      if (xpAwarded != null) 'xp_awarded': xpAwarded,
    };
    if (rating != null && rating > 0) row['rating'] = rating;
    // 2026-08-26 (Vucko: „danach wieder online sollte es trotzdem alles
    // aufgezeichnet haben"): id vom Client, damit dieselbe Strecke nach einem
    // Funkloch gefahrlos ein zweites Mal geschickt werden kann — steht sie
    // schon, lehnt Postgres mit 23505 ab statt sie zu verdoppeln.
    row['id'] = OfflineFahrtenWarteschlange.neueZeilenId();

    try {
      return await _insertRouteRow(row);
    } on PostgrestException catch (e) {
      // Fallback: Falls 'name' Spalte noch nicht existiert, ohne speichern
      if (e.code == 'PGRST204' && e.message.contains('name')) {
        debugPrint('[SavedRoutes] name-Spalte fehlt, speichere ohne name');
        row.remove('name');
        return await _insertRouteRow(row);
      } else if (e.code == 'PGRST204' &&
          e.message.contains('completed_at_end')) {
        debugPrint(
          '[SavedRoutes] completed_at_end-Spalte fehlt, speichere ohne Completion-Flag',
        );
        row.remove('completed_at_end');
        return await _insertRouteRow(row);
      } else if (e.code == 'PGRST204' && e.message.contains('group_id')) {
        debugPrint(
          '[SavedRoutes] group_id-Spalte fehlt, speichere ohne Gruppenbezug',
        );
        row.remove('group_id');
        return await _insertRouteRow(row);
      } else if (e.code == 'PGRST204') {
        debugPrint(
          '[SavedRoutes] Route-Meta-Spalten fehlen, speichere ohne Meta: ${e.message}',
        );
        row
          ..remove('route_source')
          ..remove('route_fingerprint')
          ..remove('quality_tier')
          ..remove('route_meta')
          ..remove('completed_at_end')
          ..remove('group_id')
          ..remove('top_speed_kmh')
          ..remove('xp_distance')
          ..remove('xp_curve_bonus')
          ..remove('xp_style_bonus')
          ..remove('xp_base')
          ..remove('xp_multiplier')
          ..remove('xp_streak_days')
          ..remove('xp_awarded');
        return await _insertRouteRow(row);
      } else {
        rethrow;
      }
    } catch (e) {
      // 2026-08-26 (Vucko: „danach wieder online sollte es trotzdem alles
      // aufgezeichnet haben"): Kein Netz. Bis hierhin war die aufgezeichnete
      // Strecke damit weg — die Fahrt landete zwar (seit derselben Aenderung)
      // in der Warteschlange, „Meine Strecken" blieb aber leer. Jetzt wartet
      // die Strecke genauso auf die naechste Verbindung.
      //
      // Ein PostgrestException mit echtem Fehlercode kommt hier NICHT an (die
      // Klausel darueber faengt sie) — das ist Absicht: Was der Server
      // fachlich ablehnt, wuerde er beim Nachtragen wieder ablehnen.
      await OfflineFahrtenWarteschlange.stelleAn(
        row,
        tabelle: OfflineFahrtenWarteschlange.tabelleStrecke,
      );
      rethrow;
    }
  }

  static List<List<double>> _sampleCoordinatesForFingerprint(
    List<List<double>> coordinates,
  ) {
    if (coordinates.length <= 32) {
      return coordinates.map((point) => [point[0], point[1]]).toList();
    }
    final step = (coordinates.length / 32).ceil();
    final sampled = <List<double>>[];
    for (var i = 0; i < coordinates.length; i += step) {
      sampled.add([coordinates[i][0], coordinates[i][1]]);
    }
    sampled.add([coordinates.last[0], coordinates.last[1]]);
    return sampled;
  }

  /// Speichert eine bestehende Route (z.B. empfohlene Route) für den aktuellen User.
  static Future<void> saveExistingRoute(SavedRoute route) async {
    // 2026-08-16 (T5): Auch die Home-Empfehlung, Feed-Anhaenge usw. laufen
    // hier — nicht nur der Abschluss einer Fahrt. Die Starter-Aufgabe wird
    // seit dem 24.08. erst nach dem erfolgreichen Speichern gemeldet, siehe
    // [_meldeSpeichernAufgabe].
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final savedRoutes = await getSavedRouteLibrary();
    if (hasEquivalentSavedRoute(route, savedRoutes)) {
      debugPrint(
        '[SavedRoutes] Route bereits gespeichert: id=${route.id}, '
        'fingerprint=${route.routeFingerprint ?? route.routeSignature}',
      );
      // Die Strecke LIEGT in der Sammlung — die Tat ist getan, nur eben
      // frueher. Der Haken gehoert hierher.
      _meldeSpeichernAufgabe();
      return;
    }

    final row = _buildExistingRouteInsert(userId: userId, route: route);

    try {
      await _db.from('routes').insert(row);
      _meldeSpeichernAufgabe();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        debugPrint(
          '[SavedRoutes] Route-Meta-Spalten fehlen, speichere Empfehlung ohne Meta: ${e.message}',
        );
        row
          ..remove('source_route_id')
          ..remove('route_source')
          ..remove('route_fingerprint')
          ..remove('quality_tier')
          ..remove('route_meta')
          // 2026-09-01: Auch die vier neuen Felder. Eine App, die gegen eine
          // aeltere Datenbank laeuft, soll die Strecke lieber ohne Tempo
          // speichern als gar nicht.
          ..remove('top_speed_kmh')
          ..remove('driven_km')
          ..remove('photo_url')
          ..remove('completed_at_end');
        await _db.from('routes').insert(row);
        _meldeSpeichernAufgabe();
      } else if (e.code == '23505') {
        // Unique constraint: diese Route ist für den User bereits gespeichert.
        // Auch das heisst: sie liegt in der Sammlung.
        debugPrint(
          '[SavedRoutes] Duplicate Save durch DB verhindert: id=${route.id}',
        );
        _meldeSpeichernAufgabe();
        return;
      } else {
        rethrow;
      }
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildExistingRouteInsertForTest({
    required String userId,
    required SavedRoute route,
  }) {
    return _buildExistingRouteInsert(userId: userId, route: route);
  }

  static Map<String, dynamic> _buildExistingRouteInsert({
    required String userId,
    required SavedRoute route,
  }) {
    final rawSourceRouteId = (route.sourceRouteId?.trim().isNotEmpty == true)
        ? route.sourceRouteId!.trim()
        : route.id;
    final sourceRouteId =
        _shouldPersistSourceRouteId(
          route: route,
          rawSourceRouteId: rawSourceRouteId,
        )
        ? rawSourceRouteId
        : null;
    final routeFingerprint = (route.routeFingerprint?.trim().isNotEmpty == true)
        ? route.routeFingerprint!.trim()
        : route.routeSignature;
    // Gehoert die Strecke dem Speichernden selbst? Nur dann duerfen die
    // Fahrdaten mitwandern. Eine fremde Strecke traegt die Kennung ihres
    // Besitzers oder gar keine.
    final istEigeneFahrt =
        route.userId != null && route.userId!.isNotEmpty && route.userId == userId;

    final routeMeta = Map<String, dynamic>.from(route.routeMeta)
      ..['saved_route_source'] = 'existing_route_copy'
      ..['source_route_id'] = rawSourceRouteId
      ..['source_route_fingerprint'] = routeFingerprint;

    return <String, dynamic>{
      'user_id': userId,
      'name': route.name ?? '${route.styleEmoji} ${route.style}',
      'style': route.style,
      'route_type': route.routeType ?? 'ROUND_TRIP',
      'distance_target': (route.distanceTargetKm ?? route.distanceKm).round(),
      'distance_actual': route.distanceKm,
      'duration_seconds': route.durationSeconds?.round(),
      'geometry': route.geometry,
      if (sourceRouteId != null) 'source_route_id': sourceRouteId,
      'route_source': route.routeSource ?? 'saved_route_copy',
      'route_fingerprint': routeFingerprint,
      'quality_tier': route.qualityTier,
      'route_meta': routeMeta,
      if (route.rating != null && route.rating! > 0) 'rating': route.rating,
      // 2026-09-01 (Vucko: „bei gespeicherten routen und wenn man eine route
      // teilt in den communitys sollen auch noch top speed und
      // durchschnittsgeschwindigkeit sein"):
      //
      // Diese vier Felder fielen beim Speichern still unter den Tisch. Deshalb
      // war `routes.top_speed_kmh` in der Produktion bei 1 von 299 Zeilen
      // gefuellt, und die Tempo-Kachel erschien nie — sie blendet sich bei
      // null bewusst aus. Der Durchschnitt braucht `driven_km`, sonst kann er
      // eine gefahrene Strecke nicht von einem Vorschlag unterscheiden.
      //
      // NUR bei der EIGENEN Fahrt. Kopiert jemand eine fremde Strecke aus der
      // Community, sind Hoechsttempo und gefahrene Kilometer die Zahlen des
      // ANDEREN; sie auf die eigene Kopie zu schreiben waere schlicht falsch.
      // Der bestehende Test „speichert Community-Kopie ohne Drive-XP-Felder"
      // haelt genau das fest und hat diesen Fehler beim ersten Anlauf sofort
      // aufgedeckt.
      if (istEigeneFahrt) ...<String, dynamic>{
        if (route.topSpeedKmh != null && route.topSpeedKmh! > 0)
          'top_speed_kmh': route.topSpeedKmh,
        if (route.drivenKm != null && route.drivenKm! > 0)
          'driven_km': route.drivenKm,
        if (route.photoUrl != null && route.photoUrl!.trim().isNotEmpty)
          'photo_url': route.photoUrl!.trim(),
        if (route.completedAtEnd) 'completed_at_end': true,
      },
    };
  }

  static bool _shouldPersistSourceRouteId({
    required SavedRoute route,
    required String rawSourceRouteId,
  }) {
    if (!_isUuid(rawSourceRouteId)) return false;

    final routeSource = route.routeSource?.trim().toLowerCase();
    // Eine gefahrene Spur ist keine Route. routes.source_route_id zeigt per
    // Fremdschluessel auf routes(id) — eine Fahrt-Kennung dort haette jeden
    // Insert mit 23503 abgewiesen. Zweiter Riegel neben
    // UserDriveSession.alsSpeicherbareStrecke, die gar keine mehr setzt.
    if (routeSource == 'driven_track' || routeSource == 'recorded_track') {
      return false;
    }
    if (routeSource == 'route_pool' ||
        routeSource == 'route_pool_candidate' ||
        routeSource == 'candidate_reserve') {
      return false;
    }

    final externalSourceIds = <String>{
      route.routeMeta['pool_route_id']?.toString().trim() ?? '',
      route.routeMeta['route_pool_id']?.toString().trim() ?? '',
      route.routeMeta['candidate_route_id']?.toString().trim() ?? '',
      route.routeMeta['route_pool_candidate_id']?.toString().trim() ?? '',
    }..removeWhere((value) => value.isEmpty);

    return !externalSourceIds.contains(rawSourceRouteId);
  }

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  static bool _isMissingColumnError(Object error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return error.code == '42703' ||
        error.code == 'PGRST204' ||
        message.contains('column') && message.contains('does not exist') ||
        message.contains('could not find') && message.contains('column');
  }

  /// Prüft ob eine Route (anhand ID) dem aktuellen User gehört / gespeichert ist.
  static Future<bool> isRouteSavedByUser(String routeId) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final data = await _db
          .from('routes')
          .select('id')
          .eq('id', routeId)
          .eq('user_id', userId)
          .maybeSingle();
      return data != null;
    } catch (e) {
      debugPrint('[SavedRoutes] isRouteSavedByUser Fehler: $e');
      return false;
    }
  }

  // ─── Laden ────────────────────────────────────────────────────────────────

  /// Gibt alle gespeicherten Routen des eingeloggten Users zurück,
  /// neueste zuerst. Gibt leere Liste bei Fehler zurück.
  static Future<List<SavedRoute>> getUserRoutes() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final data = await _db
          .from('routes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (data as List)
          .map((row) => SavedRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SavedRoutes] getUserRoutes Fehler: $e');
      return const [];
    }
  }

  // ─── Gespeicherte Bibliothek ─────────────────────────────────────────────

  /// Gibt eigene gespeicherte Routen-Kopien zurück.
  /// Gefahrene Routen bleiben sichtbar; XP/Analytics kommen aus Drive-Sessions.
  static Future<List<SavedRoute>> getSavedRouteCopies() async {
    final routes = await getUserRoutes();
    return savedRouteCopiesFromUserRoutes(routes);
  }

  static Future<List<SavedRoute>> getBookmarkedRoutes() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final rows = await _db
          .from('route_bookmarks')
          .select('route_id, created_at, routes(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return dedupeEquivalentRoutes(
        (rows as List)
            .map((row) => row as Map<String, dynamic>)
            .map((row) => row['routes'])
            .whereType<Map>()
            .map(
              (route) => SavedRoute.fromJson(Map<String, dynamic>.from(route)),
            ),
      );
    } catch (e) {
      debugPrint('[SavedRoutes] getBookmarkedRoutes Fehler: $e');
      return const [];
    }
  }

  static Future<List<SavedRoute>> getSavedRouteLibrary() async {
    final results = await Future.wait([
      getSavedRouteCopies(),
      getBookmarkedRoutes(),
    ]);
    return dedupeEquivalentRoutes([...results[0], ...results[1]]);
  }

  /// Liegt diese Strecke in der Sammlung des angemeldeten Nutzers?
  ///
  /// 2026-08-31 (Serverlast): Diese Frage lud bis heute die GANZE Bibliothek,
  /// und der Merken-Knopf im Feed stellt sie pro Streckenkarte einmal. Bei
  /// einem Feed mit zehn geteilten Strecken waren das zehn volle Ladungen —
  /// gemessen im Schnitt 1315 kB je Ladung.
  ///
  /// Jetzt fragt sie gezielt. Zur Genauigkeit und zu der bewusst in Kauf
  /// genommenen Grenze bei Altzeilen ohne Fingerprint siehe
  /// [liegtGleichwertigeStreckeInDerSammlung].
  ///
  /// Wichtig: Diese Antwort ist fuer die ANZEIGE des Merken-Symbols gedacht.
  /// Gegen eine doppelte Zeile schuetzt weiterhin [saveExistingRoute] mit der
  /// vollstaendigen Pruefung.
  ///
  /// Was sie NICHT entscheiden darf, ist die LOESCH-Richtung. Hier stand
  /// zuerst, beide Aufrufer benutzten sie nur zur Anzeige — das stimmte nicht:
  /// RouteBookmarkProvider.toggle leitete daraus ab, ob getippt gespeichert
  /// oder geloescht wird, und ein Falsch-Positiv haette aus einem
  /// Speichern-Tipp einen Loeschlauf gemacht (Merkzeilen und
  /// Routen-Veroeffentlichungen weg, gespeichert nichts). Deshalb prueft der
  /// Loesch-Zweig dort jetzt zusaetzlich vollstaendig ueber
  /// [istSicherInDerSammlung]. Eine Ladung bei einem Tipp ist tragbar; zehn
  /// Ladungen beim Aufbau einer Liste waren es nicht.
  static Future<bool> isRouteSaved(SavedRoute route) async {
    return liegtGleichwertigeStreckeInDerSammlung(route);
  }

  /// Die VOLLSTAENDIGE Gegenpruefung ueber die ganze Bibliothek.
  ///
  /// Nur fuer Wege, an denen etwas geloescht wird. Teuer, aber sicher.
  static Future<bool> istSicherInDerSammlung(SavedRoute route) async {
    try {
      final bibliothek = await getSavedRouteLibrary();
      return hasEquivalentSavedRoute(route, bibliothek);
    } catch (e) {
      debugPrint('[SavedRoutes] Vollpruefung fehlgeschlagen: $e');
      // Im Zweifel NICHT loeschen.
      return false;
    }
  }

  // ─── Einzelne Route laden ─────────────────────────────────────────────────

  /// Lädt eine einzelne Route anhand ihrer ID.
  static Future<SavedRoute?> getRouteById(String id) async {
    try {
      final data = await _db.from('routes').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      return SavedRoute.fromJson(data);
    } catch (e) {
      debugPrint('[SavedRoutes] getRouteById Fehler: $e');
      return null;
    }
  }

  // ─── Löschen ─────────────────────────────────────────────────────────────

  /// Löscht eine Route anhand ihrer ID.
  /// Benennt eine eigene gespeicherte Route um.
  ///
  /// Posts und Bookmarks referenzieren dieselbe `routes.id`, deshalb ist der
  /// neue Name danach überall sichtbar, wo diese Route geladen wird.
  static Future<void> renameRoute(String id, String name) async {
    final userId = _db.auth.currentUser?.id;
    final cleaned = name.trim();
    if (userId == null || cleaned.isEmpty) return;
    if (cleaned.length > AppInputLimits.routeNameMaxLength) {
      throw ArgumentError('Routenname ist zu lang.');
    }

    try {
      await _db
          .from('routes')
          .update({'name': cleaned})
          .eq('id', id)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[SavedRoutes] renameRoute Fehler: $e');
      rethrow;
    }
  }

  /// Setzt/entfernt (null) das Foto einer eigenen gespeicherten Route.
  /// Returnt true bei Erfolg (mind. eine Zeile geändert).
  static Future<bool> updateRoutePhoto(String id, String? photoUrl) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final rows = await _db
          .from('routes')
          .update({'photo_url': photoUrl})
          .eq('id', id)
          .eq('user_id', userId)
          .select('id');
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[SavedRoutes] updateRoutePhoto Fehler: $e');
      return false;
    }
  }

  static Future<void> unsaveRouteEverywhere(SavedRoute route) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    final sourceRouteId = route.sourceRouteId?.trim();
    final routeIds = <String>{
      route.id,
      if (sourceRouteId != null && sourceRouteId.isNotEmpty) sourceRouteId,
    };

    try {
      await _db
          .from('route_bookmarks')
          .delete()
          .eq('user_id', userId)
          .inFilter('route_id', routeIds.toList());
    } catch (e) {
      debugPrint('[SavedRoutes] Bookmark entfernen fehlgeschlagen: $e');
    }

    try {
      final ownRoutes = await getUserRoutes();
      final savedCopies = ownRoutes
          .where((candidate) => areEquivalentRoutes(route, candidate))
          .map((candidate) => candidate.id)
          .toSet();
      routeIds.addAll(savedCopies);

      await _deleteRoutePublicationsForUser(userId: userId, routeIds: routeIds);

      if (savedCopies.isNotEmpty) {
        await _db
            .from('routes')
            .delete()
            .eq('user_id', userId)
            .inFilter('id', savedCopies.toList());
      }
    } catch (e) {
      debugPrint(
        '[SavedRoutes] Gespeicherte Kopie entfernen fehlgeschlagen: $e',
      );
      rethrow;
    }
  }

  static Future<void> deleteRoute(String id) async {
    final userId = _db.auth.currentUser?.id;
    final routeId = id.trim();
    if (routeId.isEmpty) return;

    final routeIds = <String>{routeId};
    if (userId != null) {
      try {
        final row = await _db
            .from('routes')
            .select('source_route_id')
            .eq('id', routeId)
            .eq('user_id', userId)
            .maybeSingle();
        final sourceRouteId = row?['source_route_id']?.toString().trim();
        if (sourceRouteId != null && sourceRouteId.isNotEmpty) {
          routeIds.add(sourceRouteId);
        }
      } on PostgrestException catch (e) {
        if (!_isMissingColumnError(e)) rethrow;
      }

      await _deleteRoutePublicationsForUser(userId: userId, routeIds: routeIds);
    }

    try {
      final query = _db.from('routes').delete().eq('id', routeId);
      if (userId != null) {
        await query.eq('user_id', userId);
      } else {
        await query;
      }
    } catch (e) {
      debugPrint('[SavedRoutes] deleteRoute Fehler: $e');
      rethrow; // UI soll informiert werden, dass Löschen fehlschlug
    }
  }

  static Future<void> _deleteRoutePublicationsForUser({
    required String userId,
    required Iterable<String> routeIds,
  }) async {
    final ids = routeIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      await _db
          .from('posts')
          .delete()
          .eq('user_id', userId)
          .inFilter('shared_route_id', ids);
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e)) {
        debugPrint('[SavedRoutes] shared_route_id fehlt, Posts übersprungen.');
      } else {
        rethrow;
      }
    }

    final deletedAt = DateTime.now().toUtc().toIso8601String();
    for (final routeId in ids) {
      await _softDeleteCommunityRouteMessages(
        userId: userId,
        routeJsonKey: 'route_id',
        routeId: routeId,
        deletedAt: deletedAt,
      );
      await _softDeleteCommunityRouteMessages(
        userId: userId,
        routeJsonKey: 'source_route_id',
        routeId: routeId,
        deletedAt: deletedAt,
      );
    }
  }

  static Future<void> _softDeleteCommunityRouteMessages({
    required String userId,
    required String routeJsonKey,
    required String routeId,
    required String deletedAt,
  }) async {
    try {
      await _db
          .from('community_messages')
          .update({'deleted_at': deletedAt, 'updated_at': deletedAt})
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .filter('route_attachment->>$routeJsonKey', 'eq', routeId);
    } on PostgrestException catch (e) {
      if (_isMissingColumnError(e)) {
        debugPrint(
          '[SavedRoutes] route_attachment fehlt, Chat-Routen übersprungen.',
        );
      } else {
        rethrow;
      }
    }
  }
}
