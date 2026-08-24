import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// 2026-08-24 (Vorfall „Nutzer sitzt im Hinweis-Blatt fest", iPhone 15 Pro Max):
/// Wachhund fuer Aufrufe, die ins Betriebssystem gehen und daher haengen
/// koennen (Berechtigungs-Dialog, Einstellungen oeffnen, Standortdienst
/// abfragen). Ohne Zeitgrenze bleibt ein Blatt, das waehrend des Aufrufs alle
/// Knoepfe sperrt, fuer immer gesperrt — Neustart und Neuinstallation helfen
/// nicht, weil der Zustand jedes Mal neu entsteht.
///
/// DIE EIGENHEIT, die eine platte `Future.timeout` hier falsch macht:
/// Solange der System-Dialog offen ist, wartet der Aufruf voellig zu Recht —
/// der Nutzer liest, ueberlegt, tippt vielleicht erst nach einer Minute. Eine
/// feste Zeitgrenze wuerde genau dann zuschlagen und den Nutzer aus seiner
/// eigenen Entscheidung werfen.
///
/// Deshalb misst dieser Wachhund NICHT die Wanduhr, sondern nur die Zeit, in
/// der unsere App wirklich vorne ist (`AppLifecycleState.resumed`). Sowohl iOS
/// (System-Alert => `inactive`) als auch Android (Berechtigungs-Dialog =>
/// `inactive`/`paused`) nehmen uns waehrend des Dialogs den Vordergrund weg.
/// „Der Nutzer ueberlegt" haelt die Uhr also an, „unser Aufruf kommt nicht
/// zurueck, obwohl nichts zu sehen ist" laesst sie laufen.
class SystemAntwortWache {
  const SystemAntwortWache._();

  /// Wie fein die Vordergrund-Zeit gezaehlt wird.
  static const Duration _takt = Duration(milliseconds: 200);

  /// Wartet auf [aufgabe]. Kommt innerhalb von [grenze] Vordergrund-Zeit keine
  /// Antwort — oder wirft die Aufgabe —, liefert der Aufruf [beiZeitgrenze].
  ///
  /// Wichtig: die Aufgabe wird NICHT abgebrochen (das kann man bei einem
  /// Plattform-Kanal auch gar nicht). Wer eine spaete Antwort noch verwerten
  /// will, haengt sich zusaetzlich selbst an dasselbe Future.
  static Future<T> warte<T>(
    Future<T> aufgabe, {
    required Duration grenze,
    required T beiZeitgrenze,
  }) {
    final ergebnis = Completer<T>();
    final takt = grenze < _takt ? grenze : _takt;
    var verbraucht = Duration.zero;
    Timer? uhr;

    void beenden(T wert) {
      if (ergebnis.isCompleted) return;
      uhr?.cancel();
      ergebnis.complete(wert);
    }

    uhr = Timer.periodic(takt, (_) {
      // Uhr steht, solange wir nicht vorne sind: dann steht der Nutzer im
      // System-Dialog oder in den Einstellungen.
      if (!imVordergrund) return;
      verbraucht += takt;
      if (verbraucht >= grenze) beenden(beiZeitgrenze);
    });

    aufgabe.then(
      beenden,
      onError: (Object fehler, StackTrace _) {
        debugPrint('[SystemAntwortWache] Aufruf fehlgeschlagen: $fehler');
        beenden(beiZeitgrenze);
      },
    );

    return ergebnis.future;
  }

  /// Ist unsere App gerade vorne? Ein unbekannter Zustand (z. B. ganz frueh
  /// beim Start oder in einem reinen Dart-Test) gilt als „vorne" — sonst
  /// stuende die Uhr dort fuer immer still und die Zeitgrenze waere wirkungslos.
  static bool get imVordergrund {
    try {
      final zustand = WidgetsBinding.instance.lifecycleState;
      return zustand == null || zustand == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }
}

/// 2026-07-03 (vucko „Standort immer / direkt in Einstellungen"): Bündelt die
/// komplette Standort-Freigabe-Logik an EINER Stelle, damit alle Aufrufer
/// (Vorab-Sheet, Navigations-Start, Gruppen-Hintergrund) sich gleich verhalten.
///
/// Zielverhalten (vom Nutzer gewünscht): Wenn der Standort aktiviert werden
/// muss, kann man gleich „Immer erlauben" wählen — und wenn das Betriebssystem
/// „Immer" NICHT per Dialog vergibt, wird man DIREKT in die App-Einstellungen
/// weitergeleitet, wo „Immer/Always" mit einem Tap gesetzt werden kann.
///
/// Plattform-Realität (warum der Umweg über die Einstellungen nötig ist):
///  - iOS fragt IMMER zuerst „Beim Verwenden" ab. „Immer erlauben" kommt erst
///    bei einer zweiten Anfrage als Hochstufungs-Dialog — und wenn iOS ihn nicht
///    (mehr) zeigt, geht „Immer" nur noch über die Einstellungen.
///  - Android 11+ vergibt Hintergrund-Standort („Immer zulassen") grundsätzlich
///    NICHT per Laufzeit-Dialog, sondern NUR über die App-Einstellungen.
///
/// 2026-08-24 (Vorfall „Nutzer sitzt fest"): Kein Aufruf hier wirft noch, und
/// keiner kann mehr ewig haengen. Wer auf diese Antwort wartet und dabei seine
/// Oberflaeche sperrt, bekommt sie garantiert — spaetestens nach
/// [antwortGrenze] Vordergrund-Zeit als `unableToDetermine` („keine Antwort").
class LocationPermissionHelper {
  const LocationPermissionHelper._();

  /// Zeitgrenze fuer einen Aufruf, der einen System-Dialog zeigen KANN.
  /// Grosszuegig, weil sie nur laeuft, waehrend unsere App vorne ist: 20 s
  /// ohne Dialog und ohne Antwort sind kein Nachdenken mehr, sondern ein
  /// haengender Plattform-Kanal.
  static const Duration antwortGrenze = Duration(seconds: 20);

  /// Zeitgrenze fuer Abfragen OHNE Dialog (Standortdienst an?, Stand der
  /// Freigabe). Die antworten sofort oder gar nicht.
  static const Duration abfrageGrenze = Duration(seconds: 6);

  /// Zeitgrenze fuers Oeffnen der Einstellungen. Der Aufruf endet, sobald das
  /// System die Einstellungen startet — danach sind wir ohnehin im Hintergrund.
  static const Duration einstellungenGrenze = Duration(seconds: 8);

  /// Darf die App den Standort mindestens im Vordergrund nutzen?
  static bool isUsable(geo.LocationPermission permission) {
    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  /// Ist der Standortdienst des Geraets ueberhaupt an? Antwortet das System
  /// nicht, lautet die Antwort `false` — nie eine Ausnahme, nie ein Haenger.
  static Future<bool> isServiceEnabled({Duration? grenze}) {
    if (kIsWeb) return Future<bool>.value(true);
    return SystemAntwortWache.warte<bool>(
      geo.Geolocator.isLocationServiceEnabled(),
      grenze: grenze ?? abfrageGrenze,
      beiZeitgrenze: false,
    );
  }

  /// Fragt die Freigabe an und stuft, so weit das OS es per Dialog erlaubt, bis
  /// „Immer erlauben" hoch. Ist „Immer" per Dialog nicht (mehr) erreichbar und
  /// [openSettingsIfNeeded] gesetzt, wird DIREKT die App-Einstellungsseite
  /// geöffnet. Gibt die final ermittelte Freigabe zurück.
  ///
  /// Wirft nie und haengt nie: [grenze] begrenzt jeden einzelnen Aufruf ins
  /// System (nur Vordergrund-Zeit, siehe [SystemAntwortWache]). Der Parameter
  /// ist fuer Tests da; im Betrieb gilt [antwortGrenze].
  static Future<geo.LocationPermission> requestAlways({
    bool openSettingsIfNeeded = true,
    Duration? grenze,
  }) async {
    if (kIsWeb) return geo.LocationPermission.whileInUse;
    final dialogGrenze = grenze ?? antwortGrenze;
    final stillGrenze = grenze ?? abfrageGrenze;

    // Keine Antwort heisst NICHT „abgelehnt" — wir wissen es schlicht nicht.
    // `unableToDetermine` ist genau dafuer da; der Aufrufer kann dann ehrlich
    // „Das System hat nicht geantwortet" sagen statt etwas zu behaupten.
    var permission = await SystemAntwortWache.warte(
      geo.Geolocator.checkPermission(),
      grenze: stillGrenze,
      beiZeitgrenze: geo.LocationPermission.unableToDetermine,
    );
    if (permission == geo.LocationPermission.always) return permission;

    if (permission == geo.LocationPermission.denied) {
      // Erster System-Dialog (iOS: „Beim Verwenden"; Android: Standort-Dialog,
      // je nach Version ggf. schon mit „Immer zulassen").
      permission = await SystemAntwortWache.warte(
        geo.Geolocator.requestPermission(),
        grenze: dialogGrenze,
        beiZeitgrenze: geo.LocationPermission.unableToDetermine,
      );
    }

    // Dauerhaft blockiert → nur noch die Einstellungen helfen.
    if (permission == geo.LocationPermission.deniedForever) {
      if (openSettingsIfNeeded) {
        await openSettings(grenze: grenze);
      }
      return permission;
    }

    if (permission == geo.LocationPermission.whileInUse) {
      // Vordergrund ist da → auf „Immer" hochstufen. iOS zeigt dafür (falls
      // noch nicht abgelehnt) den Hochstufungs-Dialog; Android 11+ liefert
      // sofort denselben Stand zurück → in beiden Fällen danach direkt in die
      // Einstellungen, falls „Immer" noch fehlt.
      final upgraded = await SystemAntwortWache.warte(
        geo.Geolocator.requestPermission(),
        grenze: dialogGrenze,
        // Keine Antwort auf die Hochstufung heisst nicht, dass wir den
        // Vordergrund-Standort verloren haetten — den hatten wir schon.
        beiZeitgrenze: permission,
      );
      if (upgraded == geo.LocationPermission.always) return upgraded;
      if (openSettingsIfNeeded) {
        await openSettings(grenze: grenze);
      }
      return upgraded;
    }

    return permission;
  }

  /// Öffnet direkt die App-Standort-Einstellungen (iOS + Android).
  /// Antwortet das System nicht, kommt der Aufruf trotzdem zurueck (`false`) —
  /// der Aufrufer darf daran nicht haengenbleiben.
  static Future<bool> openSettings({Duration? grenze}) {
    if (kIsWeb) return Future<bool>.value(false);
    return SystemAntwortWache.warte<bool>(
      geo.Geolocator.openAppSettings(),
      grenze: grenze ?? einstellungenGrenze,
      beiZeitgrenze: false,
    );
  }
}
