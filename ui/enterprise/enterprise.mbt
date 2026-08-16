///|
pub(all) enum EnterpriseRoute {
  Overview
  Agreements
  LeaseRequests
  Notifications
  Costs
  Models
  MachineAccess
  OfflineCommerce
  ContractDocuments
} derive(Debug, Eq)

///|
pub(all) struct EnterpriseCostCenterRow {
  cost_center_id : String
  display_name : String
  project_count : Int
  provisional_spend : String
  budget_posture : String
} derive(Debug, Eq)

///|
pub(all) struct EnterpriseState {
  route : EnterpriseRoute
  locale : @i18n.Locale
  membership : @portal.EnterpriseMembership?
  agreements : Array[@portal.PortalAgreement]
  lease_requests : Array[@portal.EnterpriseLeaseRequest]
  notifications : Array[@notifications.NotificationRecord]
  notification_preferences : Array[@notifications.NotificationPreferenceView]
  machine_access : @machine_access.MachineAccessState
  offline_commerce : @offline_commerce.OfflineCommerceState
  contract_documents : @contract_documents.ContractDocumentsState
  cost_centers : Array[EnterpriseCostCenterRow]
  provisional_spend : String
  model_catalog : Array[@portal.EnterpriseModelSummary]
  project_id : String
  unix_username : String
  model_ids : String
  justification : String
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  loading : Bool
  success_message : String?
  error_message : String?
} derive(Eq)

///|
pub(all) enum EnterpriseMessage {
  Navigate(EnterpriseRoute)
  LocaleChanged(@i18n.Locale)
  ProjectChanged(String)
  UsernameChanged(String)
  ModelsChanged(String)
  JustificationChanged(String)
  SignAgreement(String)
  SubmitLease
  MarkNotificationRead(String, Int64)
  SetNotificationEmail(@notifications.NotificationTopic, Bool)
  MachineAccess(@machine_access.MachineAccessMessage)
  OfflineCommerce(@offline_commerce.OfflineCommerceMessage)
  ContractDocuments(@contract_documents.ContractDocumentsMessage)
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
pub fn default_state(now_unix_ms : Int64) -> EnterpriseState {
  {
    route: Overview,
    locale: @i18n.default_locale(),
    membership: None,
    agreements: [],
    lease_requests: [],
    notifications: [],
    notification_preferences: [],
    machine_access: @machine_access.default_state(@i18n.default_locale()),
    offline_commerce: @offline_commerce.default_state(
      @i18n.default_locale(),
      CustomerCommerce,
    ),
    contract_documents: @contract_documents.default_state(
      @i18n.default_locale(),
    ),
    cost_centers: [],
    provisional_spend: "—",
    model_catalog: [],
    project_id: "",
    unix_username: "",
    model_ids: "",
    justification: "",
    starts_unix_ms: now_unix_ms + 3600000L,
    expires_unix_ms: now_unix_ms + 90000000L,
    loading: false,
    success_message: None,
    error_message: None,
  }
}

///|
pub fn demo_state() -> EnterpriseState {
  let now = 1786320000000L
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let demo_packet : @contractdoc.ContractPacket = {
    packet_id: "packet-demo-youthpolicy",
    idempotency_key: "packet-demo-youthpolicy-key",
    template_id: manifest.template_id,
    template_version: manifest.template_version,
    template_sha256: manifest.sha256,
    tenant_ref: "tenant-northstar",
    organization_id: "org-northstar",
    subject_ref: "subject-alice",
    order_ref: "order-capacity-2026-08",
    preceding_packet_ref: None,
    active_forms: [
      MasterLease,
      ReservationApplication,
      AccessConfirmation,
      ViolationNotice,
      DamageAssessment,
      SettlementConfirmation,
      EarlyTerminationApplication,
    ],
    values: [],
    assignments: [],
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    artifacts: [],
    state: InformationDraft,
    execution: None,
    closure: None,
    supersession: None,
    generation_failure: None,
    revision: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
  }
  {
    ..default_state(now),
    membership: Some({
      membership_id: "membership-northstar",
      tenant_ref: "tenant-northstar",
      organization_id: "org-northstar",
      subject_ref: "subject-alice",
      roles: [OrganizationAdministrator, LegalSigner, LeaseRequester, Developer],
      active: true,
      created_unix_ms: now - 2592000000L,
    }),
    agreements: [
      {
        agreement_id: "agreement-framework-2026",
        tenant_ref: "tenant-northstar",
        organization_id: "org-northstar",
        template_ref: "framework-v3",
        title: "Enterprise capacity framework",
        summary: "Terms for time-bounded exclusive GPU capacity, acceptable use, support and sanitization.",
        rendered_document_hash: "sha256:4f94d8f0a2",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: now - 86400000L,
        updated_unix_ms: now - 86400000L,
      },
      {
        agreement_id: "agreement-dpa-2026",
        tenant_ref: "tenant-northstar",
        organization_id: "org-northstar",
        template_ref: "dpa-v2",
        title: "Data processing agreement",
        summary: "Processing scope, retention, subprocessors and incident response evidence.",
        rendered_document_hash: "sha256:95a01f36bd",
        state: Executed,
        generation: 3L,
        signer_subject_ref: Some("subject-alice"),
        signature_request_receipt: Some("portal-signature:demo-dpa"),
        executed_artifact_hash: Some("sha256:executed-dpa"),
        created_unix_ms: now - 172800000L,
        updated_unix_ms: now - 86400000L,
      },
    ],
    lease_requests: [
      {
        submission: {
          request_id: "request-eval-042",
          idempotency_key: "submit-eval-042",
          tenant_ref: "tenant-northstar",
          organization_id: "org-northstar",
          project_id: "project-vision-lab",
          unix_username: "alice",
          starts_unix_ms: now + 86400000L,
          expires_unix_ms: now + 176400000L,
          requested_model_ids: ["qwen3-32b", "bge-m3"],
          justification: "Private evaluation and adapter validation.",
        },
        subject_ref: "subject-alice",
        state: Submitted,
        generation: 1L,
        assigned_node_id: None,
        exclusive_lease_id: None,
        decision_receipt: None,
        created_unix_ms: now - 3600000L,
        updated_unix_ms: now - 3600000L,
      },
    ],
    notifications: [
      {
        event: {
          version: @notifications.contract_version,
          notification_id: "notice-access-ready-demo",
          deduplication_key: "access-ready-demo",
          source_receipt: "exclusive-lease:demo:5",
          topic: AccessCredential,
          code: "LeaseAccessReady",
          severity: Information,
          audience: Subject(
            tenant_ref="tenant-northstar",
            subject_ref="subject-alice",
          ),
          title_key: "notifications.lease_access_ready.title",
          body_key: "notifications.lease_access_ready.body",
          parameters: {
            "lease_ref": "exclusive-lease-demo",
            "credential_ref": "credential://vault/access-demo",
          },
          created_unix_ms: now - 1800000L,
          expires_unix_ms: None,
        },
        lifecycle: Unread,
        generation: 1L,
        assigned_to: None,
        acknowledged_by: None,
        acknowledged_unix_ms: None,
        silenced_until_unix_ms: None,
        resolved_by: None,
        resolved_unix_ms: None,
        updated_unix_ms: now - 1800000L,
      },
    ],
    notification_preferences: [
      {
        topic: LeaseLifecycle,
        channels: [InApp, Email],
        minimum_severity: Information,
        updated_unix_ms: now - 1800000L,
      },
    ],
    machine_access: {
      ..@machine_access.default_state(@i18n.default_locale()),
      machines: [
        {
          version: @nodelease.contract_version,
          lease_ref: "exclusive-lease-demo",
          machine_ref: "assigned-machine:exclusive-lease-demo",
          state: Active,
          generation: 5L,
          username: "alice",
          starts_unix_ms: now - 3600000L,
          expires_unix_ms: now + 86400000L,
          updated_unix_ms: now - 1800000L,
          reachability: Online,
          last_seen_unix_ms: Some(now - 5000L),
          credential_handoff: {
            state: Available,
            handoff_ref: None,
            credential_kind: "short-lived-ssh-certificate",
            valid_until_unix_ms: now + 86400000L,
            raw_secret_included: false,
          },
          can_terminate: true,
          termination_confirmation: Some("TERMINATE exclusive-lease-demo"),
        },
      ],
    },
    offline_commerce: {
      ..@offline_commerce.demo_state(@i18n.default_locale(), CustomerCommerce),
      project_id: "project-vision-lab",
    },
    contract_documents: {
      ..@contract_documents.default_state(@i18n.default_locale()),
      manifest: Some(manifest),
      packets: [demo_packet],
      selected_packet_id: Some("packet-demo-youthpolicy"),
      selected_form: Some(MasterLease),
    },
    cost_centers: [
      {
        cost_center_id: "cc-research",
        display_name: "AI Research",
        project_count: 2,
        provisional_spend: "CNY 12,760.00",
        budget_posture: "Within budget",
      },
      {
        cost_center_id: "cc-platform",
        display_name: "Platform",
        project_count: 1,
        provisional_spend: "CNY 5,660.00",
        budget_posture: "Within budget",
      },
    ],
    provisional_spend: "CNY 18,420.00",
    model_catalog: [
      {
        model_id: "qwen3-32b",
        version: "v1",
        alias_name: Some("text.default"),
        compatible_architectures: ["nvidia-gb10"],
        minimum_memory_mib: 65536,
      },
      {
        model_id: "bge-m3",
        version: "v2",
        alias_name: Some("embedding.default"),
        compatible_architectures: ["nvidia-gb10"],
        minimum_memory_mib: 4096,
      },
    ],
    project_id: "project-vision-lab",
    unix_username: "alice",
    model_ids: "qwen3-32b, bge-m3",
    justification: "Private evaluation and adapter validation.",
  }
}

///|
pub fn EnterpriseState::update(
  self : EnterpriseState,
  message : EnterpriseMessage,
) -> EnterpriseState {
  match message {
    Navigate(route) =>
      { ..self, route, success_message: None, error_message: None }
    LocaleChanged(locale) =>
      {
        ..self,
        locale,
        machine_access: { ..self.machine_access, locale, },
        offline_commerce: { ..self.offline_commerce, locale, },
        contract_documents: { ..self.contract_documents, locale, },
        success_message: None,
        error_message: None,
      }
    ProjectChanged(value) => { ..self, project_id: value }
    UsernameChanged(value) => { ..self, unix_username: value }
    ModelsChanged(value) => { ..self, model_ids: value }
    JustificationChanged(value) => { ..self, justification: value }
    SignAgreement(_) =>
      { ..self, loading: true, success_message: None, error_message: None }
    SubmitLease =>
      { ..self, loading: true, success_message: None, error_message: None }
    MarkNotificationRead(_, _) => self
    SetNotificationEmail(_, _) =>
      { ..self, loading: true, success_message: None, error_message: None }
    MachineAccess(message) =>
      { ..self, machine_access: self.machine_access.update(message) }
    OfflineCommerce(message) =>
      { ..self, offline_commerce: self.offline_commerce.update(message) }
    ContractDocuments(message) =>
      { ..self, contract_documents: self.contract_documents.update(message) }
    ClearNotice => { ..self, success_message: None, error_message: None }
  }
}

///|
pub fn lease_form_valid(state : EnterpriseState) -> Bool {
  state.membership is Some(_) &&
  state.project_id.trim() != "" &&
  state.unix_username.trim() != "" &&
  state.model_ids.trim() != "" &&
  state.justification.trim() != "" &&
  state.expires_unix_ms > state.starts_unix_ms &&
  !state.loading
}

///|
fn command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  message : EnterpriseMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  wrap : (String) -> EnterpriseMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn route_label(locale : @i18n.Locale, route : EnterpriseRoute) -> String {
  match route {
    Overview => copy(locale, "Overview", "概览")
    Agreements => copy(locale, "Agreements", "协议")
    LeaseRequests => copy(locale, "Lease requests", "租用申请")
    Notifications => copy(locale, "Notifications", "通知")
    Costs => copy(locale, "Usage & costs", "用量与成本")
    Models => copy(locale, "Model catalog", "模型目录")
    MachineAccess => copy(locale, "My machine", "我的机器")
    OfflineCommerce => copy(locale, "Orders & documents", "订单与材料")
    ContractDocuments => copy(locale, "Contract forms", "合同表单")
  }
}

///|
fn state_label(
  locale : @i18n.Locale,
  state : @portal.PortalAgreementState,
) -> String {
  match state {
    ReviewRequired => copy(locale, "Review required", "待审阅")
    SignatureRequested => copy(locale, "Signature in progress", "签署中")
    Executed => copy(locale, "Executed", "已签署")
    Declined => copy(locale, "Declined", "已拒绝")
    Superseded => copy(locale, "Superseded", "已替代")
  }
}

///|
fn request_state_label(
  locale : @i18n.Locale,
  state : @portal.LeaseRequestState,
) -> String {
  match state {
    Submitted => copy(locale, "Awaiting operator", "等待运维审核")
    Approved => copy(locale, "Node reserved", "节点已预留")
    Rejected => copy(locale, "Rejected", "已拒绝")
    Cancelled => copy(locale, "Cancelled", "已取消")
  }
}

///|
fn navigation(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let items = [
    for
      route in [
        Overview,
        Agreements,
        LeaseRequests,
        MachineAccess,
        OfflineCommerce,
        ContractDocuments,
        Notifications,
        Costs,
        Models,
      ] => {
      @html.button(
        type_="button",
        class=if state.route == route {
          "nav-item is-active"
        } else {
          "nav-item"
        },
        attrs=@html.Attrs::build().aria_current(
          if state.route == route {
            "page"
          } else {
            "false"
          },
        ),
        on_click=command(emit, Navigate(route)),
        route_label(state.locale, route),
      )
    }
  ]
  items.push(
    @html.a(
      class="nav-item nav-link",
      href="/workbench/",
      copy(state.locale, "WebIDE", "WebIDE"),
    ),
  )
  @html.aside(class="enterprise-sidebar", [
    @html.a(class="enterprise-brand", href="/enterprise/", [
      @html.span(class="brand-mark", "LN"),
      @html.span([
        @html.strong("LunaNexa"),
        @html.small(copy(state.locale, "Enterprise", "企业平台")),
      ]),
    ]),
    @html.nav(
      attrs=@html.Attrs::build().aria_label(
        copy(state.locale, "Enterprise navigation", "企业导航"),
      ),
      items,
    ),
    @html.div(class="trust-note", [
      @html.strong(copy(state.locale, "Customer boundary", "客户边界")),
      @html.p(
        copy(
          state.locale,
          "You request capacity here. LunaNexa operators select and prepare the assigned DGX node.",
          "您在此申请容量；LunaNexa 运维人员选择并准备分配的 DGX 节点。",
        ),
      ),
    ]),
  ])
}

///|
fn page_header(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let organization = match state.membership {
    Some(value) => value.organization_id
    None => copy(state.locale, "Not connected", "未连接")
  }
  @html.header(class="enterprise-topbar", [
    @html.div([
      @html.p(
        class="eyebrow",
        copy(state.locale, "ENTERPRISE CONTROL CENTER", "企业控制中心"),
      ),
      @html.h1(route_label(state.locale, state.route)),
    ]),
    @html.div(class="topbar-actions", [
      @html.div(class="locale-control", [
        @html.label(
          for_="enterprise-locale",
          copy(state.locale, "Language", "语言"),
        ),
        @html.select(
          id="enterprise-locale",
          on_change=text_command(emit, value => {
            LocaleChanged(@i18n.parse_locale(value))
          }),
          attrs=@html.Attrs::build().aria_label(
            copy(state.locale, "Interface language", "界面语言"),
          ),
          [
            @html.option(
              value=@i18n.English.storage_value(),
              selected=state.locale == English,
              @i18n.English.label(),
            ),
            @html.option(
              value=@i18n.ChineseSimplified.storage_value(),
              selected=state.locale == ChineseSimplified,
              @i18n.ChineseSimplified.label(),
            ),
          ],
        ),
      ]),
      @html.div(class="topbar-meta", [
        @html.span(class="status-dot", ""),
        @html.span(organization),
        @html.span(
          class="role-pill",
          copy(state.locale, "Tenant scoped", "限定租户范围"),
        ),
      ]),
    ]),
  ])
}

///|
fn overview_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let pending = state.agreements
    .filter(value => value.state == ReviewRequired)
    .length()
  let open_requests = state.lease_requests
    .filter(value => value.state == Submitted)
    .length()
  @html.div(class="page-stack", [
    @html.section(class="welcome-panel", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(state.locale, "YOUR LUNANEXA TENANT", "您的 LUNANEXA 租户"),
        ),
        @html.h2(
          copy(
            state.locale,
            "From agreement to an isolated GPU workspace",
            "从协议签署到隔离 GPU 工作区",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Review required agreements, request a time window, then follow preparation status. Node selection and activation remain operator-controlled.",
            "审阅必需协议、申请使用时段，然后跟踪准备状态。节点选择与激活仍由运维人员控制。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        on_click=command(emit, Navigate(LeaseRequests)),
        copy(state.locale, "Request capacity", "申请容量"),
      ),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(
          copy(state.locale, "Agreements to review", "待审阅协议"),
        ),
        @html.strong("\{pending}"),
        @html.small(
          copy(
            state.locale,
            "Legal signer action",
            "需要法定签署人操作",
          ),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(
          copy(state.locale, "Open lease requests", "待处理租用申请"),
        ),
        @html.strong("\{open_requests}"),
        @html.small(
          copy(state.locale, "Operator review queue", "运维审核队列"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Models entitled", "可用模型")),
        @html.strong(state.model_catalog.length().to_string()),
        @html.small(
          copy(state.locale, "Shared central catalog", "中央共享目录"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Current spend", "当前支出")),
        @html.strong(state.provisional_spend),
        @html.small(
          copy(state.locale, "Provisional central ledger", "中央台账暂计"),
        ),
      ]),
    ]),
    @html.section(class="workflow-panel", [
      @html.h2(copy(state.locale, "Lease readiness", "租用准备流程")),
      @html.ol(class="workflow-steps", [
        @html.li(class="is-complete", [
          @html.span("1"),
          @html.div([
            @html.strong(
              copy(state.locale, "Enterprise verified", "企业已验证"),
            ),
            @html.p(
              copy(
                state.locale,
                "Organization membership and signer authority recorded.",
                "组织成员身份与签署权限已记录。",
              ),
            ),
          ]),
        ]),
        @html.li(
          class=if pending == 0 { "is-complete" } else { "is-current" },
          [
            @html.span("2"),
            @html.div([
              @html.strong(
                copy(
                  state.locale,
                  "Execute required agreements",
                  "签署必需协议",
                ),
              ),
              @html.p(
                copy(
                  state.locale,
                  "External signature evidence is verified before execution.",
                  "外部签名证据验证后才标记为已签署。",
                ),
              ),
            ]),
          ],
        ),
        @html.li(class=if open_requests > 0 { "is-current" } else { "" }, [
          @html.span("3"),
          @html.div([
            @html.strong(copy(state.locale, "Request capacity", "申请容量")),
            @html.p(
              copy(
                state.locale,
                "Choose project, time window, username and required models.",
                "选择项目、时段、用户名与所需模型。",
              ),
            ),
          ]),
        ]),
        @html.li([
          @html.span("4"),
          @html.div([
            @html.strong(
              copy(
                state.locale,
                "Operator assigns one node",
                "运维分配一个节点",
              ),
            ),
            @html.p(
              copy(
                state.locale,
                "A credential reference is created; no raw password is stored.",
                "系统创建凭据引用，不存储明文密码。",
              ),
            ),
          ]),
        ]),
      ]),
    ]),
  ])
}

///|
fn agreements_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let records = [
    for agreement in state.agreements => agreement_card(state, emit, agreement)
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(
          copy(
            state.locale,
            "Agreements requiring your organization",
            "您组织需要处理的协议",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Review the immutable document hash before opening the external signature ceremony.",
            "在打开外部签署流程前，请核对不可变文档哈希。",
          ),
        ),
      ]),
      @html.span(class="count-pill", "\{state.agreements.length()}"),
    ]),
    @html.div(class="record-list", records),
  ])
}

///|
fn agreement_card(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  agreement : @portal.PortalAgreement,
) -> @rabbita.Html {
  let action = if agreement.state == ReviewRequired {
    @html.div(class="record-actions", [
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading,
        on_click=command(emit, SignAgreement(agreement.agreement_id)),
        copy(state.locale, "Review & sign", "审阅并签署"),
      ),
      @html.small(
        copy(
          state.locale,
          "Requests a handoff from the configured signature provider; LunaNexa never collects signing credentials.",
          "向已配置的电子签名服务请求交接；LunaNexa 不收集签署凭据。",
        ),
      ),
    ])
  } else {
    @html.nothing
  }
  @html.article(class="record-card", [
    @html.div(class="record-main", [
      @html.div(class="record-title", [
        @html.h3(agreement.title),
        @html.span(
          class="state-pill",
          state_label(state.locale, agreement.state),
        ),
      ]),
      @html.p(agreement.summary),
      @html.dl(class="record-meta", [
        @html.div([
          @html.dt(copy(state.locale, "Template", "模板")),
          @html.dd(agreement.template_ref),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Document hash", "文档哈希")),
          @html.dd(class="mono", agreement.rendered_document_hash),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Generation", "版本代")),
          @html.dd("\{agreement.generation}"),
        ]),
      ]),
    ]),
    action,
  ])
}

///|
fn lease_requests_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.div(class="lease-layout", [
    @html.section(class="request-form", [
      @html.p(
        class="eyebrow",
        copy(
          state.locale,
          "NEW EXCLUSIVE CAPACITY REQUEST",
          "新建独占容量申请",
        ),
      ),
      @html.h2(
        copy(
          state.locale,
          "Request a time-bounded workspace",
          "申请有时限的工作区",
        ),
      ),
      @html.p(
        copy(
          state.locale,
          "Request requirements, not a specific machine. An operator selects one eligible DGX Spark node after policy and availability checks.",
          "请提交需求，而不是指定机器。运维人员将在策略与可用性检查后选择一个符合条件的 DGX Spark 节点。",
        ),
      ),
      @html.div(class="form-grid", [
        @html.div(class="field", [
          @html.label(
            for_="lease-project",
            copy(state.locale, "Project ID", "项目 ID"),
          ),
          @html.input(
            id="lease-project",
            value=state.project_id,
            maxlength=160,
            on_input=text_command(emit, value => ProjectChanged(value)),
          ),
        ]),
        @html.div(class="field", [
          @html.label(
            for_="lease-username",
            copy(state.locale, "Unix username", "Unix 用户名"),
          ),
          @html.input(
            id="lease-username",
            value=state.unix_username,
            maxlength=32,
            auto_complete=Off,
            on_input=text_command(emit, value => UsernameChanged(value)),
          ),
          @html.small(
            copy(
              state.locale,
              "Password is not accepted. Access uses a short-lived credential reference.",
              "不接受密码。访问使用短期凭据引用。",
            ),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-models",
            copy(state.locale, "Model IDs", "模型 ID"),
          ),
          @html.input(
            id="lease-models",
            value=state.model_ids,
            maxlength=1000,
            on_input=text_command(emit, value => ModelsChanged(value)),
          ),
          @html.small(
            copy(
              state.locale,
              "Comma-separated models from the shared catalog.",
              "使用共享目录中的模型，逗号分隔。",
            ),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-justification",
            copy(state.locale, "Business justification", "业务说明"),
          ),
          @html.textarea(
            id="lease-justification",
            maxlength=1000,
            value=state.justification,
            on_input=text_command(emit, value => JustificationChanged(value)),
            "",
          ),
        ]),
      ]),
      @html.div(class="request-boundary", [
        @html.strong(copy(state.locale, "What happens next", "后续流程")),
        @html.p(
          copy(
            state.locale,
            "The request enters the operator queue. Approval reserves exactly one node, then provisioning, access issuance and sanitization follow the exclusive-lease state machine.",
            "申请进入运维队列。批准后只预留一个节点，随后按独占租用状态机完成配置、访问授权与清理。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        disabled=!lease_form_valid(state),
        on_click=command(emit, SubmitLease),
        copy(state.locale, "Submit lease request", "提交租用申请"),
      ),
    ]),
    @html.section(class="request-history", [
      @html.h2(copy(state.locale, "Request history", "申请记录")),
      if state.lease_requests.length() == 0 {
        @html.p(
          class="empty",
          copy(state.locale, "No requests yet.", "暂无申请。"),
        )
      } else {
        @html.div(
          class="record-list compact",
          [
            for request in state.lease_requests => {
              @html.article(class="record-card", [
                @html.div(class="record-title", [
                  @html.h3(request.submission.request_id),
                  @html.span(
                    class="state-pill",
                    request_state_label(state.locale, request.state),
                  ),
                ]),
                @html.p(request.submission.justification),
                @html.dl(class="record-meta", [
                  @html.div([
                    @html.dt(copy(state.locale, "Project", "项目")),
                    @html.dd(request.submission.project_id),
                  ]),
                  @html.div([
                    @html.dt(copy(state.locale, "Models", "模型")),
                    @html.dd(request.submission.requested_model_ids.join(", ")),
                  ]),
                  @html.div([
                    @html.dt(
                      copy(state.locale, "Assigned node", "已分配节点"),
                    ),
                    @html.dd(
                      request.assigned_node_id.unwrap_or(
                        copy(state.locale, "Not assigned", "尚未分配"),
                      ),
                    ),
                  ]),
                ]),
              ])
            }
          ],
        )
      },
    ]),
  ])
}

///|
fn costs_view(state : EnterpriseState) -> @rabbita.Html {
  let rows = [
    for center in state.cost_centers => {
      @html.tr([
        @html.td([
          @html.strong(center.display_name),
          @html.span(class="mono secondary", center.cost_center_id),
        ]),
        @html.td(center.project_count.to_string()),
        @html.td(center.provisional_spend),
        @html.td(center.budget_posture),
      ])
    }
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(
          copy(
            state.locale,
            "Usage and cost allocation",
            "用量与成本分摊",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Tenant-scoped projections from the central commercial ledger.",
            "来自中央商业台账的限定租户范围视图。",
          ),
        ),
      ]),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Provisional charges", "暂计费用")),
        @html.strong(state.provisional_spend),
        @html.small(
          copy(state.locale, "Central ledger projection", "中央台账视图"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Cost centers", "成本中心")),
        @html.strong(state.cost_centers.length().to_string()),
        @html.small(copy(state.locale, "Tenant scoped", "限定租户范围")),
      ]),
    ]),
    if rows.length() == 0 {
      @html.p(
        class="empty",
        copy(
          state.locale,
          "Commercial state is not configured for this organization.",
          "此组织尚未配置商业状态。",
        ),
      )
    } else {
      @html.section(class="data-table-panel", [
        @html.h3(copy(state.locale, "Cost centers", "成本中心")),
        @html.table([
          @html.thead([
            @html.tr([
              @html.th(copy(state.locale, "Cost center", "成本中心")),
              @html.th(copy(state.locale, "Projects", "项目数")),
              @html.th(copy(state.locale, "Spend", "支出")),
              @html.th(copy(state.locale, "Status", "状态")),
            ]),
          ]),
          @html.tbody(rows),
        ]),
      ])
    },
  ])
}

///|
fn models_view(state : EnterpriseState) -> @rabbita.Html {
  let cards = [
    for model in state.model_catalog => {
      model_card(
        state,
        model.model_id,
        model.alias_name.unwrap_or(model.version),
        "\{model.minimum_memory_mib} MiB",
      )
    }
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(
          copy(state.locale, "Shared model catalog", "共享模型目录"),
        ),
        @html.p(
          copy(
            state.locale,
            "One management-plane catalog feeds portal requests, one-click deployments and WebIDE selectors.",
            "同一个管理平面目录为企业申请、一键部署与 WebIDE 选择器提供数据。",
          ),
        ),
      ]),
    ]),
    if cards.length() == 0 {
      @html.p(
        class="empty",
        copy(
          state.locale,
          "No approved models are entitled for this tenant.",
          "此租户暂无已批准模型。",
        ),
      )
    } else {
      @html.div(class="model-grid", cards)
    },
  ])
}

///|
fn model_card(
  state : EnterpriseState,
  name : String,
  kind : String,
  size : String,
) -> @rabbita.Html {
  @html.article(class="model-card", [
    @html.div(class="model-icon", "M"),
    @html.h3(name),
    @html.p(kind),
    @html.dl([
      @html.div([
        @html.dt(copy(state.locale, "Availability", "可用性")),
        @html.dd(copy(state.locale, "Managed centrally", "中央托管")),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Artifact", "制品")),
        @html.dd(size),
      ]),
    ]),
    @html.span(class="entitled", copy(state.locale, "Entitled", "已授权")),
  ])
}

///|
fn notification_code_label(locale : @i18n.Locale, code : String) -> String {
  match code {
    "LeaseRequestApproved" =>
      copy(locale, "Capacity request approved", "容量申请已批准")
    "LeaseAccessReady" =>
      copy(locale, "Machine access is ready", "机器访问已就绪")
    "LeaseExpiring" =>
      copy(locale, "Machine access expires soon", "机器访问即将到期")
    "LeaseTerminating" =>
      copy(locale, "Machine access is terminating", "机器访问正在终止")
    "LeaseCompleted" =>
      copy(locale, "Machine access ended", "机器访问已结束")
    "AgreementActionRequired" =>
      copy(locale, "Agreement action required", "协议需要处理")
    "OfflineDocumentsRequired" =>
      copy(locale, "Offline documents required", "需要线下文件")
    "QuoteReady" => copy(locale, "Quote is ready", "报价已生成")
    "OfflinePacketReady" =>
      copy(
        locale, "Offline contract packet is ready", "线下合同文件包已生成",
      )
    "EvidenceReviewStarted" =>
      copy(locale, "Evidence review started", "凭证审核已开始")
    "EvidenceCorrectionRequired" =>
      copy(locale, "Evidence needs correction", "凭证需要修正")
    "FulfillmentReady" =>
      copy(locale, "Resource fulfillment is ready", "资源交付已就绪")
    "CommercialReversalStarted" =>
      copy(locale, "Commercial reversal started", "商务撤销已开始")
    _ => code
  }
}

///|
fn notification_severity_label(
  locale : @i18n.Locale,
  severity : @notifications.NotificationSeverity,
) -> String {
  match severity {
    Information => copy(locale, "Information", "提示")
    Warning => copy(locale, "Warning", "警告")
    Critical => copy(locale, "Critical", "严重")
  }
}

///|
fn notification_lifecycle_label(
  locale : @i18n.Locale,
  lifecycle : @notifications.NotificationLifecycle,
) -> String {
  match lifecycle {
    Unread => copy(locale, "Unread", "未读")
    Read => copy(locale, "Read", "已读")
    Acknowledged => copy(locale, "Acknowledged", "已确认")
    Resolved => copy(locale, "Resolved", "已解决")
  }
}

///|
fn notification_detail(
  locale : @i18n.Locale,
  record : @notifications.NotificationRecord,
) -> String {
  let reference = match record.event.parameters.get("lease_ref") {
    Some(value) => value
    None => record.event.parameters.get("agreement_ref").unwrap_or("")
  }
  let explanation = match record.event.code {
    "LeaseRequestApproved" =>
      copy(
        locale, "An operator approved your capacity request. Provisioning starts next.",
        "运维人员已批准您的容量申请，接下来将开始配置。",
      )
    "LeaseAccessReady" =>
      copy(
        locale, "Your exclusive machine is ready. Open its access details before the credential expires.",
        "您的独占机器已就绪。请在凭据到期前查看访问详情。",
      )
    "LeaseExpiring" =>
      copy(
        locale, "Save your work and request an extension if needed. Access closes automatically at the lease boundary.",
        "请保存工作；如有需要请申请延期。访问权限将在租约边界自动关闭。",
      )
    "LeaseTerminating" =>
      copy(
        locale, "New sessions are blocked while the node is drained and sanitized.",
        "节点正在排空并清理，新的会话已被阻止。",
      )
    "LeaseCompleted" =>
      copy(
        locale, "Credentials are revoked and the node has left your tenant boundary.",
        "凭据已撤销，节点已离开您的租户边界。",
      )
    "AgreementActionRequired" =>
      copy(
        locale, "Review the agreement and complete the requested action.", "请审阅协议并完成所需操作。",
      )
    "OfflineDocumentsRequired" =>
      copy(
        locale, "Upload the executed contract, payment receipt, and invoice evidence to continue.",
        "请上传已签署合同、付款回执和发票证据以继续流程。",
      )
    _ =>
      copy(
        locale, "Open the related record for details.", "请打开相关记录查看详情。",
      )
  }
  if reference == "" {
    explanation
  } else {
    "\{explanation} · \{reference}"
  }
}

///|
fn notification_email_enabled(
  state : EnterpriseState,
  topic : @notifications.NotificationTopic,
) -> Bool {
  state.notification_preferences.any(preference => {
    preference.topic == topic && preference.channels.contains(Email)
  })
}

///|
fn notification_preference_row(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  topic : @notifications.NotificationTopic,
  english : String,
  chinese : String,
) -> @rabbita.Html {
  let enabled = notification_email_enabled(state, topic)
  @html.li(class="record-card", [
    @html.div(class="record-main", [
      @html.h3(copy(state.locale, english, chinese)),
      @html.p(
        copy(
          state.locale,
          if enabled {
            "Email delivery is on."
          } else {
            "In-app only."
          },
          if enabled {
            "电子邮件投递已开启。"
          } else {
            "仅站内通知。"
          },
        ),
      ),
    ]),
    @html.div(class="record-actions", [
      @html.button(
        type_="button",
        disabled=state.loading,
        on_click=command(emit, SetNotificationEmail(topic, !enabled)),
        copy(
          state.locale,
          if enabled {
            "Disable email"
          } else {
            "Enable email"
          },
          if enabled {
            "关闭邮件"
          } else {
            "开启邮件"
          },
        ),
      ),
    ]),
  ])
}

///|
fn notifications_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let unread = state.notifications.count_if(record => record.lifecycle == Unread)
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(copy(state.locale, "Notification inbox", "通知收件箱")),
        @html.p(
          copy(
            state.locale,
            "Durable updates for agreements, machine access, expiry, and offline reconciliation.",
            "查看协议、机器访问、到期与线下对账的持久化更新。",
          ),
        ),
      ]),
      @html.span(
        class="count-pill",
        copy(state.locale, "\{unread} unread", "\{unread} 条未读"),
      ),
    ]),
    @html.section(
      attrs=@html.Attrs::build().aria_labelledby(
        "notification-preferences-title",
      ),
      [
        @html.h2(
          id="notification-preferences-title",
          copy(state.locale, "Delivery preferences", "投递偏好"),
        ),
        @html.p(
          copy(
            state.locale,
            "In-app delivery always remains enabled. External delivery starts only when the platform adapter is configured.",
            "站内通知始终开启。仅在平台配置外部投递适配器后，外部投递才会生效。",
          ),
        ),
        @html.ul(class="record-list", [
          notification_preference_row(
            state,
            emit,
            LeaseLifecycle,
            "Machine and lease lifecycle",
            "机器与租约生命周期",
          ),
          notification_preference_row(
            state,
            emit,
            CommercialAction,
            "Contracts and commercial actions",
            "合同与商务操作",
          ),
        ]),
      ],
    ),
    if state.notifications.length() == 0 {
      @html.p(
        class="empty",
        copy(state.locale, "No notifications yet.", "暂无通知。"),
      )
    } else {
      @html.div(
        class="record-list",
        [
          for record in state.notifications => {
            @html.article(
              class=if record.lifecycle == Unread {
                "record-card notification-card is-unread"
              } else {
                "record-card notification-card"
              },
              [
                @html.div(class="record-main", [
                  @html.div(class="record-title", [
                    @html.h3(
                      notification_code_label(state.locale, record.event.code),
                    ),
                    @html.span(
                      class="state-pill",
                      notification_severity_label(
                        state.locale,
                        record.event.severity,
                      ),
                    ),
                    @html.span(
                      class="state-pill",
                      notification_lifecycle_label(
                        state.locale,
                        record.lifecycle,
                      ),
                    ),
                  ]),
                  @html.p(notification_detail(state.locale, record)),
                  @html.dl(class="record-meta", [
                    @html.div([
                      @html.dt(copy(state.locale, "Received", "接收时间")),
                      @html.dd(
                        class="mono",
                        record.event.created_unix_ms.to_string(),
                      ),
                    ]),
                    @html.div([
                      @html.dt(copy(state.locale, "Receipt", "回执")),
                      @html.dd(class="mono", record.event.source_receipt),
                    ]),
                  ]),
                ]),
                if record.lifecycle == Unread {
                  @html.div(class="record-actions", [
                    @html.button(
                      type_="button",
                      class="primary-action",
                      on_click=command(
                        emit,
                        MarkNotificationRead(
                          record.event.notification_id,
                          record.generation,
                        ),
                      ),
                      copy(state.locale, "Mark as read", "标记为已读"),
                    ),
                  ])
                } else {
                  @html.nothing
                },
              ],
            )
          }
        ],
      )
    },
  ])
}

///|
fn content(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  match state.route {
    Overview => overview_view(state, emit)
    Agreements => agreements_view(state, emit)
    LeaseRequests => lease_requests_view(state, emit)
    Notifications => notifications_view(state, emit)
    Costs => costs_view(state)
    Models => models_view(state)
    MachineAccess => {
      let machine = { ..state.machine_access, locale: state.locale }
      match emit {
        Some(send) =>
          @machine_access.interactive_view(
            machine,
            send.map(message => MachineAccess(message)),
          )
        None => @machine_access.view(machine)
      }
    }
    OfflineCommerce => {
      let commerce = { ..state.offline_commerce, locale: state.locale }
      match emit {
        Some(send) =>
          @offline_commerce.interactive_view(
            commerce,
            send.map(message => OfflineCommerce(message)),
          )
        None => @offline_commerce.view(commerce)
      }
    }
    ContractDocuments => {
      let documents = { ..state.contract_documents, locale: state.locale }
      match emit {
        Some(send) =>
          @contract_documents.interactive_view(
            documents,
            send.map(message => ContractDocuments(message)),
          )
        None => @contract_documents.view(documents)
      }
    }
  }
}

///|
fn enterprise_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let stylesheet =
    #|:root{color-scheme:dark;--bg:#071016;--panel:#0d1820;--panel2:#111f29;--line:#223743;--ink:#ecf5f2;--muted:#91a7ad;--mint:#7ee0bd;--mint2:#35bd8d;--amber:#f1c66c}*{box-sizing:border-box}html{background:var(--bg);scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at 85% -10%,rgba(53,189,141,.12),transparent 30rem),var(--bg);color:var(--ink);font:14px/1.5 Inter,"PingFang SC","Noto Sans SC",system-ui,sans-serif}.skip-link{position:fixed;left:1rem;top:-5rem;z-index:100;padding:.65rem .9rem;background:var(--mint);color:#04251a}.skip-link:focus{top:1rem}.enterprise-root{min-height:100vh;display:grid;grid-template-columns:16rem minmax(0,1fr)}.enterprise-sidebar{position:sticky;top:0;height:100vh;padding:1.25rem 1rem;border-right:1px solid var(--line);background:rgba(7,16,22,.92);display:flex;flex-direction:column}.enterprise-brand{display:flex;gap:.75rem;align-items:center;padding:.5rem;color:var(--ink);text-decoration:none}.brand-mark{width:2.2rem;height:2.2rem;border-radius:.65rem;background:var(--mint);color:#08251c;display:grid;place-items:center;font-weight:900}.enterprise-brand span:last-child{display:flex;flex-direction:column}.enterprise-brand small{color:var(--muted)}.enterprise-sidebar nav{display:grid;gap:.3rem;margin-top:2rem}.nav-item{min-height:2.75rem;padding:.65rem .8rem;border:1px solid transparent;border-radius:.55rem;background:transparent;color:var(--muted);text-align:left;font:inherit;font-weight:700;cursor:pointer}.nav-item:hover,.nav-item:focus-visible{border-color:var(--line);color:var(--ink)}.nav-item.is-active{background:rgba(126,224,189,.1);border-color:rgba(126,224,189,.25);color:var(--mint)}.nav-link{display:flex;align-items:center;text-decoration:none}.trust-note{margin-top:auto;padding:.85rem;border:1px solid var(--line);border-radius:.7rem;background:var(--panel)}.trust-note strong{font-size:.75rem}.trust-note p{margin:.35rem 0 0;color:var(--muted);font-size:.72rem}.enterprise-main{min-width:0}.enterprise-topbar{min-height:6rem;padding:1.25rem 2rem;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;gap:1rem}.eyebrow{margin:0 0 .2rem;color:var(--mint);font-size:.66rem;font-weight:850;letter-spacing:.12em}.enterprise-topbar h1{margin:0;font-size:1.65rem}.topbar-actions,.topbar-meta{display:flex;align-items:center;gap:.75rem}.topbar-meta{color:var(--muted)}.locale-control{display:flex;align-items:center;gap:.4rem}.locale-control label{color:var(--muted);font-size:.7rem}.locale-control select{min-height:44px;padding:.5rem 1.8rem .5rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#09151c;color:var(--ink);font:inherit}.status-dot{width:.5rem;height:.5rem;border-radius:50%;background:var(--mint2)}.role-pill,.count-pill,.state-pill,.entitled{padding:.28rem .5rem;border:1px solid var(--line);border-radius:999px;font-size:.67rem}.enterprise-content{max-width:90rem;margin:0 auto;padding:2rem}.page-stack{display:grid;gap:1.25rem}.welcome-panel,.workflow-panel,.request-form,.request-history,.data-table-panel{border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96));padding:1.35rem}.welcome-panel{display:flex;justify-content:space-between;gap:2rem;align-items:end}.welcome-panel h2{max-width:50rem;margin:.2rem 0 .5rem;font-size:clamp(1.6rem,3vw,2.6rem);line-height:1.1}.welcome-panel p:last-child{max-width:48rem;margin:0;color:var(--muted)}.primary-action,.primary-button{min-height:2.75rem;padding:.65rem 1rem;border:1px solid var(--mint2);border-radius:.55rem;background:var(--mint);color:#06251a;font:inherit;font-weight:850;cursor:pointer}.primary-action:disabled,.primary-button:disabled,.quiet-button:disabled{opacity:.42;cursor:not-allowed}.quiet-button{min-height:2.75rem;padding:.65rem 1rem;border:1px solid var(--line);border-radius:.55rem;background:var(--panel2);color:var(--ink);font:inherit;font-weight:700;cursor:pointer}.metric-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.8rem}.metric{min-height:8rem;padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.metric span,.metric small{display:block;color:var(--muted)}.metric strong{display:block;margin:.45rem 0;font-size:1.8rem}.workflow-panel h2,.section-heading h2,.request-form h2,.request-history h2{margin:0}.workflow-steps{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1rem;padding:0;list-style:none}.workflow-steps li{display:flex;gap:.7rem}.workflow-steps>li>span{flex:0 0 2rem;height:2rem;border:1px solid var(--line);border-radius:50%;display:grid;place-items:center;color:var(--muted);font-weight:800}.workflow-steps .is-complete>span{background:var(--mint);color:#06251a}.workflow-steps .is-current>span{border-color:var(--amber);color:var(--amber)}.workflow-steps p{margin:.25rem 0 0;color:var(--muted);font-size:.75rem}.section-heading{display:flex;justify-content:space-between;gap:1rem;align-items:center}.section-heading p{margin:.3rem 0 0;color:var(--muted)}.record-list{display:grid;gap:.75rem}.record-card{display:flex;justify-content:space-between;gap:1.5rem;padding:1.1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.record-main{min-width:0}.record-title{display:flex;align-items:center;gap:.7rem}.record-title h3{margin:0}.record-card p{color:var(--muted)}.state-pill{color:var(--amber)}.record-meta{display:flex;flex-wrap:wrap;gap:1rem;margin:0}.record-meta div{min-width:9rem}.record-meta dt{color:var(--muted);font-size:.65rem}.record-meta dd{margin:.15rem 0 0}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.record-actions{max-width:16rem;display:flex;flex-direction:column;align-items:flex-end;gap:.5rem}.record-actions small{color:var(--muted);text-align:right}.lease-layout{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(20rem,.65fr);gap:1rem}.request-form>p{color:var(--muted)}.form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.85rem;margin:1.25rem 0}.field-wide{grid-column:1/-1}.field label{display:block;margin-bottom:.35rem;font-weight:750}.field input,.field textarea{width:100%;min-height:2.8rem;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.field textarea{min-height:7rem;resize:vertical}.field small{display:block;margin-top:.3rem;color:var(--muted)}.request-boundary{margin:1rem 0;padding:.8rem;border-left:3px solid var(--mint);background:rgba(126,224,189,.06)}.request-boundary p{margin:.25rem 0 0}.request-history .record-card{display:block}.compact .record-meta{display:grid;gap:.5rem}.empty{color:var(--muted)}.data-table-panel{overflow-x:auto}table{width:100%;border-collapse:collapse}th,td{padding:.75rem;border-bottom:1px solid var(--line);text-align:left}th{color:var(--muted);font-size:.7rem}.model-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.8rem}.model-card{position:relative;padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.model-card h3{margin:.8rem 0 .2rem}.model-card p{margin:0;color:var(--muted)}.model-card dl div{display:flex;justify-content:space-between;gap:.5rem}.model-card dt{color:var(--muted)}.model-card dd{margin:0}.model-icon{width:2.5rem;height:2.5rem;border-radius:.6rem;background:rgba(126,224,189,.13);display:grid;place-items:center;color:var(--mint);font-weight:900}.entitled{position:absolute;right:1rem;top:1rem;color:var(--mint)}.notice{margin:0 2rem;padding:.75rem 1rem;border:1px solid rgba(126,224,189,.35);border-radius:.6rem;background:rgba(126,224,189,.08);color:var(--mint)}.notice.is-error,.notice.error{border-color:rgba(241,111,111,.4);background:rgba(241,111,111,.08);color:#f5a0a0}.contract-documents{display:grid;gap:1rem}.contract-documents-header{display:flex;justify-content:space-between;align-items:end;gap:2rem;padding:1.35rem;border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96))}.contract-documents-header h1{margin:.15rem 0 .45rem}.contract-documents-header p:last-child{max-width:55rem;margin:0;color:var(--muted)}.contract-workspace{border:1px solid var(--line);border-radius:.85rem;background:var(--panel);overflow:hidden}.contract-progress{display:flex;flex-wrap:wrap;gap:.75rem;padding:.85rem 1rem;border-bottom:1px solid var(--line);color:var(--muted)}.contract-progress strong{color:var(--mint);margin-right:auto}.contract-editor-layout{display:grid;grid-template-columns:minmax(15rem,.32fr) minmax(0,1fr)}.contract-form-nav{padding:.8rem;border-right:1px solid var(--line);display:grid;align-content:start;gap:.4rem}.contract-form-tab{min-height:3.2rem;padding:.6rem .75rem;border:1px solid transparent;border-radius:.5rem;background:transparent;color:var(--ink);font:inherit;text-align:left;display:flex;flex-direction:column;cursor:pointer}.contract-form-tab small{color:var(--muted)}.contract-form-tab.is-active{border-color:rgba(126,224,189,.35);background:rgba(126,224,189,.08)}.contract-form-panel{min-width:0;padding:1.25rem}.contract-form-heading{max-width:48rem}.contract-form-heading h2{margin:.15rem 0}.contract-form-heading p:last-child{color:var(--muted)}.contract-field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.9rem;margin:1.2rem 0}.contract-field label{display:flex;justify-content:space-between;gap:.5rem;margin-bottom:.35rem;font-weight:750}.contract-field label small{color:var(--muted);font-weight:500}.contract-field input,.contract-field select,.contract-field textarea{width:100%;min-height:44px;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.contract-field textarea{min-height:7rem;resize:vertical}.contract-offline-field{padding:.8rem;border:1px dashed #51636d;border-radius:.5rem;background:rgba(145,167,173,.05)}.contract-offline-field p{margin:.25rem 0 0;color:var(--muted)}.contract-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:.65rem;padding-top:1rem;border-top:1px solid var(--line)}.modal-backdrop{position:fixed;inset:0;z-index:50;padding:1rem;background:rgba(0,0,0,.7);display:grid;place-items:center}.confirmation-dialog{width:min(36rem,100%);padding:1.4rem;border:1px solid #416454;border-radius:.8rem;background:#0d1820;box-shadow:0 1.5rem 5rem rgba(0,0,0,.5)}.confirmation-dialog h2{margin-top:0}.confirmation-dialog p{color:var(--muted)}.dialog-actions{display:flex;justify-content:flex-end;gap:.6rem}.empty-state{padding:2rem;border:1px dashed var(--line);border-radius:.8rem;color:var(--muted)}html[lang^=zh] .eyebrow{letter-spacing:.04em}@media(max-width:74rem){.metric-grid,.model-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.workflow-steps{grid-template-columns:repeat(2,minmax(0,1fr))}.lease-layout{grid-template-columns:1fr}}@media(max-width:52rem){.enterprise-root{display:block}.enterprise-sidebar{position:relative;height:auto;border-right:0;border-bottom:1px solid var(--line)}.enterprise-sidebar nav{grid-template-columns:repeat(3,minmax(0,1fr));margin-top:1rem}.trust-note{margin-top:1rem}.enterprise-topbar{padding:1rem;align-items:flex-start}.topbar-actions{align-items:flex-end;flex-direction:column}.topbar-meta{display:none}.enterprise-content{padding:1rem}.welcome-panel,.record-card,.contract-documents-header{align-items:stretch;flex-direction:column}.metric-grid,.model-grid,.workflow-steps,.form-grid,.contract-field-grid{grid-template-columns:1fr}.contract-editor-layout{grid-template-columns:1fr}.contract-form-nav{border-right:0;border-bottom:1px solid var(--line)}.field-wide{grid-column:auto}.record-actions{max-width:none;align-items:stretch}.record-actions small{text-align:left}}@media(max-width:32rem){.enterprise-sidebar nav{grid-template-columns:1fr 1fr}.enterprise-topbar{flex-wrap:wrap}.enterprise-topbar h1{font-size:1.35rem}.topbar-actions,.locale-control{width:100%;align-items:stretch}.locale-control{display:grid}.locale-control select{width:100%}.dialog-actions{display:grid}.contract-actions>*{width:100%}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important;animation:none!important}}
  let success_notice = match state.success_message {
    Some(value) =>
      @html.p(
        class="notice",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        value,
      )
    None => @html.nothing
  }
  let error_notice = match state.error_message {
    Some(value) =>
      @html.p(
        class="notice is-error",
        attrs=@html.Attrs::build().role("alert"),
        value,
      )
    None => @html.nothing
  }
  @html.div(class="enterprise-root", [
    @html.style_tag(stylesheet),
    @html.a(
      class="skip-link",
      href="#enterprise-main",
      copy(state.locale, "Skip to content", "跳到内容"),
    ),
    navigation(state, emit),
    @html.div(class="enterprise-main", [
      page_header(state, emit),
      success_notice,
      error_notice,
      @html.main_(id="enterprise-main", class="enterprise-content", [
        content(state, emit),
      ]),
    ]),
  ])
}

///|
pub fn view(state : EnterpriseState) -> @rabbita.Html {
  enterprise_view(state, None)
}

///|
pub fn interactive_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage],
) -> @rabbita.Html {
  enterprise_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : EnterpriseState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
