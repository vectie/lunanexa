///|
/// Portable pure benchmark contracts remain available at the historical
/// telemetry API while the browser uses the same implementation directly.
pub using @benchmark {
  type BenchmarkKind,
  type BenchmarkSample,
  type BenchmarkRun,
  type BenchmarkSummary,
  type BenchmarkError,
  type ServiceObjective,
  type CapacityRecommendation,
  type EvidenceBundle,
  type EvidenceBundleInput,
  type RecommendationInput,
  type RecommendationEvidence,
  summarize,
  meets_objective,
  recommend_capacity,
  build_evidence_bundle,
  build_recommendation,
}
