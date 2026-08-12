///|
priv struct RunResult {
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
  #|     throw new Error("companion endpoint must be a plain HTTP loopback origin");
  #|   }
  #|   const response = await fetch(`${base}/v1/install:run`, {
  #|     method: "POST",
  #|     headers: {
  #|       "Accept": "text/event-stream",
  #|       "Authorization": `Bearer ${token}`,
  #|       "Content-Type": "application/json"
  #|     },
  #|     cache: "no-store",
  #|     credentials: "omit",
  #|     redirect: "error",
  #|     body: payload
  #|   });
  #|   if (!response.ok || !response.body) throw new Error(`installer HTTP ${response.status}`);
  #|   const reader = response.body.getReader();
  #|   const decoder = new TextDecoder();
  #|   let buffer = "";
  #|   let terminal = null;
  #|   const lines = [];
  #|   let outputBytes = 0;
  #|   const appendLine = (text) => {
  #|     const line = String(text).slice(0, 4096);
  #|     outputBytes += new TextEncoder().encode(line).byteLength;
  #|     if (outputBytes > 1048576 || lines.length >= 500) {
  #|       throw new Error("installer output limit exceeded");
  #|     }
  #|     lines.push(line);
  #|     const log = globalThis.document?.querySelector(".terminal");
  #|     if (log) {
  #|       log.textContent = `${log.textContent || ""}\n${line}`;
  #|       log.scrollTop = log.scrollHeight;
  #|     }
  #|   };
  #|   while (true) {
  #|     const {value, done} = await reader.read();
  #|     buffer += decoder.decode(value || new Uint8Array(), {stream: !done}).replaceAll("\r\n", "\n");
  #|     if (buffer.length > 1048576) throw new Error("installer stream framing limit exceeded");
  #|     let boundary;
  #|     while ((boundary = buffer.indexOf("\n\n")) >= 0) {
  #|       const block = buffer.slice(0, boundary);
  #|       buffer = buffer.slice(boundary + 2);
  #|       for (const row of block.split("\n")) {
  #|         if (!row.startsWith("data:")) continue;
  #|         const event = JSON.parse(row.slice(5).trim());
  #|         if (event.kind === "line" && typeof event.text === "string") appendLine(event.text);
  #|         if (event.kind === "complete") terminal = event;
  #|       }
  #|     }
  #|     if (done) break;
  #|   }
  #|   if (!terminal || typeof terminal.ok !== "boolean" || !Number.isInteger(terminal.exit_code)) {
  #|     throw new Error("installer stream ended without a terminal result");
  #|   }
  #|   return JSON.stringify({ok: terminal.ok, exit_code: terminal.exit_code, lines});
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
    apply,
    confirmation: state.form.confirmation,
    ssh_user: state.form.ssh_user.trim().to_owned(),
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
    try {
      let request = request_from_state(state, apply)
      @install_contract.validate_request(request)
      let value = stream_install_promise(
        state.form.companion_endpoint,
        state.form.session_token,
        request.to_json().stringify(),
      ).wait()
      let text : String = value.cast()
      let result : RunResult = @json.from_json(@json.parse(text))
      Outcome(result)
    } catch {
      _ =>
        Rejected(
          if state.locale.is_chinese() {
            "无法启动部署。请检查本地伴随程序、会话令牌和表单字段。"
          } else {
            "Deployment could not start. Check the local companion, session token, and form fields."
          },
        )
    } noraise {
      message => message
    }
  })
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
      let next = @installer_ui.update(state, PreviewRequested)
      (next, run_command(next, false, emit))
    }
    Installer(ApplyRequested) => {
      let next = @installer_ui.update(state, ApplyRequested)
      (next, run_command(next, true, emit))
    }
    Installer(inner) => (@installer_ui.update(state, inner), @rabbita.none)
    Outcome(result) => {
      let next = result.lines.fold(init=state, fn(current, line) {
        @installer_ui.update(current, TerminalLine(line))
      })
      (
        @installer_ui.update(next, RunFinished(result.ok, result.exit_code)),
        @rabbita.none,
      )
    }
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
