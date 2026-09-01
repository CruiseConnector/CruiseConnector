// 2026-09-01 — Vucko:
//   "was ich noch moechte ist, dass man routen die man gefahren ist im
//    nachhinein noch speichern kann oder ganz wichtig fotos hinzufuegen kann
//    und bei gespeicherten routen und wenn man eine route teilt in den
//    communitys sollen auch noch top speed und durchschnittsgeschwindigkeit
//    sein"
//
// WAS VORHER FEHLTE, in drei Teilen:
//
// (a) Es gab genau EIN Zeitfenster, um aus einer gefahrenen Fahrt eine
//     gespeicherte Strecke zu machen: das Abschluss-Blatt direkt nach der
//     Fahrt. Wer dort "Verwerfen" tippte oder wessen App vorher starb, hatte
//     keinen zweiten Weg.
//
// (b) Fotos nachtraeglich hinzuzufuegen ging auf der Fahrten-Detailseite
//     laengst. Erreichbar war sie aber nur ueber "Letzte Fahrten", und die
//     zeigt bewusst nur fuenf Eintraege. Alles Aeltere war nicht aufrufbar.
//     Schlimmer: pruneRecentRidePhotos loeschte Fotos jenseits der fuenf
//     neuesten samt Datei. Ein nachgereichtes Foto haette sich also selbst
//     zerstoert. Gemessen an der Produktionsdatenbank am 01.09.: DREI Fahrten
//     mit Foto, ein Nutzer, 4,9 MB Gesamtspeicher. Die Grenze raeumte ein
//     Problem weg, das es nicht gab.
//
// (c) Das Hoechsttempo wurde beim Speichern gar nicht mitgeschrieben; in der
//     Produktion war routes.top_speed_kmh bei 1 von 299 Zeilen gefuellt. Die
//     Kachel blendet sich bei null aus, also erschien sie nie. Eine
//     Durchschnittsgeschwindigkeit gab es nirgends.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';

UserDriveSession fahrt({
  List<List<double>>? spur,
  double km = 42.5,
  int sekunden = 3600,
  double? topTempo = 118,
  String? foto,
}) {
  return UserDriveSession(
    id: '11111111-2222-3333-4444-555555555555',
    userId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    distanceKm: km,
    durationSeconds: sekunden,
    xpAwarded: 120,
    completedAtEnd: true,
    createdAt: DateTime(2026, 8, 15, 17, 30),
    trackGeometry: spur ?? const [
      [9.74, 47.41],
      [9.75, 47.42],
      [9.76, 47.43],
    ],
    topSpeedKmh: topTempo,
    photoUrl: foto,
    routeStyle: 'Kurvenjagd',
    routeType: 'ROUND_TRIP',
  );
}

void main() {
  group('Eine gefahrene Fahrt laesst sich als Strecke speichern', () {
    test('die Umwandlung liefert eine vollstaendige Strecke', () {
      final s = fahrt().alsSpeicherbareStrecke(name: 'Testfahrt');
      expect(s, isNotNull);
      expect(s!.name, 'Testfahrt');
      expect(s.distanceKm, 42.5);
      expect(s.geometry['type'], 'LineString');
      expect((s.geometry['coordinates'] as List).length, 3);
    });

    test('sie traegt die GEFAHRENE Spur, nicht eine geplante Route', () {
      final s = fahrt().alsSpeicherbareStrecke()!;
      expect(
        s.routeSource,
        'driven_track',
        reason:
            'Eine spaeter daraus gebaute Fremdfahrt muss wissen, dass sie '
            'einer echten Aufzeichnung folgt und keinem Vorschlag.',
      );
      expect(s.routeMeta['geometry_source'], 'gps_track');
      expect(s.drivenKm, 42.5, reason: 'Gefahrene Kilometer, nicht geplante.');
    });

    test('sie behaelt die Verbindung zur Fahrt, aber NICHT ueber '
        'source_route_id', () {
      final f = fahrt();
      final s = f.alsSpeicherbareStrecke()!;

      // Diese Zusicherung stand hier zuerst genau andersherum und hat den
      // Fehler festgeschrieben. routes.source_route_id traegt einen
      // Fremdschluessel auf routes(id). Eine Fahrt-Kennung steht dort nie
      // drin: am 01.09. an der Produktionsdatenbank gemessen, 190 Fahrten
      // mit Spur, NULL davon existieren als Route. Der Insert scheiterte
      // also immer mit 23503 — nachgestellt und bestaetigt, die alte
      // Fassung warf den Fremdschluesselfehler, die neue lief durch.
      // saveExistingRoute faengt nur PGRST204 und 23505 ab, 23503 landete
      // also als "Konnte gerade nicht speichern. Pruefe deine Verbindung."
      // beim Nutzer. Das Feature war fuer alle Fahrten zu 100 Prozent tot.
      expect(
        s.sourceRouteId,
        isNull,
        reason:
            'Eine Fahrt-Kennung in source_route_id laesst jeden Insert am '
            'Fremdschluessel scheitern.',
      );
      expect(
        s.routeMeta['drive_session_id'],
        f.id,
        reason: 'Die Verbindung gehoert in route_meta, nicht in den Schluessel.',
      );
    });

    test('eine GPS-Luecke wird nicht als schnurgerade Strasse ausgegeben', () {
      // Ueber alle 190 aufgezeichneten Spuren gemessen: 15 haben einen
      // Sprung ueber 1000 m, der groesste 6844 m. Als LineString gespeichert
      // waere daraus eine Luftlinie quer durch die Landschaft geworden —
      // sichtbar in der Skizze, teilbar, fahrbar, und die neu gerechnete
      // Streckenlaenge waere gefaelscht.
      final mitLuecke = UserDriveSession(
        id: 'sess-luecke',
        userId: 'user-1',
        createdAt: DateTime(2026, 9, 1),
        distanceKm: 10,
        durationSeconds: 600,
        xpAwarded: 40,
        completedAtEnd: true,
        trackGeometry: const [
          [16.3700, 48.2080],
          [16.3710, 48.2085],
          // rund 7 km Sprung
          [16.4650, 48.2085],
          [16.4660, 48.2090],
        ],
      );
      final s = mitLuecke.alsSpeicherbareStrecke()!;
      expect(s.geometry['type'], 'MultiLineString');
      final teile = s.geometry['coordinates'] as List;
      expect(teile.length, 2, reason: 'Vor und nach der Luecke je ein Stueck.');
      expect((teile.first as List).length, 2);
      expect((teile.last as List).length, 2);
    });

    test('eine lueckenlose Spur bleibt ein einfacher LineString', () {
      final s = fahrt().alsSpeicherbareStrecke()!;
      expect(s.geometry['type'], 'LineString');
    });

    test('Tempo und Foto gehen nicht verloren', () {
      final s = fahrt(foto: 'https://example.test/bild.jpg')
          .alsSpeicherbareStrecke()!;
      expect(s.topSpeedKmh, 118);
      expect(s.photoUrl, 'https://example.test/bild.jpg');
    });

    test('ohne Spur gibt es nichts zu speichern', () {
      expect(
        fahrt(spur: const []).alsSpeicherbareStrecke(),
        isNull,
        reason:
            'Eine Fahrt ohne aufgezeichnete Spur hat keine Geometrie. Lieber '
            'null als eine leere Strecke in der Sammlung.',
      );
    });
  });

  group('Durchschnittsgeschwindigkeit', () {
    SavedRoute gefahren({double km = 60, double sekunden = 3600}) =>
        SavedRoute(
          id: 'x',
          createdAt: DateTime(2026, 8, 15),
          style: 'Standard',
          distanceKm: km,
          geometry: const {'type': 'LineString', 'coordinates': []},
          durationSeconds: sekunden,
          drivenKm: km,
          routeSource: 'driven_track',
        );

    test('60 km in einer Stunde sind 60 km/h', () {
      expect(gefahren().durchschnittKmh, closeTo(60, 0.01));
    });

    test('eine bloss GEPLANTE Route zeigt keinen Durchschnitt', () {
      final geplant = SavedRoute(
        id: 'y',
        createdAt: DateTime(2026, 8, 15),
        style: 'Standard',
        distanceKm: 60,
        geometry: const {'type': 'LineString', 'coordinates': []},
        durationSeconds: 3600,
        // kein drivenKm, keine gefahrene Quelle
      );
      expect(
        geplant.durchschnittKmh,
        isNull,
        reason:
            'Dort waere die Zahl die Schaetzung des Routers. Sie als '
            'Durchschnitt auszugeben waere gelogen.',
      );
    });

    test('unmoegliche Werte werden verworfen', () {
      expect(gefahren(km: 600, sekunden: 3600).durchschnittKmh, isNull,
          reason: '600 km/h ist kein Auto auf oeffentlicher Strasse.');
      expect(gefahren(km: 1, sekunden: 3600).durchschnittKmh, isNull,
          reason: 'Unter 3 km/h war es keine Fahrt.');
      expect(gefahren(sekunden: 0).durchschnittKmh, isNull);
    });
  });

  group('Was beim Speichern in die Datenbank geht', () {
    late String quelle;

    setUpAll(() {
      quelle = File(
        'lib/data/services/saved_routes_service.dart',
      ).readAsStringSync();
    });

    test('Tempo, gefahrene Kilometer und Foto werden mitgeschrieben', () {
      // Bis zum Ende der Methode lesen, nicht auf gut Glueck eine Zeichenzahl
      // abschneiden: die Felder stehen am SCHLUSS der Map, und ein zu kurzes
      // Fenster laesst den Waechter still durchlaufen. Genau das ist beim
      // ersten Anlauf passiert.
      final i = quelle.indexOf('_buildExistingRouteInsert({');
      expect(i, greaterThanOrEqualTo(0));
      final ende = quelle.indexOf('\n  }', quelle.indexOf('return <String, dynamic>{', i));
      expect(ende, greaterThan(i));
      final block = quelle.substring(i, ende);
      for (final feld in [
        'top_speed_kmh',
        'driven_km',
        'photo_url',
        'completed_at_end',
      ]) {
        expect(
          block.contains("'$feld'"),
          isTrue,
          reason:
              'Ohne "$feld" bleibt die Spalte leer. Genau deshalb war '
              'routes.top_speed_kmh in der Produktion bei 1 von 299 Zeilen '
              'gefuellt und die Tempo-Kachel erschien nie.',
        );
      }
    });

    test('der Rueckfall bei fehlenden Spalten raeumt sie auch wieder ab', () {
      // Eine App gegen eine aeltere Datenbank soll die Strecke lieber ohne
      // Tempo speichern als gar nicht.
      // Es gibt zwei solche Rueckfaelle im Dienst. Gemeint ist der in
      // saveExistingRoute — der Weg, ueber den eine gefahrene Fahrt
      // gespeichert wird.
      final start = quelle.indexOf('static Future<void> saveExistingRoute(');
      expect(start, greaterThanOrEqualTo(0));
      final i = quelle.indexOf("if (e.code == 'PGRST204')", start);
      expect(i, greaterThanOrEqualTo(0));
      final block = quelle.substring(i, i + 1200);
      for (final feld in ['top_speed_kmh', 'driven_km', 'photo_url']) {
        expect(block.contains("remove('$feld')"), isTrue, reason: feld);
      }
    });
  });

  group('Fotos werden nicht mehr weggeraeumt, bevor man sie sieht', () {
    test('die Grenze liegt deutlich ueber fuenf', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      final treffer = RegExp(
        r'pruneRecentRidePhotos\(\{int keep = (\d+)\}\)',
      ).firstMatch(quelle);
      expect(treffer, isNotNull, reason: 'Die Funktion gibt es nicht mehr.');
      final grenze = int.parse(treffer!.group(1)!);
      expect(
        grenze,
        greaterThanOrEqualTo(50),
        reason:
            'Bei fuenf zerstoert sich das nachtraegliche Hinzufuegen von '
            'Fotos selbst: sobald fuenf neuere Foto-Fahrten da sind, ist das '
            'nachgereichte Bild samt Datei weg. Gemessen gibt es drei Fotos '
            'im ganzen System.',
      );
    });
  });

  group('Alte Fahrten sind ueberhaupt erreichbar', () {
    test('es gibt einen Weg zu allen Fahrten', () {
      expect(
        File('lib/presentation/pages/alle_fahrten_page.dart').existsSync(),
        isTrue,
      );
      final auswertung = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      expect(
        auswertung.contains('AlleFahrtenPage'),
        isTrue,
        reason:
            'Ohne diesen Weg ist die Fahrten-Detailseite fuer alles jenseits '
            'der letzten fuenf Fahrten nicht aufrufbar — und damit weder das '
            'Foto noch das Speichern.',
      );
    });

    test('die Uebersicht bleibt bewusst bei fuenf', () {
      // Vucko wollte am 25.06. ausdruecklich nur fuenf im Ueberblick. Der neue
      // Weg aendert daran nichts, er fuehrt nur zu allem dahinter.
      final auswertung = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      expect(auswertung.contains('sorted.take(5)'), isTrue);
    });
  });
}
