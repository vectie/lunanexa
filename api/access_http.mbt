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
  tools : Array[Json]?
  tool_choice : Json?
  parallel_tool_calls : Bool?
  temperature : Double?
  top_p : Double?
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
  guard bearer_secret(headers) is Some(secret) else { return KeyDenied }
  let now = @async.now()
  match self.access_store {
    Some(store) =>
      try {
        // First validate the credential without consuming quota. Personal API
        // keys remain derivative of the current account, membership, and
        // contract authorities; a stale key must not outlive any of them.
        let preview = match (tenant_ref, model) {
          (Some(tenant), Some(selected_model)) =>
            store.authorize(
              secret,
              scope,
              tenant_ref=tenant,
              model=selected_model,
              now,
              false,
            )
          (Some(tenant), None) =>
            store.authorize(secret, scope, tenant_ref=tenant, now, false)
          (None, Some(selected_model)) =>
            store.authorize(secret, scope, model=selected_model, now, false)
          (None, None) => store.authorize(secret, scope, now, false)
        }
        let account_active = match self.account_store {
          Some(accounts) =>
            accounts
            .views()
            .iter()
            .any(account => {
              account.subject_ref == preview.subject_ref &&
              account.state == Active &&
              @account.role_allows(account.roles, EnterpriseUser)
            })
          None => self.allow_legacy_unbound_access
        }
        let membership_active = match self.portal_store {
          Some(portal) =>
            try {
              let view = portal.self_view_for_organization(
                preview.subject_ref,
                preview.organization_id,
              )
              view.membership.tenant_ref == preview.tenant_ref &&
              view.membership.active &&
              @portal.role_allows(view.membership.roles, Developer)
            } catch {
              _ => false
            }
          None => self.allow_legacy_unbound_access
        }
        let contract_active = match self.contract_document_store {
          Some(contracts) =>
            contracts.has_effective_master_lease(
              preview.tenant_ref,
              preview.subject_ref,
              now,
            )
          None => self.allow_legacy_unbound_access
        }
        let trial_active = match self.account_store {
          Some(accounts) =>
            match accounts.active_trial_for_subject(preview.subject_ref, now) {
              Some(trial) =>
                trial.tenant_ref == preview.tenant_ref &&
                trial.organization_id == preview.organization_id &&
                trial.project_id == preview.project_id &&
                trial.api_key_id == Some(preview.key_id) &&
                model.map_or(true, selected => {
                  trial.allowed_models.contains(selected)
                })
              None => false
            }
          None => false
        }
        if !account_active ||
          !membership_active ||
          (!contract_active && !trial_active) {
          return KeyDenied
        }
        let value = if consume {
          match (tenant_ref, model) {
            (Some(tenant), Some(selected_model)) =>
              store.authorize(
                secret,
                scope,
                tenant_ref=tenant,
                model=selected_model,
                now,
                true,
              )
            (Some(tenant), None) =>
              store.authorize(secret, scope, tenant_ref=tenant, now, true)
            (None, Some(selected_model)) =>
              store.authorize(secret, scope, model=selected_model, now, true)
            (None, None) => store.authorize(secret, scope, now, true)
          }
        } else {
          preview
        }
        return KeyAuthorized(value)
      } catch {
        @access.AccessError::QuotaExceeded => return KeyQuotaExceeded
        _ => ()
      }
    None => ()
  }
  match self.client_handoff_store {
    Some(store) =>
      try {
        let value = match model {
          Some(selected_model) =>
            store.authorize(secret, scope, model=selected_model, now, consume)
          None => store.authorize(secret, scope, now, consume)
        }
        if tenant_ref.map(tenant => tenant != value.tenant_ref).unwrap_or(false) {
          return KeyDenied
        }
        // Desktop credentials are lease capabilities, not independent API
        // keys. Recheck both sources of authority on every request so early
        // termination also blocks model discovery and other non-inference
        // endpoints immediately.
        let workspace_active = match self.workspace_directory {
          Some(directory) =>
            try {
              ignore(
                directory.authorize_subject_for_tenant(
                  value.subject_ref,
                  value.tenant_ref,
                  Developer,
                  now,
                ),
              )
              true
            } catch {
              _ => false
            }
          None => false
        }
        let contract_active = match self.contract_document_store {
          Some(contracts) =>
            contracts.has_effective_master_lease(
              value.tenant_ref,
              value.subject_ref,
              now,
            )
          None => false
        }
        if !workspace_active || !contract_active {
          return KeyDenied
        }
        KeyAuthorized({
          key_id: value.key_id,
          tenant_ref: value.tenant_ref,
          subject_ref: value.subject_ref,
          organization_id: value.organization_id,
          project_id: value.project_id,
        })
      } catch {
        @client_handoff.ClientHandoffError::QuotaExceeded => KeyQuotaExceeded
        _ => KeyDenied
      }
    None => KeyDenied
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
  if !self.operator_authorized(headers) {
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
      // Contract governance is the source of truth for customer access. When
      // the contract store is configured, a key can only be issued for a
      // tenant/subject with a current Effective MasterLease. Keeping the
      // legacy path permissive when the store is absent preserves local
      // bootstrap compatibility; production control always wires the store.
      match self.contract_document_store {
        Some(contract_store) => {
          guard contract_store.has_effective_master_lease(
            intent.tenant_ref,
            intent.subject_ref,
            @async.now(),
          ) else {
            return api_error(
              409, "EffectiveMasterLeaseRequired", "an effective, unexpired MasterLease is required before issuing access",
              false,
            )
          }
        }
        None => ()
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
      json_reply(201, issued.public_view().to_json())
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
          organization_id: header(headers, "x-lunanexa-organization").unwrap_or(
            "default-organization",
          ),
          project_id: header(headers, "x-lunanexa-project").unwrap_or(
            "default-project",
          ),
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
  let canonical = self.invoke_workload(request, authority)
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
  if response.state != Succeeded {
    guard response.error is Some(error) else {
      return api_error(
        502, "InvalidRuntimeResponse", "failed workload omitted its public error",
        true,
      )
    }
    let (status, code) = match error.code {
      InvalidRequest => (400, "InvalidRequest")
      Unauthenticated => (401, "Unauthenticated")
      Unauthorized => (403, "Unauthorized")
      QuotaExceeded => (429, "QuotaExceeded")
      DeadlineExceeded => (504, "DeadlineExceeded")
      NoPlacement => (503, "NoPlacement")
      RuntimeUnavailable => (502, "RuntimeUnavailable")
      CancelledByCaller => (409, "CancelledByCaller")
      Internal => (500, "Internal")
    }
    return api_error(status, code, error.message, error.retryable)
  }
  if response.error is Some(_) || response.output is None {
    return api_error(
      502, "InvalidRuntimeResponse", "successful workload omitted output or retained an error",
      true,
    )
  }
  let (content, tool_calls) = openai_chat_message_from_runtime(response.output)
  let message : Map[String, Json] = {
    "role": Json::string("assistant"),
    "content": Json::string(content),
  }
  if !tool_calls.is_empty() {
    message["tool_calls"] = Json::array(tool_calls)
  }
  json_reply(200, {
    "id": "chatcmpl-\{request_digest[:32]}",
    "object": "chat.completion",
    "created": (now / 1000L).to_json(),
    "model": value.model,
    "choices": [
      {
        "index": 0,
        "message": Json::object(message),
        "finish_reason": if tool_calls.is_empty() {
          "stop"
        } else {
          "tool_calls"
        },
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
fn openai_chat_message_from_runtime(output : Json?) -> (String, Array[Json]) {
  guard output is Some(value) else { return ("", []) }
  guard value is Object(fields) else {
    return (
      match value {
        String(text) => text
        _ => value.stringify()
      },
      [],
    )
  }
  let mut content = match fields.get("output_text") {
    Some(String(text)) => text
    _ => ""
  }
  let tool_calls : Array[Json] = []
  if fields.get("chunks") is Some(Array(chunks)) {
    if content == "" {
      for chunk in chunks {
        if chunk is Object(chunk_fields) &&
          chunk_fields.get("text_delta") is Some(String(text)) {
          content += text
        }
      }
    }
    return (content, tool_calls)
  }
  guard fields.get("output") is Some(Array(items)) else {
    if content == "" {
      content = value.stringify()
    }
    return (content, tool_calls)
  }
  for item in items {
    guard item is Object(item_fields) else { continue }
    match item_fields.get("type") {
      Some(String("message")) =>
        if item_fields.get("content") is Some(Array(parts)) {
          for part in parts {
            if part is Object(part_fields) {
              match part_fields.get("text") {
                Some(String(text)) => content += text
                _ => ()
              }
            }
          }
        }
      Some(String("function_call")) => {
        let name = match item_fields.get("name") {
          Some(String(value)) => value
          _ => ""
        }
        let arguments = match item_fields.get("arguments") {
          Some(String(value)) => value
          Some(value) => value.stringify()
          None => ""
        }
        if name != "" {
          let call_id = match item_fields.get("call_id") {
            Some(String(value)) => value
            _ =>
              match item_fields.get("id") {
                Some(String(value)) => value
                _ => "call-lunanexa-\{tool_calls.length()}"
              }
          }
          tool_calls.push({
            "id": call_id,
            "type": "function",
            "function": { "name": name, "arguments": arguments },
          })
        }
      }
      _ => ()
    }
  }
  (content, tool_calls)
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
  let payload_fields : Map[String, Json] = {
    "messages": value.messages.to_json(),
  }
  if value.tools is Some(tools) {
    payload_fields["tools"] = tools.to_json()
  }
  if value.tool_choice is Some(tool_choice) {
    payload_fields["tool_choice"] = tool_choice
  }
  if value.parallel_tool_calls is Some(parallel_tool_calls) {
    payload_fields["parallel_tool_calls"] = parallel_tool_calls.to_json()
  }
  if value.temperature is Some(temperature) {
    payload_fields["temperature"] = temperature.to_json()
  }
  if value.top_p is Some(top_p) {
    payload_fields["top_p"] = top_p.to_json()
  }
  let payload = Json::object(payload_fields)
  let input_units = @utf8.encode(payload.stringify())
    .length()
    .clamp(min=1, max=budgets.openai_max_input_units)
  let request : @contracts.WorkloadEnvelope = {
    version: @contracts.contract_version,
    idempotency_key: idempotency,
    workload_id,
    tenant_ref: authority.tenant_ref,
    credential_scope: "api-key:\{authority.key_id}",
    capability: TextGenerate,
    model_selector: value.model,
    payload,
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
      max_input_units: input_units,
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
    "tools": value.tools.to_json(),
    "tool_choice": value.tool_choice.to_json(),
    "parallel_tool_calls": value.parallel_tool_calls.to_json(),
    "temperature": value.temperature.to_json(),
    "top_p": value.top_p.to_json(),
  }
  identity.stringify()
}
