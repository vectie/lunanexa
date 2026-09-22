///|
priv struct WorkspaceStartingRequest {
  memory_mib : Int
  gpu_memory_mib : Int
} derive(FromJson)

///|
priv struct WorkspaceStoppedRequest {
  workspace_id : String
} derive(FromJson)

///|
fn delivery_workspace_id(
  authority : @access.ApiAuthorization,
  client_id : String,
  delivery_id : String,
) -> String {
  let identity = [
      authority.tenant_ref,
      authority.subject_ref,
      authority.organization_id,
      authority.project_id,
      client_id,
      delivery_id,
    ]
    .to_json()
    .stringify()
  "webide-" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(identity)))
}

///|
/// Internal gateway resolution uses the same live credential/lease checks as
/// model access; knowing an operation or reservation identifier grants nothing.
async fn ApiService::handle_workspace_delivery(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) &&
    self.client_handoff_store is Some(handoffs) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      503, "DeliveryUnavailable", "delivery authority is unavailable", true,
    )
  }
  if verb == Post {
    if self.workspace_gateway_observation_token == "" ||
      header(headers, "x-lunanexa-gateway-token") !=
      Some(self.workspace_gateway_observation_token) {
      return api_error(
        403, "GatewayRequired", "runtime observations require the trusted workspace gateway",
        false,
      )
    }
    if path == "/v1/workspace-delivery/stopped" {
      let request : WorkspaceStoppedRequest = try
        @json.from_json(@json.parse(body))
      catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "workspace identity is required", false,
          )
      } noraise {
        value => value
      }
      self.resource_mutex.acquire()
      defer self.resource_mutex.release()
      for operation in deliveries.operations() {
        if operation.workspace_id == Some(request.workspace_id) &&
          operation.stage == Stopping &&
          operation.reservation_id is Some(id) {
          scheduler.confirm_node_service_stopped(
            id,
            "\{operation.operation_id}-workspace",
            @async.now(),
          )
          ignore(
            deliveries.observe(
              operation.operation_id,
              operation.generation,
              WorkspaceStopped,
              @async.now(),
            ),
          ) catch {
            error => return delivery_error(error)
          }
        }
      }
      return json_reply(200, { "recorded": true })
    }
  }
  guard self.api_key_authorization(headers, ModelList, false) is Some(authority) else {
    return api_error(
      401, "Unauthenticated", "active workspace credential is required", false,
    )
  }
  let client = header(headers, "x-lunanexa-client")
  guard handoffs.snapshot().credentials
    .iter()
    .find_first(value => value.key_id == authority.key_id)
    is Some(credential) &&
    client == Some(credential.client_id) else {
    return api_error(
      403, "ClientMismatch", "workspace client does not match credential", false,
    )
  }
  let now = @async.now()
  let authorization = try
    directory.authorize_subject_for_tenant(
      authority.subject_ref,
      authority.tenant_ref,
      Developer,
      now,
    )
  catch {
    _ =>
      return api_error(
        403, "ActiveLeaseRequired", "workspace lease is not active", false,
      )
  } noraise {
    value => value
  }
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  let candidates = deliveries
    .operations()
    .filter(operation => {
      credential.delivery_id == Some(operation.operation_id) &&
      operation.intent.tenant_id == authority.tenant_ref &&
      operation.intent.organization_id == authority.organization_id &&
      operation.intent.project_id == authority.project_id &&
      operation.intent.lease_id == authorization.lease.lease_id &&
      operation.intent.kind != ModelApi &&
      (operation.stage == StartingWorkspace || operation.stage == Ready) &&
      operation.intent.expires_at_ms > now
    })
  guard candidates.length() == 1 &&
    candidates[0].reservation_id is Some(reservation_id) &&
    scheduler.node_reservation(reservation_id) is Some(reservation) &&
    reservation.state == Reserved &&
    reservation.request.tenant_ref == authority.tenant_ref &&
    reservation.request.organization_id == authority.organization_id &&
    reservation.request.lease_id == authorization.lease.lease_id &&
    reservation.request.starts_unix_ms <= now &&
    reservation.request.expires_unix_ms > now &&
    reservation.request.node_ids.get(0) is Some(node_id) else {
    return api_error(
      404, "WorkspacePlacementUnavailable", "no unique active workspace placement is available",
      false,
    )
  }
  let operation = candidates[0]
  let container_offering = if operation.intent.kind == GpuContainer {
    guard self.gpu_container_offering is Some(offering) &&
      offering.template_id == operation.intent.template_id &&
      offering.version == operation.intent.template_version &&
      offering.client_id == credential.client_id else {
      return api_error(
        409, "ContainerOfferingUnavailable", "the selected GPU container offering is unavailable",
        false,
      )
    }
    Some(offering)
  } else {
    None
  }
  let workspace_id = delivery_workspace_id(
    authority,
    credential.client_id,
    operation.operation_id,
  )
  let expiry = if operation.intent.expires_at_ms <
    reservation.request.expires_unix_ms {
    operation.intent.expires_at_ms
  } else {
    reservation.request.expires_unix_ms
  }
  if verb == Get && path == "/v1/workspace-delivery/placement" {
    self.ensure_reservation_nodes(reservation_id) catch {
      _ =>
        return api_error(
          409, "NodeReservationPending", "reserved nodes are not ready for exclusive workloads",
          true,
        )
    }
    // Use the same deployment-owned mapping as the node reservation adapter.
    guard self.reservation_node_names.get(node_id) is Some(node_name) else {
      return api_error(
        409, "NodeMappingUnavailable", "workspace node mapping is not configured",
        true,
      )
    }
    return json_reply(200, {
      "reservation_id": reservation_id,
      "tenant_ref": authority.tenant_ref,
      "organization_id": authority.organization_id,
      "project_id": authority.project_id,
      "node_name": node_name,
      "expires_unix_ms": expiry.to_json(),
      "delivery_kind": operation.intent.kind.to_json(),
      "container_image_digest": container_offering
      .map(value => value.image_digest)
      .to_json(),
      "container_cpu_millis": container_offering
      .map(value => value.cpu_millis)
      .to_json(),
      "container_memory_mib": container_offering
      .map(value => value.memory_mib)
      .to_json(),
    })
  }
  if verb == Post && path == "/v1/workspace-delivery/ready" {
    if operation.stage == StartingWorkspace {
      ignore(
        deliveries.observe(
          operation.operation_id,
          operation.generation,
          if operation.intent.kind == GpuContainer {
            @delivery.Observation::ContainerResponded(instance_id=workspace_id)
          } else {
            @delivery.Observation::WorkspaceResponded(workspace_id~)
          },
          now,
        ),
      ) catch {
        error => return delivery_error(error)
      }
    }
    return json_reply(200, { "ready": true })
  }
  if verb == Post && path == "/v1/workspace-delivery/starting" {
    let request : WorkspaceStartingRequest = try
      @json.from_json(@json.parse(body))
    catch {
      _ =>
        return api_error(
          400, "InvalidRequest", "workspace resource budget is required", false,
        )
    } noraise {
      value => value
    }
    if container_offering is Some(offering) &&
      (
        request.memory_mib != offering.memory_mib + 512 ||
        request.gpu_memory_mib != offering.memory_mib
      ) {
      return api_error(
        409, "ContainerProfileMismatch", "gateway resources do not match the selected GPU container offering",
        false,
      )
    }
    try {
      self.ensure_reservation_nodes(reservation_id)
      ignore(
        scheduler.claim_node_service(
          reservation_id,
          authority.tenant_ref,
          {
            service_id: "\{operation.operation_id}-workspace",
            node_id,
            memory_mib: request.memory_mib,
            gpu_memory_mib: request.gpu_memory_mib,
            concurrency: 1,
          },
          now,
        ),
      )
      if operation.workspace_id is None {
        ignore(
          deliveries.observe(
            operation.operation_id,
            operation.generation,
            WorkspaceStarting(workspace_id~),
            now,
          ),
        )
      }
    } catch {
      error => return delivery_error(error)
    }
    return json_reply(200, { "recorded": true })
  }
  api_error(404, "NotFound", "workspace delivery route was not found", false)
}
