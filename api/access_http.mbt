///|
fn access_management_path(path : String) -> Bool {
  path == "/v1/access/api-keys" || path.has_prefix("/v1/access/api-keys/")
}

///|
fn openai_compatibility_path(path : String) -> Bool {
  path == "/v1/models" || path == "/v1/chat/completions"
}

///|
priv struct OpenAiChatRequest {
  model : String
  messages : Array[Json]
  stream : Bool?
  max_tokens : Int?
} derive(FromJson)

///|
fn decode_openai_chat(body : String) -> OpenAiChatRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn valid_openai_request_budget(
  value : OpenAiChatRequest,
  budgets : @settings.RequestBudgetSettings,
) -> Bool {
  match value.max_tokens {
    None => true
    Some(units) => units > 0 && units <= budgets.openai_max_output_units
  }
}

///|
fn decode_api_key_intent(body : String) -> @access.ApiKeyIssueIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn bearer_secret(headers : Map[String, String]) -> String? {
  guard header(headers, "authorization") is Some(value) &&
    value.has_prefix("Bearer ") else {
    return None
  }
  let secret = value["Bearer ".length():].to_owned()
  if secret == "" ||
    secret.length() > 4096 ||
    !secret.all(character => character >= '!' && character <= '~') {
    None
  } else {
    Some(secret)
  }
}

///|
async fn ApiService::api_key_authorization(
  self : ApiService,
  headers : Map[String, String],
  scope : @access.ApiKeyScope,
  tenant_ref? : String,
  model? : String,
  consume : Bool,
) -> @access.ApiAuthorization? {
  match self.api_key_check(headers, scope, tenant_ref, model, consume) {
    KeyAuthorized(value) => Some(value)
    KeyQuotaExceeded | KeyDenied => None
  }
}

///|
priv enum ApiKeyCheck {
  KeyAuthorized(@access.ApiAuthorization)
  KeyQuotaExceeded
  KeyDenied
}

///|
async fn ApiService::api_key_check(
  self : ApiService,
  headers : Map[String, String],
  scope : @access.ApiKeyScope,
  tenant_ref : String?,
  model : String?,
  consume : Bool,
) -> ApiKeyCheck {
  guard self.access_store is Some(store) &&
    bearer_secret(headers) is Some(secret) else {
    return KeyDenied
  }
  try {
    match (tenant_ref, model) {
      (Some(tenant), Some(selected_model)) =>
        store.authorize(
          secret,
          scope,
          tenant_ref=tenant,
          model=selected_model,
          @async.now(),
          consume,
        )
      (Some(tenant), None) =>
        store.authorize(secret, scope, tenant_ref=tenant, @async.now(), consume)
      (None, Some(selected_model)) =>
        store.authorize(
          secret,
          scope,
          model=selected_model,
          @async.now(),
          consume,
        )
      (None, None) => store.authorize(secret, scope, @async.now(), consume)
    }
  } catch {
    @access.AccessError::QuotaExceeded => KeyQuotaExceeded
    _ => KeyDenied
  } noraise {
    value => KeyAuthorized(value)
  }
}

///|
async fn ApiService::handle_access_management(
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
  guard self.access_store is Some(store) else {
    return api_error(
      503, "AccessStoreUnavailable", "durable API credential state is unavailable",
      true,
    )
  }
  match (verb, path) {
    (Get, "/v1/access/api-keys") => json_reply(200, store.views().to_json())
    (Post, "/v1/access/api-keys") => {
      guard decode_api_key_intent(body) is Some(intent) else {
        return api_error(400, "InvalidRequest", "invalid API key intent", false)
      }
      let issued = try store.issue(intent, @async.now()) catch {
        @access.AccessError::AlreadyExists(_) =>
          return api_error(
            409, "AlreadyExists", "API key identity already exists", false,
          )
        _ =>
          return api_error(
            400, "ApiKeyRejected", "API key intent was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "access.api-key.issue",
        issued.credential.key_id,
        "api-key:issued",
      )
      json_reply(201, issued.to_json())
    }
    (Post, _) if path.has_suffix(":revoke") => {
      let prefix = "/v1/access/api-keys/".length()
      let suffix = ":revoke".length()
      if path.length() <= prefix + suffix {
        return api_error(404, "NotFound", "route was not found", false)
      }
      let key_id = path[prefix:path.length() - suffix].to_owned()
      let revoked = try store.revoke(key_id, @async.now()) catch {
        _ => return api_error(404, "NotFound", "API key was not found", false)
      } noraise {
        value => value
      }
      self.operator_audit("access.api-key.revoke", key_id, "api-key:revoked")
      json_reply(200, {
        "key_id": revoked.key_id,
        "revoked_unix_ms": revoked.revoked_unix_ms.to_json(),
      })
    }
    _ => api_error(404, "NotFound", "access route was not found", false)
  }
}

///|
async fn ApiService::handle_openai_compatibility(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  match (verb, path) {
    (Get, "/v1/models") => {
      if !bearer_authorized(headers, self.inference_token) &&
        self.api_key_authorization(headers, ModelList, false) is None {
        return api_error(
          401, "Unauthenticated", "valid model-list authority is required", false,
        )
      }
      let aliases = match self.registry {
        Some(registry) => registry.snapshot().aliases
        None => []
      }
      json_reply(200, {
        "object": "list",
        "data": aliases
        .map(value => {
          "id": value.name,
          "object": "model",
          "owned_by": "lunanexa",
        })
        .to_json(),
      })
    }
    (Post, "/v1/chat/completions") => {
      guard decode_openai_chat(body) is Some(value) &&
        @contracts.valid_identifier(value.model) &&
        value.messages.length() > 0 &&
        value.messages.length() <= 256 &&
        valid_openai_request_budget(value, self.global_settings.request_budgets) else {
        return api_error(
          400, "InvalidRequest", "invalid OpenAI-compatible chat request", false,
        )
      }
      if value.stream.unwrap_or(false) {
        return api_error(
          400, "StreamingRequiresCanonicalEndpoint", "use the canonical LunaNexa streaming workload endpoint for verified SSE receipts",
          false,
        )
      }
      let key_check = self.api_key_check(
        headers,
        Inference,
        None,
        Some(value.model),
        true,
      )
      if key_check is KeyQuotaExceeded {
        return api_error(
          429, "QuotaExceeded", "API key request quota is exhausted", false,
        )
      }
      guard key_check is KeyAuthorized(authority) else {
        if !bearer_authorized(headers, self.inference_token) {
          return api_error(
            401, "Unauthenticated", "valid scoped inference API key is required",
            false,
          )
        }
        let static_authority : @access.ApiAuthorization = {
          key_id: "static-inference-authority",
          tenant_ref: header(headers, "x-lunanexa-tenant").unwrap_or(
            "default-tenant",
          ),
          subject_ref: "static-inference-subject",
        }
        return self.invoke_openai_chat(value, static_authority, headers)
      }
      self.invoke_openai_chat(value, authority, headers)
    }
    _ =>
      api_error(
        404, "NotFound", "OpenAI compatibility route was not found", false,
      )
  }
}

///|
async fn ApiService::invoke_openai_chat(
  self : ApiService,
  value : OpenAiChatRequest,
  authority : @access.ApiAuthorization,
  headers : Map[String, String],
) -> HttpReply {
  let now = @async.now()
  let (request, request_digest) = openai_workload(
    value,
    authority,
    headers,
    false,
    now,
    self.global_settings.request_budgets,
  )
  @contracts.validate_workload(request) catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "chat request violates the canonical workload contract",
        false,
      )
  }
  let workspace_headers = headers.copy()
  workspace_headers["X-LunaNexa-Subject"] = authority.subject_ref
  let (workspace_error, reserved) = self.workspace_admit(
    workspace_headers, request, true,
  )
  if workspace_error is Some(reply) {
    return reply
  }
  let canonical = self.invoke_workload(request)
  self.release_workspace_admission(request, reserved)
  if canonical.status < 200 || canonical.status >= 300 {
    return canonical
  }
  let response : @contracts.WorkloadResponse = @json.from_json(
    @json.parse(canonical.body),
  ) catch {
    _ =>
      return api_error(
        502, "InvalidRuntimeResponse", "runtime response could not be normalized",
        true,
      )
  }
  let content = match response.output {
    Some(String(value)) => value
    Some(value) => value.stringify()
    None => ""
  }
  json_reply(200, {
    "id": "chatcmpl-\{request_digest[:32]}",
    "object": "chat.completion",
    "created": (now / 1000L).to_json(),
    "model": value.model,
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": content },
        "finish_reason": "stop",
      },
    ],
    "usage": {
      "prompt_tokens": response.usage.input_units,
      "completion_tokens": response.usage.output_units,
      "total_tokens": response.usage.input_units + response.usage.output_units,
    },
    "lunanexa_receipt": response.audit_receipt,
  })
}

///|
fn openai_workload(
  value : OpenAiChatRequest,
  authority : @access.ApiAuthorization,
  headers : Map[String, String],
  stream : Bool,
  now : Int64,
  budgets : @settings.RequestBudgetSettings,
) -> (@contracts.WorkloadEnvelope, String) {
  let request_digest = digest_hex("\{body_identity(value)}|\{now}")
  let requested_output = value.max_tokens
    .unwrap_or(budgets.openai_default_output_units)
    .clamp(min=1, max=budgets.openai_max_output_units)
  let idempotency = header(headers, "idempotency-key").unwrap_or(
    "openai-\{request_digest[:32]}",
  )
  let workload_id = "openai-\{request_digest[32:64]}"
  let request : @contracts.WorkloadEnvelope = {
    version: @contracts.contract_version,
    idempotency_key: idempotency,
    workload_id,
    tenant_ref: authority.tenant_ref,
    credential_scope: "api-key:\{authority.key_id}",
    capability: TextGenerate,
    model_selector: value.model,
    payload: { "messages": value.messages.to_json() },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: now + budgets.openai_default_deadline_ms,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: budgets.openai_max_input_units,
      max_output_units: requested_output,
      max_runtime_ms: budgets.openai_default_deadline_ms,
      max_accelerator_memory_mib: budgets.openai_max_accelerator_memory_mib,
    },
    stream,
    output_format: "openai.chat.completion",
    trace_token: "trace-\{request_digest[:32]}",
  }
  (request, request_digest)
}

///|
fn body_identity(value : OpenAiChatRequest) -> String {
  let identity : Json = {
    "model": value.model,
    "messages": value.messages.to_json(),
    "max_tokens": value.max_tokens.to_json(),
  }
  identity.stringify()
}
