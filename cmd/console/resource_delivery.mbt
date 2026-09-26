///|
fn resource_delivery_read(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  if model.console.resource_delivery.loading {
    return (model, @rabbita.none)
  }
  let next = {
    ..model,
    console: {
      ..model.console,
      resource_delivery: { ..model.console.resource_delivery, loading: true, },
    },
  }
  (next, resource_delivery_command(next, false, false, emit))
}

///|
fn resource_delivery_command(
  model : AppModel,
  reserve : Bool,
  allocate_undertaking : Bool,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(ResourcesLoaded(model.credential, result)), async fn() noraise {
    try {
      let panel = model.console.resource_delivery
      if reserve {
        guard panel.leases
          .iter()
          .find_first(lease => lease.key == panel.selected_lease)
          is Some(lease) &&
          panel.confirmed_idle &&
          !panel.selected_nodes.is_empty() else {
          raise Failure("select authorized resources")
        }
        let selected = model.console.nodes.filter(node => {
          panel.selected_nodes.contains(node.node_id)
        })
        guard selected.length() == panel.selected_nodes.length() else {
          raise Failure("refresh nodes")
        }
        let mut memory_mib = 2147483647
        for node in selected {
          guard node.memory_measured &&
            node.free_memory_mib >= 36864 &&
            node.total_memory_mib >= 49152 else {
            raise Failure("refresh measured free memory before reserving")
          }
          memory_mib = Int::min(
            memory_mib,
            Int::min(node.total_memory_mib - 16384, node.free_memory_mib - 4096),
          )
        }
        let request_body : @ui.ResourceReservationRequest = {
          reservation_id: panel.reservation_id,
          idempotency_key: panel.reservation_id,
          tenant_ref: lease.tenant_ref,
          organization_id: lease.organization_id,
          authority_ref: lease.authority_ref,
          lease_id: lease.lease_id,
          node_ids: panel.selected_nodes,
          starts_unix_ms: panel.reservation_starts_ms,
          expires_unix_ms: lease.expires_unix_ms,
          memory_mib_per_node: memory_mib,
          gpu_memory_mib_per_node: memory_mib,
          max_concurrency_per_node: 4,
        }
        let body : Json = {
          "request": request_body.to_json(),
          "readiness_confirmation": "reserve-idle-nodes:\{panel.reservation_id}",
        }
        ignore(
          request(
            "POST",
            model.endpoint,
            "/v1/resource-reservations",
            model.credential,
            body=body.stringify(),
          ),
        )
      }
      if allocate_undertaking {
        guard panel.undertaking_orders
          .iter()
          .find_first(row => row.order_id == panel.selected_undertaking_order)
          is Some(order) &&
          panel.confirmed_idle &&
          panel.selected_nodes.length().to_int64() == order.node_count else {
          raise Failure("select the exact approved undertaking node count")
        }
        let body : Json = {
          "order_id": order.order_id,
          "node_ids": panel.selected_nodes.to_json(),
          "readiness_confirmation": "allocate-idle-nodes:\{order.order_id}",
        }
        for _ in 0..<20 {
          let response = request(
            "POST",
            model.endpoint,
            "/v1/undertaking-allocations",
            model.credential,
            body=body.stringify(),
          )
          let decoded = try @json.parse(response) catch {
            _ => Json::null()
          } noraise {
            value => value
          }
          let still_activating = match decoded {
            { "status": String("ActivatingAccess"), .. } => true
            _ => false
          }
          if !still_activating {
            break
          }
          @async.sleep(3000)
        }
      }
      let undertaking_orders : Array[@ui.UndertakingAllocationRow] = @json.from_json(
        parse_console_json(
          request(
            "GET",
            model.endpoint,
            "/v1/undertaking-allocations",
            model.credential,
          ),
        ),
      )
      let reservations : Array[@ui.ResourceReservationRow] = @json.from_json(
        parse_console_json(
          request(
            "GET",
            model.endpoint,
            "/v1/resource-reservations",
            model.credential,
          ),
        ),
      )
      let deliveries : Array[@ui.ResourceDeliveryRow] = @json.from_json(
        parse_console_json(
          request("GET", model.endpoint, "/v1/deliveries", model.credential),
        ),
      )
      let workspace : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
        parse_console_json(
          request("GET", model.endpoint, "/v1/workspace", model.credential),
        ),
      )
      let portal : @portal.PortalSnapshot = @json.from_json(
        parse_console_json(
          request(
            "GET",
            model.endpoint,
            "/v1/portal/operator/snapshot",
            model.credential,
          ),
        ),
      )
      let now = current_unix_ms()
      let leases : Array[@ui.ResourceLeaseOption] = []
      for lease in workspace.leases {
        if lease.state != Active ||
          lease.access != Developer ||
          lease.starts_unix_ms > now ||
          lease.expires_unix_ms <= now {
          continue
        }
        guard workspace.users
          .iter()
          .find_first(user => {
            user.subject_ref == lease.subject_ref && user.state == UserActive
          })
          is Some(user) else {
          continue
        }
        let grants = workspace.access_grants.filter(grant => {
          grant.user_id == user.user_id &&
          grant.tenant_ref == lease.tenant_ref &&
          grant.state == GrantActive &&
          grant.access == Developer &&
          grant.starts_unix_ms <= now &&
          grant.expires_unix_ms > now
        })
        grants.sort_by_key(grant => (grant.expires_unix_ms, grant.grant_id))
        guard grants.last() is Some(grant) else { continue }
        for membership in portal.memberships {
          if membership.active &&
            membership.subject_ref == lease.subject_ref &&
            membership.tenant_ref == lease.tenant_ref {
            leases.push({
              key: "\{lease.lease_id}:\{membership.organization_id}",
              label: "\{user.display_name} · \{membership.organization_id}",
              tenant_ref: lease.tenant_ref,
              organization_id: membership.organization_id,
              authority_ref: grant.grant_id,
              lease_id: lease.lease_id,
              expires_unix_ms: Int64::min(
                lease.expires_unix_ms,
                grant.expires_unix_ms,
              ),
            })
          }
        }
      }
      Ok({
        ..@ui.default_resource_delivery_panel(),
        reservations,
        deliveries,
        undertaking_orders,
        leases,
        loaded: true,
      })
    } catch {
      _ =>
        Err(
          console_copy(
            model.console.locale,
            "Unable to update resource delivery. Refresh authorization and node occupancy before retrying; no workload was stopped by this action.",
            "无法更新资源交付。请刷新授权和节点占用后重试；此操作不会停止已有任务。",
          ),
        )
    }
  })
}
