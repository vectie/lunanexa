///|
fn technical_management_path(path : String) -> Bool {
  path.has_prefix("/v1/technical/")
}

///|
priv struct PrewarmBeginRequest {
  intent : @technical.PrewarmIntent
  now_unix_ms : Int64
} derive(FromJson)

///|
priv struct PrewarmAdvanceRequest {
  operation : @technical.PrewarmOperation
  event : @technical.PrewarmEvent
  now_unix_ms : Int64
} derive(FromJson)

///|
priv struct ProbeEvaluationRequest {
  state : @technical.ProbeState
  observation : @technical.ProbeObservation
  policy : @technical.ProbePolicy
} derive(FromJson)

///|
priv struct CacheEvaluationRequest {
  telemetry : @technical.CacheEntryTelemetry
  now_unix_ms : Int64
  high_water_bytes : Int64
} derive(FromJson)

///|
priv struct AutoscaleEvaluationRequest {
  policy : @technical.AutoscalePolicy
  snapshot : @technical.AutoscaleSnapshot
} derive(FromJson)

///|
priv struct BackpressureEvaluationRequest {
  limits : @technical.AdmissionLimits
  snapshot : @technical.AdmissionSnapshot
} derive(FromJson)

///|
priv struct TransferGrantValidationRequest {
  grant : @technical.TransferGrant
  grant_use : @technical.TransferGrantUse
  authenticity : @technical.GrantAuthenticity
  consumed_nonces : Array[String]
  now_unix_ms : Int64
  maximum_clock_skew_ms : Int64
} derive(FromJson)

///|
priv struct SidecarSelectionRequest {
  requests : Array[@technical.SidecarRequest]
  allowed : Array[@technical.ReviewedSidecar]
} derive(FromJson)

///|
fn decode_prewarm_begin(body : String) -> PrewarmBeginRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_prewarm_advance(body : String) -> PrewarmAdvanceRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_probe_evaluation(body : String) -> ProbeEvaluationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_cache_evaluation(body : String) -> CacheEvaluationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_autoscale_evaluation(body : String) -> AutoscaleEvaluationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_backpressure_evaluation(
  body : String,
) -> BackpressureEvaluationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_transfer_grant_validation(
  body : String,
) -> TransferGrantValidationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_sidecar_selection(body : String) -> SidecarSelectionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
async fn ApiService::handle_technical_management(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !bearer_authorized(headers, self.operator_token) {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  match (verb, path) {
    (Post, "/v1/technical/prewarm:begin") => {
      guard decode_prewarm_begin(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid prewarm intent", false)
      }
      let decision = match self.technical_store {
        Some(store) => store.begin_prewarm(value.intent, value.now_unix_ms)
        None => @technical.begin_prewarm(value.intent, value.now_unix_ms)
      }
      json_reply(200, decision.to_json())
    }
    (Post, "/v1/technical/prewarm:advance") => {
      guard decode_prewarm_advance(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid prewarm event", false)
      }
      let decision = try {
        match self.technical_store {
          Some(store) =>
            store.advance_prewarm(
              value.operation,
              value.event,
              value.now_unix_ms,
            )
          None =>
            @technical.advance_prewarm(
              value.operation,
              value.event,
              value.now_unix_ms,
            )
        }
      } catch {
        _ =>
          return api_error(
            409, "TechnicalOperationConflict", "prewarm operation is stale or conflicts with durable state",
            false,
          )
      } noraise {
        accepted => accepted
      }
      json_reply(200, decision.to_json())
    }
    (Post, "/v1/technical/probes:evaluate") => {
      guard decode_probe_evaluation(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid probe evaluation", false,
        )
      }
      json_reply(
        200,
        @technical.evaluate_probe(value.state, value.observation, value.policy).to_json(),
      )
    }
    (Post, "/v1/technical/cache:evaluate") => {
      guard decode_cache_evaluation(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid cache telemetry", false,
        )
      }
      let findings = @technical.validate_cache_telemetry(value.telemetry)
      let action = @technical.cache_reconcile_action(
        value.telemetry,
        value.now_unix_ms,
        value.high_water_bytes,
      )
      json_reply(200, {
        "findings": findings.to_json(),
        "action": action.to_json(),
      })
    }
    (Post, "/v1/technical/autoscale:decide") => {
      guard decode_autoscale_evaluation(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid autoscale input", false,
        )
      }
      let decision = @technical.decide_autoscale(value.policy, value.snapshot)
      if self.technical_store is Some(_) {
        let target = match decision {
          ScaleUp(target_replicas~, ..) | ScaleDown(target_replicas~, ..) =>
            Some(target_replicas)
          Hold(..) => None
        }
        if target is Some(replicas) {
          let identity = digest_hex(
            "autoscale|\{value.snapshot.deployment_id}|\{value.policy.policy_version}|\{value.snapshot.observed_lease_generation}|\{value.snapshot.newest_sample_unix_ms}|\{replicas}",
          )
          let execution = self.scale_service_deployment(
            value.snapshot.deployment_id,
            { replicas, idempotency_key: "autoscale-\{identity[:48]}" },
          )
          if execution.status < 200 || execution.status >= 300 {
            return api_error(
              409, "AutoscaleExecutionRejected", "autoscale decision could not pass the deployment generation and capacity fence",
              true,
            )
          }
          return json_reply(200, {
            "decision": decision.to_json(),
            "execution": @json.parse(execution.body),
          })
        }
      }
      json_reply(200, decision.to_json())
    }
    (Post, "/v1/technical/backpressure:decide") => {
      guard decode_backpressure_evaluation(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid admission input", false,
        )
      }
      json_reply(
        200,
        @technical.decide_admission(value.limits, value.snapshot).to_json(),
      )
    }
    (Post, "/v1/technical/transfer-grants:validate") => {
      guard decode_transfer_grant_validation(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid transfer grant", false)
      }
      let decision = try {
        match self.technical_store {
          Some(store) =>
            store.validate_and_consume_transfer(
              value.grant,
              value.grant_use,
              value.authenticity,
              value.now_unix_ms,
              value.maximum_clock_skew_ms,
            )
          None =>
            @technical.validate_transfer_grant(
              value.grant,
              value.grant_use,
              value.authenticity,
              value.consumed_nonces,
              value.now_unix_ms,
              value.maximum_clock_skew_ms,
            )
        }
      } catch {
        _ =>
          return api_error(
            503, "TechnicalPersistenceFailed", "transfer grant was not consumed because durable replay state failed",
            true,
          )
      } noraise {
        accepted => accepted
      }
      json_reply(200, decision.to_json())
    }
    (Post, "/v1/technical/sidecars:select") => {
      guard decode_sidecar_selection(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid sidecar selection", false,
        )
      }
      json_reply(
        200,
        @technical.select_sidecar_profiles(value.requests, value.allowed).to_json(),
      )
    }
    _ => api_error(404, "NotFound", "technical route was not found", false)
  }
}
