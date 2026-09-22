///|
priv struct DeliveryPlacementResponse {
  reservation_id : String
  tenant_ref : String
  organization_id : String
  project_id : String
  node_name : String
  expires_unix_ms : Int64
  delivery_kind : String
  container_image_digest : String?
  container_cpu_millis : Int?
  container_memory_mib : Int?
} derive(FromJson)

///|
async fn WorkspaceHost::delivery_placement(
  self : WorkspaceHost,
  grant : @webide.Grant,
  container? : ExclusiveContainer,
  validate_container? : Bool = false,
) -> (ExclusivePlacement, Int64)? {
  if grant.expires_unix_ms <= @async.now() {
    return None
  }
  @async.with_timeout(5000, () => {
    let client = @http.Client(self.config.controller_origin)
    defer client.close()
    let response = client.get("/v1/workspace-delivery/placement", extra_headers={
      "authorization": "Bearer " + grant.api_secret,
      "x-lunanexa-client": grant.client_id,
    })
    let bytes = limited(client, 32768)
    if response.code == 401 || response.code == 403 || response.code == 404 {
      return None
    }
    if response.code != 200 {
      raise @webide.BridgeError::AuthorityUnavailable
    }
    let result : DeliveryPlacementResponse = @json.from_json(
      @json.parse(@utf8.decode(bytes)),
    )
    if validate_container && !delivery_profile_matches(result, container) {
      return None
    }
    if result.tenant_ref != grant.tenant_ref ||
      result.organization_id != grant.organization_id ||
      result.project_id != grant.project_id ||
      result.expires_unix_ms <= @async.now() ||
      !dns_label(result.reservation_id) ||
      !dns_label(result.node_name) {
      return None
    }
    Some(
      (
        {
          reservation_id: result.reservation_id,
          tenant_ref: result.tenant_ref,
          organization_id: result.organization_id,
          project_id: result.project_id,
          node_name: result.node_name,
        },
        result.expires_unix_ms,
      ),
    )
  }) catch {
    _ => raise @webide.BridgeError::AuthorityUnavailable
  }
}

///|
fn delivery_profile_matches(
  placement : DeliveryPlacementResponse,
  container : ExclusiveContainer?,
) -> Bool {
  match (placement.delivery_kind, container) {
    ("Workspace", None) => true
    ("GpuContainer", Some(runtime)) =>
      runtime.gpu &&
      pinned_image(runtime.image) &&
      placement.container_image_digest.map_or(false, digest => {
        runtime.image.has_suffix("@" + digest)
      }) &&
      placement.container_cpu_millis == Some(runtime.cpu_millis) &&
      placement.container_memory_mib == Some(runtime.memory_mib)
    _ => false
  }
}

///|
async fn WorkspaceHost::report_delivery_ready(
  self : WorkspaceHost,
  grant : @webide.Grant,
  backend : @webide.Backend,
  probe_path : String,
) -> Unit {
  @async.with_timeout(10000, () => {
    let probe = @http.Client(backend.http_url)
    defer probe.close()
    let observed = probe.get(probe_path)
    ignore(limited(probe, 1048576))
    if observed.code != 200 {
      raise HostError::WorkspaceUnavailable
    }
    let controller = @http.Client(self.config.controller_origin)
    defer controller.close()
    let recorded = controller.post(
      "/v1/workspace-delivery/ready",
      ({} : Json),
      extra_headers={
        "authorization": "Bearer " + grant.api_secret,
        "x-lunanexa-client": grant.client_id,
        "content-type": "application/json",
        "x-lunanexa-gateway-token": self.observation_token,
      },
    )
    ignore(limited(controller, 32768))
    if recorded.code != 200 && recorded.code != 204 {
      raise HostError::ControllerRejected
    }
  })
}

///|
async fn WorkspaceHost::report_delivery_starting(
  self : WorkspaceHost,
  grant : @webide.Grant,
  container : ExclusiveContainer?,
) -> Unit {
  let memory = match container {
    Some(value) => value.memory_mib
    None => self.config.memory_mib
  }
  let gpu_memory = match container {
    Some(value) if value.gpu => value.memory_mib
    _ => 0
  }
  let client = @http.Client(self.config.controller_origin)
  defer client.close()
  let response = client.post(
    "/v1/workspace-delivery/starting",
    ({ "memory_mib": memory + 512, "gpu_memory_mib": gpu_memory } : Json),
    extra_headers={
      "authorization": "Bearer " + grant.api_secret,
      "x-lunanexa-client": grant.client_id,
      "x-lunanexa-gateway-token": self.observation_token,
      "content-type": "application/json",
    },
  )
  ignore(limited(client, 32768))
  if response.code != 200 && response.code != 204 {
    raise HostError::ControllerRejected
  }
}

///|
async fn WorkspaceHost::report_delivery_stopped(
  self : WorkspaceHost,
  id : String,
) -> Unit {
  let client = @http.Client(self.config.controller_origin)
  defer client.close()
  let response = client.post(
    "/v1/workspace-delivery/stopped",
    ({ "workspace_id": id } : Json),
    extra_headers={
      "x-lunanexa-gateway-token": self.observation_token,
      "content-type": "application/json",
    },
  )
  ignore(limited(client, 32768))
  if response.code != 200 && response.code != 204 {
    raise HostError::ControllerRejected
  }
}
