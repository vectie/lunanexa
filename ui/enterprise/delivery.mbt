///|
pub(all) struct DeliveryView {
  operation_id : String
  project_id : String
  kind : String
  template_id : String
  template_version : String
  node_count : Int
  stage : String
  generation : Int64
  cache_hit : Bool
  transferred_bytes : Int64
  total_bytes : Int64?
  failure_code : String?
  expires_at_ms : Int64
  can_manage : Bool
} derive(Eq, FromJson)

///|
pub(all) struct ExternalModelServiceView {
  model_alias : String
  state : String
  can_stop : Bool
  ready : Bool
} derive(Eq, FromJson)

///|
pub(all) struct DeliveryReservationOption {
  reservation_id : String
  label : String
  node_count : Int
  expires_at_ms : Int64
} derive(Eq, FromJson)

///|
pub(all) struct DeliveryTemplateOption {
  template_id : String
  template_version : String
  kind : String
  label : String
  model_selector : String
  client_id : String?
} derive(Eq, FromJson)

///|
pub(all) struct DeliveryOptions {
  reservations : Array[DeliveryReservationOption]
  templates : Array[DeliveryTemplateOption]
} derive(Eq, FromJson)

///|
pub(all) struct CompanyWorkspaceStatus {
  status : String
  expires_unix_ms : Int64?
} derive(Eq, FromJson)

///|
pub extend CompanyWorkspaceStatus with Eq::{equal, not_equal}

///|
pub extend CompanyWorkspaceStatus with FromJson::{from_json}

///|
/// Returned once by the delivery-bound access endpoint. Never persisted in
/// browser storage or included in progress polling responses.
pub(all) struct DeliveryApiAccess {
  delivery_id : String
  key_id : String
  api_secret : String
  model : String
  base_url : String
  expires_unix_ms : Int64
  maximum_requests : Int64
  one_time : Bool
} derive(Eq, FromJson)

///|
pub(all) struct DeliveryPanel {
  operations : Array[DeliveryView]
  external_model : ExternalModelServiceView?
  options : DeliveryOptions
  company_workspace : CompanyWorkspaceStatus?
  reservation_id : String
  template_choice : String
  idempotency_key : String
  loading : Bool
  loaded : Bool
  error : String?
  stop_confirmation : String?
  external_stop_confirmation : Bool
  external_start_confirmation : Bool
  poll_generation : Int64
  api_access : DeliveryApiAccess?
} derive(Eq)

///|
pub(all) enum DeliveryMessage {
  Refresh
  ActivateCompanyWorkspace
  SelectReservation(String)
  SelectTemplate(String)
  Start
  Retry(String)
  RequestStop(String)
  CancelStop
  ConfirmStop(String)
  RequestStopExternal
  ConfirmStopExternal
  RequestStartExternal
  ConfirmStartExternal
  OpenWorkspace(String)
  IssueApiAccess(String)
  DismissApiAccess
} derive(Eq)

///|
pub fn default_delivery_panel() -> DeliveryPanel {
  {
    operations: [],
    external_model: None,
    options: { reservations: [], templates: [], },
    company_workspace: None,
    reservation_id: "",
    template_choice: "",
    idempotency_key: "",
    loading: false,
    loaded: false,
    error: None,
    stop_confirmation: None,
    external_stop_confirmation: false,
    external_start_confirmation: false,
    poll_generation: 0L,
    api_access: None,
  }
}

///|
pub fn delivery_template_choice(option : DeliveryTemplateOption) -> String {
  "\{option.kind}:\{option.template_id}:\{option.template_version}"
}

///|
pub fn selected_delivery_template(
  panel : DeliveryPanel,
) -> DeliveryTemplateOption? {
  panel.options.templates
  .iter()
  .find_first(option => {
    delivery_template_choice(option) == panel.template_choice
  })
}

///|
pub fn delivery_start_available(panel : DeliveryPanel) -> Bool {
  !panel.loading &&
  selected_delivery_template(panel) is Some(_) &&
  panel.options.reservations.any(option => {
    option.reservation_id == panel.reservation_id
  })
}

///|
/// Resolve only a published interactive delivery, including model-free GPU
/// containers. The catalog owns the client mapping; the UI never guesses it.
pub fn delivery_launch_template(
  panel : DeliveryPanel,
  operation_id : String,
) -> DeliveryTemplateOption? {
  guard panel.operations
    .iter()
    .find_first(operation => {
      operation.operation_id == operation_id &&
      (
        operation.kind == "Workspace" ||
        operation.kind == "GpuContainer" ||
        operation.kind == "ModelApi"
      ) &&
      (operation.stage == "StartingWorkspace" || operation.stage == "Ready")
    })
    is Some(operation) else {
    return None
  }
  panel.options.templates
  .iter()
  .find_first(template => {
    template.template_id == operation.template_id &&
    template.template_version == operation.template_version &&
    template.kind == operation.kind &&
    template.client_id.map_or(false, value => value != "") &&
    (template.kind == "GpuContainer" || template.model_selector != "")
  })
}

///|
pub fn DeliveryPanel::update(
  self : DeliveryPanel,
  message : DeliveryMessage,
) -> DeliveryPanel {
  if self.loading {
    return self
  }
  match message {
    SelectReservation(value) =>
      {
        ..self,
        reservation_id: value,
        idempotency_key: "",
        error: None,
        api_access: None,
      }
    SelectTemplate(value) =>
      {
        ..self,
        template_choice: value,
        idempotency_key: "",
        error: None,
        api_access: None,
      }
    RequestStop(id) => { ..self, stop_confirmation: Some(id), }
    RequestStopExternal => { ..self, external_stop_confirmation: true, }
    RequestStartExternal => { ..self, external_start_confirmation: true, }
    CancelStop =>
      {
        ..self,
        stop_confirmation: None,
        external_stop_confirmation: false,
        external_start_confirmation: false,
      }
    Refresh
    | ActivateCompanyWorkspace
    | Retry(_)
    | ConfirmStop(_)
    | ConfirmStopExternal
    | ConfirmStartExternal =>
      {
        ..self,
        loading: true,
        error: None,
        poll_generation: self.poll_generation + 1L,
      }
    OpenWorkspace(_) => self
    IssueApiAccess(_) =>
      {
        ..self,
        loading: true,
        error: None,
        api_access: None,
        poll_generation: self.poll_generation + 1L,
      }
    DismissApiAccess => { ..self, api_access: None, }
    Start =>
      if delivery_start_available(self) {
        {
          ..self,
          loading: true,
          error: None,
          poll_generation: self.poll_generation + 1L,
        }
      } else {
        self
      }
  }
}

///|
fn delivery_stage_label(stage : String, locale : @i18n.Locale) -> String {
  match stage {
    "Reserving" => copy(locale, "Reserving resources", "资源预留中")
    "PreparingModel" => copy(locale, "Preparing model", "模型准备中")
    "LoadingModel" => copy(locale, "Loading model", "模型加载中")
    "StartingWorkspace" =>
      copy(locale, "Starting workspace", "工作区启动中")
    "Ready" => copy(locale, "Ready to use", "可使用")
    "Failed" =>
      copy(locale, "Failed — retry available", "启动失败，可重试")
    "Stopping" => copy(locale, "Stopping workloads", "工作负载停止中")
    "Stopped" => copy(locale, "Stopped", "已停止")
    "Expired" => copy(locale, "Expired", "已到期")
    "Revoked" => copy(locale, "Revoked", "已撤销")
    _ => copy(locale, "Refreshing service status", "等待服务状态更新")
  }
}

///|
fn delivery_stage_guidance(
  operation : DeliveryView,
  locale : @i18n.Locale,
) -> String {
  match operation.stage {
    "Reserving" =>
      copy(
        locale, "Checking your authorized whole-node allocation. No service is ready yet.",
        "正在检查已授权的整机资源；服务尚未就绪。",
      )
    "PreparingModel" =>
      if operation.cache_hit {
        copy(
          locale, "Verified local model cache is being reused.", "正在复用已验证的本地模型缓存。",
        )
      } else {
        copy(
          locale, "Model files are being prepared. Transfer progress appears below when measured.",
          "正在准备模型文件；有实测数据时将在下方显示传输进度。",
        )
      }
    "LoadingModel" =>
      copy(
        locale, "The model is loading; readiness still needs a runtime check.", "模型正在加载；仍需通过运行时就绪检查。",
      )
    "StartingWorkspace" =>
      copy(
        locale, "The application is starting; wait for a usable workspace or API response.",
        "应用正在启动；请等待工作区或 API 真正可用。",
      )
    "Ready" =>
      copy(
        locale, "The required service checks passed. Use a permitted client entry point when available.",
        "所需服务检查已通过。可通过已授权的客户端入口使用服务。",
      )
    "Failed" =>
      if operation.can_manage {
        copy(
          locale, "Review the failure code below, then retry this same operation.",
          "查看下方失败代码后，可重试同一次交付操作。",
        )
      } else {
        copy(
          locale, "Review the failure code below and contact your administrator.",
          "查看下方失败代码，并联系管理员。",
        )
      }
    "Stopping" =>
      copy(
        locale, "Access is closing while workloads stop. Saved files follow the published retention policy.",
        "访问正在关闭，工作负载正在停止；已保存文件按公布的保留策略处理。",
      )
    _ => ""
  }
}

///|
fn delivery_kind_label(kind : String) -> String {
  match kind {
    "Workspace" => "PaaS"
    "ModelApi" => "MaaS"
    "GpuContainer" => "IaaS"
    _ => kind
  }
}

///|
fn delivery_overview_destination(kind : String) -> EnterpriseRoute {
  match kind {
    "GpuContainer" => MachineAccess
    "Workspace" => DesktopIde
    _ => Models
  }
}

///|
/// The overview intentionally projects only organization-scoped operation
/// evidence. Node identities and operator-only capacity are not exposed here.
fn delivery_overview(
  panel : DeliveryPanel,
  locale : @i18n.Locale,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let ready = panel.operations.count_if(operation => operation.stage == "Ready")
  let preparing = panel.operations.count_if(operation => {
    operation.stage == "Reserving" ||
    operation.stage == "PreparingModel" ||
    operation.stage == "LoadingModel" ||
    operation.stage == "StartingWorkspace" ||
    operation.stage == "Stopping"
  })
  let failed = panel.operations.count_if(operation => {
    operation.stage == "Failed"
  })
  let priority = panel.operations
    .iter()
    .find_first(operation => operation.stage == "Failed")
  let current = match priority {
    Some(value) => Some(value)
    None =>
      match
        panel.operations
        .iter()
        .find_first(operation => {
          operation.stage == "Reserving" ||
          operation.stage == "PreparingModel" ||
          operation.stage == "LoadingModel" ||
          operation.stage == "StartingWorkspace" ||
          operation.stage == "Stopping"
        }) {
        Some(value) => Some(value)
        None =>
          panel.operations
          .iter()
          .find_first(operation => operation.stage == "Ready")
      }
  }
  @html.section(
    class="service-status-overview",
    attrs=@html.Attrs::build().aria_labelledby("service-status-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            copy(locale, "Your services", "您的服务"),
          ),
          @html.h2(
            id="service-status-title",
            copy(locale, "Service status", "服务状态"),
          ),
          @html.p(
            copy(
              locale, "Status for your selected organization. Open a service for progress and next steps.",
              "显示当前所选组织的服务状态；打开服务可查看进度和下一步。",
            ),
          ),
        ]),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=command(emit, Navigate(Models)),
          copy(locale, "View services", "查看服务"),
        ),
      ]),
      if !panel.loaded && panel.error is Some(_) {
        @html.p(
          attrs=@html.Attrs::build().role("alert"),
          copy(
            locale, "Service status is unavailable. Open Services to retry.", "服务状态暂不可用。打开服务页面可重试。",
          ),
        )
      } else if !panel.loaded {
        @html.p(
          attrs=@html.Attrs::build().role("status"),
          copy(
            locale, "Checking service status…", "正在查询服务状态…",
          ),
        )
      } else if panel.operations.is_empty() {
        @html.p(
          copy(
            locale, "No dedicated service has been started for this organization.",
            "此组织尚未启动专属服务。",
          ),
        )
      } else {
        @html.div(class="service-status-content", [
          @html.dl(class="service-status-counts", [
            @html.div([
              @html.dt(copy(locale, "Ready", "可使用")),
              @html.dd(ready.to_string()),
            ]),
            @html.div([
              @html.dt(copy(locale, "In progress", "进行中")),
              @html.dd(preparing.to_string()),
            ]),
            @html.div([
              @html.dt(copy(locale, "Needs action", "需要处理")),
              @html.dd(failed.to_string()),
            ]),
          ]),
          match current {
            Some(operation) =>
              @html.div(class="service-status-current", [
                @html.strong(
                  "\{delivery_kind_label(operation.kind)} · \{operation.template_id}",
                ),
                @html.span(
                  attrs=@html.Attrs::build().role("status").aria_live("polite"),
                  delivery_stage_label(operation.stage, locale),
                ),
                @html.p(
                  if operation.stage == "Failed" {
                    copy(
                      locale, "The service did not become ready. Open its details for the failure code and retry action.",
                      "服务尚未就绪。打开详情可查看失败原因代码和重试操作。",
                    )
                  } else if operation.stage == "Ready" {
                    copy(
                      locale, "This service is ready for the permitted client action.",
                      "此服务已就绪，可执行获授权的客户端操作。",
                    )
                  } else {
                    copy(
                      locale, "The controller is still reconciling this service. You can leave this page and return later.",
                      "控制器仍在协调此服务；您可以离开页面，稍后返回。",
                    )
                  },
                ),
                @html.button(
                  type_="button",
                  class="quiet-button",
                  on_click=command(
                    emit,
                    Navigate(delivery_overview_destination(operation.kind)),
                  ),
                  copy(locale, "Open service details", "打开服务详情"),
                ),
              ])
            None =>
              @html.p(
                copy(
                  locale, "No active service requires attention.", "当前没有需要处理的活动服务。",
                ),
              )
          },
        ])
      },
      if panel.loaded && panel.error is Some(_) {
        @html.p(
          attrs=@html.Attrs::build().role("alert"),
          copy(
            locale, "The last refresh failed; shown status may be out of date.",
            "最近一次刷新失败，显示的状态可能已过期。",
          ),
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn delivery_panel_view(
  panel : DeliveryPanel,
  locale : @i18n.Locale,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  kind : String,
) -> @rabbita.Html {
  let templates = panel.options.templates.filter(option => option.kind == kind)
  let operations = panel.operations.filter(operation => operation.kind == kind)
  let selected_kind = selected_delivery_template(panel).map_or(false, option => {
    option.kind == kind
  })
  @html.section(class="workflow-panel", [
    @html.div(class="section-heading", [
      @html.h2(
        match kind {
          "GpuContainer" =>
            copy(locale, "GPU container deliveries", "IaaS · GPU 容器交付")
          "Workspace" =>
            copy(
              locale, "Dedicated application workspaces", "PaaS · 专属应用工作区",
            )
          _ => copy(locale, "Dedicated model APIs", "MaaS · 专属模型 API")
        },
      ),
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=panel.loading,
        on_click=command(emit, Delivery(Refresh)),
        copy(locale, "Refresh status", "刷新状态"),
      ),
    ]),
    @html.p(
      copy(
        locale, "Choose an authorized resource allocation and a published template. Your files are retained when a service stops.",
        "选择已授权资源和已发布模板。停止服务不会删除您的工作文件。",
      ),
    ),
    match panel.company_workspace {
      Some(workspace) if workspace.status == "NeedsActivation" =>
        @html.section(class="record-card", [
          @html.h3(
            copy(locale, "Activate my workspace", "开通我的个人工作区"),
          ),
          @html.p(
            copy(
              locale, "Your company already has approved machines. Activate your own bounded workspace before starting an application or model API; colleagues' files remain separate.",
              "企业机器已下发。先开通您自己的限期工作区，再启动应用或模型 API；同事的文件和聊天不会共用。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=panel.loading,
            on_click=command(emit, Delivery(ActivateCompanyWorkspace)),
            copy(locale, "Activate my access", "开通我的权限"),
          ),
        ])
      Some(workspace) if workspace.status == "Ready" =>
        @html.p(
          attrs=@html.Attrs::build().role("status"),
          copy(
            locale, "My workspace is active until ", "我的工作区权限有效至 ",
          ) +
          workspace.expires_unix_ms.map_or("—", value => {
            @contractdoc.format_unix_ms_beijing(value)
          }),
        )
      Some(workspace) if workspace.status == "NoCompanyMachines" =>
        @html.p(
          copy(
            locale, "No approved undertaking machines have been assigned to this organization yet.",
            "此企业尚无已审核并下发的承诺函机器。",
          ),
        )
      _ => @html.nothing
    },
    if panel.loading {
      @html.p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        copy(locale, "Updating…", "正在更新…"),
      )
    } else {
      @html.nothing
    },
    match panel.error {
      Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
      None => @html.nothing
    },
    match panel.api_access {
      Some(access) =>
        @html.section(class="api-key-panel", [
          @html.h3(
            copy(
              locale, "Delivery API access — shown once", "交付 API 凭据 · 仅显示一次",
            ),
          ),
          @html.p(
            copy(
              locale, "This key is bound to this exclusive model delivery. Save it now; closing this panel clears the displayed secret.",
              "此密钥仅绑定本次独占模型交付。请立即保存；关闭后将清除页面中的密钥。",
            ),
          ),
          @html.p(
            copy(locale, "API base URL: ", "API 地址：") + access.base_url,
          ),
          @html.p(copy(locale, "Model: ", "模型：") + access.model),
          @html.p(
            copy(locale, "Expires: ", "到期时间：") +
            @contractdoc.format_unix_ms_beijing(access.expires_unix_ms),
          ),
          @html.p(
            "\{access.maximum_requests} " +
            copy(locale, "maximum requests", "次请求上限"),
          ),
          @html.pre(class="one-time-secret", access.api_secret),
          @html.div(class="api-key-actions", [
            @html.button(
              type_="button",
              class="quiet-button",
              on_click=command(emit, CopyDetail(access.api_secret)),
              copy(locale, "Copy API key", "复制 API 密钥"),
            ),
            @html.button(
              type_="button",
              class="quiet-button",
              on_click=command(emit, CopyDetail(access.base_url)),
              copy(locale, "Copy API address", "复制 API 地址"),
            ),
            @html.button(
              type_="button",
              class="primary-button",
              on_click=command(emit, Delivery(DismissApiAccess)),
              copy(locale, "Saved — close", "已保存，关闭"),
            ),
          ]),
        ])
      None => @html.nothing
    },
    if kind == "ModelApi" {
      match panel.external_model {
        Some(service) =>
          @html.article(class="record-card", [
            @html.div(class="record-main", [
              @html.h3("企业共享模型 · " + service.model_alias),
              @html.p(
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                match service.state {
                  "Running" =>
                    if service.ready {
                      copy(
                        locale, "Running on the Spark pair", "运行中 · 占用两台 Spark",
                      )
                    } else {
                      copy(
                        locale, "Starting on the Spark pair; inference is not ready yet",
                        "两台 Spark 启动中 · 推理尚未就绪",
                      )
                    }
                  "Stopped" =>
                    copy(
                      locale, "Stopped; model files retained", "已停止 · 模型文件保留",
                    )
                  "Partial" =>
                    copy(
                      locale, "Partially stopped; operator attention required", "部分停止 · 需管理员处理",
                    )
                  "Unavailable" =>
                    copy(
                      locale, "Control status unavailable; no stop is confirmed",
                      "控制状态暂不可用 · 尚未确认停止",
                    )
                  _ =>
                    copy(
                      locale, "Externally operated; stop is not yet available", "站外运行 · 暂不可在此停止",
                    )
                },
              ),
              @html.p(
                copy(
                  locale, "Company-shared model. Stopping it disconnects every member; personal WebIDE files are unaffected.",
                  "企业共享模型。停止后所有成员将无法调用；个人 WebIDE 工作文件不受影响。",
                ),
              ),
            ]),
            @html.div(class="record-actions", [
              if service.can_stop &&
                (service.state == "Running" || service.state == "Partial") {
                @html.button(
                  type_="button",
                  class="quiet-button",
                  disabled=panel.loading,
                  on_click=command(emit, Delivery(RequestStopExternal)),
                  copy(locale, "Stop GLM service", "停止 GLM 服务"),
                )
              } else {
                @html.nothing
              },
              if service.can_stop && service.state == "Stopped" {
                @html.button(
                  type_="button",
                  class="primary-button",
                  disabled=panel.loading,
                  on_click=command(emit, Delivery(RequestStartExternal)),
                  copy(locale, "Start GLM service", "启动 GLM 服务"),
                )
              } else {
                @html.nothing
              },
            ]),
          ])
        None => @html.nothing
      }
    } else {
      @html.nothing
    },
    if panel.error is Some(_) && panel.options.reservations.is_empty() {
      @html.nothing
    } else if panel.loaded && panel.options.reservations.is_empty() {
      @html.div(class="empty", [
        @html.p(
          copy(
            locale, "No active exclusive resource authorization. Ask your administrator to authorize resources, or complete your machine order.",
            "暂无有效的独占资源授权。请管理员授权资源，或完成机器订单。",
          ),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=command(emit, Navigate(LeaseRequests)),
          copy(locale, "Request resources", "申请资源"),
        ),
      ])
    } else if panel.loaded && templates.is_empty() {
      @html.p(
        class="empty",
        copy(
          locale, "No published delivery template is available yet.", "尚无已发布的交付模板。",
        ),
      )
    } else if panel.loaded {
      @html.div(class="account-form", [
        @html.div(class="field", [
          @html.label(
            for_="delivery-reservation",
            copy(locale, "Authorized resources", "已授权资源"),
          ),
          @html.select(
            id="delivery-reservation",
            disabled=panel.loading,
            on_change=text_command(emit, value => {
              Delivery(SelectReservation(value))
            }),
            [
              @html.option(
                value="",
                selected=panel.reservation_id == "",
                copy(locale, "Choose resources", "选择资源"),
              ),
              ..panel.options.reservations.map(option => {
                @html.option(
                  value=option.reservation_id,
                  selected=panel.reservation_id == option.reservation_id,
                  "\{option.label} · \{option.node_count} " +
                  copy(locale, "nodes", "台") +
                  " · " +
                  @contractdoc.format_unix_ms_beijing(option.expires_at_ms),
                )
              }),
            ],
          ),
        ]),
        @html.div(class="field", [
          @html.label(
            for_="delivery-template",
            copy(locale, "Service template", "服务模板"),
          ),
          @html.select(
            id="delivery-template",
            disabled=panel.loading,
            on_change=text_command(emit, value => {
              Delivery(SelectTemplate(value))
            }),
            [
              @html.option(
                value="",
                selected=panel.template_choice == "",
                copy(locale, "Choose a template", "选择模板"),
              ),
              ..templates.map(option => {
                @html.option(
                  value=delivery_template_choice(option),
                  selected=panel.template_choice ==
                    delivery_template_choice(option),
                  "\{delivery_kind_label(option.kind)} · \{option.label} · \{option.template_version}",
                )
              }),
            ],
          ),
        ]),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!selected_kind || !delivery_start_available(panel),
          on_click=command(emit, Delivery(Start)),
          copy(locale, "Start service", "启动服务"),
        ),
      ])
    } else {
      @html.p(
        class="empty",
        copy(
          locale, "Refresh to load your authorized services.", "刷新以加载已授权服务。",
        ),
      )
    },
    @html.div(
      class="record-list",
      operations.map(operation => {
        @html.article(class="record-card", [
          @html.div(class="record-main", [
            @html.h3(
              "\{delivery_kind_label(operation.kind)} · \{operation.template_id} · \{operation.template_version}",
            ),
            @html.p(
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              if operation.kind == "GpuContainer" &&
                operation.stage == "StartingWorkspace" {
                copy(locale, "Starting GPU container", "GPU 容器启动中")
              } else {
                delivery_stage_label(operation.stage, locale)
              },
            ),
            if delivery_stage_guidance(operation, locale) != "" {
              @html.p(
                class="delivery-next-step",
                delivery_stage_guidance(operation, locale),
              )
            } else {
              @html.nothing
            },
            @html.p(
              if operation.kind == "ModelApi" {
                copy(
                  locale,
                  "Shared model service · \{operation.node_count} reserved nodes",
                  "企业共享模型服务 · 占用 \{operation.node_count} 台预留节点",
                )
              } else {
                "\{operation.node_count} " +
                copy(locale, "exclusive nodes", "台独占节点")
              },
            ),
            @html.p(
              copy(locale, "Project: ", "项目：") + operation.project_id,
            ),
            @html.p(
              copy(locale, "Expires: ", "到期时间：") +
              @contractdoc.format_unix_ms_beijing(operation.expires_at_ms),
            ),
            if operation.cache_hit {
              @html.p(
                copy(
                  locale, "Using verified local model cache", "复用已验证本地模型缓存",
                ),
              )
            } else if operation.total_bytes is Some(total) && total > 0L {
              let percent = (operation.transferred_bytes * 100L / total)
                .clamp(min=0L, max=100L)
                .to_int()
              @html.div(class="delivery-transfer-progress", [
                @html.progress(value=percent, max=100, "\{percent}%"),
                @html.p(
                  "\{percent}% · \{operation.transferred_bytes / 1048576L} / \{total / 1048576L} MiB",
                ),
              ])
            } else if operation.transferred_bytes > 0L {
              @html.p(
                "\{operation.transferred_bytes / 1048576L} MiB " +
                copy(locale, "transferred", "已传输"),
              )
            } else {
              @html.nothing
            },
            match operation.failure_code {
              Some(code) =>
                @html.p(
                  copy(locale, "Failure code: ", "失败原因代码：") + code,
                )
              None => @html.nothing
            },
          ]),
          @html.div(class="record-actions", [
            if operation.kind == "ModelApi" && operation.stage == "Ready" {
              @html.button(
                type_="button",
                class="primary-button",
                disabled=panel.loading || panel.api_access is Some(_),
                on_click=command(
                  emit,
                  Delivery(IssueApiAccess(operation.operation_id)),
                ),
                copy(
                  locale, "Create delivery API key", "创建交付 API 密钥",
                ),
              )
            } else {
              @html.nothing
            },
            if delivery_launch_template(panel, operation.operation_id)
              is Some(_) {
              @html.button(
                type_="button",
                class="primary-button",
                disabled=panel.loading,
                on_click=command(
                  emit,
                  Delivery(OpenWorkspace(operation.operation_id)),
                ),
                if operation.kind == "ModelApi" {
                  copy(locale, "Connect my WebIDE", "连接到我的 WebIDE")
                } else if operation.kind == "GpuContainer" {
                  if operation.stage == "StartingWorkspace" {
                    copy(
                      locale, "Open and start terminal", "打开并启动终端",
                    )
                  } else {
                    copy(locale, "Open terminal", "打开终端")
                  }
                } else if operation.stage == "StartingWorkspace" {
                  copy(
                    locale, "Open and start workspace", "打开并启动工作区",
                  )
                } else {
                  copy(locale, "Open workspace", "打开工作区")
                },
              )
            } else {
              @html.nothing
            },
            if operation.can_manage && operation.stage == "Failed" {
              @html.button(
                type_="button",
                class="primary-button",
                disabled=panel.loading,
                on_click=command(emit, Delivery(Retry(operation.operation_id))),
                copy(locale, "Retry", "重试"),
              )
            } else {
              @html.nothing
            },
            if operation.can_manage &&
              operation.stage != "Stopped" &&
              operation.stage != "Stopping" &&
              operation.stage != "Expired" &&
              operation.stage != "Revoked" {
              @html.button(
                type_="button",
                class="quiet-button",
                disabled=panel.loading,
                on_click=command(
                  emit,
                  Delivery(RequestStop(operation.operation_id)),
                ),
                copy(locale, "Stop service", "停止服务"),
              )
            } else {
              @html.nothing
            },
          ]),
        ])
      }),
    ),
    match panel.stop_confirmation {
      Some(id) =>
        @html.div(class="request-boundary", [
          @html.p(
            copy(
              locale, "Stop this service? Running work will end; saved workspace files remain.",
              "停止此服务？运行中的任务将结束，已保存的工作区文件保留。",
            ),
          ),
          @html.button(
            type_="button",
            class="danger-button",
            disabled=panel.loading,
            on_click=command(emit, Delivery(ConfirmStop(id))),
            copy(locale, "Confirm stop", "确认停止"),
          ),
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=panel.loading,
            on_click=command(emit, Delivery(CancelStop)),
            copy(locale, "Cancel", "取消"),
          ),
        ])
      None => @html.nothing
    },
    if panel.external_stop_confirmation {
      @html.div(class="request-boundary", [
        @html.p(
          copy(
            locale, "Stop the company-shared GLM for all members? This releases its two GPU runtimes but keeps model files and personal WebIDE data.",
            "确认停止企业共享 GLM？所有成员的推理会中断；两台 GPU 运行实例将关闭，模型文件和个人 WebIDE 数据保留。",
          ),
        ),
        @html.button(
          type_="button",
          class="danger-button",
          disabled=panel.loading,
          on_click=command(emit, Delivery(ConfirmStopExternal)),
          copy(locale, "Confirm stop GLM", "确认停止 GLM"),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=panel.loading,
          on_click=command(emit, Delivery(CancelStop)),
          copy(locale, "Cancel", "取消"),
        ),
      ])
    } else {
      @html.nothing
    },
    if panel.external_start_confirmation {
      @html.div(class="request-boundary", [
        @html.p(
          copy(
            locale, "Start the company-shared GLM on the two Spark nodes? Confirm that other workloads have been coordinated first. Inference becomes available after the model passes its health check.",
            "确认在两台 Spark 上启动企业共享 GLM？请先协调其他运行任务；模型健康检查通过后，企业成员才能调用推理。",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=panel.loading,
          on_click=command(emit, Delivery(ConfirmStartExternal)),
          copy(locale, "Confirm start GLM", "确认启动 GLM"),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=panel.loading,
          on_click=command(emit, Delivery(CancelStop)),
          copy(locale, "Cancel", "取消"),
        ),
      ])
    } else {
      @html.nothing
    },
  ])
}

///|
pub extend DeliveryView with Eq::{equal, not_equal}

///|
pub extend DeliveryView with @json.FromJson::{from_json}

///|
pub extend ExternalModelServiceView with Eq::{equal, not_equal}

///|
pub extend ExternalModelServiceView with @json.FromJson::{from_json}

///|
pub extend DeliveryReservationOption with Eq::{equal, not_equal}

///|
pub extend DeliveryReservationOption with @json.FromJson::{from_json}

///|
pub extend DeliveryTemplateOption with Eq::{equal, not_equal}

///|
pub extend DeliveryTemplateOption with @json.FromJson::{from_json}

///|
pub extend DeliveryOptions with Eq::{equal, not_equal}

///|
pub extend DeliveryOptions with @json.FromJson::{from_json}

///|
pub extend DeliveryPanel with Eq::{equal, not_equal}

///|
pub extend DeliveryMessage with Eq::{equal, not_equal}

///|
pub extend DeliveryApiAccess with Eq::{equal, not_equal}

///|
pub extend DeliveryApiAccess with @json.FromJson::{from_json}
