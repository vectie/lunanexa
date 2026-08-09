///|
priv struct RequestResult {
  output_text : String?
  receipt : String
  usage : @contracts.Usage
}

///|
priv struct ClientPublicError {
  status : Int
  code : String
  message : String
  retryable : Bool
} derive(FromJson)

///|
priv struct ClientErrorEnvelope {
  public_error : ClientPublicError
} derive(FromJson)

///|
suberror WorkbenchClientError {
  PublicRejected(String, String, String, Bool, Bool)
  InvalidPublicResponse
}

///|
priv enum PublicFailureKind {
  PublicDetail(String, String, Bool)
  WorkspaceLoadUnavailable
  WorkloadResponseInvalid
}

///|
priv enum ClientOutcome {
  WorkspaceLoaded(@workspace.WorkspaceSelfContract)
  RequestCompleted(RequestResult)
  PublicFailure(PublicFailureKind, String, Bool)
  ClockAdvanced(Int64, Int64)
}

///|
priv struct AppModel {
  endpoint : String
  scoped_token : String
  subject_ref : String
  connecting : Bool
  clock_generation : Int64
  workbench : @workbench_ui.WorkbenchState
} derive(Eq)

///|
priv enum AppMessage {
  EndpointChanged(String)
  TokenChanged(String)
  SubjectChanged(String)
  Connect
  Workbench(@workbench_ui.WorkbenchMessage)
  Outcome(ClientOutcome)
}

///|
fn app_copy(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn workbench_title(locale : @i18n.Locale) -> String {
  app_copy(locale, "LunaNexa Workbench", "LunaNexa 开发者工作台")
}

///|
extern "js" fn stored_locale() -> String =
  #| () => {
  #|   try {
  #|     const value = globalThis.localStorage?.getItem("lunanexa.locale");
  #|     return typeof value === "string" ? value : "";
  #|   } catch (_) {
  #|     return "";
  #|   }
  #| }

///|
extern "js" fn persist_locale(value : String) -> Unit =
  #| value => {
  #|   try {
  #|     globalThis.localStorage?.setItem("lunanexa.locale", value);
  #|   } catch (_) {}
  #| }

///|
extern "js" fn apply_document_locale(tag : String, title : String) -> Unit =
  #| (tag, title) => {
  #|   try {
  #|     if (globalThis.document?.documentElement) {
  #|       globalThis.document.documentElement.lang = tag;
  #|     }
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
fn sync_document_locale(locale : @i18n.Locale) -> Unit {
  apply_document_locale(locale.language_tag(), workbench_title(locale))
}

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || globalThis.location?.origin || ""

///|
extern "js" fn endpoint_is_safe(value : String) -> Bool =
  #| value => {
  #|   try {
  #|     const url = new URL(value);
  #|     const loopback = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "::1" || url.hostname === "[::1]";
  #|     return !url.username && !url.password && !url.search && !url.hash &&
  #|       (url.pathname === "" || url.pathname === "/") &&
  #|       (url.protocol === "https:" || (url.protocol === "http:" && loopback));
  #|   } catch (_) {
  #|     return false;
  #|   }
  #| }

///|
fn optional_subject_is_valid(value : String) -> Bool {
  let subject_ref = value.trim().to_owned()
  subject_ref == "" || @workspace.valid_identifier(subject_ref)
}

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn lease_clock_promise(expires_unix_ms : Int64) -> @js.Promise =
  #| expires => new Promise(resolve => {
  #|   const remaining = expires - BigInt(Date.now());
  #|   const delay = remaining <= 0n ? 0 : Number(remaining > 60000n ? 60000n : remaining);
  #|   setTimeout(() => resolve(BigInt(Date.now())), delay);
  #| })

///|
extern "js" fn random_identifier(prefix : String) -> String =
  #| prefix => `${prefix}-${crypto.randomUUID()}`

///|
extern "js" fn request_promise(
  verb : String,
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (verb, url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "application/json",
  #|     "Content-Type": "application/json",
  #|     "Authorization": `Bearer ${token}`
  #|   };
  #|   if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|   const response = await fetch(url, {
  #|     method: verb,
  #|     headers,
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body: verb === "GET" ? undefined : body
  #|   });
  #|   const text = await response.text();
  #|   if (text.length > 1048576) throw new Error("response limit");
  #|   if (!response.ok) throw new Error("request rejected");
  #|   return text;
  #| }

///|
extern "js" fn workload_promise(
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "application/json",
  #|     "Content-Type": "application/json",
  #|     "Authorization": "Bearer " + token
  #|   };
  #|   if (subject) headers["X-LunaNexa-Subject"] = subject;
  #|   const response = await fetch(url, {
  #|     method: "POST",
  #|     headers,
  #|     credentials: "same-origin",
  #|     cache: "no-store",
  #|     redirect: "error",
  #|     body
  #|   });
  #|   const text = await response.text();
  #|   if (text.length > 1048576) throw new Error("response limit");
  #|   if (response.ok) return text;
  #|   let parsed = {};
  #|   try { parsed = JSON.parse(text); } catch (_) {}
  #|   const source = parsed && typeof parsed.error === "object" ? parsed.error : {};
  #|   const code = typeof source.code === "string" && source.code.length <= 64
  #|     ? source.code : "RequestRejected";
  #|   const message = typeof source.message === "string" && source.message.length <= 256
  #|     ? source.message : "";
  #|   const retryable = source.retryable === true;
  #|   return JSON.stringify({
  #|     public_error: {
  #|       status: response.status,
  #|       code,
  #|       message,
  #|       retryable
  #|     }
  #|   });
  #| }

///|
async fn request(
  verb : String,
  endpoint : String,
  path : String,
  token : String,
  subject_ref : String,
  body? : String = "",
) -> String {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = request_promise(verb, "\{base}\{path}", token, subject_ref, body).wait()
  value.cast()
}

///|
async fn workload_request(
  endpoint : String,
  token : String,
  subject_ref : String,
  body : String,
) -> String {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = workload_promise("\{base}/v1/workloads", token, subject_ref, body).wait()
  value.cast()
}

///|
async fn load_workspace(
  endpoint : String,
  token : String,
  subject_ref : String,
) -> @workspace.WorkspaceSelfContract {
  let self_text = request(
    "GET", endpoint, "/v1/workspace/self", token, subject_ref,
  )
  let self_contract : @workspace.WorkspaceSelfContract = @json.from_json(
    @json.parse(self_text),
  )
  self_contract
}

///|
fn state_from_workspace(
  current : @workbench_ui.WorkbenchState,
  contract : @workspace.WorkspaceSelfContract,
) -> @workbench_ui.WorkbenchState {
  let lease = contract.active_lease
  let ready = contract.authorized && contract.readiness == WorkspaceReady
  let text_ready = match lease {
    Some(value) => @workspace.capability_limit(value, TextGenerate) is Some(_)
    None => false
  }
  let selector = if current.model_selector == "" {
    "text.default"
  } else {
    current.model_selector
  }
  let request_limit = match lease {
    Some(value) =>
      match @workspace.capability_limit(value, TextGenerate) {
        Some(limit) => limit.max_requests_per_hour
        None => 0
      }
    None => 0
  }
  {
    ..current,
    lease,
    now_unix_ms: current_unix_ms(),
    model_selector: selector,
    usage: { ..current.usage, requests_limit: request_limit },
    loading: false,
    success_message: if ready && text_ready {
      Some(
        app_copy(
          current.locale,
          "Scoped workspace authorization loaded.",
          "已加载限定范围的工作区访问权限。",
        ),
      )
    } else {
      None
    },
    error_message: if ready && text_ready {
      None
    } else {
      Some(
        app_copy(
          current.locale,
          "This subject has no ready text-generation lease.",
          "此主体没有已就绪的文本生成租约。",
        ),
      )
    },
  }
}

///|
fn workbench_at(
  state : @workbench_ui.WorkbenchState,
  now_unix_ms : Int64,
) -> @workbench_ui.WorkbenchState {
  let advanced = { ..state, now_unix_ms, }
  if @workbench_ui.lease_ready(state) && !@workbench_ui.lease_ready(advanced) {
    {
      ..advanced,
      success_message: None,
      error_message: Some(
        app_copy(
          state.locale,
          "The workspace lease is no longer active. Connect again after an administrator renews or replaces it.",
          "工作区租约已不再有效。请在管理员续订或替换租约后重新连接。",
        ),
      ),
    }
  } else {
    advanced
  }
}

///|
fn update_workbench_at(
  state : @workbench_ui.WorkbenchState,
  message : @workbench_ui.WorkbenchMessage,
  now_unix_ms : Int64,
) -> @workbench_ui.WorkbenchState {
  workbench_at(state, now_unix_ms).update(message)
}

///|
fn advance_clock_if_current(
  state : @workbench_ui.WorkbenchState,
  current_generation : Int64,
  tick_generation : Int64,
  now_unix_ms : Int64,
) -> @workbench_ui.WorkbenchState? {
  if current_generation == tick_generation {
    Some(workbench_at(state, now_unix_ms))
  } else {
    None
  }
}

///|
fn error_invalidates_authorization(code : @contracts.ErrorCode) -> Bool {
  code == Unauthenticated || code == Unauthorized
}

///|
fn http_error_invalidates_authorization(status : Int, code : String) -> Bool {
  status == 401 ||
  status == 403 ||
  code == "Unauthenticated" ||
  code == "Unauthorized" ||
  code == "AccessDenied" ||
  code == "WorkspaceAccessDenied"
}

///|
fn state_after_public_failure(
  state : @workbench_ui.WorkbenchState,
  message : String,
  receipt : String,
  authorization_stale : Bool,
  now_unix_ms : Int64,
) -> @workbench_ui.WorkbenchState {
  {
    ..state,
    lease: if authorization_stale {
      None
    } else {
      state.lease
    },
    now_unix_ms,
    receipt,
    loading: false,
    success_message: None,
    error_message: Some(
      if authorization_stale {
        "\{message} \{app_copy(state.locale, "Workspace authorization was invalidated; connect again before sending another request.", "工作区访问权限已失效；请重新连接后再发送请求。")}"
      } else {
        message
      },
    ),
  }
}

///|
fn public_failure_message(
  locale : @i18n.Locale,
  kind : PublicFailureKind,
) -> String {
  match kind {
    WorkspaceLoadUnavailable =>
      app_copy(
        locale, "The workspace could not be loaded. Check the endpoint, subject, and scoped credential.",
        "无法加载工作区。请检查端点、主体和限定范围的凭据。",
      )
    WorkloadResponseInvalid =>
      app_copy(
        locale, "The workload was not accepted or did not return a valid public response.",
        "工作负载未被接受，或未返回有效的公开响应。",
      )
    PublicDetail(code, message, retryable) => {
      let detail = if message == "" {
        app_copy(
          locale, "The workload was rejected.", "工作负载已被拒绝。",
        )
      } else {
        message
      }
      let retry = if retryable {
        app_copy(locale, " You may retry.", " 可以重试。")
      } else {
        ""
      }
      "\{code}: \{detail}\{retry}"
    }
  }
}

///|
fn make_workload(
  state : @workbench_ui.WorkbenchState,
  now_unix_ms : Int64,
) -> @contracts.WorkloadEnvelope raise {
  guard state.lease is Some(lease) else { fail("workspace lease missing") }
  guard @workspace.capability_limit(lease, TextGenerate) is Some(limit) else {
    fail("text generation unavailable")
  }
  guard @workbench_ui.active_file(state) is Some(file) else {
    fail("browser draft missing")
  }
  let payload : Json = {
    "instruction": state.instruction,
    "file": {
      "path": file.path,
      "language": file.language,
      "content": file.content,
    },
  }
  let input_units = @utf8.encode(payload.stringify()).length()
  if input_units > limit.max_input_units_per_request {
    fail("request exceeds lease limit")
  }
  {
    version: @contracts.contract_version,
    idempotency_key: random_identifier("idem"),
    workload_id: random_identifier("workload"),
    tenant_ref: lease.tenant_ref,
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: state.model_selector,
    payload,
    data_policy: {
      classification: Internal,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: now_unix_ms + 30000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: input_units,
      max_output_units: limit.max_output_units_per_request,
      max_runtime_ms: 30000L,
      max_accelerator_memory_mib: 8192,
    },
    stream: false,
    output_format: "text",
    trace_token: random_identifier("trace"),
  }
}

///|
async fn send_workload(
  endpoint : String,
  token : String,
  subject_ref : String,
  state : @workbench_ui.WorkbenchState,
) -> RequestResult {
  let envelope = make_workload(state, current_unix_ms())
  let response_text = workload_request(
    endpoint,
    token,
    subject_ref,
    envelope.to_json().stringify(),
  )
  let response_json = @json.parse(response_text)
  let response : @contracts.WorkloadResponse = @json.from_json(response_json) catch {
    _ => {
      let rejection : ClientErrorEnvelope = @json.from_json(response_json) catch {
        _ => raise WorkbenchClientError::InvalidPublicResponse
      }
      raise WorkbenchClientError::PublicRejected(
        rejection.public_error.code,
        rejection.public_error.message,
        "",
        http_error_invalidates_authorization(
          rejection.public_error.status,
          rejection.public_error.code,
        ),
        rejection.public_error.retryable,
      )
    }
  }
  match response.error {
    Some(error) =>
      raise WorkbenchClientError::PublicRejected(
        "\{Repr(error.code)}",
        error.message,
        error.correlation_receipt,
        error_invalidates_authorization(error.code),
        error.retryable,
      )
    None => {
      let output_text = response.output.map(output => output.stringify())
      { output_text, receipt: response.audit_receipt, usage: response.usage }
    }
  }
}

///|
fn lease_clock_command(
  state : @workbench_ui.WorkbenchState,
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  match state.lease {
    Some(lease) if state.now_unix_ms < lease.expires_unix_ms =>
      @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try lease_clock_promise(lease.expires_unix_ms).wait() catch {
          _ => ClockAdvanced(current_unix_ms(), generation)
        } noraise {
          value => {
            let now : Int64 = value.cast()
            ClockAdvanced(now, generation)
          }
        }
      })
    _ => @rabbita.none
  }
}

///|
fn connect_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      load_workspace(model.endpoint, model.scoped_token, model.subject_ref)
    catch {
      WorkbenchClientError::PublicRejected(
        code,
        message,
        receipt,
        stale,
        retryable
      ) => PublicFailure(PublicDetail(code, message, retryable), receipt, stale)
      _ => PublicFailure(WorkspaceLoadUnavailable, "", true)
    } noraise {
      contract => WorkspaceLoaded(contract)
    }
  })
}

///|
fn send_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      send_workload(
        model.endpoint,
        model.scoped_token,
        model.subject_ref,
        model.workbench,
      )
    catch {
      WorkbenchClientError::PublicRejected(
        code,
        message,
        receipt,
        stale,
        retryable
      ) => PublicFailure(PublicDetail(code, message, retryable), receipt, stale)
      _ => PublicFailure(WorkloadResponseInvalid, "", false)
    } noraise {
      result => RequestCompleted(result)
    }
  })
}

///|
fn update(
  model : AppModel,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  match message {
    EndpointChanged(value) =>
      (
        {
          ..model,
          endpoint: value,
          connecting: false,
          clock_generation: model.clock_generation + 1L,
          workbench: {
            ..model.workbench,
            lease: None,
            success_message: None,
            error_message: None,
          },
        },
        @rabbita.none,
      )
    TokenChanged(value) =>
      (
        {
          ..model,
          scoped_token: value,
          connecting: false,
          clock_generation: model.clock_generation + 1L,
          workbench: {
            ..model.workbench,
            lease: None,
            success_message: None,
            error_message: None,
          },
        },
        @rabbita.none,
      )
    SubjectChanged(value) =>
      (
        {
          ..model,
          subject_ref: value,
          connecting: false,
          clock_generation: model.clock_generation + 1L,
          workbench: {
            ..model.workbench,
            lease: None,
            success_message: None,
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Connect => {
      let endpoint = model.endpoint.trim().to_owned()
      let subject_ref = model.subject_ref.trim().to_owned()
      if !endpoint_is_safe(endpoint) {
        return (
          {
            ..model,
            connecting: false,
            workbench: {
              ..model.workbench,
              lease: None,
              loading: false,
              success_message: None,
              error_message: Some(
                app_copy(
                  model.workbench.locale,
                  "Use an HTTPS controller origin, or HTTP on loopback for local acceptance.",
                  "请使用 HTTPS 控制器源站；本地验收可在回环地址上使用 HTTP。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      if !optional_subject_is_valid(subject_ref) {
        return (
          {
            ..model,
            connecting: false,
            workbench: {
              ..model.workbench,
              lease: None,
              loading: false,
              success_message: None,
              error_message: Some(
                app_copy(
                  model.workbench.locale,
                  "The optional loopback subject must be an opaque identifier using letters, digits, '.', '-', '_', or ':'.",
                  "可选的回环主体必须是不透明标识符，只能使用字母、数字、'.'、'-'、'_' 或 ':'。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let next = {
        ..model,
        endpoint,
        subject_ref,
        connecting: true,
        clock_generation: model.clock_generation + 1L,
        workbench: {
          ..workbench_at(model.workbench, current_unix_ms()),
          success_message: None,
          error_message: None,
        },
      }
      (next, connect_command(next, emit))
    }
    Workbench(SendRequest) => {
      let current = workbench_at(model.workbench, current_unix_ms())
      if model.connecting {
        return (
          {
            ..model,
            workbench: {
              ..current,
              error_message: Some(
                app_copy(
                  current.locale,
                  "Wait for workspace authorization to finish loading.",
                  "请等待工作区访问权限加载完成。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let next = { ..model, workbench: current.update(SendRequest) }
      if next.workbench.loading {
        (next, send_command(next, emit))
      } else {
        (next, @rabbita.none)
      }
    }
    Workbench(LocaleChanged(locale)) => {
      persist_locale(locale.storage_value())
      sync_document_locale(locale)
      (
        {
          ..model,
          workbench: update_workbench_at(
            model.workbench,
            LocaleChanged(locale),
            current_unix_ms(),
          ),
        },
        @rabbita.none,
      )
    }
    Workbench(message) =>
      (
        {
          ..model,
          workbench: update_workbench_at(
            model.workbench,
            message,
            current_unix_ms(),
          ),
        },
        @rabbita.none,
      )
    Outcome(WorkspaceLoaded(contract)) => {
      let next = {
        ..model,
        connecting: false,
        subject_ref: contract.subject_ref,
        workbench: state_from_workspace(model.workbench, contract),
      }
      (next, lease_clock_command(next.workbench, next.clock_generation, emit))
    }
    Outcome(RequestCompleted(result)) =>
      (
        {
          ..model,
          connecting: false,
          workbench: {
            ..model.workbench,
            now_unix_ms: current_unix_ms(),
            output_text: result.output_text.unwrap_or(
              app_copy(
                model.workbench.locale,
                "Request completed without normalized output.",
                "请求已完成，但没有规范化输出。",
              ),
            ),
            receipt: result.receipt,
            usage: {
              requests_used: model.workbench.usage.requests_used + 1,
              requests_limit: model.workbench.usage.requests_limit,
              input_units: model.workbench.usage.input_units +
              result.usage.input_units,
              output_units: model.workbench.usage.output_units +
              result.usage.output_units,
              accelerator_ms: model.workbench.usage.accelerator_ms +
              result.usage.accelerator_ms,
            },
            loading: false,
            success_message: Some(
              app_copy(
                model.workbench.locale,
                "Workload completed with a public receipt.",
                "工作负载已完成，并生成公开回执。",
              ),
            ),
            error_message: None,
          },
        },
        @rabbita.none,
      )
    Outcome(PublicFailure(kind, receipt, authorization_stale)) =>
      (
        {
          ..model,
          connecting: false,
          workbench: state_after_public_failure(
            model.workbench,
            public_failure_message(model.workbench.locale, kind),
            receipt,
            authorization_stale,
            current_unix_ms(),
          ),
        },
        @rabbita.none,
      )
    Outcome(ClockAdvanced(now_unix_ms, generation)) => {
      let advanced = advance_clock_if_current(
        model.workbench,
        model.clock_generation,
        generation,
        now_unix_ms,
      )
      match advanced {
        None => (model, @rabbita.none)
        Some(workbench) => {
          let next = { ..model, workbench, }
          (
            next,
            lease_clock_command(next.workbench, next.clock_generation, emit),
          )
        }
      }
    }
  }
}

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let ready = @workbench_ui.lease_ready(model.workbench)
  let locale = model.workbench.locale
  @html.div(class="workbench-app", [
    @html.style_tag(
      (
        #|.workbench-app{position:relative;min-height:100vh;background:#070b11}
        #|.connection-panel{color:var(--ink,#f4f7fb)}
        #|.connection-panel>summary{list-style:none}
        #|.connection-panel>summary::-webkit-details-marker{display:none}
        #|.connection-summary{min-height:2.6rem;padding:.45rem 1rem;display:flex;align-items:center;justify-content:space-between;gap:1rem;border-bottom:1px solid var(--line,#253248);background:#0a1019;cursor:pointer}
        #|.connection-summary>div{display:flex;align-items:center;gap:.5rem}
        #|.connection-summary strong{font-size:.73rem}
        #|.summary-indicator{width:.45rem;height:.45rem;border-radius:50%;background:var(--accent,#75e6b6)}
        #|.summary-endpoint{overflow:hidden;max-width:34rem;color:var(--muted,#91a0b7);font:600 .66rem/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;text-overflow:ellipsis;white-space:nowrap}
        #|.connection-body{padding:1rem;border-bottom:1px solid var(--line,#253248);background:var(--panel,#101824)}
        #|.connection-heading{margin-bottom:.9rem}
        #|.connection-kicker{margin:0 0 .28rem;color:var(--accent,#75e6b6);font-size:.62rem;font-weight:850;letter-spacing:.13em}
        #|.connection-heading h2{margin:0;font-size:1.05rem;letter-spacing:-.015em}
        #|.connection-heading p:last-child{margin:.35rem 0 0;color:var(--muted,#91a0b7);font-size:.74rem;line-height:1.5}
        #|.connection-primary{display:grid;grid-template-columns:minmax(13rem,1fr) auto;gap:.65rem;align-items:end}
        #|.connection-field label{display:block;margin-bottom:.32rem;color:var(--muted-strong,#bdc7d5);font-size:.7rem;font-weight:750}
        #|.connection-field input{width:100%;min-height:2.75rem;padding:.62rem .7rem;border:1px solid var(--line-strong,#33445f);border-radius:.55rem;background:#111c2a;color:var(--ink,#f4f7fb)}
        #|.connection-field input::placeholder{color:#65758e}
        #|.connection-primary button{min-height:2.75rem;border-color:var(--accent-strong,#37c98e);background:var(--accent,#75e6b6);color:var(--accent-ink,#06261a);font-weight:850}
        #|.connection-advanced{margin-top:.7rem;border-top:1px solid var(--line,#253248)}
        #|.connection-advanced>summary{padding:.7rem 0 .2rem;color:var(--muted-strong,#bdc7d5);font-size:.7rem;font-weight:700;cursor:pointer}
        #|.connection-advanced>summary:after{content:" +";color:var(--muted,#91a0b7)}
        #|.connection-advanced[open]>summary:after{content:" −"}
        #|.advanced-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.65rem;padding-top:.55rem}
        #|.connection-security,.connection-loading{margin:.75rem 0 0;padding:.68rem .75rem;border:1px solid var(--line,#253248);border-radius:.5rem;background:rgba(255,255,255,.018);color:var(--muted,#91a0b7);font-size:.68rem;line-height:1.5}
        #|.connection-loading{border-color:rgba(117,230,182,.35);color:var(--accent,#75e6b6)}
        #|.connection-panel.is-gated{position:absolute;z-index:20;top:7rem;right:max(2rem,calc((100vw - 76rem)/2));width:24rem;border:1px solid var(--line-strong,#33445f);border-radius:.85rem;overflow:hidden;background:var(--panel,#101824);box-shadow:var(--shadow,0 24px 70px rgba(0,0,0,.34))}
        #|.connection-panel.is-gated>.connection-summary{display:none}
        #|.connection-panel.is-gated .connection-body{padding:1.25rem;border-bottom:0}
        #|.connection-panel.is-gated .connection-primary{grid-template-columns:1fr}
        #|.connection-panel.is-gated .connection-primary button{width:100%}
        #|.connection-panel.is-connected{position:relative;z-index:14}
        #|.connection-panel.is-connected[open] .connection-body{display:grid;grid-template-columns:minmax(14rem,20rem) minmax(20rem,1fr);gap:0 1rem}
        #|.connection-panel.is-connected[open] .connection-heading{grid-row:1/4}
        #|.connection-panel.is-connected[open] .connection-security,.connection-panel.is-connected[open] .connection-loading{grid-column:2}
        #|@media(max-width:64rem){.connection-panel.is-gated{position:relative;top:auto;right:auto;width:auto;margin:1rem;border-radius:.75rem}.connection-panel.is-gated>.connection-summary{display:none}.connection-panel.is-connected[open] .connection-body{display:block}}
        #|@media(max-width:48rem){.connection-summary{align-items:flex-start;flex-direction:column;gap:.2rem}.summary-endpoint{max-width:100%}.advanced-grid,.connection-primary{grid-template-columns:1fr}.connection-primary button{width:100%}}
      ),
    ),
    @html.details(
      class=if ready {
        "connection-panel is-connected"
      } else {
        "connection-panel is-gated"
      },
      open=!ready,
      attrs=@html.Attrs::build().aria_label(
        app_copy(locale, "Workspace connection", "工作区连接"),
      ),
      [
        @html.summary(class="connection-summary", [
          @html.div([
            @html.span(class="summary-indicator", ""),
            @html.strong(
              app_copy(locale, "Controller connection", "控制器连接"),
            ),
          ]),
          @html.span(class="summary-endpoint", model.endpoint),
        ]),
        @html.div(class="connection-body", [
          @html.div(class="connection-heading", [
            @html.p(
              class="connection-kicker",
              app_copy(
                locale, "SECURE WORKSPACE ACCESS", "安全工作区访问",
              ),
            ),
            @html.h2(
              app_copy(locale, "Connect to LunaNexa", "连接到 LunaNexa"),
            ),
            @html.p(
              app_copy(
                locale, "Load your individual lease, quota, and provider-neutral model tools.",
                "加载个人工作区租约、配额和不绑定特定提供商的模型工具。",
              ),
            ),
          ]),
          @html.div(class="connection-primary", [
            @html.div(class="connection-field", [
              @html.label(
                for_="workspace-token",
                app_copy(
                  locale, "Scoped inference token", "限定范围的推理令牌",
                ),
              ),
              @html.input(
                id="workspace-token",
                input_type=Password,
                value=model.scoped_token,
                placeholder=app_copy(
                  locale, "Paste your expiring token", "粘贴有时效的令牌",
                ),
                auto_complete=Off,
                attrs=@html.Attrs::build().disabled(
                  model.connecting || model.workbench.loading,
                ),
                on_input=emit.map(value => TokenChanged(value)),
              ),
            ]),
            @html.button(
              type_="button",
              disabled=model.endpoint.trim() == "" ||
                model.scoped_token == "" ||
                model.connecting ||
                model.workbench.loading,
              on_click=emit(Connect),
              app_copy(locale, "Connect / refresh", "连接 / 刷新"),
            ),
          ]),
          @html.details(class="connection-advanced", [
            @html.summary(
              app_copy(
                locale, "Advanced connection settings", "高级连接设置",
              ),
            ),
            @html.div(class="advanced-grid", [
              @html.div(class="connection-field", [
                @html.label(
                  for_="workspace-endpoint",
                  app_copy(locale, "Controller endpoint", "控制器端点"),
                ),
                @html.input(
                  id="workspace-endpoint",
                  value=model.endpoint,
                  placeholder="https://controller.example",
                  attrs=@html.Attrs::build().disabled(
                    model.connecting || model.workbench.loading,
                  ),
                  on_input=emit.map(value => EndpointChanged(value)),
                ),
              ]),
              @html.div(class="connection-field", [
                @html.label(
                  for_="workspace-subject",
                  app_copy(
                    locale, "Opaque subject reference (loopback acceptance)", "不透明主体引用（回环验收）",
                  ),
                ),
                @html.input(
                  id="workspace-subject",
                  value=model.subject_ref,
                  placeholder="subject-opaque",
                  auto_complete=Off,
                  attrs=@html.Attrs::build().disabled(
                    model.connecting || model.workbench.loading,
                  ),
                  on_input=emit.map(value => SubjectChanged(value)),
                ),
              ]),
            ]),
          ]),
          @html.p(
            class="connection-security",
            app_copy(
              locale, "The token stays in browser memory for this page, is never displayed in clear text or logged, and is never sent to a managed GPU node. Verified mTLS ingress derives the opaque subject automatically; only loopback acceptance clients may send the subject header directly.",
              "令牌仅保留在此页面的浏览器内存中，绝不会以明文显示或写入日志，也绝不会发送到受管 GPU 节点。已验证的 mTLS 入口会自动派生不透明主体；只有回环验收客户端可以直接发送主体标头。",
            ),
          ),
          if model.connecting {
            @html.p(
              class="connection-loading",
              attrs=@html.Attrs::build()
                .role("status")
                .aria_live("polite")
                .aria_busy("true"),
              app_copy(
                locale, "Loading workspace authorization…", "正在加载工作区访问权限…",
              ),
            )
          } else {
            @html.nothing
          },
        ]),
      ],
    ),
    @workbench_ui.interactive_view(
      model.workbench,
      emit.map(message => Workbench(message)),
    ),
  ])
}

///|
fn main {
  let locale = @i18n.parse_locale(stored_locale())
  sync_document_locale(locale)
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      scoped_token: "",
      subject_ref: "",
      connecting: false,
      clock_generation: 0L,
      workbench: @workbench_ui.default_state(current_unix_ms()).update(
        LocaleChanged(locale),
      ),
    },
    view=app_view,
    update~,
  ).mount("app")
}
