import 'dart:io';

import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/location_always_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/notification_permission_notice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (Vorfall „App haengt auf der Cruise-Seite"): Ein Nutzer mit
/// iPhone 15 Pro Max kam nicht mehr aus dem Blatt „Routing verstehen" heraus.
/// Das Blatt liess sich weder wegtippen (`isDismissible: false`) noch
/// wegwischen (`enableDrag: false`), hatte kein X, und der einzige Ausgang —
/// der Knopf „Verstanden" — war an `_readToBottom` gekoppelt. Diese Flagge
/// wurde AUSSCHLIESSLICH in einem `ScrollNotification`-Handler gesetzt.
///
/// Passt der Inhalt in die (auf 720 gedeckelte) Blatthoehe, gibt es nichts zu
/// scrollen. `BouncingScrollPhysics` erbt dann `shouldAcceptUserOffset` von
/// `ScrollPhysics` — und das liefert bei `pixels == 0` und
/// `minScrollExtent == maxScrollExtent` **false**. Die Wischgeste wird gar
/// nicht erst angenommen, es feuert NIE eine ScrollNotification, der Knopf
/// bleibt fuer immer gesperrt. Auf Android holt die Zurueck-Geste den Nutzer
/// noch heraus, auf iOS gibt es sie nicht: harte Sackgasse.
///
/// Warum ausgerechnet das 15 Pro Max: 430 Punkte Breite = die breiteste
/// iPhone-Klasse = die wenigsten Zeilenumbrueche = der kuerzeste Inhalt.
///
/// DIESE DATEI HAELT ZWEI DINGE FEST:
///
///  1. **Verhalten**: Jedes Blatt, das sich nicht wegwischen laesst, muss
///     schon im ERSTEN Bild einen bedienbaren Knopf haben — auch dann, wenn
///     der Inhalt vollstaendig hineinpasst. Der „Nichts zu scrollen"-Zustand
///     wird hier nicht ueber die Geraetegroesse erraten (Testschriften haben
///     andere Masse als echte), sondern deterministisch ueber eine winzige
///     Schriftskalierung erzwungen. Genau diesen Zustand haben echte iPhones
///     mit kleiner Systemschrift auf einem breiten Display.
///
///  2. **Umfang**: Das „Erst bis unten lesen"-Muster darf sich nicht
///     unbemerkt vermehren. Ein Quelltext-Waechter zaehlt alle Dateien mit
///     diesem Muster und vergleicht sie mit der Liste unten. Wer ein neues
///     Lese-Tor baut, muss es hier eintragen UND mit einem Verhaltenstest
///     absichern. Der Waechter schlaegt bei harmlosen Text-, Farb- oder
///     Layout-Aenderungen NICHT an, weil er nur nach dem Bauteil sucht, das
///     den Nutzer einsperren kann.
void main() {
  // ───────────────────────────────────────────────────────────────────────
  // 1. Verhalten: Ausweg im ersten Bild
  // ───────────────────────────────────────────────────────────────────────

  group('Blaetter ohne Wisch-Ausgang haben immer einen bedienbaren Knopf', () {
    // Das breiteste iPhone (15 Pro Max) — das Geraet aus dem Vorfall.
    const iPhone15ProMax = Size(430, 932);

    testWidgets(
      'Routing-Hinweis: Inhalt passt ins Blatt → Knopf ist trotzdem frei',
      (tester) async {
        await _pumpeBlatt(
          tester,
          const RoutingOnboardingSheet(),
          groesse: iPhone15ProMax,
          textSkala: _winzigeSchrift,
        );

        // Vorbedingung: Es gibt hier wirklich nichts zu scrollen. Ohne diese
        // Zusicherung wuerde der Test etwas anderes pruefen als er behauptet.
        expect(
          _scrollWeg(tester),
          0.0,
          reason:
              'Der Test soll den Fall "Inhalt passt komplett hinein" pruefen. '
              'Gibt es hier Scroll-Weg, misst er den falschen Zustand.',
        );

        expect(
          _bedienbarerKnopfVorhanden(tester),
          isTrue,
          reason:
              'Kein bedienbarer Knopf im ersten Bild. Das Blatt laesst sich '
              'weder wegtippen noch wegwischen (isDismissible/enableDrag = '
              'false) — der Nutzer sitzt fest.',
        );
        expect(
          find.text('Erst vollständig lesen'),
          findsNothing,
          reason:
              'Das Blatt wartet auf Scrollen, obwohl es nichts zu scrollen '
              'gibt. Genau so hing die App am 24.08. fest.',
        );
      },
    );

    testWidgets(
      'Gruppen-Sicherheitshinweis: Inhalt passt ins Blatt → Tor ist frei',
      (tester) async {
        await _pumpeBlatt(
          tester,
          const GroupSafetyNoticeSheet(),
          groesse: iPhone15ProMax,
          textSkala: _winzigeSchrift,
        );

        expect(_scrollWeg(tester), 0.0);
        expect(
          find.text('Erst bis unten scrollen'),
          findsNothing,
          reason:
              'Der Nichts-zu-scrollen-Ausweg aus initState fehlt oder greift '
              'nicht mehr → Gruppenerstellung waere blockiert.',
        );
      },
    );

    testWidgets('Standort-Hinweis hat im ersten Bild einen bedienbaren Knopf', (
      tester,
    ) async {
      await _pumpeBlatt(
        tester,
        const LocationAlwaysNoticeSheet(),
        groesse: iPhone15ProMax,
        textSkala: _winzigeSchrift,
      );
      expect(_bedienbarerKnopfVorhanden(tester), isTrue);
    });

    testWidgets(
      'Mitteilungs-Hinweis hat im ersten Bild einen bedienbaren Knopf',
      (tester) async {
        await _pumpeBlatt(
          tester,
          const NotificationPermissionNoticeSheet(),
          groesse: iPhone15ProMax,
          textSkala: _winzigeSchrift,
        );
        expect(_bedienbarerKnopfVorhanden(tester), isTrue);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. Verhalten: der normale Weg bleibt heil
  // ───────────────────────────────────────────────────────────────────────

  group('Der normale Lese-Weg funktioniert weiter', () {
    testWidgets('Routing-Hinweis: Scrollen bis unten gibt den Knopf frei', (
      tester,
    ) async {
      // Schmales Geraet + grosse Schrift → der Inhalt laeuft sicher ueber.
      await _pumpeBlatt(
        tester,
        const RoutingOnboardingSheet(),
        groesse: const Size(320, 640),
        textSkala: 1.0,
      );
      expect(
        _scrollWeg(tester),
        greaterThan(0.0),
        reason: 'Vorbedingung: Hier MUSS es etwas zu scrollen geben.',
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verstanden'), findsOneWidget);
      expect(_bedienbarerKnopfVorhanden(tester), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 3. Quelltext-Waechter: das Muster darf sich nicht vermehren
  // ───────────────────────────────────────────────────────────────────────

  test('Kein unbekanntes „Erst bis unten lesen"-Tor in lib/', () {
    final gefunden = _dateienMitLeseTor().toSet();
    final unbekannt = gefunden.difference(_bekannteLeseTore);
    final verschwunden = _bekannteLeseTore.difference(gefunden);

    expect(
      unbekannt,
      isEmpty,
      reason:
          'Neues Lese-Tor gefunden: ${unbekannt.join(", ")}.\n'
          'Ein Knopf, der nur ueber eine ScrollNotification freigeschaltet '
          'wird, sperrt jeden Nutzer aus, bei dem der Inhalt vollstaendig ins '
          'Blatt passt (breites Display oder kleine Systemschrift). '
          'BouncingScrollPhysics nimmt die Wischgeste dann gar nicht erst an.\n'
          'Zu tun: (1) den Fall maxScrollExtent <= 0 behandeln, so wie in '
          'group_safety_notice_sheet.dart; (2) die Datei in '
          '_bekannteLeseTore eintragen; (3) einen Verhaltenstest wie oben '
          'ergaenzen.',
    );
    expect(
      verschwunden,
      isEmpty,
      reason:
          'Diese Dateien stehen in _bekannteLeseTore, haben aber kein '
          'Lese-Tor mehr: ${verschwunden.join(", ")}. Bitte aus der Liste '
          'nehmen, damit sie ehrlich bleibt.',
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Werkzeuge
// ═══════════════════════════════════════════════════════════════════════════

/// So klein, dass der Inhalt jedes Blattes garantiert hineinpasst. Damit ist
/// der „nichts zu scrollen"-Zustand deterministisch — unabhaengig davon, wie
/// die Testschrift misst und wie viel Text gerade im Blatt steht.
///
/// Die Blaetter deckeln die Skalierung nach OBEN (`maxScaleFactor: 1.08`),
/// nicht nach unten; dieser Wert kommt also unveraendert an.
const double _winzigeSchrift = 0.3;

/// Dateien, die heute bewusst ein „erst bis unten lesen"-Tor haben.
/// Beide sind oben mit einem Verhaltenstest abgesichert.
const Set<String> _bekannteLeseTore = {
  'lib/presentation/widgets/cruise/routing_onboarding_sheet.dart',
  'lib/presentation/widgets/group_safety_notice_sheet.dart',
};

Future<void> _pumpeBlatt(
  WidgetTester tester,
  Widget blatt, {
  required Size groesse,
  required double textSkala,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = groesse;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: groesse,
          textScaler: TextScaler.linear(textSkala),
        ),
        child: Scaffold(body: blatt),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Wie viel Weg die Scroll-Flaeche des Blattes hergibt. 0 = nichts zu scrollen.
double _scrollWeg(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  return scrollable.position.maxScrollExtent;
}

/// Gibt es irgendeinen Knopf, den der Nutzer JETZT druecken kann?
bool _bedienbarerKnopfVorhanden(WidgetTester tester) {
  // `find.byType` vergleicht den exakten Laufzeittyp — Oberklassen wie
  // ButtonStyleButton treffen damit nie. Deshalb ueber alle Widgets filtern.
  final knoepfe = tester.allWidgets;
  return knoepfe.any(
    (w) =>
        (w is ButtonStyleButton && w.onPressed != null) ||
        (w is IconButton && w.onPressed != null) ||
        (w is InkWell && w.onTap != null),
  );
}

// ── Quelltext-Waechter ─────────────────────────────────────────────────────

/// Sucht in `lib/` nach dem gefaehrlichen Bauteil, und zwar nur nach diesem:
///
///   * die Datei hoert auf `ScrollNotification` UND liest `maxScrollExtent`,
///   * dabei setzt sie eine Flagge auf `true` (das Lese-Tor),
///   * und diese Flagge — direkt oder ueber EINE abgeleitete Variable —
///     entscheidet in einem `? … : null`-Ausdruck darueber, ob ein Bedien-
///     element ueberhaupt anklickbar ist.
///
/// Erst diese Kette sperrt jemanden ein. Ein `maxScrollExtent` fuer einen
/// Verlaufs-Schatten oder fuers Nachladen einer Liste trifft die Regel nicht —
/// deshalb schlaegt der Waechter bei harmlosem Code nicht an.
final RegExp _hoertAufScrollen = RegExp(
  r'NotificationListener\s*<\s*Scroll\w*Notification\s*>',
);

List<String> _dateienMitLeseTor() {
  final treffer = <String>[];
  for (final datei in _dartDateien(Directory('lib'))) {
    final quelle = datei.readAsStringSync();
    // Whitespace-tolerant: der Formatierer bricht `NotificationListener<
    // ScrollNotification>` gern ueber drei Zeilen um.
    if (!_hoertAufScrollen.hasMatch(quelle)) continue;
    if (!quelle.contains('maxScrollExtent')) continue;

    final zeilen = quelle.split('\n');
    final flaggen = _torFlaggen(zeilen);
    if (flaggen.isEmpty) continue;

    // Eine Ebene Ableitung mitnehmen: `final canAccept = _readToBottom && …;`
    final namen = <String>{...flaggen};
    for (final flagge in flaggen) {
      final abgeleitet = RegExp(
        r'(?:final|var)\s+(\w+)\s*=[^;]*\b' + flagge + r'\b',
      ).allMatches(quelle);
      namen.addAll(abgeleitet.map((m) => m.group(1)!));
    }

    final sperrtBedienelement = zeilen.any(
      (z) =>
          z.contains(': null') &&
          namen.any((n) => RegExp(r'\b' + n + r'\b').hasMatch(z)),
    );
    if (sperrtBedienelement) {
      treffer.add(datei.path.replaceFirst(RegExp(r'^\./'), ''));
    }
  }
  treffer.sort();
  return treffer;
}

/// Flaggen, die in unmittelbarer Nachbarschaft von `maxScrollExtent` auf
/// `true` gesetzt werden — also aus dem Scroll-Ereignis heraus.
Set<String> _torFlaggen(List<String> zeilen) {
  final flaggen = <String>{};
  final setzt = RegExp(r'(\w+)\s*=\s*true');
  for (var i = 0; i < zeilen.length; i++) {
    final m = setzt.firstMatch(zeilen[i]);
    if (m == null) continue;
    // Fenster grosszuegig: Pruefung und Freigabe stehen oft in getrennten
    // kleinen Methoden direkt untereinander (`_freigebenWennAmEnde` →
    // `_alsGelesenMerken`). Enger gefasst rutscht das Tor durch.
    final von = (i - 25).clamp(0, zeilen.length);
    final bis = (i + 25).clamp(0, zeilen.length);
    final umfeld = zeilen.sublist(von, bis).join('\n');
    if (umfeld.contains('maxScrollExtent')) flaggen.add(m.group(1)!);
  }
  return flaggen;
}

Iterable<File> _dartDateien(Directory wurzel) sync* {
  for (final eintrag in wurzel.listSync(recursive: true)) {
    if (eintrag is File && eintrag.path.endsWith('.dart')) yield eintrag;
  }
}
