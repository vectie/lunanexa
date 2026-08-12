///|
fn header_value(headers : Map[String, String], name : String) -> String? {
  for key, value in headers {
    if key.to_lower() == name.to_lower() {
      return Some(value)
    }
  }
  None
}

///|
fn identity_signature(
  pathname : String,
  actor_ref : String,
  role : String,
  now_unix_ms : Int64,
  secret : String,
) -> String {
  let payload = "GET\n\{pathname}\n\{actor_ref}\n\{role}\n\{now_unix_ms}"
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(payload).view(),
    ),
  )
}

///|
fn diagnostic_headers(
  config : GuideProbeConfig,
  plan : @guide_monitor.GuideProbePlan,
  identity_secret : String,
  now_unix_ms : Int64,
) -> Map[String, String] {
  let pathname = "/api/coursebook/admin/diagnostics"
  {
    "Accept": "application/json",
    "X-LunaNexa-Actor": config.actor_ref,
    "X-LunaNexa-Role": config.role,
    "X-LunaNexa-Auth-Timestamp": now_unix_ms.to_string(),
    "X-LunaNexa-Auth-Signature": identity_signature(
      pathname,
      config.actor_ref,
      config.role,
      now_unix_ms,
      identity_secret,
    ),
    "X-LunaNexa-Correlation-Id": plan.correlation_receipt,
  }
}

///|
async fn[T : FromJson] bounded_json_get(
  config : GuideProbeConfig,
  path : String,
  headers : Map[String, String],
) -> T {
  let read = async fn() {
    let (response, stream) = @http.get_stream(
      "\{config.origin}\{path}",
      headers~,
    ) catch {
      _ => raise TransportUnavailable
    }
    defer stream.close()
    if response.code >= 300 && response.code < 400 {
      raise RedirectRejected
    }
    if response.code != 200 {
      raise TransportUnavailable
    }
    match header_value(response.headers, "content-type") {
      Some(value) if value.to_lower().has_prefix("application/json") => ()
      _ => raise MalformedResponse
    }
    let buffer = @buffer.Buffer(
      size_hint=config.maximum_response_bytes.min(65536),
    )
    for total = 0 {
      let remaining = config.maximum_response_bytes - total + 1
      match stream.read_some(max_len=remaining.min(65536)) {
        None => break
        Some(chunk) => {
          let next = total + chunk.length()
          if next > config.maximum_response_bytes {
            raise ResponseTooLarge
          }
          buffer.write_bytes(chunk)
          continue next
        }
      }
    }
    let text = @utf8.decode(buffer.to_bytes()) catch {
      _ => raise MalformedResponse
    }
    @json.from_json(@json.parse(text)) catch {
      _ => raise MalformedResponse
    }
  }
  @async.with_timeout(
    config.request_timeout_ms,
    read,
    error=GuideProbeError::TransportUnavailable,
  )
}

///|
fn validate_health(health : HealthEnvelope) -> Unit raise GuideProbeError {
  if health.dependencies.admin_diagnostics.enabled is None {
    raise UntrustedResponse
  }
}

///|
fn observation_from_projection(
  policy : @guide_monitor.GuideMonitorPolicy,
  plan : @guide_monitor.GuideProbePlan,
  health : HealthEnvelope,
  envelope : DiagnosticsEnvelope,
  observation_secret : String,
  now_unix_ms : Int64,
) -> @guide_monitor.GuideHealthObservation raise GuideProbeError {
  validate_health(health)
  let generated_unix_ms = envelope.diagnostics.generated_unix_ms.to_int64()
  let knowledge_age_ms = envelope.diagnostics.knowledge.age_ms.to_int64()
  if !envelope.ok ||
    envelope.category != "overview" ||
    envelope.correlation_receipt != plan.correlation_receipt ||
    envelope.diagnostics.contract_version != "lunanexa.guide-diagnostics.v1" ||
    envelope.diagnostics.generated_unix_ms != generated_unix_ms.to_double() ||
    envelope.diagnostics.knowledge.age_ms != knowledge_age_ms.to_double() ||
    generated_unix_ms < plan.scheduled_unix_ms ||
    generated_unix_ms > now_unix_ms + policy.future_skew_ms ||
    !@contracts.valid_identifier(
      envelope.diagnostics.knowledge.revision,
      maximum_length=128,
    ) ||
    knowledge_age_ms < 0L ||
    knowledge_age_ms > 315360000000L {
    raise UntrustedResponse
  }
  @guide_monitor.sign_observation(
    {
      version: @guide_monitor.contract_version,
      observation_id: "guide-observation-\{plan.correlation_receipt}",
      target_ref: plan.target_ref,
      correlation_receipt: plan.correlation_receipt,
      scheduled_unix_ms: plan.scheduled_unix_ms,
      observed_unix_ms: generated_unix_ms,
      coursebook_ok: health.ok && health.dependencies.coursebook.ok,
      admin_diagnostics_enabled: health.dependencies.admin_diagnostics.enabled.unwrap(),
      admin_diagnostics_ok: health.dependencies.admin_diagnostics.ok,
      knowledge_revision: envelope.diagnostics.knowledge.revision,
      knowledge_stale: envelope.diagnostics.knowledge.stale,
      knowledge_age_ms,
      signature: "",
    },
    observation_secret,
  )
}

///|
async fn fetch_observation(
  config : GuideProbeConfig,
  policy : @guide_monitor.GuideMonitorPolicy,
  plan : @guide_monitor.GuideProbePlan,
  identity_secret : String,
  observation_secret : String,
  now_unix_ms : Int64,
) -> @guide_monitor.GuideHealthObservation {
  let health : HealthEnvelope = bounded_json_get(config, plan.health_path, {
    "Accept": "application/json",
  })
  let diagnostics : DiagnosticsEnvelope = bounded_json_get(
    config,
    plan.diagnostics_path,
    diagnostic_headers(config, plan, identity_secret, now_unix_ms),
  )
  observation_from_projection(
    policy, plan, health, diagnostics, observation_secret, now_unix_ms,
  )
}
