///|
fn environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
fn endpoint(base : String, path : String) -> String {
  if base.has_suffix("/") {
    "\{base[:-1]}\{path}"
  } else {
    "\{base}\{path}"
  }
}

///|
fn benchmark_kind(value : String) -> @telemetry.BenchmarkKind raise {
  match value {
    "concurrency" => Concurrency
    "saturation" => Saturation
    "cold-start" => ColdStart
    "long-stream" => LongStream
    "mixed-workload" => MixedWorkload
    _ =>
      raise Failure::Failure(
        "kind must be concurrency, saturation, cold-start, long-stream, or mixed-workload",
      )
  }
}

///|
async fn run_sample(
  base : String,
  inference_token : String,
  template : @contracts.WorkloadEnvelope,
  kind : @telemetry.BenchmarkKind,
  index : Int,
) -> @telemetry.BenchmarkSample {
  let accepted = @async.now()
  let request = {
    ..template,
    workload_id: "\{template.workload_id}-benchmark-\{index}",
    idempotency_key: "\{template.idempotency_key}-benchmark-\{index}-\{accepted}",
    deadline_unix_ms: accepted +
    template.resource_ceiling.max_runtime_ms +
    5000L,
    trace_token: "benchmark-\{index}",
    stream: false,
  }
  let transport = @client.HttpTransport::new(inference_token)
  let provider = @client.Client::new(
    {
      endpoint: base,
      inference_credential_ref: "environment:LUNANEXA_INFERENCE_TOKEN",
      timeout_ms: request.resource_ceiling.max_runtime_ms + 5000L,
    },
    transport,
  )
  if kind == LongStream {
    let completed_responses : Array[@contracts.WorkloadResponse] = []
    let failed = try {
      provider.stream({ ..request, stream: true }, event => {
        if event.response is Some(response) {
          completed_responses.push(response)
        }
      })
      false
    } catch {
      _ => true
    }
    let completed = @async.now()
    guard !failed && completed_responses.last() is Some(response) else {
      return {
        latency_ms: (completed - accepted).to_int(),
        queue_ms: 0,
        load_ms: 0,
        first_output_ms: 0,
        output_units: 0,
        duration_ms: (completed - accepted).max(1L).to_int(),
        utilization_per_mille: 0,
        failed: true,
      }
    }
    return {
      latency_ms: (completed - accepted).to_int(),
      queue_ms: response.usage.queue_ms.to_int(),
      load_ms: (response.timing.started_unix_ms -
      response.timing.accepted_unix_ms)
      .max(0L)
      .to_int(),
      first_output_ms: (response.timing.first_output_unix_ms -
      response.timing.accepted_unix_ms)
      .max(0L)
      .to_int(),
      output_units: response.usage.output_units,
      duration_ms: (completed - accepted).max(1L).to_int(),
      utilization_per_mille: 0,
      failed: response.state != Succeeded,
    }
  }
  try provider.invoke(request) catch {
    _ => {
      let completed = @async.now()
      {
        latency_ms: (completed - accepted).to_int(),
        queue_ms: 0,
        load_ms: 0,
        first_output_ms: 0,
        output_units: 0,
        duration_ms: (completed - accepted).max(1L).to_int(),
        utilization_per_mille: 0,
        failed: true,
      }
    }
  } noraise {
    response => {
      let completed = @async.now()
      {
        latency_ms: (completed - accepted).to_int(),
        queue_ms: response.usage.queue_ms.to_int(),
        load_ms: (response.timing.started_unix_ms -
        response.timing.accepted_unix_ms)
        .max(0L)
        .to_int(),
        first_output_ms: (response.timing.first_output_unix_ms -
        response.timing.accepted_unix_ms)
        .max(0L)
        .to_int(),
        output_units: response.usage.output_units,
        duration_ms: (completed - accepted).max(1L).to_int(),
        utilization_per_mille: 0,
        failed: response.state != Succeeded,
      }
    }
  }
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 6 else {
    raise Failure::Failure(
      "usage: lunanexa-benchmark WORKLOAD.json PROFILE KIND ITERATIONS CONCURRENCY",
    )
  }
  let iterations = @string.parse_int64(args[4]).to_int()
  let concurrency = @string.parse_int64(args[5]).to_int()
  if iterations <= 0 || concurrency <= 0 || concurrency > 1024 {
    raise Failure::Failure(
      "iterations and concurrency must be positive and bounded",
    )
  }
  let template = @contracts.decode_workload(@fs.read_file(args[1]).text())
  let kind = benchmark_kind(args[3])
  let templates = if kind == MixedWorkload {
    guard @env.get_env_var("LUNANEXA_MIXED_WORKLOAD_FILES") is Some(files) else {
      raise Failure::Failure(
        "mixed-workload runs require LUNANEXA_MIXED_WORKLOAD_FILES",
      )
    }
    let values = [
      for path in files.split(",") => {
        @contracts.decode_workload(@fs.read_file(path.trim().to_owned()).text())
      }
    ]
    if values.length() < 2 {
      raise Failure::Failure(
        "mixed-workload runs require at least two workload files",
      )
    }
    values
  } else {
    [template]
  }
  let base = environment("LUNANEXA_ENDPOINT")
  let inference_token = environment("LUNANEXA_INFERENCE_TOKEN")
  let samples : Array[@telemetry.BenchmarkSample] = []
  let run_started = @async.now()
  let mut offset = 0
  while offset < iterations {
    let batch = (iterations - offset).min(concurrency)
    @async.with_task_group <| group => {
      let tasks = [
        for index = offset; index < offset + batch; index = index + 1 => {
          group.spawn(() => {
            run_sample(
              base,
              inference_token,
              templates[index % templates.length()],
              kind,
              index,
            )
          })
        }
      ]
      for task in tasks {
        samples.push(task.wait())
      }
    }
    offset += batch
  }
  let now = @async.now()
  let (telemetry_response, telemetry_body) = @http.get(
    endpoint(base, "/v1/telemetry"),
    headers={
      "Authorization": "Bearer \{environment("LUNANEXA_OPERATOR_TOKEN")}",
      "Accept": "application/json",
    },
  )
  let mut peak_utilization = 0
  if telemetry_response.code >= 200 && telemetry_response.code < 300 {
    let snapshot : @telemetry.TelemetrySnapshot = @json.from_json(
      @json.parse(telemetry_body.text()),
    )
    for sample in snapshot.samples {
      if sample.metric == "accelerator_utilization_per_mille" &&
        sample.timestamp_unix_ms >= run_started &&
        sample.timestamp_unix_ms <= now {
        peak_utilization = peak_utilization.max(sample.value.to_int())
      }
    }
  }
  let measured_samples = [
    for sample in samples => {
      { ..sample, utilization_per_mille: peak_utilization }
    }
  ]
  let run : @telemetry.BenchmarkRun = {
    run_id: "benchmark:\{args[2]}:\{now}",
    profile: args[2],
    model_digest: environment("LUNANEXA_MODEL_ARTIFACT_DIGEST"),
    runtime_digest: environment("LUNANEXA_RUNTIME_IMAGE_DIGEST"),
    hardware_profile: environment("LUNANEXA_HARDWARE_PROFILE"),
    kind,
    concurrency,
    samples: measured_samples,
  }
  let (response, body) = @http.post(
    endpoint(base, "/v1/benchmarks"),
    run.to_json(),
    headers={
      "Authorization": "Bearer \{environment("LUNANEXA_OPERATOR_TOKEN")}",
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
  )
  let output = body.text()
  if response.code < 200 || response.code >= 300 {
    raise Failure::Failure(
      "benchmark evidence was rejected with status \{response.code}",
    )
  }
  println(output)
}
