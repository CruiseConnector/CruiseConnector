/// Mutable debug/telemetry state for the last route-generation run.
///
/// RouteService exposes compatibility accessors for legacy callers, but the
/// backing state lives here so resets and future telemetry exports stay local.
class RouteDebugState {
  RouteDebugState({required String defaultGenerationSource})
    : _defaultGenerationSource = defaultGenerationSource {
    reset(defaultGenerationSource: defaultGenerationSource);
  }

  String _defaultGenerationSource;

  bool fromCache = false;
  bool sessionCacheHit = false;
  bool recentFallbackUsed = false;
  bool persistentCacheFallbackUsed = false;
  bool preparedBufferHit = false;
  bool preparedBufferUsed = false;
  bool duplicateFallbackUsed = false;
  bool emergencyFallbackUsed = false;
  bool poolFallbackUsed = false;
  bool poolDistanceRuleApplied = false;
  bool poolRejectedTooFar = false;
  bool poolExactBucketMissing = false;
  bool alternativeDistanceOffered = false;
  int poolCandidateCount = 0;
  int poolSeenCandidateCount = 0;
  bool duplicateSkipped = false;
  String? sourceDecision;
  String? liveAttemptReason;
  String? poolUsedReason;
  List<String> previousFingerprints = const [];
  int? requestedDistanceBucket;
  int? returnedDistanceBucket;
  bool accessLegUsed = false;
  double? accessLegDistanceKm;
  String generationSource = '';
  String subscriptionTier = 'premium';
  String? requestedStyle;
  String? poolMatchId;
  String? poolMatchTier;
  double? poolStartDistanceKm;
  bool deadEndSpikeDetected = false;
  int apiCallCount = 0;
  int? generationStartedAtMs;
  String? debugFingerprint;
  double? similarityToPreviousPercent;
  String? debugTrigger;
  String? coverageStatus;
  bool seedJobCreated = false;
  bool duplicateSeedJobPrevented = false;
  bool poolBootstrapPending = false;
  String? regionDifficulty;
  String? hardRegionStatus;
  String? chosenCluster;
  bool candidateInserted = false;
  bool verifiedInserted = false;
  bool candidateSaveFailed = false;
  bool candidateDuplicateFingerprint = false;
  String? candidateDuplicateSource;
  bool candidateCoverageRefreshFailed = false;
  String? candidateSaveErrorType;
  String? candidateSaveErrorCode;
  String? candidateSaveErrorReason;
  String? candidateSaveSkippedReason;
  bool temporaryCandidate = false;
  bool hardRegionExplorationUsed = false;
  bool movingStartDetected = false;
  String? startSnapStrategy;
  bool? startOnMotorway;
  double? avoidManeuverRadiusUsed;

  void reset({String? defaultGenerationSource}) {
    if (defaultGenerationSource != null) {
      _defaultGenerationSource = defaultGenerationSource;
    }

    fromCache = false;
    sessionCacheHit = false;
    recentFallbackUsed = false;
    persistentCacheFallbackUsed = false;
    preparedBufferHit = false;
    preparedBufferUsed = false;
    duplicateFallbackUsed = false;
    emergencyFallbackUsed = false;
    poolFallbackUsed = false;
    poolDistanceRuleApplied = false;
    poolRejectedTooFar = false;
    poolExactBucketMissing = false;
    alternativeDistanceOffered = false;
    poolCandidateCount = 0;
    poolSeenCandidateCount = 0;
    duplicateSkipped = false;
    sourceDecision = null;
    liveAttemptReason = null;
    poolUsedReason = null;
    previousFingerprints = const [];
    requestedDistanceBucket = null;
    returnedDistanceBucket = null;
    accessLegUsed = false;
    accessLegDistanceKm = null;
    generationSource = _defaultGenerationSource;
    subscriptionTier = 'premium';
    requestedStyle = null;
    poolMatchId = null;
    poolMatchTier = null;
    poolStartDistanceKm = null;
    deadEndSpikeDetected = false;
    apiCallCount = 0;
    generationStartedAtMs = null;
    debugFingerprint = null;
    similarityToPreviousPercent = null;
    debugTrigger = null;
    coverageStatus = null;
    seedJobCreated = false;
    duplicateSeedJobPrevented = false;
    poolBootstrapPending = false;
    regionDifficulty = null;
    hardRegionStatus = null;
    chosenCluster = null;
    candidateInserted = false;
    verifiedInserted = false;
    candidateSaveFailed = false;
    candidateDuplicateFingerprint = false;
    candidateDuplicateSource = null;
    candidateCoverageRefreshFailed = false;
    candidateSaveErrorType = null;
    candidateSaveErrorCode = null;
    candidateSaveErrorReason = null;
    candidateSaveSkippedReason = null;
    temporaryCandidate = false;
    hardRegionExplorationUsed = false;
    movingStartDetected = false;
    startSnapStrategy = null;
    startOnMotorway = null;
    avoidManeuverRadiusUsed = null;
  }
}
