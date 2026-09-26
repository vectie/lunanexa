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
pub(all) struct UndertakingAllocationRow {
  order_id : String
  organization_id : String
  purchaser_subject_ref : String
  node_count : Int64
  expires_unix_ms : Int64?
  status : String
  node_ids : Array[String]
} derive(Eq, FromJson)

///|
pub(all) struct ResourceDeliveryPanel {
  leases : Array[ResourceLeaseOption]
  reservations : Array[ResourceReservationRow]
  deliveries : Array[ResourceDeliveryRow]
  undertaking_orders : Array[UndertakingAllocationRow]
  selected_undertaking_order : String
  selected_lease : String
  selected_nodes : Array[String]
  confirmed_idle : Bool
  reservation_id : String
  loading : Bool
  reservation_starts_ms : Int64
  loaded : Bool
  error : String?
  checked_unix_ms : Int64
} derive(Eq)

///|
pub(all) enum ResourceDeliveryMessage {
  RefreshResources
  SelectResourceLease(String)
  ToggleResourceNode(String)
  ConfirmResourceIdle
  ReserveResources
  SelectUndertakingOrder(String)
  AllocateUndertaking
} derive(Eq)

///|
pub fn default_resource_delivery_panel() -> ResourceDeliveryPanel {
  {
    leases: [],
    reservations: [],
    deliveries: [],
    undertaking_orders: [],
    selected_undertaking_order: "",
    selected_lease: "",
    selected_nodes: [],
    confirmed_idle: false,
    reservation_id: "",
    reservation_starts_ms: 0L,
    loading: false,
    loaded: false,
    error: None,
    checked_unix_ms: 0L,
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
    RefreshResources | ReserveResources | AllocateUndertaking =>
      { ..self, loading: true, error: None, }
    SelectUndertakingOrder(value) =>
      {
        ..self,
        selected_undertaking_order: value,
        selected_nodes: [],
        confirmed_idle: false,
      }
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
pub fn undertaking_allocation_available(panel : ResourceDeliveryPanel) -> Bool {
  guard panel.undertaking_orders
    .iter()
    .find_first(row => {
      row.order_id == panel.selected_undertaking_order &&
      (
        row.status == "ReadyForAllocation" ||
        row.status == "ActivatingAccess" ||
        row.status == "ReadyForNodes"
      )
    })
    is Some(order) else {
    return false
  }
  !panel.loading &&
  panel.confirmed_idle &&
  panel.selected_nodes.length().to_int64() == order.node_count
}

///|
/// A selectable node needs measured free memory, not merely an idle GPU.
/// Undertakings allocate the whole Spark and therefore use the stricter
/// whole-host threshold enforced by the controller.
fn resource_node_selectable(
  node : NodeRow,
  reservations : Array[ResourceReservationRow],
  undertaking : Bool,
) -> Bool {
  let occupied = reservations.any(row => {
    row.state != "Released" && row.request.node_ids.contains(node.node_id)
  })
  node.state == Active &&
  (!undertaking || node.usage_pool == "enterprise-dedicated") &&
  node.memory_measured &&
  node.workloads == 0 &&
  !occupied &&
  node.total_memory_mib >= 49152 &&
  node.free_memory_mib >= 36864 &&
  (
    !undertaking ||
    node.free_memory_mib.to_int64() * 4L >=
    node.total_memory_mib.to_int64() * 3L
  )
}

///|
fn undertaking_node_unavailable_reason(
  locale : @i18n.Locale,
  node : NodeRow,
) -> String {
  if node.usage_pool != "enterprise-dedicated" {
    localized(locale, "outside enterprise pool", "非企业专属池")
  } else if !node.memory_measured {
    localized(locale, "memory not measured", "内存未上报")
  } else if node.free_memory_mib.to_int64() * 4L <
    node.total_memory_mib.to_int64() * 3L {
    localized(locale, "insufficient free memory", "可用内存不足")
  } else if node.workloads > 0 {
    localized(locale, "workload running", "仍有工作负载")
  } else {
    localized(locale, "not available", "不可预留")
  }
}

///|
fn undertaking_allocation_status(
  locale : @i18n.Locale,
  status : String,
) -> String {
  match status {
    "AwaitingApprovalOrEvidence" =>
      localized(
        locale, "Awaiting signed approval or payment review", "待签署审批或到账核验",
      )
    "OrderClosed" =>
      localized(
        locale, "Order closed; create a new order", "订单已关闭，需重新下单",
      )
    "OrderExpired" =>
      localized(
        locale, "Order expired; create a new order", "订单已到期，需重新下单",
      )
    "LeaseTermUnavailable" =>
      localized(
        locale, "Lease term is not active", "租期未开始或已结束",
      )
    "ReadyForAllocation" =>
      localized(locale, "Ready to allocate", "可下发整机")
    "ActivatingAccess" =>
      localized(locale, "Activating access", "正在开通权限")
    "ReadyForNodes" =>
      localized(
        locale, "Access active; select nodes", "权限已开通，待下发整机",
      )
    "Allocated" => localized(locale, "Allocated", "已下发")
    "AuthorityEnded" =>
      localized(locale, "Authority ended", "授权已失效，等待回收")
    "Releasing" =>
      localized(locale, "Releasing resources", "正在回收资源")
    _ => localized(locale, "Order not ready", "订单尚未就绪")
  }
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
    @html.h3(
      localized(state.locale, "Undertaking allocation", "承诺函整机下发"),
    ),
    @html.p(
      localized(
        state.locale,
        "After the signed undertaking, manager approval and full offline-payment review, select exactly the quoted number of idle enterprise-pool nodes. Trial nodes remain untouched. Access activation may take time; the same action can be continued safely.",
        "承诺函签署、甲方审批及线下足额到账核验完成后，从企业专属池选择与报价台数一致的空闲节点；试用节点不参与下发。权限激活可能需要等待；可安全继续同一操作。",
      ),
    ),
    if panel.loaded && panel.undertaking_orders.is_empty() {
      @html.p(
        localized(
          state.locale,
          "No undertaking order has been submitted yet.",
          "暂无已提交的承诺函订单。",
        ),
      )
    } else if panel.loaded {
      @html.div(class="form-grid", [
        @html.label(
          for_="undertaking-allocation-order",
          localized(state.locale, "Undertaking order", "承诺函订单"),
        ),
        @html.select(
          id="undertaking-allocation-order",
          disabled=panel.loading,
          on_change=text_command(emit, value => {
            ResourceDelivery(SelectUndertakingOrder(value))
          }),
          [
            @html.option(
              value="",
              selected=panel.selected_undertaking_order == "",
              localized(state.locale, "Choose an order", "选择订单"),
            ),
            ..panel.undertaking_orders.map(row => {
              @html.option(
                value=row.order_id,
                selected=row.order_id == panel.selected_undertaking_order,
                "\{row.organization_id} · \{row.order_id} · \{row.node_count} " +
                localized(state.locale, "nodes", "台") +
                " · " +
                undertaking_allocation_status(state.locale, row.status),
              )
            }),
          ],
        ),
        match
          panel.undertaking_orders
          .iter()
          .find_first(row => row.order_id == panel.selected_undertaking_order) {
          Some(row) =>
            @html.div([
              @html.p(
                undertaking_allocation_status(state.locale, row.status) +
                " · \{row.node_count} " +
                localized(state.locale, "nodes required", "台机器"),
              ),
              @html.p(
                localized(
                  state.locale,
                  "Order authority expires: ",
                  "订单授权截止：",
                ) +
                row.expires_unix_ms.map_or("—", value => {
                  @contractdoc.format_unix_ms_beijing(value)
                }),
              ),
              if row.status == "Allocated" {
                @html.p(
                  localized(
                    state.locale,
                    "Assigned nodes: ",
                    "已下发节点：",
                  ) +
                  row.node_ids.join(", "),
                )
              } else {
                @html.nothing
              },
            ])
          None => @html.nothing
        },
        @html.div(
          class="record-actions",
          state.nodes.map(node => {
            let available = resource_node_selectable(
              node,
              panel.reservations,
              true,
            )
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
                " · " + undertaking_node_unavailable_reason(state.locale, node)
              }),
            )
          }),
        ),
        @html.p(
          localized(
            state.locale,
            "Confirm host-native and Kubernetes tasks are stopped; 0% GPU utilization alone is not proof of idleness.",
            "确认宿主机和 Kubernetes 任务均已停止；GPU 0% 利用率不代表机器空闲。",
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
              "Idle review confirmed",
              "已确认所选节点空闲",
            )
          } else {
            localized(
              state.locale,
              "Confirm selected nodes are idle",
              "确认所选节点空闲",
            )
          },
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!undertaking_allocation_available(panel),
          on_click=command(emit, ResourceDelivery(AllocateUndertaking)),
          localized(
            state.locale,
            "Allocate selected nodes",
            "下发所选整机",
          ),
        ),
      ])
    } else {
      @html.nothing
    },
    @html.h3(
      localized(state.locale, "Other resource grants", "其他资源授权"),
    ),
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
            let available = resource_node_selectable(
              node,
              panel.reservations,
              false,
            )
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
pub extend UndertakingAllocationRow with Eq::{equal, not_equal}

///|
pub extend UndertakingAllocationRow with @json.FromJson::{from_json}

///|
pub extend ResourceDeliveryPanel with Eq::{equal, not_equal}

///|
pub extend ResourceDeliveryMessage with Eq::{equal, not_equal}
