import 'package:cruise_connect/data/services/navigation_reroute_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 6, 16, 12);

  NavigationRerouteDecision evaluate({
    bool isOutsideCorridor = true,
    bool approachingDestination = false,
    bool nearRouteEnd = false,
    bool makingForwardProgress = false,
    bool maneuverOvershoot = false,
    bool headingOpposed = false,
    double distanceMeters = 70,
    double corridorMeters = 45,
    Duration offFor = const Duration(milliseconds: 1800),
    bool isRerouting = false,
    Duration? sinceLastReroute,
    bool lastRerouteFailed = false,
    double speedMps = 13,
  }) {
    return NavigationRerouteDecisionEngine.evaluate(
      isOutsideCorridor: isOutsideCorridor,
      approachingDestination: approachingDestination,
      nearRouteEnd: nearRouteEnd,
      makingForwardProgress: makingForwardProgress,
      maneuverOvershoot: maneuverOvershoot,
      headingOpposed: headingOpposed,
      distanceMeters: distanceMeters,
      corridorMeters: corridorMeters,
      offRouteSince: t0.subtract(offFor),
      now: t0,
      isRerouting: isRerouting,
      lastRerouteTime: sinceLastReroute == null
          ? null
          : t0.subtract(sinceLastReroute),
      lastRerouteFailed: lastRerouteFailed,
      speedMps: speedMps,
    );
  }

  test(
    'normal off-route triggers after 1.8s, well under the 4s requirement',
    () {
      expect(
        evaluate(offFor: const Duration(milliseconds: 1799)).shouldTrigger,
        isFalse,
      );

      final decision = evaluate(offFor: const Duration(milliseconds: 1800));

      expect(decision.shouldTrackOffRoute, isTrue);
      expect(decision.clearlyOffRoute, isFalse);
      expect(
        decision.requiredOffRouteDuration,
        const Duration(milliseconds: 1800),
      );
      expect(decision.shouldTrigger, isTrue);
    },
  );

  test('clearly off-route or missed maneuver uses the fast 0.9s lane', () {
    expect(
      evaluate(
        maneuverOvershoot: true,
        offFor: const Duration(milliseconds: 899),
      ).shouldTrigger,
      isFalse,
    );

    final decision = evaluate(
      maneuverOvershoot: true,
      offFor: const Duration(milliseconds: 900),
    );

    expect(decision.clearlyOffRoute, isTrue);
    expect(
      decision.requiredOffRouteDuration,
      const Duration(milliseconds: 900),
    );
    expect(decision.shouldTrigger, isTrue);
  });

  test('large route gap also counts as clearly off-route', () {
    final decision = evaluate(
      distanceMeters: 120,
      corridorMeters: 45,
      offFor: const Duration(milliseconds: 900),
    );

    expect(decision.clearlyOffRoute, isTrue);
    expect(decision.shouldTrigger, isTrue);
  });

  test('progress, destination approach, and route end suppress reroute', () {
    expect(evaluate(makingForwardProgress: true).shouldTrigger, isFalse);
    expect(evaluate(approachingDestination: true).shouldTrigger, isFalse);
    expect(evaluate(nearRouteEnd: true).shouldTrigger, isFalse);
  });

  test('success cooldown is shortened at high speed', () {
    expect(
      evaluate(
        speedMps: 30,
        sinceLastReroute: const Duration(milliseconds: 999),
      ).shouldTrigger,
      isFalse,
    );

    final decision = evaluate(
      speedMps: 30,
      sinceLastReroute: const Duration(milliseconds: 1000),
    );

    expect(decision.cooldownDuration, const Duration(milliseconds: 1000));
    expect(decision.shouldTrigger, isTrue);
  });

  test('failed reroutes keep the longer failure cooldown', () {
    expect(
      evaluate(
        lastRerouteFailed: true,
        sinceLastReroute: const Duration(milliseconds: 2999),
      ).shouldTrigger,
      isFalse,
    );

    final decision = evaluate(
      lastRerouteFailed: true,
      sinceLastReroute: const Duration(seconds: 3),
    );

    expect(decision.cooldownDuration, const Duration(seconds: 3));
    expect(decision.shouldTrigger, isTrue);
  });

  test('does not start a second reroute while one is already running', () {
    expect(evaluate(isRerouting: true).shouldTrigger, isFalse);
  });

  test('maximum wait cap exposes the 4s reroute deadline', () {
    expect(
      evaluate(offFor: const Duration(milliseconds: 3999)).maximumWaitExceeded,
      isFalse,
    );

    final decision = evaluate(offFor: const Duration(seconds: 4));

    expect(decision.maxOffRouteDuration, const Duration(seconds: 4));
    expect(decision.maximumWaitExceeded, isTrue);
    expect(decision.shouldTrigger, isTrue);
  });
}
