///|
pub(all) enum RunState {
  Idle
  RunningPreview
  RunningApply
  Succeeded
  Failed
} derive(Debug, Eq)

///|
pub(all) struct DeploymentForm {
  local_simulation : Bool
  companion_endpoint : String
  session_token : String
  ssh_user : String
  ssh_key_path : String
  known_hosts_path : String
  management_node : String
  management_host : String
  compute_targets : String
  cluster_namespace : String
  kubeconfig_path : String
  rendered_directory : String
  secret_directory : String
  cli_path : String
  confirmation : String
} derive(Debug, Eq)

///|
pub(all) struct InstallerState {
  locale : @i18n.Locale
  form : DeploymentForm
  run_state : RunState
  preview_verified : Bool
  terminal_lines : Array[String]
  error_message : String?
} derive(Debug, Eq)

///|
pub(all) enum InstallerMessage {
  LocaleChanged(@i18n.Locale)
  DeploymentTargetChanged(String)
  CompanionEndpointChanged(String)
  SessionTokenChanged(String)
  SshUserChanged(String)
  SshKeyPathChanged(String)
  KnownHostsPathChanged(String)
  ManagementNodeChanged(String)
  ManagementHostChanged(String)
  ComputeTargetsChanged(String)
  ClusterNamespaceChanged(String)
  KubeconfigPathChanged(String)
  RenderedDirectoryChanged(String)
  SecretDirectoryChanged(String)
  CliPathChanged(String)
  ConfirmationChanged(String)
  PreviewRequested
  ApplyRequested
  TerminalLine(String)
  RunFinished(Bool, Int)
  RunRejected(String)
  ClearTerminal
} derive(Debug, Eq)

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
pub fn default_state(locale~ : @i18n.Locale) -> InstallerState {
  {
    locale,
    form: {
      local_simulation: false,
      companion_endpoint: "http://127.0.0.1:4198",
      session_token: "",
      ssh_user: "cluster-admin",
      ssh_key_path: "",
      known_hosts_path: "",
      management_node: "management-01",
      management_host: "",
      compute_targets: "dgx-spark-01=\ndgx-spark-02=\ndgx-spark-03=\ndgx-spark-04=",
      cluster_namespace: "lunanexa",
      kubeconfig_path: "",
      rendered_directory: "",
      secret_directory: "",
      cli_path: "",
      confirmation: "",
    },
    run_state: Idle,
    preview_verified: false,
    terminal_lines: [],
    error_message: None,
  }
}

///|
pub fn is_running(state : InstallerState) -> Bool {
  state.run_state == RunningPreview || state.run_state == RunningApply
}

///|
pub fn form_complete(state : InstallerState) -> Bool {
  let form = state.form
  form.companion_endpoint.trim() != "" &&
  form.session_token.length() >= 32 &&
  form.cluster_namespace.trim() != "" &&
  form.kubeconfig_path.trim() != "" &&
  (
    form.local_simulation ||
    (
      form.ssh_user.trim() != "" &&
      form.ssh_key_path.trim() != "" &&
      form.known_hosts_path.trim() != "" &&
      form.management_node.trim() != "" &&
      form.management_host.trim() != "" &&
      form.compute_targets.split("\n").filter(line => line.trim() != "").count() ==
      4 &&
      form.rendered_directory.trim() != "" &&
      form.secret_directory.trim() != "" &&
      form.cli_path.trim() != ""
    )
  )
}

///|
pub fn update(
  state : InstallerState,
  message : InstallerMessage,
) -> InstallerState {
  match message {
    LocaleChanged(locale) => { ..state, locale, error_message: None }
    DeploymentTargetChanged(value) =>
      {
        ..state,
        form: {
          ..state.form,
          local_simulation: value == "local-colima",
          kubeconfig_path: if value == "local-colima" &&
            state.form.kubeconfig_path.trim() == "" {
            "~/.kube/lunanexa-sim"
          } else {
            state.form.kubeconfig_path
          },
        },
        preview_verified: false,
      }
    CompanionEndpointChanged(value) =>
      {
        ..state,
        form: { ..state.form, companion_endpoint: value },
        preview_verified: false,
      }
    SessionTokenChanged(value) =>
      {
        ..state,
        form: { ..state.form, session_token: value },
        preview_verified: false,
      }
    SshUserChanged(value) =>
      {
        ..state,
        form: { ..state.form, ssh_user: value },
        preview_verified: false,
      }
    SshKeyPathChanged(value) =>
      {
        ..state,
        form: { ..state.form, ssh_key_path: value },
        preview_verified: false,
      }
    KnownHostsPathChanged(value) =>
      {
        ..state,
        form: { ..state.form, known_hosts_path: value },
        preview_verified: false,
      }
    ManagementNodeChanged(value) =>
      {
        ..state,
        form: { ..state.form, management_node: value },
        preview_verified: false,
      }
    ManagementHostChanged(value) =>
      {
        ..state,
        form: { ..state.form, management_host: value },
        preview_verified: false,
      }
    ComputeTargetsChanged(value) =>
      {
        ..state,
        form: { ..state.form, compute_targets: value },
        preview_verified: false,
      }
    ClusterNamespaceChanged(value) =>
      {
        ..state,
        form: { ..state.form, cluster_namespace: value },
        preview_verified: false,
      }
    KubeconfigPathChanged(value) =>
      {
        ..state,
        form: { ..state.form, kubeconfig_path: value },
        preview_verified: false,
      }
    RenderedDirectoryChanged(value) =>
      {
        ..state,
        form: { ..state.form, rendered_directory: value },
        preview_verified: false,
      }
    SecretDirectoryChanged(value) =>
      {
        ..state,
        form: { ..state.form, secret_directory: value },
        preview_verified: false,
      }
    CliPathChanged(value) =>
      {
        ..state,
        form: { ..state.form, cli_path: value },
        preview_verified: false,
      }
    ConfirmationChanged(value) =>
      { ..state, form: { ..state.form, confirmation: value } }
    PreviewRequested =>
      {
        ..state,
        run_state: RunningPreview,
        preview_verified: false,
        terminal_lines: [
          copy(
            state.locale,
            "$ starting dry-run preview",
            "$ 开始预检演练",
          ),
        ],
        error_message: None,
      }
    ApplyRequested =>
      {
        ..state,
        run_state: RunningApply,
        terminal_lines: [
          copy(
            state.locale,
            "$ starting confirmed deployment",
            "$ 开始已确认的部署",
          ),
        ],
        error_message: None,
      }
    TerminalLine(line) => {
      let lines = [..state.terminal_lines, line]
      {
        ..state,
        terminal_lines: if lines.length() > 500 {
          lines[lines.length() - 500:].to_owned()
        } else {
          lines
        },
      }
    }
    RunFinished(ok, exit_code) =>
      {
        ..state,
        run_state: if ok {
          Succeeded
        } else {
          Failed
        },
        preview_verified: state.run_state == RunningPreview && ok,
        terminal_lines: [
          ..state.terminal_lines,
          if ok {
            copy(
              state.locale,
              "[complete] command exited successfully",
              "[完成] 命令执行成功",
            )
          } else {
            copy(
              state.locale,
              "[failed] exit code \{exit_code}",
              "[失败] 退出代码 \{exit_code}",
            )
          },
        ],
      }
    RunRejected(message) =>
      {
        ..state,
        run_state: Failed,
        preview_verified: false,
        error_message: Some(message),
      }
    ClearTerminal => { ..state, terminal_lines: [], error_message: None }
  }
}

///|
fn emit_value(
  emit : @rabbita.Emit[InstallerMessage],
  wrap : (String) -> InstallerMessage,
) -> @rabbita.Emit[String] {
  emit.map(wrap)
}

///|
fn field(
  label : String,
  id : String,
  value : String,
  placeholder : String,
  disabled : Bool,
  on_input : @rabbita.Emit[String],
  secret? : Bool = false,
  hidden? : Bool = false,
) -> @rabbita.Html {
  @html.div(
    class=if hidden {
      "install-field simulation-hidden"
    } else {
      "install-field"
    },
    [
      @html.label(for_=id, label),
      @html.input(
        id~,
        input_type=if secret { Password } else { Text },
        value~,
        placeholder~,
        auto_complete=Off,
        attrs=@html.Attrs::build().disabled(disabled),
        on_input~,
      ),
    ],
  )
}

///|
fn styles() -> String {
  let body_reset = "body{margin:0}"
  body_reset +
  (
    #|:root{color-scheme:dark;--bg:#071018;--panel:#0d1823;--panel2:#101e2b;--line:#253749;--muted:#92a4b7;--ink:#edf4f8;--accent:#68ddb0;--danger:#ff867d;--warning:#e9bf70;font-family:Inter,"Noto Sans SC","PingFang SC",system-ui,sans-serif}.installer-shell{min-height:100vh;background:radial-gradient(circle at 85% 0,rgba(42,133,116,.14),transparent 32rem),var(--bg);color:var(--ink)}*{box-sizing:border-box}.installer-shell .simulation-hidden{display:none}.install-topbar{position:sticky;top:0;z-index:10;display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.8rem clamp(1rem,3vw,2.5rem);border-bottom:1px solid var(--line);background:rgba(7,16,24,.94);backdrop-filter:blur(16px)}.brand{display:flex;align-items:center;gap:.7rem}.brand-mark{display:grid;width:2rem;height:2rem;place-items:center;border-radius:.45rem;background:var(--accent);color:#05251a;font-weight:900}.brand strong{display:block;font-size:.88rem}.brand span:last-child{display:block;color:var(--muted);font-size:.68rem}.top-actions{display:flex;align-items:center;gap:.7rem}.top-actions a{color:var(--muted);font-size:.72rem}.top-actions select{min-height:2.75rem;padding:0 .7rem;border:1px solid var(--line);border-radius:.45rem;background:var(--panel);color:var(--ink)}.install-main{width:min(92rem,100%);margin:auto;padding:clamp(1rem,3vw,2.5rem);display:grid;grid-template-columns:minmax(0,1.05fr) minmax(24rem,.95fr);gap:1.25rem}.install-intro{grid-column:1/-1;display:flex;justify-content:space-between;gap:2rem;align-items:end;padding-bottom:.5rem}.install-intro p{max-width:56rem;margin:.45rem 0 0;color:var(--muted);line-height:1.55}.install-intro h1{margin:0;font-size:clamp(1.65rem,3vw,2.35rem);letter-spacing:-.035em}.safety-badge{flex:none;padding:.5rem .7rem;border:1px solid rgba(104,221,176,.35);border-radius:999px;color:var(--accent);font-size:.7rem;font-weight:800}.install-card{border:1px solid var(--line);border-radius:.8rem;background:linear-gradient(180deg,rgba(255,255,255,.025),transparent),var(--panel);overflow:hidden}.card-heading{padding:1rem 1.1rem;border-bottom:1px solid var(--line)}.card-heading h2{margin:0;font-size:1rem}.card-heading p{margin:.35rem 0 0;color:var(--muted);font-size:.73rem;line-height:1.5}.install-section{padding:1rem 1.1rem;border-bottom:1px solid var(--line)}.install-section:last-child{border-bottom:0}.section-label{margin:0 0 .75rem;color:var(--accent);font-size:.66rem;font-weight:850;letter-spacing:.1em;text-transform:uppercase}.field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.75rem}.install-field label{display:block;margin:0 0 .3rem;color:#becad5;font-size:.7rem;font-weight:750}.install-field input,.install-field textarea,.install-field select{width:100%;min-height:2.75rem;padding:.65rem .72rem;border:1px solid #31485c;border-radius:.5rem;background:#08131d;color:var(--ink);font:inherit}.install-field textarea{min-height:8.7rem;resize:vertical;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.72rem;line-height:1.6}.install-field input:focus,.install-field textarea:focus,.install-field select:focus,.top-actions select:focus,button:focus{outline:2px solid var(--accent);outline-offset:2px}.field-help{margin:.5rem 0 0;color:var(--muted);font-size:.67rem;line-height:1.5}.simulation-note{margin:.75rem 0 0;padding:.7rem;border:1px solid rgba(104,221,176,.28);border-radius:.5rem;background:rgba(104,221,176,.06);color:#bdf5df;font-size:.68rem;line-height:1.5}.terminal-card{position:sticky;top:5.5rem;align-self:start}.terminal-toolbar{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.75rem 1rem;border-bottom:1px solid var(--line)}.terminal-status{display:flex;align-items:center;gap:.5rem;font-size:.72rem;font-weight:800}.status-dot{width:.5rem;height:.5rem;border-radius:50%;background:#637488}.status-dot.running{background:var(--warning);box-shadow:0 0 0 .25rem rgba(233,191,112,.1)}.status-dot.ok{background:var(--accent)}.status-dot.failed{background:var(--danger)}button{min-height:2.75rem;padding:.55rem .85rem;border:1px solid #355068;border-radius:.5rem;background:#142435;color:var(--ink);font-weight:800;cursor:pointer}button:hover:not(:disabled){border-color:#5d829f}button:disabled{opacity:.45;cursor:not-allowed}.terminal-toolbar button{min-height:2.1rem;padding:.35rem .6rem;font-size:.68rem}.terminal{height:min(60vh,37rem);margin:0;padding:1rem;overflow:auto;background:#03080d;color:#c9d8e3;font:500 .72rem/1.65 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap;overflow-wrap:anywhere}.terminal-empty{color:#667b8d}.run-actions{display:grid;grid-template-columns:1fr 1fr;gap:.75rem}.preview-button{border-color:#3f7768;background:#163b31;color:#bdf5df}.danger-zone{margin-top:.85rem;padding:.85rem;border:1px solid rgba(255,134,125,.32);border-radius:.6rem;background:rgba(255,134,125,.045)}.danger-zone strong{display:block;color:#ffc1bc;font-size:.76rem}.danger-zone p{margin:.35rem 0 .65rem;color:#b9a5a6;font-size:.68rem;line-height:1.5}.danger-button{width:100%;border-color:#9d4e4a;background:#562725;color:#fff}.error-banner{grid-column:1/-1;padding:.75rem 1rem;border:1px solid rgba(255,134,125,.4);border-radius:.55rem;background:rgba(255,134,125,.08);color:#ffc9c5;font-size:.75rem}.stage-list{display:grid;gap:.45rem;margin:0;padding:0;list-style:none}.stage-list li{display:flex;gap:.6rem;color:var(--muted);font-size:.7rem}.stage-number{color:var(--accent);font-family:ui-monospace,monospace}[lang^=zh] .section-label{letter-spacing:0;text-transform:none}@media(max-width:62rem){.install-main{grid-template-columns:1fr}.terminal-card{position:relative;top:auto}.terminal{height:28rem}}@media(max-width:40rem){.install-topbar,.install-intro{align-items:flex-start;flex-direction:column}.top-actions{width:100%;justify-content:space-between}.field-grid,.run-actions{grid-template-columns:1fr}.install-main{padding:1rem}.safety-badge{align-self:flex-start}}
  )
}

///|
fn run_label(locale : @i18n.Locale, state : RunState) -> String {
  match state {
    Idle => copy(locale, "Waiting for preview", "等待预检")
    RunningPreview => copy(locale, "Preview running", "正在预检")
    RunningApply => copy(locale, "Deployment running", "正在部署")
    Succeeded => copy(locale, "Completed", "已完成")
    Failed => copy(locale, "Needs attention", "需要处理")
  }
}

///|
fn run_tone(state : RunState) -> String {
  match state {
    RunningPreview | RunningApply => "running"
    Succeeded => "ok"
    Failed => "failed"
    Idle => ""
  }
}

///|
fn stage_label(
  locale : @i18n.Locale,
  index : Int,
  fallback : String,
  local_simulation : Bool,
) -> String {
  if !locale.is_chinese() {
    return fallback
  }
  if local_simulation {
    return match index {
      0 => "验证专用 Colima 配置"
      1 => "验证 Docker 和 kind 工具"
      2 => "检查或创建五个 Kubernetes 节点"
      3 => "应用仅用于模拟的放置探针"
      4 => "验证一个管理节点和四个计算节点"
      _ => fallback
    }
  }
  match index {
    0 => "验证本地路径"
    1 => "SSH 主机密钥预检"
    2 => "检查管理节点磁盘和 Kubernetes"
    3 => "检查四台 DGX GPU 工作节点"
    4 => "标记管理节点和 GPU 节点"
    5 => "应用已渲染的管理平面清单"
    6 => "安装受保护的节点材料"
    7 => "签发一次性注册令牌"
    8 => "应用节点代理并验证心跳"
    _ => fallback
  }
}

///|
pub fn interactive_view(
  state : InstallerState,
  emit : @rabbita.Emit[InstallerMessage],
) -> @rabbita.Html {
  let running = is_running(state)
  let complete = form_complete(state)
  let locale = state.locale
  let local_simulation = state.form.local_simulation
  let stage_names = if local_simulation {
    @install_contract.local_stage_names()
  } else {
    @install_contract.stage_names()
  }
  @html.div(class="installer-shell", [
    @html.style_tag(styles()),
    @html.header(class="install-topbar", [
      @html.div(class="brand", [
        @html.span(class="brand-mark", "LN"),
        @html.div([
          @html.strong("LunaNexa"),
          @html.span(copy(locale, "Cluster installer", "集群安装器")),
        ]),
      ]),
      @html.div(class="top-actions", [
        @html.a(
          href="../console/",
          copy(locale, "Back to console", "返回控制台"),
        ),
        @html.select(
          attrs=@html.Attrs::build().aria_label(
            copy(locale, "Language", "语言"),
          ),
          on_change=emit_value(emit, value => {
            LocaleChanged(@i18n.parse_locale(value))
          }),
          [
            @html.option(value="en", selected=locale == English, "English"),
            @html.option(
              value="zh-CN",
              selected=locale == ChineseSimplified,
              "简体中文",
            ),
          ],
        ),
      ]),
    ]),
    @html.main_(class="install-main", [
      @html.div(class="install-intro", [
        @html.div([
          @html.h1(
            copy(
              locale, "Deploy your private DGX cluster", "部署您的私有 DGX 集群",
            ),
          ),
          @html.p(
            if local_simulation {
              copy(
                locale, "Preview and reconcile one lightweight management node plus four compute workers inside the dedicated Colima simulation.",
                "在专用 Colima 模拟中预览并协调一个轻量管理节点和四个计算工作节点。",
              )
            } else {
              copy(
                locale, "Verify SSH trust, inspect one management node and four DGX workers, preview every stage, then run the reviewed LunaNexa installation with live redacted output.",
                "验证 SSH 信任，检查一台管理节点和四台 DGX 工作节点，预览每个阶段，然后通过实时脱敏输出执行经过审核的 LunaNexa 安装。",
              )
            },
          ),
        ]),
        @html.span(
          class="safety-badge",
          copy(
            locale, "Dry-run first · no arbitrary shell", "先预检 · 不允许任意 Shell",
          ),
        ),
      ]),
      match state.error_message {
        Some(message) =>
          @html.div(
            class="error-banner",
            attrs=@html.Attrs::build().role("alert"),
            message,
          )
        None => @html.nothing
      },
      @html.section(class="install-card", [
        @html.div(class="card-heading", [
          @html.h2(copy(locale, "Cluster inventory", "集群清单")),
          @html.p(
            if local_simulation {
              copy(
                locale, "The isolated kubeconfig is the only local path required. No credentials or production manifests are used.",
                "只需要隔离的 kubeconfig 路径。不使用密钥或生产清单。",
              )
            } else {
              copy(
                locale, "Paths refer to files on the trusted operator machine running the local companion. Secret contents never enter this page.",
                "路径指向运行本地伴随程序的可信运维机器上的文件。密钥内容绝不会进入此页面。",
              )
            },
          ),
        ]),
        @html.div(class="install-section", [
          @html.p(
            class="section-label",
            copy(locale, "1 · Local companion", "1 · 本地伴随程序"),
          ),
          @html.div(class="field-grid", [
            field(
              copy(locale, "Companion endpoint", "伴随程序端点"),
              "companion-endpoint",
              state.form.companion_endpoint,
              "http://127.0.0.1:4198",
              running,
              emit_value(emit, value => CompanionEndpointChanged(value)),
            ),
            field(
              copy(locale, "Session token", "会话令牌"),
              "session-token",
              state.form.session_token,
              copy(
                locale, "Paste token printed by start script", "粘贴启动脚本输出的令牌",
              ),
              running,
              emit_value(emit, value => SessionTokenChanged(value)),
              secret=true,
            ),
            @html.div(class="install-field", [
              @html.label(
                for_="deployment-target",
                copy(locale, "Deployment target", "部署目标"),
              ),
              @html.select(
                id="deployment-target",
                attrs=@html.Attrs::build().disabled(running),
                on_change=emit_value(emit, value => {
                  DeploymentTargetChanged(value)
                }),
                [
                  @html.option(
                    value="remote-cluster",
                    selected=!local_simulation,
                    copy(locale, "Remote DGX cluster", "远程 DGX 集群"),
                  ),
                  @html.option(
                    value="local-colima",
                    selected=local_simulation,
                    copy(
                      locale, "Local Colima simulation", "本地 Colima 模拟",
                    ),
                  ),
                ],
              ),
            ]),
          ]),
          if local_simulation {
            @html.p(
              class="simulation-note",
              copy(
                locale, "Simulation uses the isolated kind-lunanexa-sim context. SSH, NVIDIA, secrets, production manifests and ingress are skipped.",
                "模拟仅使用隔离的 kind-lunanexa-sim 上下文。将跳过 SSH、NVIDIA、密钥、生产清单和入口。",
              ),
            )
          } else {
            @html.nothing
          },
        ]),
        @html.div(
          class=if local_simulation {
            "install-section simulation-hidden"
          } else {
            "install-section"
          },
          [
            @html.p(
              class="section-label",
              copy(locale, "2 · SSH trust", "2 · SSH 信任"),
            ),
            @html.div(class="field-grid", [
              field(
                copy(locale, "SSH user", "SSH 用户"),
                "ssh-user",
                state.form.ssh_user,
                "cluster-admin",
                running || local_simulation,
                emit_value(emit, value => SshUserChanged(value)),
              ),
              field(
                copy(locale, "Private key path", "私钥路径"),
                "ssh-key",
                state.form.ssh_key_path,
                "/Users/operator/.ssh/lunanexa",
                running || local_simulation,
                emit_value(emit, value => SshKeyPathChanged(value)),
              ),
              field(
                copy(
                  locale, "Pinned known_hosts path", "固定 known_hosts 路径",
                ),
                "known-hosts",
                state.form.known_hosts_path,
                "/Users/operator/.ssh/known_hosts",
                running || local_simulation,
                emit_value(emit, value => KnownHostsPathChanged(value)),
              ),
            ]),
            @html.p(
              class="field-help",
              copy(
                locale, "StrictHostKeyChecking=yes and BatchMode=yes are always enforced. Password prompts and first-use host-key acceptance are rejected.",
                "始终强制执行 StrictHostKeyChecking=yes 和 BatchMode=yes。拒绝密码提示和首次使用时接受主机密钥。",
              ),
            ),
          ],
        ),
        @html.div(
          class=if local_simulation {
            "install-section simulation-hidden"
          } else {
            "install-section"
          },
          [
            @html.p(
              class="section-label",
              copy(locale, "3 · Nodes", "3 · 节点"),
            ),
            @html.div(class="field-grid", [
              field(
                copy(
                  locale, "Management Kubernetes node", "管理 Kubernetes 节点",
                ),
                "management-node",
                state.form.management_node,
                "management-01",
                running || local_simulation,
                emit_value(emit, value => ManagementNodeChanged(value)),
              ),
              field(
                copy(locale, "Management SSH host", "管理节点 SSH 主机"),
                "management-host",
                state.form.management_host,
                "10.0.0.10",
                running || local_simulation,
                emit_value(emit, value => ManagementHostChanged(value)),
              ),
            ]),
            @html.div(class="install-field", [
              @html.label(
                for_="compute-targets",
                copy(
                  locale, "Four compute nodes · node-name=ssh-host", "四台计算节点 · 节点名=SSH 主机",
                ),
              ),
              @html.textarea(
                id="compute-targets",
                value=state.form.compute_targets,
                attrs=@html.Attrs::build().disabled(running || local_simulation),
                on_input=emit_value(emit, value => ComputeTargetsChanged(value)),
                "",
              ),
            ]),
          ],
        ),
        @html.div(class="install-section", [
          @html.p(
            class="section-label",
            copy(
              locale, "4 · Local deployment paths", "4 · 本地部署路径",
            ),
          ),
          @html.div(class="field-grid", [
            field(
              copy(locale, "Kubernetes namespace", "Kubernetes 命名空间"),
              "cluster-namespace",
              state.form.cluster_namespace,
              "lunanexa",
              running,
              emit_value(emit, value => ClusterNamespaceChanged(value)),
            ),
            field(
              "kubeconfig",
              "kubeconfig",
              state.form.kubeconfig_path,
              "/Users/operator/.kube/config",
              running,
              emit_value(emit, value => KubeconfigPathChanged(value)),
            ),
            field(
              copy(
                locale, "Rendered manifest directory", "已渲染清单目录",
              ),
              "rendered-directory",
              state.form.rendered_directory,
              "/srv/lunanexa/rendered",
              running || local_simulation,
              emit_value(emit, value => RenderedDirectoryChanged(value)),
              hidden=local_simulation,
            ),
            field(
              copy(
                locale, "Protected node-material directory", "受保护节点材料目录",
              ),
              "secret-directory",
              state.form.secret_directory,
              "/srv/lunanexa/secrets",
              running || local_simulation,
              emit_value(emit, value => SecretDirectoryChanged(value)),
              hidden=local_simulation,
            ),
            field(
              copy(locale, "LunaNexa CLI path", "LunaNexa CLI 路径"),
              "cli-path",
              state.form.cli_path,
              "/usr/local/bin/lunanexa",
              running || local_simulation,
              emit_value(emit, value => CliPathChanged(value)),
              hidden=local_simulation,
            ),
          ]),
        ]),
        @html.div(class="install-section", [
          @html.p(
            class="section-label",
            copy(locale, "Reviewed stages", "已审核阶段"),
          ),
          @html.ul(
            class="stage-list",
            [
              for index, name in stage_names => {
                @html.li([
                  @html.span(
                    class="stage-number",
                    "\{index + 1}/\{stage_names.length()}",
                  ),
                  @html.span(stage_label(locale, index, name, local_simulation)),
                ])
              }
            ],
          ),
        ]),
        @html.div(class="install-section", [
          @html.div(class="run-actions", [
            @html.button(
              type_="button",
              class="preview-button",
              disabled=!complete || running,
              on_click=emit(PreviewRequested),
              copy(locale, "Preview and verify", "预览并验证"),
            ),
            @html.button(
              type_="button",
              disabled=true,
              copy(
                locale, "Changes require confirmation below", "更改需要在下方确认",
              ),
            ),
          ]),
          @html.div(class="danger-zone", [
            @html.strong(
              if local_simulation {
                copy(
                  locale, "Reconcile the local five-node simulation", "协调本地五节点模拟",
                )
              } else {
                copy(
                  locale, "Apply changes to five remote machines", "将更改应用到五台远程机器",
                )
              },
            ),
            @html.p(
              if local_simulation {
                copy(
                  locale, "Run preview first. Applying creates or reconciles only the Colima kind topology and tiny placement probes. Type DEPLOY 4 NODES exactly.",
                  "请先运行预检。应用操作只会创建或协调 Colima kind 拓扑和轻量放置探针。请准确输入 DEPLOY 4 NODES。",
                )
              } else {
                copy(
                  locale, "Run preview first. Applying labels nodes, installs protected material, applies manifests, and starts enrollment. Type DEPLOY 4 NODES exactly.",
                  "请先运行预检。应用操作将标记节点、安装受保护材料、应用清单并开始注册。请准确输入 DEPLOY 4 NODES。",
                )
              },
            ),
            field(
              copy(locale, "Confirmation phrase", "确认短语"),
              "confirmation",
              state.form.confirmation,
              @install_contract.apply_confirmation,
              running,
              emit_value(emit, value => ConfirmationChanged(value)),
            ),
            @html.button(
              type_="button",
              class="danger-button",
              disabled=!complete ||
                !state.preview_verified ||
                running ||
                state.form.confirmation != @install_contract.apply_confirmation,
              on_click=emit(ApplyRequested),
              if local_simulation {
                copy(locale, "Reconcile simulation", "协调模拟")
              } else {
                copy(locale, "Deploy cluster", "部署集群")
              },
            ),
          ]),
        ]),
      ]),
      @html.section(class="install-card terminal-card", [
        @html.div(class="terminal-toolbar", [
          @html.div(class="terminal-status", [
            @html.span(class="status-dot \{run_tone(state.run_state)}", ""),
            @html.span(run_label(locale, state.run_state)),
          ]),
          @html.button(
            type_="button",
            disabled=running || state.terminal_lines.length() == 0,
            on_click=emit(ClearTerminal),
            copy(locale, "Clear", "清空"),
          ),
        ]),
        @html.pre(
          class="terminal",
          attrs=@html.Attrs::build().role("log").aria_live("polite"),
          if state.terminal_lines.length() == 0 {
            copy(
              locale, "Terminal output will appear here after preview starts.\nSecrets are redacted and command input is disabled.",
              "预检开始后，终端输出将显示在这里。\n密钥会被脱敏，且命令输入已禁用。",
            )
          } else {
            state.terminal_lines.join("\n")
          },
        ),
      ]),
    ]),
  ])
}

///|
#warnings("-alert_unstable")
pub fn render(state : InstallerState) -> String {
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(interactive_view(state, _ => @rabbita.none))
  })
}
