///|
pub fn bounded_metric(sample : @contracts.TelemetrySample) -> Bool {
  bounded_metric_with_settings(
    sample,
    @settings.default_global_admin_settings().telemetry_safety,
  )
}

///|
pub fn bounded_metric_with_settings(
  sample : @contracts.TelemetrySample,
  limits : @settings.TelemetrySafetySettings,
) -> Bool {
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
    "accelerator_memory_total_mib"
    | "accelerator_memory_free_mib"
    | "accelerator_memory_used_mib" => sample.value <= limits.maximum_memory_mib
    "accelerator_healthy_count" =>
      sample.value <= limits.maximum_accelerator_count
    "accelerator_utilization_per_mille" => sample.value <= 1000.0
    "accelerator_temperature_celsius" =>
      sample.value <= limits.maximum_temperature_celsius
    "accelerator_power_watts" => sample.value <= limits.maximum_power_watts
    "runtime_queue_depth" => sample.value <= 1000000.0
    "runtime_requests_total" | "runtime_failures_total" =>
      sample.value <= 1000000000000000.0
    "runtime_load_ms" | "runtime_first_output_ms" => sample.value <= 86400000.0
    _ => false
  }
}
