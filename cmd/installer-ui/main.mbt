///|
priv struct RunResult {
  outcome : String
  ok : Bool
  exit_code : Int
  lines : Array[String]
} derive(FromJson)

///|
priv enum AppMessage {
  Installer(@installer_ui.InstallerMessage)
  Outcome(RunResult)
  Rejected(String)
}

///|
extern "js" fn stored_locale() -> String =
  #| () => {
  #|   try { return globalThis.localStorage?.getItem("lunanexa.locale") || ""; }
  #|   catch (_) { return ""; }
  #| }

///|
extern "js" fn sync_locale(
  value : String,
  language : String,
  title : String,
) -> Unit =
  #| (value, language, title) => {
  #|   try { globalThis.localStorage?.setItem("lunanexa.locale", value); } catch (_) {}
  #|   try {
  #|     if (globalThis.document?.documentElement) globalThis.document.documentElement.lang = language;
  #|     if (globalThis.document) globalThis.document.title = title;
  #|   } catch (_) {}
  #| }

///|
extern "js" fn stream_install_promise(
  endpoint : String,
  token : String,
  payload : String,
) -> @js.Promise =
  #| async (endpoint, token, payload) => {
  #|   const lines = [];
  #|   const result = (outcome, ok = false, exit_code = -1) =>
  #|     JSON.stringify({outcome, ok, exit_code, lines});
  #|   let base;
  #|   try {
  #|     const url = new URL(endpoint);
  #|     const loopback = url.protocol === "http:" &&
  #|       (url.hostname === "127.0.0.1" || url.hostname === "[::1]" || url.hostname === "::1");
  #|     if (!loopback || url.username || url.password || (url.pathname !== "/" && url.pathname !== "") || url.search || url.hash) {
  #|       throw new Error("companion endpoint must be a plain HTTP loopback origin");
  #|     }
  #|     base = url.origin;
  #|   } catch (_) {
  #|     return result("rejected");
  #|   }
  #|   let reader;
  #|   try {
  #|     const response = await fetch(`${base}/v1/install:run`, {
  #|       method: "POST",
  #|       headers: {
  #|         "Accept": "text/event-stream",
  #|         "Authorization": `Bearer ${token}`,
  #|         "Content-Type": "application/json"
  #|       },
  #|       cache: "no-store",
  #|       credentials: "omit",
  #|       redirect: "error",
  #|       body: payload
  #|     });
  #|     // These statuses are emitted only by the companion's pre-execution guards.
  #|     if ([400, 401, 403, 404, 413].includes(response.status)) return result("rejected");
  #|     if (!response.ok || !response.body) return result("unknown");
  #|     reader = response.body.getReader();
  #|     const decoder = new TextDecoder();
  #|     let buffer = "";
  #|     let outputBytes = 0;
  #|     let renderedLines = 0;
  #|     const appendToLog = (line) => {
  #|       try {
  #|         const log = globalThis.document?.querySelector(".terminal");
  #|         if (!log) return;
  #|         log.textContent = renderedLines === 0 ? line : `${log.textContent || ""}\n${line}`;
  #|         renderedLines += 1;
  #|         log.scrollTop = log.scrollHeight;
  #|       } catch (_) { /* Rendering failure cannot change the command outcome. */ }
  #|     };
  #|     const appendLine = (text) => {
  #|       // Keep the companion's redactions, and never echo the session bearer.
  #|       const sensitive = (token && text.includes(token)) ||
  #|         /authorization:|bearer |password[=:]|private[-_]key|node-token|bootstrap-token|operator-token|"secret"|secret=/i.test(text);
  #|       const line = (sensitive ? "[redacted sensitive output]" : text).slice(0, 4096);
  #|       outputBytes += new TextEncoder().encode(line).byteLength;
  #|       if (outputBytes > 1048576 || lines.length >= 500) {
  #|         throw new Error("installer output limit exceeded");
  #|       }
  #|       lines.push(line);
  #|       appendToLog(line);
  #|     };
  #|     while (true) {
  #|       const {value, done} = await reader.read();
  #|       buffer += decoder.decode(value || new Uint8Array(), {stream: !done});
  #|       buffer = buffer.replaceAll("\r\n", "\n");
  #|       if (buffer.length > 1048576) throw new Error("installer stream framing limit exceeded");
  #|       let boundary;
  #|       while ((boundary = buffer.indexOf("\n\n")) >= 0) {
  #|         const block = buffer.slice(0, boundary);
  #|         buffer = buffer.slice(boundary + 2);
  #|         for (const row of block.split("\n")) {
  #|           if (!row.startsWith("data:")) continue;
  #|           const event = JSON.parse(row.slice(5).trim());
  #|           if (event?.kind === "line" && typeof event.text === "string") {
  #|             appendLine(event.text);
  #|           } else if (event?.kind === "complete" && typeof event.ok === "boolean" &&
  #|                      Number.isInteger(event.exit_code) && event.exit_code >= -2147483648 &&
  #|                      event.exit_code <= 2147483647 && event.ok === (event.exit_code === 0)) {
  #|             return result("complete", event.ok, event.exit_code);
  #|           } else {
  #|             throw new Error("invalid installer event");
  #|           }
  #|         }
  #|       }
  #|       if (done) break;
  #|     }
  #|     return result("unknown");
  #|   } catch (_) {
  #|     // Once POST has been attempted, transport/parser limits prove no outcome.
  #|     // Return the bounded received evidence; never retry or imply rollback.
  #|     return result("unknown");
  #|   } finally {
  #|     if (reader) {
  #|       try { void reader.cancel().catch(() => {}); } catch (_) {}
  #|       try { reader.releaseLock(); } catch (_) {}
  #|     }
  #|   }
  #| }

///|
fn title(locale : @i18n.Locale) -> String {
  if locale.is_chinese() {
    "LunaNexa | 集群安装器"
  } else {
    "LunaNexa | Cluster Installer"
  }
}

///|
fn request_from_state(
  state : @installer_ui.InstallerState,
  apply : Bool,
) -> @install_contract.InstallRequest raise {
  {
    version: @install_contract.request_version,
    deployment_target: state.form.deployment_target,
    apply,
    confirmation: state.form.confirmation,
    ssh_user: state.form.ssh_user.trim().to_owned(),
    ssh_port: @string.parse_int64(state.form.ssh_port.trim()).to_int(),
    ssh_key_path: state.form.ssh_key_path.trim().to_owned(),
    known_hosts_path: state.form.known_hosts_path.trim().to_owned(),
    management_node: state.form.management_node.trim().to_owned(),
    management_host: state.form.management_host.trim().to_owned(),
    compute_nodes: @install_contract.parse_compute_targets(
      state.form.compute_targets,
    ),
    cluster_namespace: state.form.cluster_namespace.trim().to_owned(),
    kubeconfig_path: state.form.kubeconfig_path.trim().to_owned(),
    rendered_directory: state.form.rendered_directory.trim().to_owned(),
    management_secret_manifest: state.form.management_secret_manifest
    .trim()
    .to_owned(),
    secret_directory: state.form.secret_directory.trim().to_owned(),
    cli_path: state.form.cli_path.trim().to_owned(),
  }
}

///|
fn run_command(
  state : @installer_ui.InstallerState,
  apply : Bool,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    let request = try {
      let request = request_from_state(state, apply)
      @install_contract.validate_request(request)
      request
    } catch {
      _ => return Rejected(rejection_message(state.locale))
    }
    try {
      let value = stream_install_promise(
        state.form.companion_endpoint,
        state.form.session_token,
        request.to_json().stringify(),
      ).wait()
      let text : String = value.cast()
      let result : RunResult = @json.from_json(@json.parse(text))
      Outcome(result)
    } catch {
      _ => Outcome({ outcome: "unknown", ok: false, exit_code: -1, lines: [], })
    } noraise {
      message => message
    }
  })
}

///|
fn rejection_message(locale : @i18n.Locale) -> String {
  if locale.is_chinese() {
    "请求在执行前被阻止。请检查本地伴随程序、会话令牌和表单字段。"
  } else {
    "Request blocked before execution. Check the local companion, session token, and form fields."
  }
}

///|
fn apply_outcome(
  state : @installer_ui.InstallerState,
  result : RunResult,
) -> @installer_ui.InstallerState {
  let next = result.lines.fold(init=state, fn(current, line) {
    @installer_ui.update(current, TerminalLine(line))
  })
  @installer_ui.update(
    next,
    match result.outcome {
      "complete" => RunFinished(result.ok, result.exit_code)
      "rejected" => RunRejected(rejection_message(state.locale))
      _ => RunOutcomeUnknown
    },
  )
}

///|
fn update(
  state : @installer_ui.InstallerState,
  message : AppMessage,
  emit : @rabbita.Emit[AppMessage],
) -> (@installer_ui.InstallerState, @rabbita.Cmd) {
  match message {
    Installer(LocaleChanged(locale)) => {
      sync_locale(locale.storage_value(), locale.language_tag(), title(locale))
      (@installer_ui.update(state, LocaleChanged(locale)), @rabbita.none)
    }
    Installer(PreviewRequested) => {
      guard @installer_ui.can_preview(state) else {
        return (state, @rabbita.none)
      }
      let next = @installer_ui.update(state, PreviewRequested)
      (next, run_command(next, false, emit))
    }
    Installer(ApplyRequested) => {
      guard @installer_ui.can_apply(state) else {
        return (state, @rabbita.none)
      }
      let next = @installer_ui.update(state, ApplyRequested)
      (next, run_command(next, true, emit))
    }
    Installer(inner) => (@installer_ui.update(state, inner), @rabbita.none)
    Outcome(result) => (apply_outcome(state, result), @rabbita.none)
    Rejected(message) =>
      (@installer_ui.update(state, RunRejected(message)), @rabbita.none)
  }
}

///|
fn main {
  let locale = @i18n.parse_locale(stored_locale())
  sync_locale(locale.storage_value(), locale.language_tag(), title(locale))
  @rabbita.elmish(
    model=@installer_ui.default_state(locale~),
    view=(state, emit) => {
      @installer_ui.interactive_view(
        state,
        emit.map(message => Installer(message)),
      )
    },
    update~,
  ).mount("app")
}
