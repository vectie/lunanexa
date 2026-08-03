///|
priv struct BrowserStreamEvent {
  sequence : Int
  kind : String
  text : String
  receipt : String
} derive(FromJson)

///|
extern "js" fn configured_endpoint() -> String =
  #| () => globalThis.LUNANEXA_API_ENDPOINT || ""

///|
extern "js" fn current_unix_ms() -> Int64 = "() => BigInt(Date.now())"

///|
extern "js" fn request_promise(
  verb : String,
  url : String,
  token : String,
  body : String,
) -> @js.Promise =
  #| async (verb, url, token, body) => {
  #|   const response = await fetch(url, {
  #|     method: verb,
  #|     headers: {
  #|       "Accept": "application/json",
  #|       "Content-Type": "application/json",
  #|       "Authorization": `Bearer ${token}`
  #|     },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
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
  body : String,
) -> @js.Promise =
  #| async (url, token, body) => {
  #|   const response = await fetch(url, {
  #|     method: "POST",
  #|     headers: {
  #|       "Accept": "text/event-stream",
  #|       "Content-Type": "application/json",
  #|       "Authorization": `Bearer ${token}`
  #|     },
  #|     credentials: "same-origin",
  #|     cache: "no-store",
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
  body? : String = "",
) -> String {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = request_promise(verb, "\{base}\{path}", token, body).wait()
  value.cast()
}

///|
async fn stream_request(
  endpoint : String,
  token : String,
  body : String,
) -> Array[@ui.StreamEventView] {
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  let value = stream_request_promise("\{base}/v1/workloads:stream", token, body).wait()
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
async fn load_console(
  endpoint : String,
  token : String,
  audit_token : String,
  route : @ui.OperatorRoute,
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
        placement_reason: "assigned to \{assignment.node_id} at generation \{assignment.generation}",
      }
    }
  ]
  let active_nodes = nodes.count_if(node => node.state == Active)
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
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "",
  }
}

///|
priv enum LoadOutcome {
  Loaded(@ui.ConsoleState)
  LoadFailed(String)
  ActionComplete(String)
  StreamComplete(Array[@ui.StreamEventView])
  ActionFailed(String)
}

///|
priv struct AppModel {
  endpoint : String
  credential : String
  audit_credential : String
  inference_credential : String
  console : @ui.ConsoleState
  next_directive_generation : Int64
} derive(Eq)

///|
priv enum AppMessage {
  CredentialChanged(String)
  AuditCredentialChanged(String)
  InferenceCredentialChanged(String)
  Connect
  Console(@ui.ConsoleMessage)
  Outcome(LoadOutcome)
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
      )
    catch {
      _ =>
        LoadFailed(
          "The controller could not be reached or rejected this credential.",
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
    Connect => {
      let next = {
        ..model,
        console: { ..model.console, loading: true, error_message: None },
      }
      (next, load_command(next, emit))
    }
    Outcome(Loaded(state)) => ({ ..model, console: state }, @rabbita.none)
    Outcome(LoadFailed(message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            error_message: Some(message),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionComplete(message)) => {
      let next = {
        ..model,
        next_directive_generation: model.next_directive_generation + 1L,
        console: {
          ..model.console,
          confirmation: None,
          loading: true,
          success_message: Some(message),
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
            success_message: Some("Streaming invocation completed."),
          },
        },
        @rabbita.none,
      )
    Outcome(ActionFailed(message)) =>
      (
        {
          ..model,
          console: {
            ..model.console,
            loading: false,
            error_message: Some(message),
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
    Console(SubmitOperation) => {
      let (verb, path, inference) = match model.console.operation_name {
        "issue-enrollment-token" => ("POST", "/v1/enrollment/tokens", false)
        "register-runtime" => ("POST", "/v1/runtimes", false)
        "register-model" => ("POST", "/v1/models", false)
        "record-license" => ("POST", "/v1/licenses", false)
        "record-verification" => ("POST", "/v1/verifications", false)
        "record-evaluation" => ("POST", "/v1/evaluations", false)
        "approve-model" => ("POST", "/v1/models/approve", false)
        "promote-alias" => ("POST", "/v1/aliases/promote", false)
        "set-quota" => ("PUT", "/v1/quotas", false)
        "publish-assignment" => ("PUT", "/v1/assignments", false)
        "invoke-workload" => ("POST", "/v1/workloads", true)
        "record-benchmark" => ("POST", "/v1/benchmarks", false)
        _ => ("", "", false)
      }
      if path == "" || (inference && model.inference_credential == "") {
        return (
          {
            ..model,
            console: {
              ..model.console,
              error_message: Some(
                "Select a supported operation and provide the inference token when invoking.",
              ),
            },
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
            stream_request(model.endpoint, token, model.console.operation_body)
          catch {
            _ => ActionFailed("The streaming invocation was rejected.")
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
              body=model.console.operation_body,
            )
          catch {
            _ => ActionFailed("The typed operation was rejected.")
          } noraise {
            _ =>
              ActionComplete(
                "Operation \{model.console.operation_name} completed.",
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
          _ => ActionFailed("The drain request was rejected.")
        } noraise {
          _ => ActionComplete("Drain requested for \{node_id}.")
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
          _ => ActionFailed("The cordon request was rejected.")
        } noraise {
          _ => ActionComplete("Cordon requested for \{node_id}.")
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
          _ => ActionFailed("The alias rollback was rejected.")
        } noraise {
          _ => ActionComplete("Alias \{alias_name} was rolled back.")
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
          _ => ActionFailed("The deployment stop was rejected.")
        } noraise {
          _ =>
            ActionComplete(
              "Deployment assignment \{assignment_id} was stopped.",
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
  @html.div([
    @html.section(
      class="connection-panel",
      attrs=@html.Attrs::build().aria_label("Controller connection"),
      [
        @html.label(for_="operator-token", "Operator token"),
        @html.input(
          id="operator-token",
          input_type=Password,
          value=model.credential,
          auto_complete=Off,
          on_input=emit.map(value => CredentialChanged(value)),
        ),
        @html.label(for_="inference-token", "Inference token"),
        @html.input(
          id="inference-token",
          input_type=Password,
          value=model.inference_credential,
          auto_complete=Off,
          on_input=emit.map(value => InferenceCredentialChanged(value)),
        ),
        @html.label(for_="audit-token", "Audit token"),
        @html.input(
          id="audit-token",
          input_type=Password,
          value=model.audit_credential,
          auto_complete=Off,
          on_input=emit.map(value => AuditCredentialChanged(value)),
        ),
        @html.button(
          type_="button",
          disabled=model.credential == "" ||
            model.audit_credential == "" ||
            model.console.loading,
          on_click=emit(Connect),
          "Connect / refresh",
        ),
      ],
    ),
    @ui.interactive_view(model.console, emit.map(message => Console(message))),
  ])
}

///|
fn main {
  @rabbita.elmish(
    model={
      endpoint: configured_endpoint(),
      credential: "",
      audit_credential: "",
      inference_credential: "",
      console: @ui.default_state(),
      next_directive_generation: 1L,
    },
    view=app_view,
    update~,
  ).mount("app")
}
