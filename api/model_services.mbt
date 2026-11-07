///|
/// Deployment-owned runtime binding supplied by the host, never by a browser.
priv struct AdoptedModelService {
  service_id : String
  model_alias : String
  artifact_digest : String
  owner : @deployment.ServiceOwner
  node_ids : Array[String]
  runtime_kind : @deployment.ServiceRuntimeKind
  binding_ref : String
} derive(FromJson)

///|
fn runtime_state(raw : String) -> @deployment.ServiceRuntimeState {
  match raw {
    "Running" => Running
    "Stopped" => Stopped
    "Partial" => Partial
    _ => Unknown
  }
}

///|
/// All lifecycle writers hold resource_mutex while checking and committing.
/// Reservations remain the authority for company delivery budgets.
async fn ApiService::check_service_resources(
  self : ApiService,
  candidate : @deployment.ModelServiceInstance,
) -> Unit {
  let now = @async.now()
  for node in candidate.node_ids {
    if self.exclusive_lease_store is Some(leases) &&
      leases.node_blocks_managed_placement(node) {
      raise @deployment.DeploymentError::InvalidState(
        "node belongs to an exclusive lease",
      )
    }
    if self.scheduler is Some(scheduler) && scheduler.node_is_reserved(node) {
      guard candidate.owner.reservation_id is Some(id) &&
        scheduler.node_reservation(id) is Some(reservation) &&
        reservation.state == Reserved &&
        reservation.request.tenant_ref == candidate.owner.tenant_ref &&
        reservation.request.organization_id == candidate.owner.organization_id &&
        reservation.request.node_ids.contains(node) &&
        reservation.request.starts_unix_ms <= now &&
        reservation.request.expires_unix_ms > now else {
        raise @deployment.DeploymentError::InvalidState(
          "node belongs to another resource reservation",
        )
      }
    } else if candidate.owner.reservation_id is Some(_) {
      raise @deployment.DeploymentError::InvalidState(
        "service reservation is unavailable",
      )
    }
  }
  if self.deployment_store is Some(store) {
    for current in store.services() {
      if @deployment.service_conflicts(candidate, current) {
        raise @deployment.DeploymentError::InvalidState(
          "node belongs to another model service",
        )
      }
    }
  }
}

///|
async fn ApiService::node_has_service_allocation(
  self : ApiService,
  node : String,
) -> Bool {
  match self.deployment_store {
    Some(store) =>
      store
      .services()
      .any(s => {
        s.node_ids.contains(node) &&
        (s.holds_resources() || s.reserves_company_node())
      })
    None => false
  }
}

///|
async fn ApiService::register_assignment_service(
  self : ApiService,
  assignment : @contracts.DesiredAssignment,
  owner : @deployment.ServiceOwner,
) -> Unit {
  // Cache preparation does not create a model runtime or reserve GPU capacity.
  if assignment.runtime.name == "lunanexa-artifact-preparation" {
    return
  }
  let value : @deployment.ModelServiceInstance = {
    service_id: assignment.assignment_id,
    model_alias: assignment.deployment_id,
    artifact_digest: assignment.artifact.digest,
    owner,
    node_ids: [assignment.node_id],
    runtime_kind: NodeAssignment,
    binding_ref: assignment.assignment_id,
    // Shared placement is available only inside an explicit company budget.
    // Platform deployments claim the whole node, including while pending.
    exclusive: owner.reservation_id is None,
    generation: 1L,
    desired_running: true,
    observed: Unknown,
    updated_unix_ms: @async.now(),
  }
  self.check_service_resources(value)
  if self.deployment_store is Some(store) {
    store.adopt_service(value)
    let current = store.service(value.service_id).unwrap()
    if !current.desired_running {
      ignore(
        store.set_service_desired(
          current.service_id,
          current.generation,
          true,
          @async.now(),
        ),
      )
    }
  }
}

///|
async fn ApiService::retire_assignment_service(
  self : ApiService,
  id : String,
) -> Unit {
  if self.deployment_store is Some(store) &&
    store.service(id) is Some(current) &&
    current.desired_running {
    ignore(
      store.set_service_desired(id, current.generation, false, @async.now()),
    )
  }
}

///|
/// Observation only: recovery never replays a start, scale or switch request.
pub async fn ApiService::reconcile_model_services(self : ApiService) -> Unit {
  guard self.deployment_store is Some(store) else { return }
  {
    self.resource_mutex.acquire()
    defer self.resource_mutex.release()
    for assignment in self.store.assignments() {
      let owner : @deployment.ServiceOwner = match
        (assignment.reservation, self.scheduler) {
        (Some(authority), Some(scheduler)) => {
          guard scheduler.node_reservation(authority.reservation_id) is Some(r) else {
            continue
          }
          {
            tenant_ref: r.request.tenant_ref,
            organization_id: r.request.organization_id,
            reservation_id: Some(authority.reservation_id),
          }
        }
        _ => { tenant_ref: "", organization_id: "", reservation_id: None, }
      }
      self.register_assignment_service(assignment, owner)
    }
    for instance in store.services() {
      if instance.runtime_kind == NodeAssignment &&
        instance.desired_running &&
        !self.store
        .assignments()
        .any(a => a.assignment_id == instance.binding_ref) {
        self.retire_assignment_service(instance.service_id)
      }
    }
  }
  // Read-only adapter calls never hold global resource admission hostage.
  // Generation guards discard an observation overtaken by a new intent.
  for instance in store.services() {
    let observed : @deployment.ServiceRuntimeState = if instance.runtime_kind ==
      NodeAssignment {
      let assigned = self.store
        .assignments()
        .any(a => a.assignment_id == instance.binding_ref)
      let now = @async.now()
      let heartbeat = self.store
        .heartbeats()
        .iter()
        .find_first(h => {
          instance.node_ids.contains(h.node_id) &&
          h.timestamp_unix_ms >= instance.updated_unix_ms &&
          h.timestamp_unix_ms <= now &&
          now - h.timestamp_unix_ms <=
          self.global_settings.control_timing.heartbeat_timeout_ms
        })
      match heartbeat {
        Some(h) if h.running_deployments.contains(instance.model_alias) =>
          Running
        Some(_) if !assigned => Stopped
        _ => Unknown
      }
    } else {
      runtime_state(
        @async.with_timeout(5000, () => {
          self.observe_service_binding(
            instance.runtime_kind,
            instance.binding_ref,
          )
        }) catch {
          _ => "Unknown"
        },
      )
    }
    store.observe_service(
      instance.service_id,
      instance.generation,
      observed,
      @async.now(),
    ) catch {
      @deployment.DeploymentError::InvalidState(_) => ()
      error => raise error
    }
  }
}

///|
pub fn ApiService::with_runtime_controls(
  self : ApiService,
  controls : Map[String, async (String) -> String],
) -> ApiService {
  { ..self, runtime_controls: controls, }
}

///|
pub async fn ApiService::adopt_model_services_json(
  self : ApiService,
  raw : String?,
) -> ApiService {
  guard raw is Some(raw) else { return self }
  guard self.deployment_store is Some(store) else {
    raise Failure("model service deployment store unavailable")
  }
  let bindings : Array[AdoptedModelService] = @json.from_json(@json.parse(raw))
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  for binding in bindings {
    guard binding.runtime_kind != NodeAssignment &&
      (binding.owner.tenant_ref == "") == (binding.owner.organization_id == "") &&
      @contracts.valid_identifier(binding.service_id) &&
      @contracts.valid_identifier(binding.model_alias) &&
      binding.node_ids.length() > 0 &&
      binding.node_ids.all(n => @contracts.valid_identifier(n)) else {
      raise Failure("invalid adopted model service binding")
    }
    // A restart never issues start/stop. Status failure holds an unknown claim.
    let observed = runtime_state(
      self.observe_service_binding(binding.runtime_kind, binding.binding_ref) catch {
        _ => "Unknown"
      },
    )
    let value : @deployment.ModelServiceInstance = {
      service_id: binding.service_id,
      model_alias: binding.model_alias,
      artifact_digest: binding.artifact_digest,
      owner: binding.owner,
      node_ids: binding.node_ids,
      runtime_kind: binding.runtime_kind,
      binding_ref: binding.binding_ref,
      exclusive: true,
      generation: 1L,
      desired_running: observed != Stopped,
      observed,
      updated_unix_ms: @async.now(),
    }
    if store.service(value.service_id) is None {
      // Stopped platform bindings can coexist with another owner's allocation;
      // only a later start may acquire that resource.
      if value.holds_resources() {
        self.check_service_resources(value)
      }
      store.adopt_service(value)
    } else {
      store.adopt_service(value)
      let current = store.service(value.service_id).unwrap()
      store.observe_service(
        current.service_id,
        current.generation,
        observed,
        @async.now(),
      )
    }
  }
  self
}

///|
async fn ApiService::observe_service_binding(
  self : ApiService,
  kind : @deployment.ServiceRuntimeKind,
  binding : String,
) -> String {
  guard kind != NodeAssignment else {
    raise Failure("assignment observation uses node receipts")
  }
  guard self.runtime_controls.get(binding) is Some(control) else {
    raise Failure("runtime adapter unavailable")
  }
  control("status")
}

///|
async fn ApiService::apply_model_service_action(
  self : ApiService,
  id : String,
  action : String,
) -> @deployment.ModelServiceInstance {
  guard self.deployment_store is Some(store) &&
    store.service(id) is Some(current) else {
    raise @deployment.DeploymentError::InvalidState("model service not found")
  }
  guard action == "start" || action == "stop" else {
    raise Failure("unsupported model service action")
  }
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  // Always re-read after acquiring the resource lock.
  let current = store.service(current.service_id).unwrap()
  guard current.runtime_kind != NodeAssignment else {
    raise Failure(
      "use the deployment operation for signed assignment lifecycle",
    )
  }
  if action == "start" {
    self.check_service_resources(current)
  }
  let desired = store.set_service_desired(
    id,
    current.generation,
    action == "start",
    @async.now(),
  )
  errdefer @async.protect_from_cancel(() => {
    store.observe_service(id, desired.generation, Unknown, @async.now())
  })
  guard self.runtime_controls.get(current.binding_ref) is Some(control) else {
    raise Failure("runtime adapter unavailable")
  }
  // Execution mechanics differ; admission, intent and retry semantics do not.
  let before = control("status")
  let state = if (action == "start" && before == "Running") ||
    (action == "stop" && before == "Stopped") {
    before
  } else {
    control(action)
  }
  let observed = runtime_state(state)
  store.observe_service(id, desired.generation, observed, @async.now())
  guard observed != Unknown else { raise Failure("runtime state unavailable") }
  store.service(id).unwrap()
}

///|
fn model_services_path(path : String) -> Bool {
  path == "/v1/model-services" ||
  path.has_prefix("/v1/model-services/") ||
  path == "/v1/portal/self/model-services" ||
  path.has_prefix("/v1/portal/self/model-services/")
}

///|
async fn ApiService::handle_model_services(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.deployment_store is Some(store) else {
    return api_error(
      503, "ServiceUnavailable", "deployment store unavailable", true,
    )
  }
  let customer = path.has_prefix("/v1/portal/")
  let prefix = if customer {
    "/v1/portal/self/model-services"
  } else {
    "/v1/model-services"
  }
  let mut tenant : String? = None
  let mut organization : String? = None
  let mut can_manage = false
  let mut actor = ""
  if customer {
    guard self.portal_store is Some(portal) &&
      self.portal_subject(headers, allow_asserted_subject) is Some(subject) else {
      return api_error(
        401, "Unauthenticated", "enterprise sign-in is required", false,
      )
    }
    let view = portal_view_for_request(portal, subject, headers) catch {
      error => return portal_error_reply(error)
    }
    tenant = Some(view.membership.tenant_ref)
    organization = Some(view.membership.organization_id)
    can_manage = view.membership.roles.contains(OrganizationAdministrator)
    actor = "portal:" + subject
  } else {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthenticated", "operator authority required", false,
      )
    }
    can_manage = true
    actor = self.operator_identity(headers).unwrap()
  }
  let visible = store
    .services()
    .filter(s => {
      !customer ||
      (
      // Personal delivery replicas keep their project/lease-scoped API.
        s.runtime_kind != NodeAssignment &&
        tenant == Some(s.owner.tenant_ref) &&
        organization == Some(s.owner.organization_id)
      )
    })
  if verb == Get && path == prefix {
    return if customer {
      json_reply(
        200,
        Json(
          [
            for s in visible => self.model_service_portal_view(s, can_manage)
          ],
        ),
      )
    } else {
      json_reply(
        200,
        Json(
          [
            for instance in visible => {
              self.model_service_operator_view(instance)
            }
          ],
        ),
      )
    }
  }
  let action = if path.has_suffix(":start") {
    "start"
  } else if path.has_suffix(":stop") {
    "stop"
  } else {
    ""
  }
  guard path.has_prefix(prefix + "/") &&
    action != "" &&
    path.length() > prefix.length() + action.length() + 2 else {
    return api_error(404, "NotFound", "model service not found", false)
  }
  let id = path[prefix.length() + 1:path.length() - action.length() - 1].to_owned()
  guard visible.any(s => s.service_id == id) else {
    return api_error(404, "NotFound", "model service not found", false)
  }
  if verb != Post {
    return api_error(
      405, "MethodNotAllowed", "unsupported service action", false,
    )
  }
  if !can_manage {
    return api_error(
      403, "OrganizationAdministratorRequired", "company administrator permission required",
      false,
    )
  }
  let result = self.apply_model_service_action(id, action) catch {
    _ =>
      return api_error(
        409, "ServiceConflict", "资源归属冲突或运行状态尚未确认，请刷新后重试",
        true,
      )
  }
  self.operator_audit_as(
    actor,
    "model-service." + action,
    id,
    "service:\{id}:\{result.generation}",
  )
  json_reply(
    200,
    if customer {
      self.model_service_portal_view(result, can_manage)
    } else {
      self.model_service_operator_view(result)
    },
  )
}

///|
async fn ApiService::model_service_portal_view(
  self : ApiService,
  instance : @deployment.ModelServiceInstance,
  can_manage : Bool,
) -> Json {
  let (ready, context) = self.model_service_readiness(instance)
  {
    "service_id": instance.service_id,
    "model_alias": instance.model_alias,
    "state": match instance.observed {
      Running => "Running"
      Stopped => "Stopped"
      Partial => "Partial"
      Unknown => "Unavailable"
    },
    "can_stop": can_manage && instance.runtime_kind != NodeAssignment,
    "ready": ready,
    "context_window_tokens": Json(context),
  }
}

///|
async fn ApiService::model_service_readiness(
  self : ApiService,
  instance : @deployment.ModelServiceInstance,
) -> (Bool, Int32?) {
  if instance.observed != Running {
    return (false, None)
  }
  if self.external_text_route is Some(route) &&
    route.model_alias == instance.model_alias {
    self.external_text_observation()
  } else {
    (true, None)
  }
}

///|
async fn ApiService::model_service_operator_view(
  self : ApiService,
  instance : @deployment.ModelServiceInstance,
) -> Json {
  let (ready, _) = self.model_service_readiness(instance)
  guard Json(instance) is Object(fields) else {
    fail("expected service object")
  }
  fields["ready"] = Json(ready)
  Json(fields)
}
