///|
/// Complete static workbench copy; dynamic messages have typed helpers.
priv enum StaticMessage {
  OpenCodebuddyWithScopedLunanexaClient
  ContinueInWorkbuddyThroughTheNorthbound
  HandTheActiveBrowserDraftTo
  OpenQoderWithAnExpiringProvider
  OpenAGenericClientThroughThe
  ThatBrowserDraftIsUnavailable
  AnActiveTextGenerationLeaseModel
  GenericClient
  Pending
  Connecting
  Connected
  ClientSideHandoff
  NeedsAttention
  Revoked
  WorkspaceReady
  LeaseExpired
  LeaseRevoked
  LeaseSuspended
  ApprovalPending
  AccessRequired
  ThisCapacityLeaseHasExpiredAsk
  ThisCapacityLeaseWasRevokedAnd
  ThisCapacityLeaseIsSuspendedNew
  ThisCapacityLeaseIsAwaitingApproval
  TheActiveLeaseIsOutsideIts
  ConnectWithAScopedInferenceToken
  LunanexaDeveloperWorkspace
  YourWorkspaceIsNotReady
  VerifyIdentity
  LoadAnOpaqueSubjectThroughTrusted
  CheckCapacity
  ConfirmAScopedTimeBoundedLease
  StartBuilding
  OpenTheLocalEditorAndGeneric
  TrustBoundary
  ALeaseNeverGrantsADgx
  Language
  InterfaceLanguage
  AuthorizationNotLoaded
  Workbench
  LocalDraftsProviderNeutralModels
  CapacityLease
  CopyLeaseId
  ProjectDrafts
  Explorer
  NoBrowserLocalDraftFilesAdd
  BrowserLocalOnly
  NoRepositoryCredentialIdeAgentShell
  SelectADraft
  ChooseABrowserLocalFileTo
  BrowserDraft
  CodeEditor
  LocalEditing
  ManagedNodeMountsNone
  Result
  NormalizedOutput
  AwaitingRequest
  SendingCanonicalWorkload
  RunTheSelectedDraftToInspect
  ModelRequest
  ModelTool
  RunWithLunanexa
  LeaseActive
  ModelAlias
  ChooseAnAuthorizedAliasManualInput
  Instruction
  Sending
  SendRequest
  EphemeralNoCacheNoTrainingReuse
  SessionUsage
  RequestQuota
  InputUnits
  OutputUnits
  AcceleratorMs
  ObservedInThisBrowserPageAuthoritative
  ClientSideExtension
  OpenTheSameScopedProviderContract
  PrepareVsCodeHandoff
  PrepareClientHandoff
  ClientIntegrations
  ContinueInYourPreferredClient
  VsCodeCodebuddyWorkbuddyTraeAnd
  SkipToWorkspace
  DeveloperWorkspace
}

///|
fn static_message(locale : @i18n.Locale, key : StaticMessage) -> String {
  match key {
    OpenCodebuddyWithScopedLunanexaClient =>
      @i18n.copy(
        locale, "Open CodeBuddy with scoped LunaNexa client metadata.", "使用限定范围的 LunaNexa 客户端元数据打开 CodeBuddy。",
      )
    ContinueInWorkbuddyThroughTheNorthbound =>
      @i18n.copy(
        locale, "Continue in WorkBuddy through the northbound contract.", "通过北向契约在 WorkBuddy 中继续。",
      )
    HandTheActiveBrowserDraftTo =>
      @i18n.copy(
        locale, "Hand the active browser draft to a local Trae client.", "将当前浏览器本地草稿交接给本地 Trae 客户端。",
      )
    OpenQoderWithAnExpiringProvider =>
      @i18n.copy(
        locale, "Open Qoder with an expiring provider-neutral handoff.", "通过有时效且不绑定特定提供商的交接打开 Qoder。",
      )
    OpenAGenericClientThroughThe =>
      @i18n.copy(
        locale, "Open a generic client through the scoped contract.", "通过限定范围的契约打开通用客户端。",
      )
    ThatBrowserDraftIsUnavailable =>
      @i18n.copy(
        locale, "That browser draft is unavailable.", "该浏览器草稿不可用。",
      )
    AnActiveTextGenerationLeaseModel =>
      @i18n.copy(
        locale, "An active text-generation lease, model, file, and instruction are required.",
        "需要有效的文本生成租约、模型、文件和指令。",
      )
    GenericClient => @i18n.copy(locale, "Generic client", "通用客户端")
    Pending => @i18n.copy(locale, "Pending", "待处理")
    Connecting => @i18n.copy(locale, "Connecting", "正在连接")
    Connected => @i18n.copy(locale, "Connected", "已连接")
    ClientSideHandoff =>
      @i18n.copy(locale, "Client-side handoff", "客户端交接")
    NeedsAttention => @i18n.copy(locale, "Needs attention", "需要处理")
    Revoked => @i18n.copy(locale, "Revoked", "已撤销")
    WorkspaceReady => @i18n.copy(locale, "Workspace ready", "工作区就绪")
    LeaseExpired => @i18n.copy(locale, "Lease expired", "租约已过期")
    LeaseRevoked => @i18n.copy(locale, "Lease revoked", "租约已撤销")
    LeaseSuspended => @i18n.copy(locale, "Lease suspended", "租约已暂停")
    ApprovalPending => @i18n.copy(locale, "Approval pending", "待审批")
    AccessRequired =>
      @i18n.copy(locale, "Access required", "需要访问权限")
    ThisCapacityLeaseHasExpiredAsk =>
      @i18n.copy(
        locale, "This capacity lease has expired. Ask an administrator for a new bounded lease.",
        "此工作区租约已过期。请联系管理员申请新的有期限租约。",
      )
    ThisCapacityLeaseWasRevokedAnd =>
      @i18n.copy(
        locale, "This capacity lease was revoked and cannot start new work.", "此工作区租约已撤销，无法启动新工作。",
      )
    ThisCapacityLeaseIsSuspendedNew =>
      @i18n.copy(
        locale, "This capacity lease is suspended. New work is disabled.", "此工作区租约已暂停，新工作已禁用。",
      )
    ThisCapacityLeaseIsAwaitingApproval =>
      @i18n.copy(
        locale, "This capacity lease is awaiting approval.", "此工作区租约待审批。",
      )
    TheActiveLeaseIsOutsideIts =>
      @i18n.copy(
        locale, "The active lease is outside its valid time window.", "当前租约不在有效时间范围内。",
      )
    ConnectWithAScopedInferenceToken =>
      @i18n.copy(
        locale, "Connect with a scoped inference token and verified identity to load your authorization. Loopback acceptance may also use an opaque subject reference.",
        "使用限定范围的推理令牌和已验证身份进行连接，以加载限定范围的访问权限。本地回环验收也可使用不透明主体引用。",
      )
    LunanexaDeveloperWorkspace =>
      @i18n.copy(
        locale, "LUNANEXA DEVELOPER WORKSPACE", "LUNANEXA 开发者工作台",
      )
    YourWorkspaceIsNotReady =>
      @i18n.copy(locale, "Your workspace is not ready", "工作区尚未就绪")
    VerifyIdentity => @i18n.copy(locale, "Verify identity", "验证身份")
    LoadAnOpaqueSubjectThroughTrusted =>
      @i18n.copy(
        locale, "Load an opaque subject through trusted ingress.", "通过受信任入口加载不透明主体。",
      )
    CheckCapacity => @i18n.copy(locale, "Check capacity", "检查容量")
    ConfirmAScopedTimeBoundedLease =>
      @i18n.copy(
        locale, "Confirm a scoped, time-bounded lease.", "确认限定范围且有时效的租约。",
      )
    StartBuilding => @i18n.copy(locale, "Start building", "开始开发")
    OpenTheLocalEditorAndGeneric =>
      @i18n.copy(
        locale, "Open the local editor and generic model tools.", "打开本地编辑器和通用模型工具。",
      )
    TrustBoundary => @i18n.copy(locale, "Trust boundary", "信任边界")
    ALeaseNeverGrantsADgx =>
      @i18n.copy(
        locale, "A lease never grants a DGX login, managed-node filesystem, arbitrary shell, repository checkout, or editor-agent installation.",
        "租约绝不会授予 DGX 登录、受管节点文件系统、任意 Shell、代码仓库检出或编辑器代理安装权限。",
      )
    Language => @i18n.copy(locale, "Language", "语言")
    InterfaceLanguage =>
      @i18n.copy(locale, "Interface language", "界面语言")
    AuthorizationNotLoaded =>
      @i18n.copy(locale, "Authorization not loaded", "访问权限未加载")
    Workbench =>
      @i18n.copy(
        locale, "能源谷“创未来”街区算力平台 Workbench", "能源谷“创未来”街区算力平台 开发者工作台",
      )
    LocalDraftsProviderNeutralModels =>
      @i18n.copy(
        locale, "Local drafts · provider-neutral models", "浏览器本地草稿 · 不绑定特定提供商的模型",
      )
    CapacityLease => @i18n.copy(locale, "Capacity lease", "容量租约")
    CopyLeaseId => @i18n.copy(locale, "Copy lease ID", "复制租约编号")
    ProjectDrafts => @i18n.copy(locale, "Project drafts", "项目草稿")
    Explorer => @i18n.copy(locale, "EXPLORER", "资源管理器")
    NoBrowserLocalDraftFilesAdd =>
      @i18n.copy(
        locale, "No browser-local draft files. Add a local draft before sending a request.",
        "没有浏览器本地草稿。请先添加本地草稿，再发送请求。",
      )
    BrowserLocalOnly =>
      @i18n.copy(locale, "Browser-local only", "仅限浏览器本地")
    NoRepositoryCredentialIdeAgentShell =>
      @i18n.copy(
        locale, "No repository, credential, IDE agent, shell, or filesystem is mounted on a managed GPU node.",
        "受管节点文件系统不会挂载代码仓库、凭据、IDE 代理或任意 Shell。",
      )
    SelectADraft => @i18n.copy(locale, "Select a draft", "选择草稿")
    ChooseABrowserLocalFileTo =>
      @i18n.copy(
        locale, "Choose a browser-local file to begin editing.", "选择浏览器本地文件以开始编辑。",
      )
    BrowserDraft => @i18n.copy(locale, "Browser draft", "浏览器本地草稿")
    CodeEditor => @i18n.copy(locale, "Code editor", "代码编辑器")
    LocalEditing => @i18n.copy(locale, "Local editing", "本地编辑")
    ManagedNodeMountsNone =>
      @i18n.copy(
        locale, "Managed-node mounts: none", "受管节点挂载：无",
      )
    Result => @i18n.copy(locale, "RESULT", "结果")
    NormalizedOutput =>
      @i18n.copy(locale, "Normalized output", "规范化输出")
    AwaitingRequest => @i18n.copy(locale, "Awaiting request", "等待请求")
    SendingCanonicalWorkload =>
      @i18n.copy(
        locale, "Sending canonical workload…", "正在发送规范工作负载…",
      )
    RunTheSelectedDraftToInspect =>
      @i18n.copy(
        locale, "Run the selected draft to inspect normalized output and its auditable receipt.",
        "运行所选草稿，以检查标准化输出及其可审计回执。",
      )
    ModelRequest => @i18n.copy(locale, "Model request", "模型请求")
    ModelTool => @i18n.copy(locale, "MODEL TOOL", "模型工具")
    RunWithLunanexa =>
      @i18n.copy(locale, "Run with LunaNexa", "使用 LunaNexa 运行")
    LeaseActive => @i18n.copy(locale, "Lease active", "租约有效")
    ModelAlias => @i18n.copy(locale, "Model alias", "模型别名")
    ChooseAnAuthorizedAliasManualInput =>
      @i18n.copy(
        locale, "Choose an authorized alias. Manual input never grants access; the server checks every request.",
        "选择已授权别名。手动输入不会授予权限；服务器逐次检查请求。",
      )
    Instruction => @i18n.copy(locale, "Instruction", "指令")
    Sending => @i18n.copy(locale, "Sending…", "正在发送…")
    SendRequest => @i18n.copy(locale, "Send request", "发送请求")
    EphemeralNoCacheNoTrainingReuse =>
      @i18n.copy(
        locale, "Ephemeral · no cache · no training reuse · bounded deadline",
        "临时处理 · 不缓存 · 不用于训练 · 有期限",
      )
    SessionUsage => @i18n.copy(locale, "Session usage", "会话用量")
    RequestQuota => @i18n.copy(locale, "Request quota", "请求配额")
    InputUnits => @i18n.copy(locale, "Input units", "输入单元")
    OutputUnits => @i18n.copy(locale, "Output units", "输出单元")
    AcceleratorMs =>
      @i18n.copy(locale, "Accelerator ms", "加速器耗时（ms）")
    ObservedInThisBrowserPageAuthoritative =>
      @i18n.copy(
        locale, "Observed in this browser page; authoritative metering remains in the controller receipt and operator telemetry.",
        "此处仅显示本浏览器页面观测到的用量；权威计量仍以控制器回执和运维遥测为准。",
      )
    ClientSideExtension =>
      @i18n.copy(locale, "Client-side extension", "客户端扩展")
    OpenTheSameScopedProviderContract =>
      @i18n.copy(
        locale, "Open the same scoped provider contract in a local VS Code extension.",
        "在本地 VS Code 扩展中打开同一限定范围且不绑定特定提供商的契约。",
      )
    PrepareVsCodeHandoff =>
      @i18n.copy(locale, "Prepare VS Code handoff", "准备 VS Code 交接")
    PrepareClientHandoff =>
      @i18n.copy(locale, "Prepare client handoff", "准备客户端交接")
    ClientIntegrations =>
      @i18n.copy(locale, "CLIENT INTEGRATIONS", "客户端集成")
    ContinueInYourPreferredClient =>
      @i18n.copy(
        locale, "Continue in your preferred client", "在常用客户端中继续",
      )
    VsCodeCodebuddyWorkbuddyTraeAnd =>
      @i18n.copy(
        locale, "VS Code, CodeBuddy, WorkBuddy, Trae, and Qoder remain client-side. Handoffs never install credentials, repositories, shells, or agents on GPU nodes.",
        "VS Code、CodeBuddy、WorkBuddy、Trae 和 Qoder 始终位于客户端。交接绝不会在 GPU 节点上安装凭据、代码仓库、Shell 或代理。",
      )
    SkipToWorkspace =>
      @i18n.copy(locale, "Skip to workspace", "跳到工作区")
    DeveloperWorkspace =>
      @i18n.copy(locale, "Developer workspace", "开发者工作台")
  }
}
