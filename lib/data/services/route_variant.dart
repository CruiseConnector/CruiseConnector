import 'package:flutter/foundation.dart';

@immutable
class RouteVariant {
  const RouteVariant({
    required this.index,
    required this.seed,
    required this.angleOffset,
    required this.radiusJitter,
    required this.offsetBearing,
    required this.fingerprintHint,
    required this.variantHint,
    this.offsetSide,
    this.styleBias,
  });

  final int index;
  final int seed;
  final double angleOffset;
  final double radiusJitter;
  final int? offsetSide;
  final double offsetBearing;
  final String fingerprintHint;
  final String variantHint;
  final String? styleBias;
}
