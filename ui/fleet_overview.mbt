///|
/// This is an operator projection of observed state. A quiet node is only a
/// candidate for the controller's placement preflight, never an allocation.
fn fleet_node_posture(
  state : ConsoleState,
  node : NodeRow,
  now_unix_ms : Int64,
) -> (String, String, String) {
  let locale = state.locale
  if node.state == Unreachable {
    return (
      "unknown",
      localized(locale, "Unreachable", "不可达"),
      localized(
        locale, "Heartbeat expired; capacity is unknown.", "心跳已过期，容量状态未知。",
      ),
    )
  }
  if node.state == Retired {
    return (
      "blocked",
      localized(locale, "Retired", "已退役"),
      localized(locale, "Removed from placement.", "已退出资源放置。"),
    )
  }
  let lease = state.exclusive_node_leases
    .iter()
    .find_first(lease => {
      lease.node_id == node.node_id &&
      lease.state != "Requested" &&
      lease.state != "Completed" &&
      lease.state != "Cancelled"
    })
  match lease {
    Some(value) =>
      return (
        "reserved",
        localized(locale, "Exclusive lease", "独占租约"),
        localized(
          locale,
          "Lease state: \{value.state}. Node is unavailable to shared placement.",
          "租约状态：\{value.state}。节点不能用于共享放置。",
        ),
      )
    None => ()
  }
  if state.resource_delivery.loaded {
    let reservation = state.resource_delivery.reservations
      .iter()
      .find_first(reservation => {
        reservation.state != "Released" &&
        reservation.request.node_ids.contains(node.node_id)
      })
    match reservation {
      Some(value) =>
        return (
          "reserved",
          localized(locale, "Reserved allocation", "资源已预留"),
          localized(
            locale,
            "Reservation state: \{value.state}.",
            "预留状态：\{value.state}。",
          ),
        )
      None => ()
    }
  }
  if node.state != Active {
    return (
      "blocked",
      localized(locale, "Maintenance", "维护中"),
      localized(
        locale, "Node is not accepting new placement.", "节点当前不接受新放置。",
      ),
    )
  }
  if node.workloads > 0 {
    return (
      "running",
      localized(locale, "Managed workload", "托管工作负载"),
      localized(
        locale,
        "\{node.workloads} controller-reported workload(s) on this node.",
        "此节点有 \{node.workloads} 个控制器上报的工作负载。",
      ),
    )
  }
  if node.accelerators.is_empty() {
    return (
      "unknown",
      localized(locale, "Inventory unknown", "设备清单未知"),
      localized(
        locale, "No accelerator inventory was reported; capacity cannot be assessed.",
        "未上报加速设备清单，无法判断容量。",
      ),
    )
  }
  if node.accelerators.any(device => !device.healthy) {
    return (
      "blocked",
      localized(locale, "Device attention", "设备需检查"),
      localized(
        locale, "An accelerator reported unhealthy; inspect node evidence before placement.",
        "有加速设备上报异常；放置前请检查节点证据。",
      ),
    )
  }
  if !node.memory_measured {
    return (
      "unknown",
      localized(locale, "Memory not measured", "内存未实测"),
      localized(
        locale, "Host free memory is not measured; placement cannot be inferred from GPU utilization.",
        "未取得宿主机可用内存实测值；不能凭 GPU 利用率判断可放置容量。",
      ),
    )
  }
  if node.total_memory_mib >= 49152 && node.free_memory_mib < 32768 {
    return (
      "blocked",
      localized(locale, "Host memory pressured", "宿主内存紧张"),
      localized(
        locale, "Less than 32 GiB is currently available; inspect running host and container tasks before allocating.",
        "当前可用内存不足 32 GiB；分配前请检查宿主机及容器中的运行任务。",
      ),
    )
  }
  if !state.resource_delivery.loaded ||
    state.resource_delivery.error is Some(_) ||
    (
      now_unix_ms > 0L &&
      (
        state.resource_delivery.checked_unix_ms <= 0L ||
        now_unix_ms - state.resource_delivery.checked_unix_ms >= 60000L
      )
    ) {
    return (
      "unknown",
      localized(locale, "Allocation unknown", "分配状态未知"),
      localized(
        locale, "Reservation records are unavailable; refresh before planning placement.",
        "预留记录不可用；规划放置前请刷新。",
      ),
    )
  }
  (
    "candidate",
    localized(locale, "Candidate for preflight", "可进入预检"),
    localized(
      locale, "No reported workload; reservation, policy and readiness still require controller preflight.",
      "未上报工作负载；预留、策略和就绪状态仍需由控制器预检。",
    ),
  )
}

///|
fn fleet_node_card(
  state : ConsoleState,
  node : NodeRow,
  now_unix_ms : Int64,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let (tone, posture, explanation) = fleet_node_posture(
    state, node, now_unix_ms,
  )
  let memory = if node.memory_measured {
    localized(
      state.locale,
      "\{memory_gib(node.free_memory_mib)} free / \{memory_gib(node.total_memory_mib)}",
      "可用 \{memory_gib(node.free_memory_mib)} / \{memory_gib(node.total_memory_mib)}",
    )
  } else {
    localized(state.locale, "Not measured", "未实测")
  }
  let utilization = if node.utilization_per_mille >= 0 {
    "\{node.utilization_per_mille / 10}.\{node.utilization_per_mille % 10}%"
  } else {
    localized(state.locale, "No fresh sample", "无新近采样")
  }
  let open_alerts = state.notifications.count_if(alert => {
    alert.node_ref == node.node_id && alert.lifecycle != Resolved
  })
  @html.article(class="fleet-node fleet-node-\{tone}", [
    @html.div(class="fleet-node-heading", [
      @html.div([
        @html.h3(node.node_id),
        @html.p(
          class="secondary",
          architecture_label(state.locale, node.architecture) +
          " · " +
          (match node.usage_pool {
            "trial" => localized(state.locale, "Trial pool", "试用池")
            "enterprise-dedicated" =>
              localized(state.locale, "Enterprise pool", "企业专属池")
            _ =>
              localized(state.locale, "Pool unclassified", "资源池未分类")
          }),
        ),
      ]),
      @html.span(class="fleet-posture fleet-posture-\{tone}", posture),
    ]),
    @html.p(class="fleet-node-explanation", explanation),
    @html.dl(class="fleet-node-facts", [
      @html.div([
        @html.dt(localized(state.locale, "Measured memory", "实测内存")),
        @html.dd(memory),
      ]),
      @html.div([
        @html.dt(localized(state.locale, "GPU load", "GPU 负载")),
        @html.dd(utilization),
      ]),
      @html.div([
        @html.dt(localized(state.locale, "Last heartbeat", "最近心跳")),
        @html.dd(node.last_seen),
      ]),
      @html.div([
        @html.dt(localized(state.locale, "Open alerts", "未解决告警")),
        @html.dd(open_alerts.to_string()),
      ]),
    ]),
    if node.accelerators.is_empty() {
      @html.p(
        class="fleet-device-note",
        localized(
          state.locale,
          "No device inventory reported.",
          "未上报设备清单。",
        ),
      )
    } else {
      @html.div(
        class="fleet-devices",
        [
          for device in node.accelerators => {
            @html.div(class="fleet-device", [
              @html.strong(device.device_id),
              @html.span(
                if device.healthy {
                  localized(state.locale, "Healthy", "健康")
                } else {
                  localized(state.locale, "Unhealthy", "异常")
                },
              ),
              @html.span(
                if node.architecture.contains("gb10") ||
                  node.architecture.contains("sm121") {
                  localized(
                    state.locale,
                    "Unified memory device · see measured node pool above",
                    "统一内存设备 · 以上方实测节点内存为准",
                  )
                } else {
                  localized(
                    state.locale,
                    "\{memory_gib(device.memory_free_mib)} / \{memory_gib(device.memory_total_mib)} free (last inventory)",
                    "最近清单可用 \{memory_gib(device.memory_free_mib)} / \{memory_gib(device.memory_total_mib)}",
                  )
                },
              ),
            ])
          }
        ],
      )
    },
    @html.div(class="fleet-node-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, Navigate(Nodes)),
        localized(state.locale, "Inspect node evidence", "查看节点证据"),
      ),
      if open_alerts > 0 {
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=command(emit, Navigate(Alerts)),
          localized(state.locale, "Review alerts", "查看告警"),
        )
      } else {
        @html.nothing
      },
    ]),
  ])
}

///|
fn fleet_overview(
  state : ConsoleState,
  now_unix_ms : Int64,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(
    class="fleet-overview",
    attrs=@html.Attrs::build().aria_labelledby("fleet-overview-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(class="eyebrow", localized(state.locale, "Fleet", "集群")),
          @html.h2(
            id="fleet-overview-title",
            localized(state.locale, "Node status wall", "节点状态总览"),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Observed resource evidence and allocation authority. Placement requires a controller preflight.",
              "查看资源观测与分配授权；实际放置仍需控制器预检。",
            ),
          ),
        ]),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=command(emit, Navigate(Nodes)),
          localized(state.locale, "All node details", "全部节点详情"),
        ),
      ]),
      if state.nodes.is_empty() {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No nodes enrolled yet.",
            "尚无已注册节点。",
          ),
        )
      } else {
        @html.div(
          class="fleet-node-grid",
          [
            for node in state.nodes => {
              fleet_node_card(state, node, now_unix_ms, emit)
            }
          ],
        )
      },
      if state.resource_delivery.error is Some(_) {
        @html.p(
          class="fleet-device-note",
          attrs=@html.Attrs::build().role("alert"),
          localized(
            state.locale,
            "Reservation read failed. Candidate status is withheld until the records can be refreshed.",
            "读取预留记录失败；刷新成功前不会显示预检候选状态。",
          ),
        )
      } else if !state.resource_delivery.loaded {
        @html.p(
          class="fleet-device-note",
          localized(
            state.locale,
            "Reservation records are still loading; candidate labels do not confirm availability.",
            "预留记录尚未加载；预检候选状态不代表资源可用。",
          ),
        )
      } else if now_unix_ms > 0L &&
        now_unix_ms - state.resource_delivery.checked_unix_ms >= 60000L {
        @html.p(
          class="fleet-device-note",
          attrs=@html.Attrs::build().role("status"),
          localized(
            state.locale,
            "Reservation records are stale; candidate status is withheld until the next successful refresh.",
            "预留记录已过期；下次刷新成功前不会显示预检候选状态。",
          ),
        )
      } else {
        @html.nothing
      },
    ],
  )
}
