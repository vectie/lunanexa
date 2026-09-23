///|
pub(all) struct ResourceLeaseOption {
  key : String
  label : String
  tenant_ref : String
  organization_id : String
  authority_ref : String
  lease_id : String
  expires_unix_ms : Int64
} derive(Eq)

///|
pub(all) struct ResourceReservationRequest {
  reservation_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  authority_ref : String
  lease_id : String
  node_ids : Array[String]
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  memory_mib_per_node : Int
  gpu_memory_mib_per_node : Int
  max_concurrency_per_node : Int
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct ResourceReservationRow {
  request : ResourceReservationRequest
  state : String
  generation : Int64
} derive(Eq, FromJson)

///|
pub(all) struct ResourceDeliveryRow {
  operation_id : String
  template_id : String
  template_version : String
  kind : String
  node_count : Int
  stage : String
  failure_code : String?
  cache_hit : Bool
  transferred_bytes : Int64
  expires_at_ms : Int64
} derive(Eq, FromJson)

///|
pub(all) struct ResourceDeliveryPanel {
  leases : Array[ResourceLeaseOption]
  reservations : Array[ResourceReservationRow]
  deliveries : Array[ResourceDeliveryRow]
  selected_lease : String
  selected_nodes : Array[String]
  confirmed_idle : Bool
  reservation_id : String
  loading : Bool
  reservation_starts_ms : Int64
  loaded : Bool
  error : String?
} derive(Eq)

///|
pub(all) enum ResourceDeliveryMessage {
  RefreshResources
  SelectResourceLease(String)
  ToggleResourceNode(String)
  ConfirmResourceIdle
  ReserveResources
} derive(Eq)

///|
pub fn default_resource_delivery_panel() -> ResourceDeliveryPanel {
  {
    leases: [],
    reservations: [],
    deliveries: [],
    selected_lease: "",
    selected_nodes: [],
    confirmed_idle: false,
    reservation_id: "",
    reservation_starts_ms: 0L,
    loading: false,
    loaded: false,
    error: None,
  }
}

///|
pub fn ResourceDeliveryPanel::update(
  self : ResourceDeliveryPanel,
  message : ResourceDeliveryMessage,
) -> ResourceDeliveryPanel {
  if self.loading {
    return self
  }
  match message {
    RefreshResources | ReserveResources =>
      { ..self, loading: true, error: None, }
    SelectResourceLease(value) =>
      {
        ..self,
        selected_lease: value,
        confirmed_idle: false,
        reservation_id: "",
      }
    ToggleResourceNode(value) =>
      {
        ..self,
        selected_nodes: if self.selected_nodes.contains(value) {
          self.selected_nodes.filter(node => node != value)
        } else {
          [..self.selected_nodes, value]
        },
        confirmed_idle: false,
        reservation_id: "",
      }
    ConfirmResourceIdle => { ..self, confirmed_idle: !self.confirmed_idle, }
  }
}

///|
pub fn resource_reservation_available(panel : ResourceDeliveryPanel) -> Bool {
  !panel.loading &&
  panel.confirmed_idle &&
  !panel.selected_nodes.is_empty() &&
  panel.leases.any(lease => lease.key == panel.selected_lease)
}

///|
fn resource_delivery_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let panel = state.resource_delivery
  @html.section(class="data-table-panel", [
    @html.div(class="section-heading", [
      @html.h2(
        localized(
          state.locale,
          "Exclusive resource delivery",
          "整机资源交付",
        ),
      ),
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=panel.loading,
        on_click=command(emit, ResourceDelivery(RefreshResources)),
        localized(state.locale, "Refresh", "刷新"),
      ),
    ]),
    @html.p(
      localized(
        state.locale,
        "Reserve whole nodes for an existing active workspace authorization. This does not extend the lease or start workloads.",
        "为已有有效工作区授权预留整台节点；不延长租期，也不立即启动工作负载。",
      ),
    ),
    if panel.loading {
      @html.p(
        attrs=@html.Attrs::build().role("status"),
        localized(
          state.locale,
          "Updating resources…",
          "正在更新资源…",
        ),
      )
    } else {
      @html.nothing
    },
    match panel.error {
      Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
      None => @html.nothing
    },
    if panel.loaded && panel.leases.is_empty() {
      @html.p(
        localized(
          state.locale,
          "No active Developer lease is available. Enable the intended user's bounded authorization first.",
          "暂无有效 Developer 租约。请先为目标用户开通限时权限。",
        ),
      )
    } else if panel.loaded {
      @html.div(class="form-grid", [
        @html.label(
          for_="resource-lease",
          localized(
            state.locale,
            "Authorized user and organization",
            "已授权用户与企业",
          ),
        ),
        @html.select(
          id="resource-lease",
          disabled=panel.loading,
          on_change=text_command(emit, value => {
            ResourceDelivery(SelectResourceLease(value))
          }),
          [
            @html.option(
              value="",
              selected=panel.selected_lease == "",
              localized(state.locale, "Choose authorization", "选择授权"),
            ),
            ..panel.leases.map(lease => {
              @html.option(
                value=lease.key,
                selected=lease.key == panel.selected_lease,
                "\{lease.label} · \{@contractdoc.format_unix_ms_beijing(lease.expires_unix_ms)}",
              )
            }),
          ],
        ),
        @html.div(
          class="record-actions",
          state.nodes.map(node => {
            let occupied = panel.reservations.any(row => {
              row.state != "Released" &&
              row.request.node_ids.contains(node.node_id)
            })
            let available = node.state == Active &&
              node.workloads == 0 &&
              !occupied
            @html.button(
              type_="button",
              class="quiet-button",
              disabled=panel.loading || !available,
              attrs=@html.Attrs::build().aria_pressed(
                panel.selected_nodes.contains(node.node_id).to_string(),
              ),
              on_click=command(
                emit,
                ResourceDelivery(ToggleResourceNode(node.node_id)),
              ),
              node.node_id +
              (if available {
                ""
              } else {
                localized(state.locale, " · unavailable", " · 不可预留")
              }),
            )
          }),
        ),
        @html.p(
          localized(
            state.locale,
            "GPU utilization at 0% is not proof a node is idle. Confirm that existing host-native and Kubernetes workloads have been coordinated and stopped before allocation.",
            "GPU 利用率为 0% 不代表空闲。分配前须确认宿主进程及 Kubernetes 现有任务已协调并停止。",
          ),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=panel.loading,
          attrs=@html.Attrs::build().aria_pressed(
            panel.confirmed_idle.to_string(),
          ),
          on_click=command(emit, ResourceDelivery(ConfirmResourceIdle)),
          if panel.confirmed_idle {
            localized(
              state.locale,
              "Idle-node review confirmed",
              "已确认所选节点无其他任务",
            )
          } else {
            localized(
              state.locale,
              "Confirm selected nodes have no other workloads",
              "确认所选节点无其他任务",
            )
          },
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!resource_reservation_available(panel),
          on_click=command(emit, ResourceDelivery(ReserveResources)),
          localized(
            state.locale,
            "Reserve selected nodes",
            "预留所选整机",
          ),
        ),
      ])
    } else {
      @html.nothing
    },
    @html.h3(localized(state.locale, "Reservations", "资源预留")),
    @html.ul(
      panel.reservations.map(row => {
        @html.li(
          "\{row.request.organization_id} · \{row.request.node_ids.length()} " +
          localized(state.locale, "nodes", "台") +
          " · \{row.state} · \{@contractdoc.format_unix_ms_beijing(row.request.expires_unix_ms)}",
        )
      }),
    ),
    @html.h3(localized(state.locale, "Delivery progress", "交付进度")),
    @html.ul(
      panel.deliveries.map(row => {
        @html.li([
          @html.strong(
            "\{row.template_id}@\{row.template_version} · \{row.kind}",
          ),
          @html.p(
            "\{row.stage} · \{row.node_count} " +
            localized(state.locale, "nodes", "台"),
          ),
          if row.cache_hit {
            @html.p(
              localized(
                state.locale,
                "Verified cache reused",
                "复用已验证缓存",
              ),
            )
          } else {
            @html.p("\{row.transferred_bytes / 1048576L} MiB")
          },
          match row.failure_code {
            Some(code) => @html.p(code)
            None => @html.nothing
          },
        ])
      }),
    ),
  ])
}

///|
pub extend ResourceLeaseOption with Eq::{equal, not_equal}

///|
pub extend ResourceReservationRequest with Eq::{equal, not_equal}

///|
pub extend ResourceReservationRequest with ToJson::{to_json}

///|
pub extend ResourceReservationRequest with @json.FromJson::{from_json}

///|
pub extend ResourceReservationRow with Eq::{equal, not_equal}

///|
pub extend ResourceReservationRow with @json.FromJson::{from_json}

///|
pub extend ResourceDeliveryRow with Eq::{equal, not_equal}

///|
pub extend ResourceDeliveryRow with @json.FromJson::{from_json}

///|
pub extend ResourceDeliveryPanel with Eq::{equal, not_equal}

///|
pub extend ResourceDeliveryMessage with Eq::{equal, not_equal}
