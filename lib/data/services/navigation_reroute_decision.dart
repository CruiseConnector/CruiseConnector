class NavigationRerouteDecision {
  const NavigationRerouteDecision({
    required this.shouldTrackOffRoute,
    required this.clearlyOffRoute,
    required this.sustained,
    required this.cooldownOk,
    required this.shouldTrigger,
    required this.requiredOffRouteDuration,
    required this.maxOffRouteDuration,
    required this.maximumWaitExceeded,
    required this.cooldownDuration,
  });

  final bool shouldTrackOffRoute;
  final bool clearlyOffRoute;
  final bool sustained;
  final bool cooldownOk;
  final bool shouldTrigger;
  final Duration requiredOffRouteDuration;
  final Duration maxOffRouteDuration;
  final bool maximumWaitExceeded;
  final Duration cooldownDuration;
}

class NavigationRerouteDecisionEngine {
  const NavigationRerouteDecisionEngine._();

  static const normalOffRouteDuration = Duration(milliseconds: 1800);
  static const clearOffRouteDuration = Duration(milliseconds: 900);
  static const maxOffRouteDuration = Duration(seconds: 4);
  static const normalSuccessCooldown = Duration(seconds: 2);
  static const highSpeedSuccessCooldown = Duration(milliseconds: 1000);
  static const failureCooldown = Duration(seconds: 3);
  static const highSpeedThresholdMps = 22.0;
  static const clearDistanceMultiplier = 2.5;

  static NavigationRerouteDecision evaluate({
    required bool isOutsideCorridor,
    required bool approachingDestination,
    required bool nearRouteEnd,
    required bool makingForwardProgress,
    required bool maneuverOvershoot,
    required bool headingOpposed,
    required double distanceMeters,
    required double corridorMeters,
    required DateTime? offRouteSince,
    required DateTime now,
    required bool isRerouting,
    required DateTime? lastRerouteTime,
    required bool lastRerouteFailed,
    required double speedMps,
    Duration normalDuration = normalOffRouteDuration,
    Duration clearDuration = clearOffRouteDuration,
    Duration maxDuration = maxOffRouteDuration,
    Duration normalCooldown = normalSuccessCooldown,
    Duration highSpeedCooldown = highSpeedSuccessCooldown,
    Duration failedCooldown = failureCooldown,
    double highSpeedThreshold = highSpeedThresholdMps,
    double distanceMultiplier = clearDistanceMultiplier,
  }) {
    final shouldTrack =
        isOutsideCorridor &&
        !approachingDestination &&
        !nearRouteEnd &&
        !makingForwardProgress;
    final safeDistance = distanceMeters.isFinite ? distanceMeters : 0.0;
    final safeCorridor = corridorMeters.isFinite && corridorMeters > 0.0
        ? corridorMeters
        : 0.0;
    final clearly =
        maneuverOvershoot ||
        headingOpposed ||
        (safeCorridor > 0.0 &&
            safeDistance > safeCorridor * distanceMultiplier);

    final offFor = offRouteSince == null
        ? Duration.zero
        : now.difference(offRouteSince);
    final requiredDuration = clearly ? clearDuration : normalDuration;
    final maximumWaitExceeded = offFor >= maxDuration;
    final sustained =
        offFor >= normalDuration || (clearly && offFor >= clearDuration);

    final safeSpeed = speedMps.isFinite ? speedMps : 0.0;
    final successCooldown = safeSpeed > highSpeedThreshold
        ? highSpeedCooldown
        : normalCooldown;
    final cooldown = lastRerouteFailed ? failedCooldown : successCooldown;
    final cooldownOk =
        lastRerouteTime == null || now.difference(lastRerouteTime) >= cooldown;

    return NavigationRerouteDecision(
      shouldTrackOffRoute: shouldTrack,
      clearlyOffRoute: clearly,
      sustained: sustained,
      cooldownOk: cooldownOk,
      shouldTrigger: shouldTrack && sustained && !isRerouting && cooldownOk,
      requiredOffRouteDuration: requiredDuration,
      maxOffRouteDuration: maxDuration,
      maximumWaitExceeded: maximumWaitExceeded,
      cooldownDuration: cooldown,
    );
  }
}
