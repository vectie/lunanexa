///|
test "nvidia-smi parser aggregates multiple accelerators" {
  let snapshot = @node.parse_nvidia_smi_csv(
    "10, 1024, 8192, 42, 55.5\n30, 2048, 8192, 51, 60.25\n",
  )
  assert_eq(snapshot.accelerator_count, 2)
  assert_eq(snapshot.memory_used_mib, 3072.0)
  assert_eq(snapshot.memory_total_mib, 16384.0)
  assert_eq(snapshot.memory_measured, true)
  assert_eq(snapshot.utilization_per_mille, 200.0)
  assert_eq(snapshot.maximum_temperature_celsius, 51.0)
  assert_eq(snapshot.power_watts, 115.75)
}

///|
test "nvidia-smi parser accepts unified-memory rows without memory counters" {
  // NVIDIA GB10 reports memory.used/memory.total as N/A over NVML while
  // utilization, temperature and power remain real driver readings.
  let snapshot = @node.parse_nvidia_smi_csv("0, [N/A], [N/A], 39, 3.95\n")
  assert_eq(snapshot.accelerator_count, 1)
  assert_eq(snapshot.memory_measured, false)
  assert_eq(snapshot.memory_used_mib, 0.0)
  assert_eq(snapshot.memory_total_mib, 0.0)
  assert_eq(snapshot.utilization_per_mille, 0.0)
  assert_eq(snapshot.maximum_temperature_celsius, 39.0)
  assert_eq(snapshot.power_watts, 3.95)
  try
    @node.parse_nvidia_smi_csv(
      "0, N/A, N/A, 39, 3.95\n12, 1024, 8192, 42, 55.5\n",
    )
    |> ignore
  catch {
    @node.TelemetryCollectorError::MalformedSample(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("mixed measured/unified memory rows were accepted")
  }
}

///|
test "nvidia-smi parser rejects malformed and physically invalid data" {
  let invalid = [
    "", "10,20,30,40", "101,20,30,40,50", "10,31,30,40,50", "10,-1,30,40,50", "10,N/A,30,40,50",
    "10,NaN,30,40,50", "10,20,0,40,50", "10,20,30,201,50", "10,20,30,40,100001",
    "10,20,30,40,50,60",
  ]
  for sample in invalid {
    try @node.parse_nvidia_smi_csv(sample) catch {
      @node.TelemetryCollectorError::MalformedSample(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("malformed accelerator sensor row was accepted")
    }
  }
}

///|
async test "collector rejects executable injection before spawning" {
  try
    @node.collect_accelerator_sensors("/usr/bin/nvidia-smi;touch /tmp/pwned")
  catch {
    @node.TelemetryCollectorError::UnsupportedBinary(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("arbitrary sensor executable was accepted")
  }
}
