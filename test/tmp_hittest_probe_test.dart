import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Probe 2: Gewinnt der Hochwisch-Erkenner der Vollbild-Leiste gegen die
/// Karte, die mit EagerGestureRecognizer im Baum liegt?
void main() {
  testWidgets('Hochwischen ueber der Karte', (tester) async {
    var wischer = 0;
    var knopf = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // "Karte" mit eagerGestures wie CruiseMapLibreMap
              Positioned.fill(
                child: RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer
                        >(EagerGestureRecognizer.new, (_) {}),
                  },
                  child: const ColoredBox(color: Colors.green),
                ),
              ),
              // Vollbild-Leiste
              Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 50),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 54,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => knopf++,
                              child: const Text('Gruppe einstellen'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 120,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) {
                        if ((d.primaryDelta ?? 0) < -6) wischer++;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Hochwischen mitten in der 120-px-Zone (Bildschirm 600 hoch → y 540).
    await tester.dragFrom(const Offset(400, 545), const Offset(0, -90));
    await tester.pumpAndSettle();
    debugPrint('WISCHER=$wischer');

    await tester.tap(find.text('Gruppe einstellen'));
    await tester.pump();
    debugPrint('KNOPF=$knopf');

    expect(wischer, greaterThan(0), reason: 'Hochwischen muesste greifen');
  });
}
