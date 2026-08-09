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
pub async fn FileTelemetry::open(path : String) -> FileTelemetry {
  let telemetry : FileTelemetry = {
    path,
    samples: [],
    benchmark_runs: [],
    benchmark_summaries: [],
    mutex: @async.Mutex::Mutex(),
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
  if !bounded_metric(sample) {
    raise PayloadMetricRejected
  }
  self.mutex.acquire()
  self.samples.push(sample)
  while self.samples.length() > 10000 {
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
  while self.benchmark_runs.length() > 256 {
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
