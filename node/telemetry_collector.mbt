///|
pub(all) suberror TelemetryCollectorError {
  UnsupportedBinary(String)
  CommandFailed(Int)
  MalformedSample(String)
} derive(Debug, Eq)

///|
pub(all) struct AcceleratorSensorSnapshot {
  accelerator_count : Int
  memory_used_mib : Double
  memory_total_mib : Double
  utilization_per_mille : Double
  maximum_temperature_celsius : Double
  power_watts : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
fn finite_bounded(value : Double, maximum : Double) -> Bool {
  !value.is_nan() && value >= 0.0 && value <= maximum
}

///|
fn parse_sensor_value(value : String, maximum : Double) -> Double raise {
  let parsed = @string.parse_double(value.trim()) catch {
    _ => raise TelemetryCollectorError::MalformedSample(value)
  }
  if !finite_bounded(parsed, maximum) {
    raise TelemetryCollectorError::MalformedSample(value)
  }
  parsed
}

///| Parse the fixed, unit-free CSV emitted by the allowlisted nvidia-smi query.

///| Each row is utilization %, memory used MiB, memory total MiB,

///| temperature Celsius, and power Watts. The result intentionally aggregates

///|
/// only node-level statistics; it never reports tenant inputs or process data.
pub fn parse_nvidia_smi_csv(output : String) -> AcceleratorSensorSnapshot raise {
  parse_nvidia_smi_csv_with_limits(
    output,
    @settings.default_global_admin_settings().telemetry_safety,
  )
}

///|
pub fn parse_nvidia_smi_csv_with_limits(
  output : String,
  limits : @settings.TelemetrySafetySettings,
) -> AcceleratorSensorSnapshot raise {
  let rows = output
    .split("\n")
    .map(row => row.trim().to_owned())
    .filter(row => row != "")
    .collect()
  if rows.length() == 0 || rows.length() > limits.maximum_sensor_rows {
    raise TelemetryCollectorError::MalformedSample("accelerator row count")
  }
  let mut memory_used = 0.0
  let mut memory_total = 0.0
  let mut utilization_percent = 0.0
  let mut maximum_temperature = 0.0
  let mut power_watts = 0.0
  for row in rows {
    if row.length() > limits.maximum_sensor_row_characters ||
      row.contains("N/A") {
      raise TelemetryCollectorError::MalformedSample(row)
    }
    let fields = row.split(",").map(field => field.trim().to_owned()).collect()
    if fields.length() != 5 {
      raise TelemetryCollectorError::MalformedSample(row)
    }
    let utilization = parse_sensor_value(fields[0], 100.0)
    let used = parse_sensor_value(fields[1], limits.maximum_memory_mib)
    let total = parse_sensor_value(fields[2], limits.maximum_memory_mib)
    let temperature = parse_sensor_value(
      fields[3],
      limits.maximum_temperature_celsius,
    )
    let power = parse_sensor_value(fields[4], limits.maximum_power_watts)
    if total <= 0.0 || used > total {
      raise TelemetryCollectorError::MalformedSample(row)
    }
    utilization_percent += utilization
    memory_used += used
    memory_total += total
    maximum_temperature = maximum_temperature.max(temperature)
    power_watts += power
  }
  {
    accelerator_count: rows.length(),
    memory_used_mib: memory_used,
    memory_total_mib: memory_total,
    utilization_per_mille: utilization_percent *
    10.0 /
    rows.length().to_double(),
    maximum_temperature_celsius: maximum_temperature,
    power_watts,
  }
}

///| Collect a narrow, fixed set of accelerator health metrics. The executable

///| path and arguments are allowlisted and the process receives no inherited

///|
/// environment, so inventory or control-plane data cannot become commands.
pub async fn collect_accelerator_sensors(
  binary : String,
  limits? : @settings.TelemetrySafetySettings = @settings.default_global_admin_settings().telemetry_safety,
) -> AcceleratorSensorSnapshot {
  if binary != "/usr/bin/nvidia-smi" && binary != "/usr/local/bin/nvidia-smi" {
    raise TelemetryCollectorError::UnsupportedBinary(binary)
  }
  let (status, stdout, _) = @process.collect_output(
    binary,
    [
      "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
      "--format=csv,noheader,nounits",
    ],
    inherit_env=false,
  )
  if status != 0 {
    raise TelemetryCollectorError::CommandFailed(status)
  }
  parse_nvidia_smi_csv_with_limits(stdout.text(), limits)
}
