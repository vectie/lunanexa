///|
pub(all) struct TelemetrySnapshot {
  schema_version : String
  samples : Array[@contracts.TelemetrySample]
  benchmark_runs : Array[BenchmarkRun]
  benchmark_summaries : Array[BenchmarkSummary]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror TelemetryError {
  PayloadMetricRejected
  InvalidTelemetryState(String)
} derive(Debug, Eq)

///|
pub struct FileTelemetry {
  path : String
  sample_history_limit : Int
  benchmark_history_limit : Int
  safety_limits : @settings.TelemetrySafetySettings
  samples : Array[@contracts.TelemetrySample]
  benchmark_runs : Array[BenchmarkRun]
  benchmark_summaries : Array[BenchmarkSummary]
  mutex : @async.Mutex
}

///|
fn FileTelemetry::snapshot_unlocked(self : FileTelemetry) -> TelemetrySnapshot {
  {
    schema_version: "lunanexa.telemetry.v1",
    samples: self.samples.copy(),
    benchmark_runs: self.benchmark_runs.copy(),
    benchmark_summaries: self.benchmark_summaries.copy(),
  }
}

///|
async fn write_telemetry(path : String, snapshot : TelemetrySnapshot) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
pub async fn FileTelemetry::open(
  path : String,
  sample_history_limit? : Int = 10000,
  benchmark_history_limit? : Int = 256,
  safety_limits? : @settings.TelemetrySafetySettings = @settings.default_global_admin_settings().telemetry_safety,
) -> FileTelemetry {
  if sample_history_limit <= 0 ||
    sample_history_limit > 1000000 ||
    benchmark_history_limit <= 0 ||
    benchmark_history_limit > 65536 {
    raise InvalidTelemetryState("history limits must be positive and bounded")
  }
  let telemetry : FileTelemetry = {
    path,
    sample_history_limit,
    benchmark_history_limit,
    safety_limits,
    samples: [],
    benchmark_runs: [],
    benchmark_summaries: [],
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : TelemetrySnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidTelemetryState("\{Repr(error)}")
    }
    if snapshot.schema_version != "lunanexa.telemetry.v1" {
      raise InvalidTelemetryState("unsupported telemetry snapshot")
    }
    telemetry.samples.push_iter(snapshot.samples.iter())
    telemetry.benchmark_runs.push_iter(snapshot.benchmark_runs.iter())
    telemetry.benchmark_summaries.push_iter(snapshot.benchmark_summaries.iter())
    let mut pruned = false
    while telemetry.samples.length() > sample_history_limit {
      ignore(telemetry.samples.remove(0))
      pruned = true
    }
    while telemetry.benchmark_runs.length() > benchmark_history_limit {
      ignore(telemetry.benchmark_runs.remove(0))
      ignore(telemetry.benchmark_summaries.remove(0))
      pruned = true
    }
    if pruned {
      write_telemetry(path, telemetry.snapshot_unlocked())
    }
  } else {
    write_telemetry(path, telemetry.snapshot_unlocked())
  }
  telemetry
}

///|
async fn FileTelemetry::persist(self : FileTelemetry) -> Unit {
  write_telemetry(self.path, self.snapshot_unlocked())
}

///|
pub async fn FileTelemetry::record_sample(
  self : FileTelemetry,
  sample : @contracts.TelemetrySample,
) -> Unit {
  if !bounded_metric_with_settings(sample, self.safety_limits) {
    raise PayloadMetricRejected
  }
  self.mutex.acquire()
  self.samples.push(sample)
  while self.samples.length() > self.sample_history_limit {
    ignore(self.samples.remove(0))
  }
  try self.persist() catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileTelemetry::record_benchmark(
  self : FileTelemetry,
  run : BenchmarkRun,
) -> BenchmarkSummary {
  let summary = summarize(run)
  self.mutex.acquire()
  self.benchmark_runs.push(run)
  self.benchmark_summaries.push(summary)
  while self.benchmark_runs.length() > self.benchmark_history_limit {
    ignore(self.benchmark_runs.remove(0))
    ignore(self.benchmark_summaries.remove(0))
  }
  try self.persist() catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  summary
}

///|
pub async fn FileTelemetry::snapshot(self : FileTelemetry) -> TelemetrySnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}
