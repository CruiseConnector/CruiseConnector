export interface Coordinate {
  latitude: number;
  longitude: number;
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
  manual_waypoints?: Coordinate[];
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
  max_candidate_attempts?: number;
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
  rejectReasons: Record<string, number>;
  searchPhases: string[];
  lastPlanLabels?: string[];
  variantHint?: string;
  fingerprintHint?: string;
  duplicateSkips: number;
  emergencyDuplicateUsed?: boolean;
  terminalShortCircuit?: boolean;
  exhausted?: boolean;
}

export interface MapboxRouteFetchResult {
  route: any | null;
  routes?: any[];
  outcome: "ok" | "no_route" | "http_error" | "network_error" | "timeout";
  statusCode?: number;
  details?: string;
}
