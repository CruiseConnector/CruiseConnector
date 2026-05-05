export interface Coordinate {
  latitude: number;
  longitude: number;
}

export interface PreferenceArea extends Coordinate {
  radius_m?: number;
  bearing_from_start?: number;
  distance_from_start_km?: number;
}

export type RouteMode =
  | "Kurvenjagd"
  | "Sport Mode"
  | "Abendrunde"
  | "Entdecker"
  | "Standard";

export interface RequestData {
  planning_type: "Zufall" | "Wegpunkte";
  route_type?: "ROUND_TRIP" | "POINT_TO_POINT";
  required_waypoints?: Coordinate[];
  user_waypoints?: Coordinate[];
  manual_waypoints?: Coordinate[];
  waypoint_mode?: "required_stops";
  waypoint_order?: "fixed" | "auto_optimize";
  max_search_ms?: number;
  original_planning_type?: "waypoints" | "Wegpunkte";
  effective_planning_type?: "random" | "Zufall";
  generation_mode?: "random_with_preferences";
  preference_areas?: PreferenceArea[];
  preference_area_count?: number;
  preference_applied?: boolean;
  close_loop?: boolean;
  allow_seed_generation?: boolean;
  targetDistance?: number; // in km
  startLocation: Coordinate;
  destination_location?: Coordinate;
  mode?: RouteMode;
  randomSeed?: number;
  detour_level?: number;
  detour_factor?: number;
  avoid_highways?: boolean;
  direction_hint?: number;
  offset_side?: number;
  style_profile?: string;
  waypoint_shape_factor?: number;
  zigzag_waypoints?: boolean;
  continue_straight?: boolean;
  route_variant_hint?: string;
  variant_hint?: string;
  route_fingerprint_hint?: string;
  fingerprint_hint?: string;
  previous_route_fingerprints?: string[];
  max_candidate_attempts?: number;
  moving_start?: boolean;
  current_heading?: number;
  current_speed_mps?: number;
  location_accuracy_m?: number;
  heading_accuracy_deg?: number;
  speed_accuracy_mps?: number;
  start_radius_m?: number;
  start_bearing_tolerance_deg?: number;
  avoid_maneuver_radius_m?: number;
  start_on_motorway?: boolean;
  simplify_waypoints?: boolean;
  max_waypoints?: number;
}

export interface DistanceConfig {
  radiusKm: number;
  minKm: number;
  maxKm: number;
  acceptableMinKm: number;
  acceptableMaxKm: number;
  waypointRadiusMeters: number;
}

export type RouteQualityTier = "ideal" | "good" | "acceptable" | "rejected";

export interface RouteQualityEvaluation {
  passed: boolean;
  reason: string;
  overlapPercent: number;
  hasUTurn: boolean;
  tier: RouteQualityTier;
  score: number;
  baseScore?: number;
  styleFitScore?: number;
  styleFitReasons?: string[];
  styleMetrics?: RouteStyleMetrics;
  coordinateCount: number;
  actualDistanceKm: number;
  distanceDeltaKm: number;
  preferenceMatchScore?: number;
  matchedPreferenceCount?: number;
  preferenceAreaDistancesMeters?: number[];
  preferenceIgnoredReason?: string | null;
  shapeMetrics?: RouteShapeMetrics;
  safeFallbackUsed?: boolean;
  safeFallbackReason?: string | null;
  requestedStyle?: string | null;
  deliveredStyle?: string | null;
  styleDowngraded?: boolean;
}

export interface PreferenceMatchSummary {
  matchedPreferenceCount: number;
  preferenceMatchScore: number;
  preferenceAreaDistancesMeters: number[];
  preferenceIgnoredReason?: string | null;
}

export interface RouteStyleMetrics {
  curveDensityPerKm: number;
  curveDensityPer50Km: number;
  averageSegmentLengthMeters: number;
  sharpTurnCount: number;
  sharpTurnRate: number;
  smoothnessScore: number;
  headingChangeTotal: number;
  headingChangePerKm: number;
  zigzagScore: number;
  stubPenalty: number;
  sectorDiversityScore: number;
  loopnessScore: number;
  spurScore: number;
  deadEndArmScore: number;
  outAndBackScore: number;
  overlapScore: number;
}

export interface RouteShapeMetrics {
  loopnessScore: number;
  spurScore: number;
  deadEndArmScore: number;
  outAndBackScore: number;
  overlapScore: number;
  centralReturnPercent: number;
  centerReentryCount: number;
  radialPeakCount: number;
  middleCoverageRatio: number;
  geometricUTurnCount: number;
  oppositeOverlapPercent: number;
  foldedLoopPenalty: number;
  repeatedStartAreaPercent: number;
  spurArmPercent: number;
  cleanupRemovedPercent: number;
  cleanupDistanceRetentionRatio: number;
  cleanupLoopCount: number;
  cleanupUTurnCount: number;
}

export interface RouteCleanupEvaluation {
  passed: boolean;
  reason: string;
  removedPointPercent: number;
  distanceRetentionRatio: number;
  removedLoops: number;
  cleanedDistanceKm: number;
  cleanedGeometricUTurnCount: number;
  fingerprint: string;
  cleanedCoordinates?: Coordinate[];
}

export interface RoundTripCandidatePlan {
  label: string;
  waypoints: Coordinate[];
  radiuses: string;
}

export interface RoundTripSearchResult {
  route: any | null;
  waypoints: Coordinate[];
  radiuses: string;
  quality: RouteQualityEvaluation | null;
  candidateAttempts: number;
  acceptedCandidates: number;
  rejectedCandidates: number;
  mapboxCallCount?: number;
  evaluatedRouteCount?: number;
  guidanceHydrationCount?: number;
  searchStageSuccess?: string | null;
  selectedCandidateFamily?: string | null;
  distanceFitTier?: string | null;
  rejectReasons: Record<string, number>;
  searchPhases: string[];
  lastPlanLabels?: string[];
  variantHint?: string;
  fingerprintHint?: string;
  duplicateSkips: number;
  emergencyDuplicateUsed?: boolean;
  safeFallbackUsed?: boolean;
  safeFallbackReason?: string | null;
  requestedStyle?: string | null;
  deliveredStyle?: string | null;
  styleDowngraded?: boolean;
  terminalShortCircuit?: boolean;
  exhausted?: boolean;
  preferenceMatch?: PreferenceMatchSummary | null;
}

export interface MapboxRouteFetchResult {
  route: any | null;
  routes?: any[];
  outcome: "ok" | "no_route" | "http_error" | "network_error" | "timeout";
  statusCode?: number;
  details?: string;
}
