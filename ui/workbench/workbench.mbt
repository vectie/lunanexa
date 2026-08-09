///|
/// A browser-owned draft. This type never represents a managed-node path.
pub(all) struct DraftFile {
  path : String
  language : String
  content : String
} derive(Debug, Eq)

///|
pub(all) struct UsageSummary {
  requests_used : Int
  requests_limit : Int
  input_units : Int
  output_units : Int
  accelerator_ms : Int64
} derive(Debug, Eq)

///|
pub(all) struct IntegrationSummary {
  provider : @workspace.IntegrationProvider
  state : @workspace.ConnectionState
  description : String
} derive(Debug, Eq)

///|
pub(all) struct WorkbenchState {
  locale : @i18n.Locale
  lease : @workspace.WorkspaceLease?
  now_unix_ms : Int64
  files : Array[DraftFile]
  active_path : String
  model_selector : String
  instruction : String
  output_text : String
  receipt : String
  usage : UsageSummary
  integrations : Array[IntegrationSummary]
  selected_editor : @workspace.EditorConnectionKind?
  selected_integration : @workspace.IntegrationProvider?
  loading : Bool
  success_message : String?
  error_message : String?
} derive(Eq)

///|
pub(all) enum WorkbenchMessage {
  LocaleChanged(@i18n.Locale)
  SelectFile(String)
  DraftChanged(String)
  ModelChanged(String)
  InstructionChanged(String)
  SendRequest
  SelectEditor(@workspace.EditorConnectionKind)
  SelectIntegration(@workspace.IntegrationProvider)
  ClearNotice
} derive(Eq)

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn integration_description(
  locale : @i18n.Locale,
  provider : @workspace.IntegrationProvider,
) -> String {
  match provider {
    CodeBuddy =>
      copy(
        locale, "Open CodeBuddy with scoped LunaNexa client metadata.", "使用限定范围的 LunaNexa 客户端元数据打开 CodeBuddy。",
      )
    WorkBuddy =>
      copy(
        locale, "Continue in WorkBuddy through the northbound contract.", "通过北向契约在 WorkBuddy 中继续。",
      )
    Trae =>
      copy(
        locale, "Hand the active browser draft to a local Trae client.", "将当前浏览器本地草稿交接给本地 Trae 客户端。",
      )
    Qoder =>
      copy(
        locale, "Open Qoder with an expiring provider-neutral handoff.", "通过有时效且不绑定特定提供商的交接打开 Qoder。",
      )
    Generic =>
      copy(
        locale, "Open a generic client through the scoped contract.", "通过限定范围的契约打开通用客户端。",
      )
  }
}

///|
fn initial_integrations(locale : @i18n.Locale) -> Array[IntegrationSummary] {
  [
    {
      provider: CodeBuddy,
      state: Disconnected,
      description: integration_description(locale, CodeBuddy),
    },
    {
      provider: WorkBuddy,
      state: Disconnected,
      description: integration_description(locale, WorkBuddy),
    },
    {
      provider: Trae,
      state: Disconnected,
      description: integration_description(locale, Trae),
    },
    {
      provider: Qoder,
      state: Disconnected,
      description: integration_description(locale, Qoder),
    },
  ]
}

///|
pub fn default_state(now_unix_ms : Int64) -> WorkbenchState {
  let locale = @i18n.default_locale()
  {
    locale,
    lease: None,
    now_unix_ms,
    files: [
      {
        path: "src/main.mbt",
        language: "MoonBit",
        content: "fn main {\n  println(\"Hello from LunaNexa\")\n}\n",
      },
      {
        path: "README.mbt.md",
        language: "Markdown",
        content: "# Browser-local workspace\n\nDrafts remain in this browser.\n",
      },
    ],
    active_path: "src/main.mbt",
    model_selector: "text.default",
    instruction: "Explain the selected code and suggest one focused test.",
    output_text: "",
    receipt: "",
    usage: {
      requests_used: 0,
      requests_limit: 0,
      input_units: 0,
      output_units: 0,
      accelerator_ms: 0L,
    },
    integrations: initial_integrations(locale),
    selected_editor: None,
    selected_integration: None,
    loading: false,
    success_message: None,
    error_message: None,
  }
}

///|
pub fn demo_state() -> WorkbenchState {
  let now = 2000000000000L
  {
    ..default_state(now),
    lease: Some({
      version: @workspace.contract_version,
      lease_id: "lease-demo-01",
      tenant_ref: "tenant-opaque-demo",
      subject_ref: "subject-opaque-demo",
      access: Developer,
      limits: {
        max_active_sessions: 2,
        max_session_duration_ms: 28800000L,
        capabilities: [
          {
            capability: TextGenerate,
            max_concurrent_requests: 2,
            max_requests_per_hour: 200,
            max_input_units_per_request: 32768,
            max_output_units_per_request: 8192,
          },
        ],
      },
      starts_unix_ms: now - 3600000L,
      expires_unix_ms: now + 21600000L,
      state: Active,
      policy_receipt: "policy-demo-01",
    }),
    model_selector: "text.default",
    usage: {
      requests_used: 42,
      requests_limit: 200,
      input_units: 1280,
      output_units: 640,
      accelerator_ms: 18420L,
    },
  }
}

///|
pub fn lease_ready(state : WorkbenchState) -> Bool {
  match state.lease {
    Some(lease) =>
      lease.state == Active &&
      state.now_unix_ms >= lease.starts_unix_ms &&
      state.now_unix_ms < lease.expires_unix_ms &&
      @workspace.capability_limit(lease, TextGenerate) is Some(_)
    None => false
  }
}

///|
pub fn can_send(state : WorkbenchState) -> Bool {
  lease_ready(state) &&
  active_file(state) is Some(_) &&
  state.model_selector != "" &&
  @workspace.valid_identifier(state.model_selector) &&
  state.instruction.trim() != "" &&
  state.instruction.length() <= 4096 &&
  !state.loading
}

///|
pub fn active_file(state : WorkbenchState) -> DraftFile? {
  for file in state.files {
    if file.path == state.active_path {
      return Some(file)
    }
  }
  None
}

///|
pub fn WorkbenchState::update(
  self : WorkbenchState,
  message : WorkbenchMessage,
) -> WorkbenchState {
  match message {
    LocaleChanged(locale) =>
      {
        ..self,
        locale,
        integrations: [
          for integration in self.integrations => {
            {
              ..integration,
              description: integration_description(locale, integration.provider),
            }
          }
        ],
        success_message: None,
        error_message: None,
      }
    SelectFile(path) =>
      if self.files.any(file => file.path == path) {
        { ..self, active_path: path, error_message: None }
      } else {
        {
          ..self,
          error_message: Some(
            copy(
              self.locale,
              "That browser draft is unavailable.",
              "该浏览器草稿不可用。",
            ),
          ),
        }
      }
    DraftChanged(content) => {
      let files = [
        for file in self.files => {
          if file.path == self.active_path {
            { ..file, content, }
          } else {
            file
          }
        }
      ]
      { ..self, files, }
    }
    ModelChanged(value) => { ..self, model_selector: value }
    InstructionChanged(value) => { ..self, instruction: value }
    SendRequest =>
      if can_send(self) {
        {
          ..self,
          loading: true,
          output_text: "",
          receipt: "",
          success_message: None,
          error_message: None,
        }
      } else {
        {
          ..self,
          error_message: Some(
            copy(
              self.locale,
              "An active text-generation lease, model, file, and instruction are required.",
              "需要有效的文本生成租约、模型、文件和指令。",
            ),
          ),
        }
      }
    SelectEditor(editor) =>
      {
        ..self,
        selected_editor: Some(editor),
        selected_integration: None,
        error_message: None,
      }
    SelectIntegration(provider) =>
      {
        ..self,
        selected_editor: None,
        selected_integration: Some(provider),
        error_message: None,
      }
    ClearNotice =>
      {
        ..self,
        selected_editor: None,
        selected_integration: None,
        success_message: None,
        error_message: None,
      }
  }
}

///|
fn command(
  emit : @rabbita.Emit[WorkbenchMessage]?,
  message : WorkbenchMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[WorkbenchMessage]?,
  wrap : (String) -> WorkbenchMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn provider_label(
  locale : @i18n.Locale,
  provider : @workspace.IntegrationProvider,
) -> String {
  match provider {
    CodeBuddy => "CodeBuddy"
    WorkBuddy => "WorkBuddy"
    Trae => "Trae"
    Qoder => "Qoder"
    Generic => copy(locale, "Generic client", "通用客户端")
  }
}

///|
fn provider_mark(provider : @workspace.IntegrationProvider) -> String {
  match provider {
    CodeBuddy => "CB"
    WorkBuddy => "WB"
    Trae => "TR"
    Qoder => "QD"
    Generic => "GC"
  }
}

///|
fn editor_label(editor : @workspace.EditorConnectionKind) -> String {
  match editor {
    WebIde => "Web IDE"
    VSCode => "VS Code"
  }
}

///|
fn connection_label(
  locale : @i18n.Locale,
  state : @workspace.ConnectionState,
) -> String {
  match state {
    Pending => copy(locale, "Pending", "待处理")
    Connecting => copy(locale, "Connecting", "正在连接")
    Connected => copy(locale, "Connected", "已连接")
    Disconnected => copy(locale, "Client-side handoff", "客户端交接")
    Failed => copy(locale, "Needs attention", "需要处理")
    Revoked => copy(locale, "Revoked", "已撤销")
  }
}

///|
fn lease_is_denied(state : WorkbenchState) -> Bool {
  match state.lease {
    Some(lease) => lease.state is (Expired | Revoked)
    None => false
  }
}

///|
fn access_status_label(state : WorkbenchState) -> String {
  if lease_ready(state) {
    copy(state.locale, "Workspace ready", "工作区就绪")
  } else {
    match state.lease {
      Some(lease) =>
        match lease.state {
          Expired => copy(state.locale, "Lease expired", "租约已过期")
          Revoked => copy(state.locale, "Lease revoked", "租约已撤销")
          Suspended => copy(state.locale, "Lease suspended", "租约已暂停")
          Requested => copy(state.locale, "Approval pending", "待审批")
          Active => copy(state.locale, "Access required", "需要访问权限")
        }
      None => copy(state.locale, "Access required", "需要访问权限")
    }
  }
}

///|
fn lease_gate(state : WorkbenchState) -> @rabbita.Html {
  let gate_message = match state.lease {
    Some(lease) =>
      match lease.state {
        Expired =>
          copy(
            state.locale,
            "This capacity lease has expired. Ask an administrator for a new bounded lease.",
            "此工作区租约已过期。请联系管理员申请新的有期限租约。",
          )
        Revoked =>
          copy(
            state.locale,
            "This capacity lease was revoked and cannot start new work.",
            "此工作区租约已撤销，无法启动新工作。",
          )
        Suspended =>
          copy(
            state.locale,
            "This capacity lease is suspended. New work is disabled.",
            "此工作区租约已暂停，新工作已禁用。",
          )
        Requested =>
          copy(
            state.locale,
            "This capacity lease is awaiting approval.",
            "此工作区租约待审批。",
          )
        Active =>
          copy(
            state.locale,
            "The active lease is outside its valid time window.",
            "当前租约不在有效时间范围内。",
          )
      }
    None =>
      copy(
        state.locale,
        "Connect with a scoped inference token and verified identity to load your authorization. Loopback acceptance may also use an opaque subject reference.",
        "使用限定范围的推理令牌和已验证身份进行连接，以加载限定范围的访问权限。本地回环验收也可使用不透明主体引用。",
      )
  }
  @html.main_(id="main", class="entry-gate", [
    @html.div(class="gate-copy", [
      @html.p(
        class="eyebrow",
        copy(
          state.locale,
          "LUNANEXA DEVELOPER WORKSPACE",
          "LUNANEXA 开发者工作台",
        ),
      ),
      @html.h1(
        copy(
          state.locale,
          "Your workspace is not ready",
          "工作区尚未就绪",
        ),
      ),
      @html.p(class="gate-lede", gate_message),
      @html.div(class="gate-steps", [
        @html.div(class="gate-step", [
          @html.span(class="step-number", "01"),
          @html.div([
            @html.strong(copy(state.locale, "Verify identity", "验证身份")),
            @html.span(
              copy(
                state.locale,
                "Load an opaque subject through trusted ingress.",
                "通过受信任入口加载不透明主体。",
              ),
            ),
          ]),
        ]),
        @html.div(class="gate-step", [
          @html.span(class="step-number", "02"),
          @html.div([
            @html.strong(copy(state.locale, "Check capacity", "检查容量")),
            @html.span(
              copy(
                state.locale,
                "Confirm a scoped, time-bounded lease.",
                "确认限定范围且有时效的租约。",
              ),
            ),
          ]),
        ]),
        @html.div(class="gate-step", [
          @html.span(class="step-number", "03"),
          @html.div([
            @html.strong(copy(state.locale, "Start building", "开始开发")),
            @html.span(
              copy(
                state.locale,
                "Open the local editor and generic model tools.",
                "打开本地编辑器和通用模型工具。",
              ),
            ),
          ]),
        ]),
      ]),
      @html.p(class="boundary-note gate-boundary", [
        @html.strong(copy(state.locale, "Trust boundary", "信任边界")),
        @html.span(
          copy(
            state.locale,
            "A lease never grants a DGX login, managed-node filesystem, arbitrary shell, repository checkout, or editor-agent installation.",
            "租约绝不会授予 DGX 登录、受管节点文件系统、任意 Shell、代码仓库检出或编辑器代理安装权限。",
          ),
        ),
      ]),
    ]),
  ])
}

///|
fn locale_control(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  let english = @i18n.default_locale()
  let chinese = english.alternate()
  @html.div(class="locale-control", [
    @html.label(
      for_="workbench-locale",
      copy(state.locale, "Language", "语言"),
    ),
    @html.select(
      id="workbench-locale",
      on_change=text_command(emit, value => {
        LocaleChanged(@i18n.parse_locale(value))
      }),
      attrs=@html.Attrs::build().aria_label(
        copy(state.locale, "Interface language", "界面语言"),
      ),
      [
        @html.option(
          value=english.storage_value(),
          selected=state.locale == english,
          english.label(),
        ),
        @html.option(
          value=chinese.storage_value(),
          selected=state.locale == chinese,
          chinese.label(),
        ),
      ],
    ),
  ])
}

///|
fn topbar(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  let lease_copy = match state.lease {
    Some(lease) => {
      let minutes = ((lease.expires_unix_ms - state.now_unix_ms) / 60000L).max(
        0L,
      )
      copy(
        state.locale,
        "Lease \{lease.lease_id} · \{minutes}m remaining",
        "租约 \{lease.lease_id} · 剩余 \{minutes} 分钟",
      )
    }
    None =>
      copy(state.locale, "Authorization not loaded", "访问权限未加载")
  }
  @html.header(class="topbar", [
    @html.div(class="brand", [
      @html.span(class="product-mark", "LN"),
      @html.div(class="brand-copy", [
        @html.strong(
          copy(
            state.locale,
            "LunaNexa Workbench",
            "LunaNexa 开发者工作台",
          ),
        ),
        @html.span(
          class="secondary",
          copy(
            state.locale,
            "Local drafts · provider-neutral models",
            "浏览器本地草稿 · 不绑定特定提供商的模型",
          ),
        ),
      ]),
    ]),
    @html.div(class="readiness", [
      locale_control(state, emit),
      @html.span(
        class=if lease_ready(state) {
          "status-pill is-ready"
        } else if lease_is_denied(state) {
          "status-pill is-danger"
        } else {
          "status-pill is-blocked"
        },
        access_status_label(state),
      ),
      @html.div(class="lease-meta", [
        @html.span(
          class="secondary",
          copy(state.locale, "Capacity lease", "容量租约"),
        ),
        @html.strong(class="mono", lease_copy),
      ]),
    ]),
  ])
}

///|
fn file_tree(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  @html.aside(
    class="file-panel",
    attrs=@html.Attrs::build().aria_label(
      copy(state.locale, "Project drafts", "项目草稿"),
    ),
    [
      @html.div(class="panel-title", [
        @html.div([
          @html.p(
            class="panel-kicker",
            copy(state.locale, "EXPLORER", "资源管理器"),
          ),
          @html.h2(copy(state.locale, "Project drafts", "项目草稿")),
        ]),
        @html.span(
          class="count-badge mono",
          copy(
            state.locale,
            "\{state.files.length()} LOCAL",
            "\{state.files.length()} 个本地草稿",
          ),
        ),
      ]),
      if state.files.length() == 0 {
        @html.p(
          class="empty-state",
          copy(
            state.locale,
            "No browser-local draft files. Add a local draft before sending a request.",
            "没有浏览器本地草稿。请先添加本地草稿，再发送请求。",
          ),
        )
      } else {
        @html.ul(
          class="file-list",
          [
            for file in state.files => {
              @html.li(
                @html.button(
                  type_="button",
                  class=if file.path == state.active_path {
                    "file active"
                  } else {
                    "file"
                  },
                  attrs=@html.Attrs::build().aria_current(
                    if file.path == state.active_path {
                      "page"
                    } else {
                      "false"
                    },
                  ),
                  on_click=command(emit, SelectFile(file.path)),
                  [
                    @html.span(class="file-path", file.path),
                    @html.small(file.language),
                  ],
                ),
              )
            }
          ],
        )
      },
      @html.p(class="boundary-note compact", [
        @html.strong(
          copy(state.locale, "Browser-local only", "仅限浏览器本地"),
        ),
        @html.span(
          copy(
            state.locale,
            "No repository, credential, IDE agent, shell, or filesystem is mounted on a managed GPU node.",
            "受管节点文件系统不会挂载代码仓库、凭据、IDE 代理或任意 Shell。",
          ),
        ),
      ]),
    ],
  )
}

///|
fn editor(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  match active_file(state) {
    None =>
      @html.section(class="editor-panel empty-state", [
        @html.h2(copy(state.locale, "Select a draft", "选择草稿")),
        @html.p(
          copy(
            state.locale,
            "Choose a browser-local file to begin editing.",
            "选择浏览器本地文件以开始编辑。",
          ),
        ),
      ])
    Some(file) =>
      @html.section(
        class="editor-panel",
        attrs=@html.Attrs::build().aria_labelledby("editor-title"),
        [
          @html.div(class="editor-tabs", [
            @html.div(class="active-tab", [
              @html.span(class="tab-indicator", ""),
              @html.h2(id="editor-title", file.path),
            ]),
            @html.div(class="editor-meta", [
              @html.span(
                class="draft-state",
                copy(state.locale, "Browser draft", "浏览器本地草稿"),
              ),
              @html.span(class="mono secondary", file.language),
            ]),
          ]),
          @html.label(
            for_="code-editor",
            copy(state.locale, "Code editor", "代码编辑器"),
          ),
          @html.textarea(
            id="code-editor",
            class="code-editor",
            rows=22,
            value=file.content,
            attrs=@html.Attrs::build().spellcheck(false),
            on_input=text_command(emit, value => DraftChanged(value)),
            "",
          ),
          @html.div(class="editor-statusbar", [
            @html.span(copy(state.locale, "Local editing", "本地编辑")),
            @html.span(
              class="mono",
              copy(
                state.locale,
                "Managed-node mounts: none",
                "受管节点挂载：无",
              ),
            ),
          ]),
        ],
      )
  }
}

///|
fn output_view(state : WorkbenchState) -> @rabbita.Html {
  @html.section(
    class="output-view",
    attrs=@html.Attrs::build().aria_labelledby("output-title"),
    [
      @html.div(class="panel-title", [
        @html.div([
          @html.p(class="panel-kicker", copy(state.locale, "RESULT", "结果")),
          @html.h3(
            id="output-title",
            copy(state.locale, "Normalized output", "规范化输出"),
          ),
        ]),
        if state.receipt == "" {
          @html.span(
            class="secondary",
            copy(state.locale, "Awaiting request", "等待请求"),
          )
        } else {
          @html.span(class="receipt-chip mono", state.receipt)
        },
      ]),
      if state.loading {
        @html.p(
          class="loading-state",
          attrs=@html.Attrs::build()
            .role("status")
            .aria_live("polite")
            .aria_busy("true"),
          copy(
            state.locale,
            "Sending canonical workload…",
            "正在发送规范工作负载…",
          ),
        )
      } else if state.output_text == "" {
        @html.p(
          class="empty-state compact",
          copy(
            state.locale,
            "Run the selected draft to inspect normalized output and its auditable receipt.",
            "运行所选草稿，以检查标准化输出及其可审计回执。",
          ),
        )
      } else {
        @html.pre(state.output_text)
      },
    ],
  )
}

///|
fn run_panel(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  @html.aside(
    class="run-panel",
    attrs=@html.Attrs::build().aria_label(
      copy(state.locale, "Model request", "模型请求"),
    ),
    [
      @html.div(class="panel-title", [
        @html.div([
          @html.p(
            class="panel-kicker",
            copy(state.locale, "MODEL TOOL", "模型工具"),
          ),
          @html.h2(
            copy(state.locale, "Run with LunaNexa", "使用 LunaNexa 运行"),
          ),
        ]),
        @html.span(
          class=if lease_ready(state) {
            "mini-status is-ready"
          } else if lease_is_denied(state) {
            "mini-status is-danger"
          } else {
            "mini-status is-blocked"
          },
          if lease_ready(state) {
            copy(state.locale, "Lease active", "租约有效")
          } else {
            access_status_label(state)
          },
        ),
      ]),
      @html.label(
        for_="model-selector",
        copy(state.locale, "Model alias", "模型别名"),
      ),
      @html.input(
        id="model-selector",
        value=state.model_selector,
        placeholder="text.default",
        attrs=@html.Attrs::build()
          .disabled(state.loading)
          .aria_describedby("model-selector-help"),
        on_input=text_command(emit, value => ModelChanged(value)),
      ),
      @html.p(
        id="model-selector-help",
        class="privacy-copy",
        copy(
          state.locale,
          "Use a provider-neutral model alias such as text.default.",
          "使用不绑定特定提供商的模型别名，例如 text.default。",
        ),
      ),
      @html.label(
        for_="instruction",
        copy(state.locale, "Instruction", "指令"),
      ),
      @html.textarea(
        id="instruction",
        rows=6,
        maxlength=4096,
        value=state.instruction,
        disabled=state.loading,
        on_input=text_command(emit, value => InstructionChanged(value)),
        "",
      ),
      @html.button(
        type_="button",
        class="primary-action",
        disabled=!can_send(state),
        on_click=command(emit, SendRequest),
        if state.loading {
          copy(state.locale, "Sending…", "正在发送…")
        } else {
          copy(state.locale, "Send request", "发送请求")
        },
      ),
      @html.p(
        class="privacy-copy request-policy",
        copy(
          state.locale,
          "Ephemeral · no cache · no training reuse · bounded deadline",
          "临时处理 · 不缓存 · 不用于训练 · 有期限",
        ),
      ),
      @html.div(class="usage", [
        @html.div(class="usage-heading", [
          @html.h3(copy(state.locale, "Session usage", "会话用量")),
          @html.strong(
            class="mono",
            "\{state.usage.requests_used}/\{state.usage.requests_limit}",
          ),
        ]),
        @html.progress(
          value=state.usage.requests_used,
          max=state.usage.requests_limit.max(1),
          copy(state.locale, "Request quota", "请求配额"),
        ),
        @html.div(class="usage-stats", [
          @html.div([
            @html.strong(class="mono", "\{state.usage.input_units}"),
            @html.span(copy(state.locale, "Input units", "输入单元")),
          ]),
          @html.div([
            @html.strong(class="mono", "\{state.usage.output_units}"),
            @html.span(copy(state.locale, "Output units", "输出单元")),
          ]),
          @html.div([
            @html.strong(class="mono", "\{state.usage.accelerator_ms}"),
            @html.span(
              copy(state.locale, "Accelerator ms", "加速器耗时（ms）"),
            ),
          ]),
        ]),
        @html.p(
          class="privacy-copy",
          copy(
            state.locale,
            "Observed in this browser page; authoritative metering remains in the controller receipt and operator telemetry.",
            "此处仅显示本浏览器页面观测到的用量；权威计量仍以控制器回执和运维遥测为准。",
          ),
        ),
      ]),
    ],
  )
}

///|
fn integrations(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  let cards = [
    @html.article(class="integration-card featured", [
      @html.div(class="integration-heading", [
        @html.span(class="integration-mark", "VS"),
        @html.div([
          @html.strong("VS Code"),
          @html.span(
            class="secondary",
            copy(state.locale, "Client-side extension", "客户端扩展"),
          ),
        ]),
      ]),
      @html.p(
        copy(
          state.locale,
          "Open the same scoped provider contract in a local VS Code extension.",
          "在本地 VS Code 扩展中打开同一限定范围且不绑定特定提供商的契约。",
        ),
      ),
      @html.button(
        type_="button",
        disabled=!lease_ready(state),
        on_click=command(emit, SelectEditor(VSCode)),
        copy(state.locale, "Prepare VS Code handoff", "准备 VS Code 交接"),
      ),
    ]),
  ]
  for integration in state.integrations {
    cards.push(
      @html.article(class="integration-card", [
        @html.div(class="integration-heading", [
          @html.span(
            class="integration-mark",
            provider_mark(integration.provider),
          ),
          @html.div([
            @html.strong(provider_label(state.locale, integration.provider)),
            @html.span(
              class="secondary",
              connection_label(state.locale, integration.state),
            ),
          ]),
        ]),
        @html.p(integration.description),
        @html.button(
          type_="button",
          disabled=!lease_ready(state),
          on_click=command(emit, SelectIntegration(integration.provider)),
          copy(state.locale, "Prepare client handoff", "准备客户端交接"),
        ),
      ]),
    )
  }
  @html.section(
    class="integrations",
    attrs=@html.Attrs::build().aria_labelledby("integrations-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            copy(state.locale, "CLIENT INTEGRATIONS", "客户端集成"),
          ),
          @html.h2(
            id="integrations-title",
            copy(
              state.locale,
              "Continue in your preferred client",
              "在常用客户端中继续",
            ),
          ),
        ]),
        @html.p(
          class="secondary",
          copy(
            state.locale,
            "VS Code, CodeBuddy, WorkBuddy, Trae, and Qoder remain client-side. Handoffs never install credentials, repositories, shells, or agents on GPU nodes.",
            "VS Code、CodeBuddy、WorkBuddy、Trae 和 Qoder 始终位于客户端。交接绝不会在 GPU 节点上安装凭据、代码仓库、Shell 或代理。",
          ),
        ),
      ]),
      @html.div(class="integration-grid", cards),
      match (state.selected_editor, state.selected_integration) {
        (Some(editor), _) =>
          @html.p(
            class="notice",
            attrs=@html.Attrs::build().role("status").aria_live("polite"),
            copy(
              state.locale,
              "\{editor_label(editor)} handoff requested. Only opaque, expiring client metadata may leave this browser; no node access was created.",
              "已请求 \{editor_label(editor)} 交接。只有不透明且有时效的客户端元数据可离开此浏览器；未创建任何节点访问权限。",
            ),
          )
        (_, Some(provider)) =>
          @html.p(
            class="notice",
            attrs=@html.Attrs::build().role("status").aria_live("polite"),
            copy(
              state.locale,
              "\{provider_label(state.locale, provider)} handoff requested. Only opaque, expiring client metadata may leave this browser; no node access was created.",
              "已请求 \{provider_label(state.locale, provider)} 交接。只有不透明且有时效的客户端元数据可离开此浏览器；未创建任何节点访问权限。",
            ),
          )
        _ => @html.nothing
      },
    ],
  )
}

///|
fn workbench_view(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage]?,
) -> @rabbita.Html {
  let ready = lease_ready(state) || state.loading
  @html.div(
    class=if ready {
      "workbench-shell workspace-ready"
    } else {
      "workbench-shell workspace-blocked"
    },
    [
      @html.style_tag(
        (
          #|:root{color-scheme:dark;--bg:#070b11;--chrome:#0b111b;--panel:#101824;--panel-raised:#151f2d;--panel-soft:#192536;--editor:#090f18;--ink:#f4f7fb;--muted:#91a0b7;--muted-strong:#bdc7d5;--line:#253248;--line-strong:#33445f;--accent:#75e6b6;--accent-strong:#37c98e;--accent-ink:#06261a;--accent-soft:rgba(117,230,182,.1);--warning:#f1c478;--warning-soft:rgba(241,196,120,.11);--danger:#ff9aab;--danger-soft:rgba(255,154,171,.1);--focus:#9ac1ff;--shadow:0 24px 70px rgba(0,0,0,.34)}
          #|*{box-sizing:border-box}
          #|html{background:var(--bg)}
          #|body{min-width:20rem;margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei","Noto Sans CJK SC",sans-serif;text-rendering:optimizeLegibility}
          #|button,input,select,textarea{font:inherit}
          #|button{min-height:2.75rem;padding:.55rem .8rem;border:1px solid var(--line-strong);border-radius:.55rem;background:var(--panel-raised);color:var(--ink);font-weight:650;cursor:pointer;transition:border-color .16s ease,background-color .16s ease,color .16s ease}
          #|button:hover:not(:disabled){border-color:#4a6080;background:var(--panel-soft)}
          #|button:disabled{cursor:not-allowed;opacity:.46}
          #|button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible,.skip-link:focus{outline:3px solid var(--focus);outline-offset:2px}
          #|::selection{background:rgba(137,174,251,.28)}
          #|.sr-only,.skip-link,.editor-panel>label{position:absolute;left:-9999px}
          #|.skip-link:focus{left:1rem;top:1rem;z-index:50;padding:.7rem .9rem;border:1px solid var(--focus);border-radius:.5rem;background:var(--panel-raised);color:var(--ink)}
          #|.workbench-shell{min-height:100vh;background:radial-gradient(circle at 50% -20%,rgba(83,111,157,.12),transparent 33rem),var(--bg)}
          #|.topbar{position:sticky;top:0;z-index:12;min-height:4.25rem;padding:.65rem 1rem;display:flex;align-items:center;justify-content:space-between;gap:1rem;border-bottom:1px solid var(--line);background:rgba(11,17,27,.96);box-shadow:0 8px 28px rgba(0,0,0,.16)}
          #|.topbar>div{display:flex;align-items:center}
          #|.brand{gap:.75rem}
          #|.brand-copy strong,.brand-copy span,.readiness span{display:block}
          #|.brand-copy strong{font-size:.92rem;letter-spacing:-.01em}
          #|.product-mark{display:grid!important;place-items:center;width:2.55rem;height:2.55rem;border:1px solid rgba(117,230,182,.5);border-radius:.7rem;background:linear-gradient(145deg,rgba(117,230,182,.16),rgba(137,174,251,.08));color:var(--accent);font-size:.8rem;font-weight:850;letter-spacing:.06em;box-shadow:inset 0 1px rgba(255,255,255,.08)}
          #|.secondary{color:var(--muted);font-size:.78rem}
          #|.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace}
          #|.readiness{justify-content:flex-end;gap:.8rem;flex-wrap:wrap}
          #|.locale-control{display:flex;align-items:center;gap:.45rem}
          #|.locale-control label{color:var(--muted);font-size:.7rem;font-weight:700}
          #|.locale-control select{min-height:2.75rem;padding:.45rem 1.85rem .45rem .65rem;border:1px solid var(--line-strong);border-radius:.55rem;background:var(--panel-raised);color:var(--ink);font-size:.75rem;font-weight:700;cursor:pointer}
          #|.status-pill,.mini-status{display:inline-flex!important;align-items:center;gap:.42rem;white-space:nowrap;border:1px solid;border-radius:999px;font-size:.72rem;font-weight:800;letter-spacing:.01em}
          #|.status-pill{min-height:2rem;padding:.35rem .68rem}
          #|.status-pill:before,.mini-status:before{content:"";width:.46rem;height:.46rem;border-radius:50%;background:currentColor}
          #|.is-ready{border-color:rgba(117,230,182,.36);background:var(--accent-soft);color:var(--accent)}
          #|.is-blocked{border-color:rgba(241,196,120,.4);background:var(--warning-soft);color:var(--warning)}
          #|.is-danger{border-color:rgba(255,154,171,.4);background:var(--danger-soft);color:var(--danger)}
          #|.lease-meta{min-width:13rem;padding-left:.8rem;border-left:1px solid var(--line)}
          #|.lease-meta span,.lease-meta strong{display:block}
          #|.lease-meta strong{max-width:100%;margin-top:.16rem;color:var(--muted-strong);font-size:.72rem;font-weight:600;overflow-wrap:anywhere}
          #|.workspace-main{min-height:calc(100vh - 4.25rem)}
          #|.workspace-grid{display:grid;grid-template-columns:14.5rem minmax(28rem,1fr) 21rem;min-height:43rem;border-bottom:1px solid var(--line)}
          #|.file-panel,.run-panel,.editor-panel,.editor-stack{min-width:0}
          #|.file-panel,.run-panel{background:var(--panel)}
          #|.file-panel{display:flex;flex-direction:column;padding:.8rem;border-right:1px solid var(--line)}
          #|.run-panel{padding:1rem;border-left:1px solid var(--line)}
          #|.editor-stack{display:grid;grid-template-rows:minmax(31rem,1fr) minmax(11rem,auto);background:var(--editor)}
          #|.editor-panel{display:flex;min-height:0;flex-direction:column;background:var(--editor)}
          #|.panel-title,.editor-tabs{display:flex;align-items:center;justify-content:space-between;gap:.75rem}
          #|.panel-title{padding:.2rem 0 .85rem}
          #|.panel-title h2,.panel-title h3,.editor-tabs h2{margin:0;color:var(--ink);font-size:.84rem;line-height:1.3}
          #|.panel-kicker{margin:0 0 .28rem;color:var(--muted);font-size:.62rem;font-weight:850;letter-spacing:.13em}
          #|.count-badge,.receipt-chip{padding:.28rem .45rem;border:1px solid var(--line);border-radius:.35rem;background:rgba(255,255,255,.025);color:var(--muted);font-size:.62rem}
          #|.editor-tabs{min-height:3.15rem;padding:.55rem .85rem;border-bottom:1px solid var(--line);background:var(--chrome)}
          #|.active-tab,.editor-meta{display:flex;align-items:center;gap:.55rem}
          #|.tab-indicator{width:.5rem;height:.5rem;border-radius:50%;background:var(--accent)}
          #|.draft-state{padding:.2rem .42rem;border:1px solid var(--line);border-radius:.35rem;color:var(--muted-strong);font-size:.65rem;font-weight:700}
          #|.file-list{list-style:none;margin:0;padding:0}
          #|.file-list li{margin:.15rem 0}
          #|.file{position:relative;width:100%;min-height:3rem;padding:.48rem .6rem .48rem 1rem;text-align:left;border:1px solid transparent;border-radius:.5rem;background:transparent;color:var(--muted)}
          #|.file:before{content:"";position:absolute;left:.15rem;top:.62rem;bottom:.62rem;width:2px;border-radius:2px;background:transparent}
          #|.file span,.file small{display:block}
          #|.file-path{overflow:hidden;color:inherit;font-size:.78rem;font-weight:650;text-overflow:ellipsis;white-space:nowrap}
          #|.file small{margin-top:.18rem;color:#718096;font-size:.66rem}
          #|.file.active,.file:hover{border-color:var(--line);background:var(--panel-raised);color:var(--ink)}
          #|.file.active:before{background:var(--accent)}
          #|.file-panel .boundary-note{margin-top:auto}
          #|.code-editor{display:block;width:100%;min-height:31rem;flex:1;margin:0;padding:1.2rem 1.35rem;border:0;resize:none;background:linear-gradient(90deg,rgba(255,255,255,.018) 0,rgba(255,255,255,.018) 3.25rem,transparent 3.25rem),var(--editor);color:#e4ebf5;caret-color:var(--accent);font:13.5px/1.72 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;tab-size:2}
          #|.editor-statusbar{min-height:1.8rem;padding:.35rem .85rem;display:flex;align-items:center;justify-content:space-between;gap:1rem;border-top:1px solid var(--line);background:#0b131e;color:var(--muted);font-size:.64rem}
          #|.run-panel label{display:block;margin:.85rem 0 .32rem;color:var(--muted-strong);font-size:.7rem;font-weight:750}
          #|.run-panel input,.run-panel select,.run-panel textarea{width:100%;padding:.65rem .7rem;border:1px solid var(--line-strong);border-radius:.55rem;background:#111c2a;color:var(--ink)}
          #|.run-panel input::placeholder,.run-panel textarea::placeholder{color:#65758e}
          #|.mini-status{padding:.26rem .48rem;font-size:.64rem}
          #|.primary-action{width:100%;margin-top:.85rem;border-color:var(--accent-strong);background:var(--accent);color:var(--accent-ink);font-weight:850;box-shadow:0 8px 24px rgba(55,201,142,.12)}
          #|.primary-action:hover:not(:disabled){border-color:#9cf0ca;background:#8cebc4}
          #|.privacy-copy{color:var(--muted);font-size:.7rem;line-height:1.5}
          #|.request-policy{padding:.55rem .65rem;border:1px solid var(--line);border-radius:.45rem;background:rgba(255,255,255,.018)}
          #|.usage{margin-top:1rem;padding-top:.9rem;border-top:1px solid var(--line)}
          #|.usage-heading{display:flex;align-items:center;justify-content:space-between;gap:1rem}
          #|.usage h3,.usage p{margin:.4rem 0}
          #|.usage h3{font-size:.78rem}
          #|.usage-heading strong{color:var(--muted-strong);font-size:.72rem}
          #|.usage progress{width:100%;height:.38rem;border:0;accent-color:var(--accent)}
          #|.usage-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:.4rem;margin:.75rem 0}
          #|.usage-stats>div{min-width:0;padding:.48rem;border:1px solid var(--line);border-radius:.42rem;background:rgba(255,255,255,.018)}
          #|.usage-stats strong,.usage-stats span{display:block;overflow:hidden;text-overflow:ellipsis}
          #|.usage-stats strong{font-size:.7rem}
          #|.usage-stats span{margin-top:.18rem;color:var(--muted);font-size:.58rem}
          #|.output-view{min-width:0;padding:.8rem 1rem 1rem;border-top:1px solid var(--line);background:#0b131e}
          #|.output-view .panel-title{padding-bottom:.55rem}
          #|.output-view pre{max-height:18rem;overflow:auto;margin:.25rem 0 0;padding:.85rem;border:1px solid var(--line);border-radius:.5rem;background:var(--editor);white-space:pre-wrap;color:#dce6f3;font:12.5px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace}
          #|.integrations{padding:1.75rem 1rem 2.5rem;border-top:1px solid var(--line);background:#0a1019}
          #|.section-heading{display:flex;align-items:end;justify-content:space-between;gap:2rem;max-width:88rem;margin:0 auto .8rem}
          #|.section-heading>p{max-width:42rem;margin:.2rem 0 .8rem;line-height:1.55}
          #|.eyebrow{margin:0 0 .3rem;color:var(--accent);font-size:.65rem;font-weight:850;letter-spacing:.14em}
          #|.section-heading h2{margin:.15rem 0 .4rem;font-size:1.1rem;letter-spacing:-.015em}
          #|.integration-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.65rem;max-width:88rem;margin:0 auto}
          #|.integration-card{display:flex;min-height:10rem;flex-direction:column;padding:.85rem;border:1px solid var(--line);border-radius:.65rem;background:var(--panel);box-shadow:inset 0 1px rgba(255,255,255,.025)}
          #|.integration-card.featured{border-color:rgba(117,230,182,.42);background:linear-gradient(140deg,rgba(117,230,182,.07),var(--panel) 55%)}
          #|.integration-heading{display:flex;align-items:center;gap:.65rem}
          #|.integration-heading strong,.integration-heading span{display:block}
          #|.integration-mark{display:grid!important;place-items:center;width:2rem;height:2rem;border:1px solid var(--line-strong);border-radius:.5rem;background:var(--editor);color:var(--muted-strong);font-size:.62rem;font-weight:850;letter-spacing:.05em}
          #|.integration-card p{flex:1;color:var(--muted);font-size:.77rem;line-height:1.5}
          #|.integration-card button{align-self:flex-start;min-height:2.35rem;font-size:.73rem}
          #|.notice,.error-state,.success-state,.boundary-note,.loading-state{padding:.72rem .8rem;border:1px solid var(--line);border-radius:.52rem;background:var(--panel-raised);font-size:.78rem;line-height:1.5}
          #|.notice{max-width:88rem;margin:1rem auto 0}
          #|.error-state{margin:1rem;border-color:rgba(255,154,171,.48);background:var(--danger-soft);color:var(--danger)}
          #|.success-state{margin:1rem;border-color:rgba(117,230,182,.42);background:var(--accent-soft);color:var(--accent)}
          #|.boundary-note{color:var(--muted)}
          #|.boundary-note strong,.boundary-note span{display:block}
          #|.boundary-note strong{margin-bottom:.25rem;color:var(--muted-strong);font-size:.7rem}
          #|.boundary-note.compact{margin-top:1rem;padding:.62rem}
          #|.empty-state{padding:1rem;color:var(--muted)}
          #|.empty-state.compact{padding:.65rem}
          #|.entry-gate{display:grid;grid-template-columns:minmax(0,1fr) 24rem;gap:3.5rem;max-width:76rem;margin:0 auto;padding:clamp(4rem,8vh,7rem) 2rem 4rem}
          #|.gate-copy{max-width:42rem}
          #|.entry-gate h1{max-width:11ch;margin:.35rem 0 1rem;font-size:clamp(2.5rem,5vw,4.8rem);line-height:.98;letter-spacing:-.055em}
          #|.gate-lede{max-width:37rem;margin:0;color:var(--muted-strong);font-size:1rem;line-height:1.7}
          #|.gate-steps{display:grid;gap:.55rem;margin:1.8rem 0}
          #|.gate-step{display:grid;grid-template-columns:2.4rem minmax(0,1fr);gap:.8rem;align-items:start;padding:.72rem 0;border-top:1px solid var(--line)}
          #|.step-number{display:grid;place-items:center;width:2rem;height:2rem;border:1px solid var(--line-strong);border-radius:.55rem;background:var(--panel);color:var(--accent);font:700 .64rem/1 ui-monospace,SFMono-Regular,Menlo,monospace}
          #|.gate-step strong,.gate-step span{display:block}
          #|.gate-step strong{font-size:.82rem}
          #|.gate-step div span{margin-top:.22rem;color:var(--muted);font-size:.75rem;line-height:1.45}
          #|.gate-boundary{margin-top:1rem;background:rgba(255,255,255,.018)}
          #|html[lang^="zh"] .eyebrow,html[lang^="zh"] .panel-kicker,html[lang^="zh"] .connection-kicker{letter-spacing:.03em;text-transform:none}
          #|@media(max-width:76rem){.workspace-grid{grid-template-columns:13rem minmax(24rem,1fr)}.run-panel{grid-column:1/-1;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:0 1rem;border-top:1px solid var(--line);border-left:0}.run-panel>.panel-title,.run-panel>.primary-action,.run-panel>.request-policy,.run-panel>.usage{grid-column:1/-1}.integration-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
          #|@media(max-width:64rem){.entry-gate{display:block;max-width:44rem;padding-top:3rem}.gate-copy{max-width:none}}
          #|@media(max-width:48rem){.topbar,.section-heading{align-items:flex-start;flex-direction:column}.topbar{position:relative}.readiness{width:100%;justify-content:space-between}.lease-meta{min-width:0}.workspace-grid{display:block}.file-panel,.run-panel{border:0;border-bottom:1px solid var(--line)}.run-panel{display:block}.editor-stack{display:block}.code-editor{min-height:25rem;resize:vertical}.integration-grid{grid-template-columns:1fr}.integrations{padding:1.25rem .7rem 2rem}.entry-gate{padding:2.5rem 1rem}.entry-gate h1{font-size:clamp(2.4rem,13vw,3.6rem)}.editor-statusbar{align-items:flex-start;flex-direction:column;gap:.2rem}.usage-stats{grid-template-columns:1fr}}
          #|@media(max-width:30rem){.brand-copy .secondary,.lease-meta .secondary{display:none}.readiness{align-items:flex-start;flex-direction:column}.lease-meta{padding-left:0;border-left:0}.editor-meta .draft-state{display:none}}
          #|@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important;animation:none!important}}
        ),
      ),
      @html.a(
        href="#main",
        class="skip-link",
        copy(state.locale, "Skip to workspace", "跳到工作区"),
      ),
      topbar(state, emit),
      match state.error_message {
        Some(message) =>
          @html.p(
            class="error-state",
            attrs=@html.Attrs::build().role("alert"),
            message,
          )
        None => @html.nothing
      },
      match state.success_message {
        Some(message) =>
          @html.p(
            class="success-state",
            attrs=@html.Attrs::build().role("status").aria_live("polite"),
            message,
          )
        None => @html.nothing
      },
      if ready {
        @html.main_(id="main", class="workspace-main", [
          @html.h1(
            class="sr-only",
            copy(state.locale, "Developer workspace", "开发者工作台"),
          ),
          @html.div(class="workspace-grid", [
            file_tree(state, emit),
            @html.div(class="editor-stack", [
              editor(state, emit),
              output_view(state),
            ]),
            run_panel(state, emit),
          ]),
          integrations(state, emit),
        ])
      } else {
        lease_gate(state)
      },
    ],
  )
}

///|
pub fn view(state : WorkbenchState) -> @rabbita.Html {
  workbench_view(state, None)
}

///|
pub fn interactive_view(
  state : WorkbenchState,
  emit : @rabbita.Emit[WorkbenchMessage],
) -> @rabbita.Html {
  workbench_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : WorkbenchState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
