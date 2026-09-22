///|
struct ArtifactPreparationProgress {
  mut stage : Int
  mut cache_hit : Bool
  total_bytes : Int64
  mut completed_file_bytes : Int64
  mut current_file_bytes : Int64
  mut transferred_bytes : Int64
}

///|
fn ArtifactMaterializer::mark_cache_hit(
  self : ArtifactMaterializer,
  deployment_id : String,
) -> Unit {
  if self.progress.get(deployment_id) is Some(progress) {
    progress.cache_hit = true
  }
}

///|
/// Preparation stage: 1 checking, 2 transferring, 3 verified, 4 failed.
/// This is model preparation evidence only; it never declares runtime readiness.
pub fn ArtifactMaterializer::preparation_samples(
  self : ArtifactMaterializer,
  node_id : String,
  deployment_id : String,
  timestamp_unix_ms : Int64,
) -> Array[@contracts.TelemetrySample] {
  guard self.progress.get(deployment_id) is Some(progress) else { return [] }
  [
    for
      (metric, value) in [
        ("artifact_preparation_stage", progress.stage.to_double()),
        ("artifact_cache_hit", if progress.cache_hit { 1.0 } else { 0.0 }),
        (
          "artifact_bytes_present",
          (progress.completed_file_bytes + progress.current_file_bytes).to_double(),
        ),
        ("artifact_bytes_total", progress.total_bytes.to_double()),
        ("artifact_transfer_bytes", progress.transferred_bytes.to_double()),
      ] => { node_id, deployment_id, metric, value, timestamp_unix_ms, }
  ]
}
