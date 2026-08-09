///|
priv struct BrowserStreamEvent {
  sequence : Int
  kind : String
  text : String
  receipt : String
} derive(FromJson)

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || globalThis.location?.origin || ""

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn stored_locale_preference() -> String =
  #| () => {
  #|   try {
  #|     return globalThis.localStorage?.getItem("lunanexa.locale") || "";
  #|   } catch (_) {
  #|     return "";
  #|   }
  #| }

///|
extern "js" fn commit_locale_preference(
  storage_value : String,
  language_tag : String,
  title : String,
) -> Unit =
  #| (storageValue, languageTag, title) => {
  #|   try {
  #|     globalThis.localStorage?.setItem("lunanexa.locale", storageValue);
  #|   } catch (_) {}
  #|   try {
  #|     if (globalThis.document?.documentElement) {
  #|       globalThis.document.documentElement.lang = languageTag;
  #|     }
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
fn console_copy(
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
fn console_document_title(locale : @i18n.Locale) -> String {
  console_copy(
    locale, "LunaNexa | Cluster Operations", "LunaNexa | 集群运维",
  )
}

///|
fn apply_console_locale(locale : @i18n.Locale) -> Unit {
  commit_locale_preference(
    locale.storage_value(),
    locale.language_tag(),
    console_document_title(locale),
  )
}

///|
extern "js" fn format_unix_ms(value : Int64, unavailable : String) -> String =
  #| (value, unavailable) => {
  #|   const milliseconds = Number(value);
  #|   if (!Number.isFinite(milliseconds) || Math.abs(milliseconds) > 8640000000000000) {
  #|     return unavailable;
  #|   }
  #|   try {
  #|     return new Date(milliseconds).toISOString().replace("T", " ").replace(/:\d\d\.\d\d\dZ$/, " UTC");
  #|   } catch (_) {
  #|     return unavailable;
  #|   }
  #| }

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
  #|   if (!response.ok) throw new Error(`HTTP ${response.status}`);
  #|   return text;
  #| }

///|
extern "js" fn stream_request_promise(
  url : String,
  token : String,
  subject_ref : String,
  body : String,
) -> @js.Promise =
  #| async (url, token, subject, body) => {
  #|   const headers = {
  #|     "Accept": "text/event-stream",
  #|     "Content-Type": "application/json",
  #|     "Authorization": `Bearer ${token}`
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
  #|   if (!response.ok || !response.body) throw new Error(`HTTP ${response.status}`);
  #|   const reader = response.body.getReader();
  #|   const decoder = new TextDecoder();
  #|   const encoder = new TextEncoder();
  #|   const events = [];
  #|   let buffer = "";
  #|   let outputBytes = 0;
  #|   const accept = block => {
  #|     for (const line of block.split("\n")) {
  #|       if (!line.startsWith("data:")) continue;
  #|       const data = line.slice(5).trim();
  #|       if (!data) continue;
  #|       const event = JSON.parse(data);
  #|       const output = event.output;
  #|       let text = "";
  #|       if (output && typeof output.text_delta === "string") text = output.text_delta;
  #|       else if (output != null) text = JSON.stringify(output);
  #|       const bytes = encoder.encode(text).byteLength;
  #|       if (bytes > 65536 || outputBytes + bytes > 1048576 || events.length >= 512) {
  #|         throw new Error("stream display limit exceeded");
  #|       }
  #|       outputBytes += bytes;
  #|       const receipt = event.response?.audit_receipt || event.response?.error?.correlation_receipt || "";
  #|       events.push({ sequence: event.sequence, kind: event.kind, text, receipt });
  #|     }
  #|   };
  #|   while (true) {
  #|     const { value, done } = await reader.read();
  #|     buffer += decoder.decode(value || new Uint8Array(), { stream: !done }).replaceAll("\r\n", "\n");
  #|     if (buffer.length > 2097152) throw new Error("stream framing limit exceeded");
  #|     let boundary;
  #|     while ((boundary = buffer.indexOf("\n\n")) >= 0) {
  #|       accept(buffer.slice(0, boundary));
  #|       buffer = buffer.slice(boundary + 2);
  #|     }
  #|     if (done) break;
  #|   }
  #|   if (!events.some(event => event.kind === "Completed" || event.kind === "Failed" || event.kind === "Cancelled")) {
  #|     throw new Error("stream ended without a terminal event");
  #|   }
  #|   return JSON.stringify(events);
  #| }

///|
async fn request(
  verb : String,
  endpoint : String,
  path : String,
  token : String,
  subject_ref? : String = "",
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
async fn stream_request(
  endpoint : String,
  token : String,
  subject_ref : String,
  body : String,
) -> Array[@ui.StreamEventView] {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = stream_request_promise(
    "\{base}/v1/workloads:stream",
    token,
    subject_ref,
    body,
  ).wait()
  let text : String = value.cast()
  let events : Array[BrowserStreamEvent] = @json.from_json(@json.parse(text))
  [
    for event in events => {
      {
        sequence: event.sequence,
        kind: event.kind,
        text: event.text,
        receipt: event.receipt,
      }
    }
  ]
}

///|
fn architecture(heartbeat : @contracts.NodeHeartbeat) -> String {
  heartbeat.inventory.accelerators
  .get(0)
  .map(device => device.architecture)
  .unwrap_or("unreported")
}

///|
fn free_memory(heartbeat : @contracts.NodeHeartbeat) -> Int {
  let mut total = 0
  for device in heartbeat.inventory.accelerators {
    total += device.memory_free_mib
  }
  total
}

///|
fn license_status(
  registry : @contracts.RegistryReadContract,
  license_id : String,
) -> String {
  for license in registry.licenses {
    if license.license_id == license_id {
      return license.status
    }
  }
  "missing"
}

///|
fn evaluation_status(
  registry : @contracts.RegistryReadContract,
  model_id : String,
  version : String,
) -> String {
  for evaluation in registry.evaluations {
    if evaluation.model_id == model_id && evaluation.model_version == version {
      return if evaluation.passed { "passed" } else { "failed" }
    }
  }
  "missing"
}

///|
fn alias_name(
  registry : @contracts.RegistryReadContract,
  model_id : String,
  version : String,
) -> String {
  for alias_record in registry.aliases {
    if alias_record.model_id == model_id && alias_record.version == version {
      return alias_record.name
    }
  }
  "—"
}

///|
fn workspace_user_id(
  users : Array[@workspace.WorkspaceUser],
  subject_ref : String,
) -> String {
  users
  .iter()
  .find_first(user => user.subject_ref == subject_ref)
  .map(user => user.user_id)
  .unwrap_or(subject_ref)
}

///|
fn workspace_resource(limits : @workspace.WorkspaceLimits) -> String {
  if limits.capabilities.length() == 0 {
    return "No inference capabilities"
  }
  [
    for limit in limits.capabilities => {
      let name = match limit.capability {
        TextGenerate => "Text generation"
        EmbeddingCreate => "Embeddings"
        ImageGenerate => "Image generation"
        VideoGenerate => "Video generation"
        AudioGenerate => "Audio generation"
      }
      "\{name} · \{limit.max_concurrent_requests} concurrent"
    }
  ].join(", ")
}

///|
fn optional_subject_is_valid(value : String) -> Bool {
  let subject_ref = value.trim().to_owned()
  subject_ref == "" || @workspace.valid_identifier(subject_ref)
}

///|
fn catalog_template_key(template : @deployment.ModelServiceTemplate) -> String {
  "\{template.template_id}@\{template.version}"
}

///|
fn quick_deployment_intent(
  state : @ui.ConsoleState,
  now_unix_ms : Int64,
) -> @deployment.ModelServiceIntent? {
  let deployment_id = state.quick_deployment_id.trim().to_owned()
  let replicas = @string.parse_int64(state.quick_replicas.trim()).to_int() catch {
    _ => return None
  }
  guard @contracts.valid_identifier(deployment_id, maximum_length=128) &&
    replicas > 0 &&
    replicas <= 64 &&
    state.catalog_templates
    .iter()
    .find_first(template => {
      catalog_template_key(template) == state.quick_template
    })
    is Some(template) else {
    return None
  }
  Some({
    version: @contracts.contract_version,
    idempotency_key: "console:\{deployment_id}:\{now_unix_ms}",
    deployment_id,
    template: { template_id: template.template_id, version: template.version },
    replicas,
    data_class: template.data_policy.classification,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
  })
}

///|
fn service_deployment_action_path(
  deployment_id : String,
  action : String,
) -> String {
  "/v1/service-deployments/\{deployment_id}/\{action}"
}

///|
priv enum WorkspaceLifecycleAction {
  ActivateWorkspaceUser(String)
  SuspendWorkspaceUser(String)
  RevokeWorkspaceUser(String)
  ActivateWorkspaceLease(String)
}

///|
fn workspace_lifecycle_path(action : WorkspaceLifecycleAction) -> String {
  match action {
    ActivateWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:activate"
    SuspendWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:suspend"
    RevokeWorkspaceUser(user_id) => "/v1/workspace/users/\{user_id}:revoke"
    ActivateWorkspaceLease(lease_id) =>
      "/v1/workspace/leases/\{lease_id}:activate"
  }
}

///|
fn user_confirmation_scope(
  users : Array[@ui.UserAccessRow],
  user_id : String,
) -> String {
  users
  .iter()
  .find_first(user => user.user_id == user_id)
  .map(user => "\{user.user_id} · \{user.display_name} · \{user.email}")
  .unwrap_or(user_id)
}

///|
fn prepare_user_confirmation(
  state : @ui.ConsoleState,
  user_id : String,
  action : @ui.DestructiveAction,
) -> @ui.ConsoleState {
  {
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        action,
        user_confirmation_scope(state.users, user_id),
      ),
    ),
  }
}

///|
async fn load_console(
  endpoint : String,
  token : String,
  audit_token : String,
  route : @ui.OperatorRoute,
  locale : @i18n.Locale,
) -> @ui.ConsoleState {
  let heartbeats : Array[@contracts.NodeHeartbeat] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/nodes", token)),
  )
  let assignments : Array[@contracts.DesiredAssignment] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/assignments", token)),
  )
  let audit : Array[@contracts.AuditEvent] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/audit", audit_token)),
  )
  let registry : @contracts.RegistryReadContract = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/registry", token)),
  )
  let scheduler : @contracts.SchedulerReadContract = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/scheduler", token)),
  )
  let telemetry : @contracts.TelemetryReadContract = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/telemetry", token)),
  )
  let workspace : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/workspace", token)),
  )
  let catalog_templates : Array[@deployment.ModelServiceTemplate] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/catalog/templates", token)),
  )
  let service_deployments : Array[@deployment.DeploymentOperation] = @json.from_json(
    @json.parse(request("GET", endpoint, "/v1/service-deployments", token)),
  )
  let now = current_unix_ms()
  let nodes : Array[@ui.NodeRow] = [
    for heartbeat in heartbeats => {
      {
        node_id: heartbeat.node_id,
        state: if now - heartbeat.timestamp_unix_ms > 15000L {
          Unreachable
        } else {
          heartbeat.state
        },
        architecture: architecture(heartbeat),
        free_memory_mib: free_memory(heartbeat),
        workloads: heartbeat.running_deployments.length(),
      }
    }
  ]
  let models : Array[@ui.ModelRow] = [
    for model in registry.models => {
      {
        model_id: model.model_id,
        version: model.version,
        state: model.state,
        license_status: license_status(registry, model.license_id),
        evaluation_status: evaluation_status(
          registry,
          model.model_id,
          model.version,
        ),
        compatibility: model.compatible_architectures.join(", "),
        alias_name: alias_name(registry, model.model_id, model.version),
      }
    }
  ]
  let deployments : Array[@ui.DeploymentRow] = [
    for assignment in assignments => {
      let running = heartbeats.any(heartbeat => {
        heartbeat.node_id == assignment.node_id &&
        now - heartbeat.timestamp_unix_ms <= 15000L &&
        heartbeat.running_deployments.any(id => id == assignment.deployment_id)
      })
      {
        assignment_id: assignment.assignment_id,
        deployment_id: assignment.deployment_id,
        desired: Ready,
        observed: if running {
          Ready
        } else {
          Preparing
        },
        placement_reason: "\{assignment.node_id} · #\{assignment.generation}",
      }
    }
  ]
  let active_nodes = nodes.count_if(node => node.state == Active)
  let users : Array[@ui.UserAccessRow] = [
    for user in workspace.users => {
      {
        user_id: user.user_id,
        display_name: user.display_name,
        email: user.email,
        state: user.state,
        last_active: user.last_active_unix_ms
        .map(timestamp => format_unix_ms(timestamp, "Unavailable"))
        .unwrap_or("Never"),
        grant_count: workspace.access_grants.count_if(grant => {
          grant.user_id == user.user_id
        }),
      }
    }
  ]
  let access_grants : Array[@ui.AccessGrantRow] = [
    for grant in workspace.access_grants => {
      {
        grant_id: grant.grant_id,
        user_id: grant.user_id,
        role: grant.access,
        scope: grant.tenant_ref,
        expires_at: format_unix_ms(grant.expires_unix_ms, "Unavailable"),
        state: grant.state,
      }
    }
  ]
  let compute_leases : Array[@ui.ComputeLeaseRow] = [
    for lease in workspace.leases => {
      {
        lease_id: lease.lease_id,
        user_id: workspace_user_id(workspace.users, lease.subject_ref),
        workspace: lease.tenant_ref,
        resource: workspace_resource(lease.limits),
        started_at: format_unix_ms(lease.starts_unix_ms, "Unavailable"),
        expires_at: format_unix_ms(lease.expires_unix_ms, "Unavailable"),
        state: lease.state,
      }
    }
  ]
  let request_details : Array[@ui.RequestDetail] = []
  for event in audit {
    if event.action.has_prefix("workload.") {
      request_details.push({
        timestamp_unix_ms: event.timestamp_unix_ms,
        action: event.action,
        model_selector: event.target,
        result: event.result,
        receipt: event.correlation_receipt,
      })
    }
  }
  while request_details.length() > 50 {
    ignore(request_details.remove(0))
  }
  {
    locale,
    route,
    overview: {
      active_nodes,
      total_nodes: heartbeats.length(),
      active_models: models.count_if(model => model.state == Approved),
      queue_depth: scheduler.queued_count.unwrap_or(scheduler.active.length()),
      alerts: nodes.count_if(node => node.state == Unreachable),
      recent_changes: audit.length().min(20),
    },
    nodes,
    models,
    deployments,
    catalog_templates,
    service_deployments,
    requests: {
      count: audit.count_if(event => event.action.has_prefix("workload.")),
      p95_ms: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.latency_p95_ms)
      .unwrap_or(0),
      throughput_per_second: telemetry.benchmark_summaries
      .last()
      .map(summary => summary.throughput_units_per_second)
      .unwrap_or(0),
      errors: audit.count_if(event => {
        event.action == "workload.fail" || event.result != "accepted"
      }),
    },
    request_details,
    stream_events: [],
    benchmark_evidence: [
      for summary in telemetry.benchmark_summaries => {
        "\{summary.profile} · p95 \{summary.latency_p95_ms} ms · \{summary.throughput_units_per_second}/s · failures \{summary.failure_per_mille}‰ · \{summary.run_id}"
      }
    ],
    policies: {
      quota_count: scheduler.quotas.length(),
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: [
        for runtime in registry.runtimes => runtime.name
      ],
    },
    audit: [
      for event in audit => {
        {
          actor: event.actor,
          decision: event.action,
          evidence: event.target,
          result: event.result,
          receipt: event.correlation_receipt,
        }
      }
    ],
    users,
    access_grants,
    compute_leases,
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: catalog_templates
    .get(0)
    .map(catalog_template_key)
    .unwrap_or(""),
    quick_replicas: "1",
  }
}

///|
priv enum LoadOutcome {
  Loaded(@ui.ConsoleState)
  LoadFailed(@i18n.Locale, String)
  ActionComplete(@i18n.Locale, String)
  StreamComplete(Array[@ui.StreamEventView])
  ActionFailed(@i18n.Locale, String)
}

///|
priv struct AppModel {
  endpoint : String
  credential : String
  audit_credential : String
  inference_credential : String
  inference_subject_ref : String
  console : @ui.ConsoleState
  next_directive_generation : Int64
} derive(Eq)

///|
priv enum AppMessage {
  CredentialChanged(String)
  AuditCredentialChanged(String)
  InferenceCredentialChanged(String)
  InferenceSubjectChanged(String)
  Connect
  Console(@ui.ConsoleMessage)
  Outcome(LoadOutcome)
}

///|
fn merge_loaded_console(
  current : @ui.ConsoleState,
  loaded : @ui.ConsoleState,
) -> @ui.ConsoleState {
  {
    ..loaded,
    locale: current.locale,
    route: current.route,
    operation_name: current.operation_name,
    operation_body: current.operation_body,
    quick_deployment_id: current.quick_deployment_id,
    quick_template: if current.quick_template == "" {
      loaded.quick_template
    } else {
      current.quick_template
    },
    quick_replicas: current.quick_replicas,
    success_message: current.success_message,
  }
}

///|
fn switch_console_locale(
  state : @ui.ConsoleState,
  locale : @i18n.Locale,
) -> @ui.ConsoleState {
  {
    ..state,
    locale,
    // Notices are UI-owned, ephemeral copy. Clear them rather than retaining a
    // message rendered in the previous language; operational state is kept.
    error_message: None,
    success_message: None,
  }
}

///|
fn switch_app_locale(model : AppModel, locale : @i18n.Locale) -> AppModel {
  { ..model, console: switch_console_locale(model.console, locale) }
}

///|
fn locale_fenced_notice(
  current : @i18n.Locale,
  dispatched : @i18n.Locale,
  detailed : String,
  generic_english : String,
  generic_chinese : String,
) -> String {
  if current == dispatched {
    detailed
  } else {
    console_copy(current, generic_english, generic_chinese)
  }
}

///|
fn load_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      load_console(
        model.endpoint,
        model.credential,
        model.audit_credential,
        model.console.route,
        model.console.locale,
      )
    catch {
      _ =>
        LoadFailed(
          model.console.locale,
          console_copy(
            model.console.locale,
            "The controller could not be reached or rejected this credential.",
            "无法连接控制器，或控制器拒绝了此凭据。",
          ),
        )
    } noraise {
      state => Loaded(state)
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
    CredentialChanged(value) => ({ ..model, credential: value }, @rabbita.none)
    AuditCredentialChanged(value) =>
      ({ ..model, audit_credential: value }, @rabbita.none)
    InferenceCredentialChanged(value) =>
      ({ ..model, inference_credential: value }, @rabbita.none)
    InferenceSubjectChanged(value) =>
      ({ ..model, inference_subject_ref: value }, @rabbita.none)
    Console(LocaleChanged(locale)) => {
      apply_console_locale(locale)
      (switch_app_locale(model, locale), @rabbita.none)
    }
    Connect => {
      let next = {
        ..model,
        console: { ..model.console, loading: true, error_message: None },
      }
      (next, load_command(next, emit))
    }
    Outcome(Loaded(state)) =>
      (
        { ..model, console: merge_loaded_console(model.console, state) },
        @rabbita.none,
      )
    Outcome(LoadFailed(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            error_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                message,
                "Controller refresh failed.",
                "控制器刷新失败。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionComplete(dispatched_locale, message)) => {
      let next = {
        ..model,
        next_directive_generation: model.next_directive_generation + 1L,
        console: {
          ..model.console,
          confirmation: None,
          loading: true,
          success_message: Some(
            locale_fenced_notice(
              model.console.locale,
              dispatched_locale,
              message,
              "Operation completed.",
              "操作已完成。",
            ),
          ),
        },
      }
      (next, load_command(next, emit))
    }
    Outcome(StreamComplete(events)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            route: Requests,
            stream_events: events,
            loading: false,
            error_message: None,
            success_message: Some(
              console_copy(
                model.console.locale,
                "Streaming invocation completed.",
                "流式调用已完成。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionFailed(dispatched_locale, message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            error_message: Some(
              locale_fenced_notice(
                model.console.locale,
                dispatched_locale,
                message,
                "Operation failed.",
                "操作失败。",
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(Navigate(route)) =>
      ({ ..model, console: { ..model.console, route, } }, @rabbita.none)
    Console(BeginDrain(node_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(DrainNode(node_id), node_id),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginCordon(node_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(CordonNode(node_id), node_id),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginRollback(alias_name)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(RollbackAlias(alias_name), alias_name),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginStopDeployment(assignment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                StopDeployment(assignment_id),
                assignment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginRollbackServiceDeployment(deployment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                RollbackServiceDeployment(deployment_id),
                deployment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(BeginDeleteServiceDeployment(deployment_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                DeleteServiceDeployment(deployment_id),
                deployment_id,
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(PromoteServiceDeployment(deployment_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "promote"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service promotion was rejected.",
                "模型服务提升被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was promoted.",
                "模型服务 \{deployment_id} 已提升。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ActivateUser(user_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(ActivateWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be activated.",
                "无法激活该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was activated.",
                "用户 \{user_id} 已激活。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(BeginSuspendUser(user_id)) =>
      (
        {
          ..model,
          console: prepare_user_confirmation(
            model.console,
            user_id,
            SuspendUser(user_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginRevokeUser(user_id)) =>
      (
        {
          ..model,
          console: prepare_user_confirmation(
            model.console,
            user_id,
            RevokeUser(user_id),
          ),
        },
        @rabbita.none,
      )
    Console(BeginRevokeAccessGrant(grant_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                RevokeAccessGrant(grant_id),
                model.console.access_grants
                .iter()
                .find_first(grant => grant.grant_id == grant_id)
                .map(grant => {
                  "\{grant.grant_id} · \{grant.user_id} · \{grant.scope}"
                })
                .unwrap_or(grant_id),
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(ActivateComputeLease(lease_id)) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(ActivateWorkspaceLease(lease_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The workspace lease could not be activated.",
                "无法激活该工作区租约。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Workspace lease \{lease_id} was activated.",
                "工作区租约 \{lease_id} 已激活。",
              ),
            )
        }
      })
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: true,
            error_message: None,
            success_message: None,
          },
        },
        cmd,
      )
    }
    Console(BeginEndComputeLease(lease_id)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            confirmation: Some(
              @ui.confirmation_receipt(
                EndComputeLease(lease_id),
                model.console.compute_leases
                .iter()
                .find_first(lease => lease.lease_id == lease_id)
                .map(lease => {
                  "\{lease.lease_id} · \{lease.user_id} · \{lease.workspace}"
                })
                .unwrap_or(lease_id),
              ),
            ),
          },
        },
        @rabbita.none,
      )
    Console(DismissConfirmation) =>
      (
        { ..model, console: { ..model.console, confirmation: None } },
        @rabbita.none,
      )
    Console(Refresh) => (model, load_command(model, emit))
    Console(OperationChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_name: value } },
        @rabbita.none,
      )
    Console(OperationBodyChanged(value)) =>
      (
        { ..model, console: { ..model.console, operation_body: value } },
        @rabbita.none,
      )
    Console(QuickDeploymentIdChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_deployment_id: value } },
        @rabbita.none,
      )
    Console(QuickTemplateChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_template: value } },
        @rabbita.none,
      )
    Console(QuickReplicasChanged(value)) =>
      (
        { ..model, console: { ..model.console, quick_replicas: value } },
        @rabbita.none,
      )
    Console(SubmitQuickDeployment) => {
      guard quick_deployment_intent(model.console, current_unix_ms())
        is Some(intent) else {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                console_copy(
                  model.console.locale,
                  "Choose an approved template, a valid service name, and 1–64 replicas.",
                  "请选择已批准模板、有效服务名称以及 1–64 个副本。",
                ),
              ),
            },
          },
          @rabbita.none,
        )
      }
      let deployment_id = intent.deployment_id
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/service-deployments",
            model.credential,
            body=intent.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Deployment preflight blocked or rejected this model service.",
                "部署预检阻止或拒绝了此模型服务。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} entered reconciliation.",
                "模型服务 \{deployment_id} 已进入协调流程。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(SubmitOperation) => {
      let (verb, path, inference) = match model.console.operation_name {
        "issue-enrollment-token" => ("POST", "/v1/enrollment/tokens", false)
        "register-runtime" => ("POST", "/v1/runtimes", false)
        "register-model" => ("POST", "/v1/models", false)
        "register-template" => ("POST", "/v1/catalog/templates", false)
        "plan-deployment" => ("POST", "/v1/deployment-plans", false)
        "deploy-service" => ("POST", "/v1/service-deployments", false)
        "record-license" => ("POST", "/v1/licenses", false)
        "record-verification" => ("POST", "/v1/verifications", false)
        "record-evaluation" => ("POST", "/v1/evaluations", false)
        "approve-model" => ("POST", "/v1/models/approve", false)
        "promote-alias" => ("POST", "/v1/aliases/promote", false)
        "set-quota" => ("PUT", "/v1/quotas", false)
        "invite-user" => ("POST", "/v1/workspace/users", false)
        "grant-access" => ("POST", "/v1/workspace/access-grants", false)
        "create-compute-lease" => ("POST", "/v1/workspace/leases", false)
        "publish-assignment" => ("PUT", "/v1/assignments", false)
        "invoke-workload" => ("POST", "/v1/workloads", true)
        "record-benchmark" => ("POST", "/v1/benchmarks", false)
        _ => ("", "", false)
      }
      let inference_subject = model.inference_subject_ref.trim().to_owned()
      if path == "" ||
        (inference && model.inference_credential == "") ||
        (inference && !optional_subject_is_valid(inference_subject)) {
        let message = if inference &&
          !optional_subject_is_valid(inference_subject) {
          console_copy(
            model.console.locale,
            "The optional opaque subject reference must use only letters, digits, '.', '-', '_', or ':', up to 256 characters. Leave it empty when verified mTLS derives identity; the header is accepted only for loopback acceptance.",
            "可选的不透明主体引用只能包含字母、数字、句点、连字符、下划线或冒号，且不超过 256 个字符。经验证的 mTLS 可推导身份时请留空；仅回环验收客户端可直接发送此标头。",
          )
        } else {
          console_copy(
            model.console.locale,
            "Select a supported operation and provide the inference token when invoking.",
            "请选择受支持的操作，并在调用时提供推理令牌。",
          )
        }
        return (
          {
            ..model,
            console: { ..model.console, error_message: Some(message) },
          },
          @rabbita.none,
        )
      }
      let token = if inference {
        model.inference_credential
      } else {
        model.credential
      }
      let wants_stream = if model.console.operation_name == "invoke-workload" {
        try
          @contracts.decode_workload(model.console.operation_body).stream
        catch {
          _ => false
        } noraise {
          value => value
        }
      } else {
        false
      }
      let cmd = if wants_stream {
        @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
          try
            stream_request(
              model.endpoint,
              token,
              inference_subject,
              model.console.operation_body,
            )
          catch {
            _ =>
              ActionFailed(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "The streaming invocation was rejected.",
                  "流式调用被拒绝。",
                ),
              )
          } noraise {
            events => StreamComplete(events)
          }
        })
      } else {
        @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
          try
            request(
              verb,
              model.endpoint,
              path,
              token,
              subject_ref=if inference { inference_subject } else { "" },
              body=model.console.operation_body,
            )
          catch {
            _ =>
              ActionFailed(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "The typed operation was rejected.",
                  "类型化操作被拒绝。",
                ),
              )
          } noraise {
            _ =>
              ActionComplete(
                model.console.locale,
                console_copy(
                  model.console.locale,
                  "Operation \{model.console.operation_name} completed.",
                  "操作 \{model.console.operation_name} 已完成。",
                ),
              )
          }
        })
      }
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(DrainNode(node_id))) => {
      let generation = current_unix_ms()
      let directive : @contracts.NodeDirective = {
        node_id,
        desired_state: Draining,
        generation,
        issued_unix_ms: generation,
        receipt: "console:drain:\{node_id}:\{generation}",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "PUT",
            model.endpoint,
            "/v1/nodes/directive",
            model.credential,
            body=directive.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The drain request was rejected.",
                "排空请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Drain requested for \{node_id}.",
                "已请求排空 \{node_id}。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(CordonNode(node_id))) => {
      let generation = current_unix_ms()
      let directive : @contracts.NodeDirective = {
        node_id,
        desired_state: Cordoned,
        generation,
        issued_unix_ms: generation,
        receipt: "console:cordon:\{node_id}:\{generation}",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "PUT",
            model.endpoint,
            "/v1/nodes/directive",
            model.credential,
            body=directive.to_json().stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The cordon request was rejected.",
                "封锁调度请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Cordon requested for \{node_id}.",
                "已请求封锁调度 \{node_id}。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RollbackAlias(alias_name))) => {
      let body : Json = {
        "alias_name": alias_name,
        "actor": "console-operator",
      }
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/aliases/rollback",
            model.credential,
            body=body.stringify(),
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model alias rollback was rejected.",
                "模型别名回滚被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model alias \{alias_name} was rolled back.",
                "模型别名 \{alias_name} 已回滚。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(StopDeployment(assignment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/assignments/\{assignment_id}/stop",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The deployment stop was rejected.",
                "停止部署的请求被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Deployment assignment \{assignment_id} was stopped.",
                "部署分配 \{assignment_id} 已停止。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RollbackServiceDeployment(deployment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "rollback"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service rollback was rejected.",
                "模型服务回滚被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was rolled back.",
                "模型服务 \{deployment_id} 已回滚。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(DeleteServiceDeployment(deployment_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            service_deployment_action_path(deployment_id, "delete"),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The model service deletion was rejected.",
                "模型服务删除被拒绝。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Model service \{deployment_id} was deleted.",
                "模型服务 \{deployment_id} 已删除。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(SuspendUser(user_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(SuspendWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be suspended.",
                "无法暂停该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was suspended.",
                "用户 \{user_id} 已暂停。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RevokeUser(user_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            workspace_lifecycle_path(RevokeWorkspaceUser(user_id)),
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The user could not be revoked.",
                "无法撤销该用户。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "User \{user_id} was revoked.",
                "用户 \{user_id} 已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(RevokeAccessGrant(grant_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/workspace/access-grants/\{grant_id}:revoke",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The access grant could not be revoked.",
                "无法撤销该访问授权。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Access grant \{grant_id} was revoked.",
                "访问授权 \{grant_id} 已撤销。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
    Console(ConfirmAction(EndComputeLease(lease_id))) => {
      let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        try
          request(
            "POST",
            model.endpoint,
            "/v1/workspace/leases/\{lease_id}:end",
            model.credential,
          )
        catch {
          _ =>
            ActionFailed(
              model.console.locale,
              console_copy(
                model.console.locale,
                "The workspace lease could not be ended.",
                "无法结束该工作区租约。",
              ),
            )
        } noraise {
          _ =>
            ActionComplete(
              model.console.locale,
              console_copy(
                model.console.locale,
                "Workspace lease \{lease_id} was ended.",
                "工作区租约 \{lease_id} 已结束。",
              ),
            )
        }
      })
      ({ ..model, console: { ..model.console, loading: true } }, cmd)
    }
  }
}

///|
fn app_view(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Html {
  let locale = model.console.locale
  @html.div(class="console-root", [
    @html.details(
      class="connection-panel",
      attrs=@html.Attrs::build().aria_label(
        console_copy(locale, "Controller connection", "控制器连接"),
      ),
      [
        @html.summary([
          @html.span(
            class=if model.credential != "" && model.audit_credential != "" {
              "connection-state connection-state-ready"
            } else {
              "connection-state connection-state-needed"
            },
            if model.credential != "" && model.audit_credential != "" {
              console_copy(locale, "Credentials configured", "凭据已配置")
            } else {
              console_copy(locale, "Credentials required", "需要凭据")
            },
          ),
          @html.span(
            class="connection-summary-label",
            console_copy(locale, "Controller connection", "控制器连接"),
          ),
          @html.span(class="connection-endpoint", model.endpoint),
        ]),
        @html.div(class="connection-form", [
          @html.div(class="connection-field", [
            @html.label(
              for_="operator-token",
              console_copy(locale, "Operator token", "运维令牌"),
            ),
            @html.input(
              id="operator-token",
              input_type=Password,
              value=model.credential,
              auto_complete=Off,
              on_input=emit.map(value => CredentialChanged(value)),
            ),
          ]),
          @html.div(class="connection-field", [
            @html.label(
              for_="audit-token",
              console_copy(locale, "Audit token", "审计令牌"),
            ),
            @html.input(
              id="audit-token",
              input_type=Password,
              value=model.audit_credential,
              auto_complete=Off,
              on_input=emit.map(value => AuditCredentialChanged(value)),
            ),
          ]),
          @html.div(class="connection-field", [
            @html.label(
              for_="inference-token",
              console_copy(
                locale, "Inference token (optional)", "推理令牌（可选）",
              ),
            ),
            @html.input(
              id="inference-token",
              input_type=Password,
              value=model.inference_credential,
              auto_complete=Off,
              on_input=emit.map(value => InferenceCredentialChanged(value)),
            ),
          ]),
          @html.div(class="connection-field", [
            @html.label(
              for_="inference-subject",
              console_copy(
                locale, "Opaque inference subject reference (optional)", "不透明主体引用（可选）",
              ),
            ),
            @html.input(
              id="inference-subject",
              value=model.inference_subject_ref,
              maxlength=256,
              auto_complete=Off,
              attrs=@html.Attrs::build().aria_describedby(
                "inference-subject-help",
              ),
              on_input=emit.map(value => InferenceSubjectChanged(value)),
            ),
            @html.span(
              id="inference-subject-help",
              class="connection-help",
              console_copy(
                locale, "Leave empty when verified mTLS derives identity. Only loopback acceptance clients may send this header directly.",
                "经验证的 mTLS 可推导身份时请留空。仅回环验收客户端可直接发送此标头。",
              ),
            ),
          ]),
          @html.div(class="connection-actions", [
            @html.span(
              class="secondary",
              console_copy(
                locale, "Credentials stay in browser memory and are never written into cluster metadata.",
                "凭据仅保存在浏览器内存中，绝不会写入集群元数据。",
              ),
            ),
            @html.button(
              type_="button",
              class="primary-button",
              disabled=model.credential == "" ||
                model.audit_credential == "" ||
                model.console.loading,
              on_click=emit(Connect),
              console_copy(locale, "Connect and refresh", "连接并刷新"),
            ),
          ]),
        ]),
      ],
    ),
    @ui.interactive_view(model.console, emit.map(message => Console(message))),
  ])
}

///|
fn main {
  let locale = @i18n.parse_locale(stored_locale_preference())
  apply_console_locale(locale)
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      credential: "",
      audit_credential: "",
      inference_credential: "",
      inference_subject_ref: "",
      console: { ..@ui.default_state(), locale, },
      next_directive_generation: 1L,
    },
    view=app_view,
    update~,
  ).mount("app")
}
