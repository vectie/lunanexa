///|
pub fn bounded_metric(sample : @contracts.TelemetrySample) -> Bool {
  if sample.node_id == "" ||
    sample.node_id.length() > 128 ||
    sample.node_id.contains_char('\n') ||
    sample.deployment_id.length() > 128 ||
    sample.deployment_id.contains_char('\n') ||
    sample.timestamp_unix_ms <= 0L ||
    sample.value < 0.0 {
    return false
  }
  match sample.metric {
    "accelerator_memory_total_mib" | "accelerator_memory_free_mib" =>
      sample.value <= 1000000000.0
    "accelerator_healthy_count" => sample.value <= 1024.0
    "accelerator_utilization_per_mille" => sample.value <= 1000.0
    "runtime_queue_depth" => sample.value <= 1000000.0
    "runtime_requests_total" | "runtime_failures_total" =>
      sample.value <= 1000000000000000.0
    "runtime_load_ms" | "runtime_first_output_ms" => sample.value <= 86400000.0
    _ => false
  }
}
