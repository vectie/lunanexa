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
  options : DeliveryOptions
  reservation_id : String
  template_choice : String
  idempotency_key : String
  loading : Bool
  loaded : Bool
  error : String?
  stop_confirmation : String?
  poll_generation : Int64
  api_access : DeliveryApiAccess?
} derive(Eq)

///|
pub(all) enum DeliveryMessage {
  Refresh
  SelectReservation(String)
  SelectTemplate(String)
  Start
  Retry(String)
  RequestStop(String)
  CancelStop
  ConfirmStop(String)
  OpenWorkspace(String)
  IssueApiAccess(String)
  DismissApiAccess
} derive(Eq)

///|
pub fn default_delivery_panel() -> DeliveryPanel {
  {
    operations: [],
    options: { reservations: [], templates: [], },
    reservation_id: "",
    template_choice: "",
    idempotency_key: "",
    loading: false,
    loaded: false,
    error: None,
    stop_confirmation: None,
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
    CancelStop => { ..self, stop_confirmation: None, }
    Refresh | Retry(_) | ConfirmStop(_) =>
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
fn delivery_kind_label(kind : String) -> String {
  match kind {
    "Workspace" => "PaaS"
    "ModelApi" => "MaaS"
    "GpuContainer" => "IaaS"
    _ => kind
  }
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
    if panel.error is Some(_) && panel.options.reservations.is_empty() {
      @html.nothing
    } else if panel.loaded && panel.options.reservations.is_empty() {
      @html.p(
        class="empty",
        copy(
          locale, "No active exclusive resource authorization. Ask your administrator to authorize resources, or complete your machine order.",
          "暂无有效的独占资源授权。请管理员授权资源，或完成机器订单。",
        ),
      )
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
  ])
}

///|
pub extend DeliveryView with Eq::{equal, not_equal}

///|
pub extend DeliveryView with @json.FromJson::{from_json}

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
