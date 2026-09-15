///|
/// Deployment-owned configuration, not a customer supplied endpoint. Keep old
/// bindings until their durable jobs have been reconciled and removed upstream.
pub(all) struct MediaBinding {
  deployment_id : String
  deployment_generation : Int64
  node_id : String
  origin : String
  bearer : String?
  profile : @media_provider.Profile
  instance_id : String?
} derive(FromJson)

///|
/// One operator-qualified template/node profile serves every subsequent order;
/// customers never configure endpoints or wait for per-order config edits.
pub(all) struct MediaTemplateBinding {
  template_id : String
  template_version : String
  node_id : String
  origin : String
  bearer : String?
  profile : @media_provider.Profile
  runtime_route : @contracts.RuntimeRoutePolicy?
} derive(FromJson)

///|
pub struct MediaService {
  jobs : @media_jobs.JobStore
  runtime : @media_runtime.VideoRuntime
  bindings : Array[MediaBinding]
  templates : Array[MediaTemplateBinding]
}

///|
fn MediaBinding::provider(
  self : MediaBinding,
) -> @media_provider.Provider raise {
  match self.bearer {
    Some(token) =>
      @media_provider.Provider::new(self.origin, self.profile, bearer=token)
    None => @media_provider.Provider::new(self.origin, self.profile)
  }
}

///|
fn MediaBinding::identity(self : MediaBinding) -> String {
  // Token rotation does not change runtime identity; endpoint, model, profile,
  // placement or generation changes do. Old jobs cannot migrate implicitly.
  let material : Json = {
    "deployment": self.deployment_id,
    "generation": self.deployment_generation.to_json(),
    "node": self.node_id,
    "origin": self.origin,
    "profile": self.profile.to_json(),
  }
  if self.instance_id is Some(instance_id) && material is Object(fields) {
    fields["instance_id"] = instance_id.to_json()
  }
  "media-" + digest_hex(material.stringify())
}

///|
fn MediaBinding::execution_context(
  self : MediaBinding,
) -> @media_jobs.ExecutionContext {
  {
    deployment_id: self.deployment_id,
    generation: self.deployment_generation,
    node_id: self.node_id,
    instance_id: self.instance_id,
  }
}

///|
async fn ApiService::media_execution_context(
  self : ApiService,
  jobs : @media_jobs.JobStore,
  fixed : Array[MediaBinding],
  templates : Array[MediaTemplateBinding],
  identity : String,
) -> @media_jobs.ExecutionContext {
  if jobs.context_for_binding(identity) is Some(context) {
    return context
  }
  guard self
    .media_all_bindings(fixed, templates)
    .filter(binding => binding.identity() == identity)
    .get(0)
    is Some(binding) else {
    raise @media_runtime.RuntimeError::AuthorityUnavailable
  }
  let context = binding.execution_context()
  jobs.remember_execution(identity, context)
  context
}

///|
pub fn ApiService::with_media_jobs(
  self : ApiService,
  jobs : @media_jobs.JobStore,
  bindings : Array[MediaBinding],
) -> ApiService raise {
  self.configure_media(jobs, bindings, [])
}

///|
pub fn ApiService::with_media_templates(
  self : ApiService,
  jobs : @media_jobs.JobStore,
  templates : Array[MediaTemplateBinding],
) -> ApiService raise {
  if templates.length() > 128 {
    raise Failure("too many media profiles")
  }
  let identities : Map[String, Bool] = Map([])
  for template in templates {
    let identity = template.template_id +
      ":" +
      template.template_version +
      ":" +
      template.node_id
    if !@contracts.valid_identifier(template.template_id) ||
      !@contracts.valid_identifier(template.template_version) ||
      !@contracts.valid_identifier(template.node_id) ||
      identities.contains(identity) {
      raise Failure("invalid or duplicate media template profile")
    }
    let origin = match template.runtime_route {
      None => template.origin
      Some(policy) => {
        if !policy.valid() || template.origin != "" {
          raise Failure(
            "managed media route requires a valid private boundary and no static fallback",
          )
        }
        "http://" + policy.network + ":" + policy.port.to_string()
      }
    }
    let probe : MediaBinding = {
      deployment_id: "validation",
      deployment_generation: 1L,
      node_id: template.node_id,
      origin,
      bearer: template.bearer,
      profile: template.profile,
      instance_id: None,
    }
    ignore(probe.provider())
    identities[identity] = true
  }
  self.configure_media(jobs, [], templates)
}

///|
async fn ApiService::media_all_bindings(
  self : ApiService,
  fixed : Array[MediaBinding],
  templates : Array[MediaTemplateBinding],
) -> Array[MediaBinding] {
  let result = fixed.copy()
  guard self.deployment_store is Some(deployments) else { return result }
  let assignments = self.store.assignments()
  let heartbeats = self.store.heartbeats()
  let now = @async.now()
  // Historical operations are retained by the deployment store. Reconstruct
  // old immutable binding IDs too, so expiry cleanup still targets the original
  // generation after an order ends. Retain old versioned profiles until cleanup.
  for operation in deployments.operations() {
    guard operation.plan.replicas.length() == 1 &&
      operation.plan.template is Some(deployed) &&
      deployed.capability == VideoGenerate else {
      continue
    }
    for template in templates {
      if template.template_id == deployed.template_id &&
        template.template_version == deployed.version &&
        template.node_id == operation.plan.replicas[0].node_id &&
        template.profile.model == deployed.model_selector {
        let mut origin = template.origin
        let mut instance_id : String? = None
        if template.runtime_route is Some(policy) {
          if !@controller.deployment_operation_ready(
              operation, assignments, heartbeats, now,
            ) {
            continue
          }
          let candidates : Array[@contracts.RuntimeEndpoint] = []
          for heartbeat in heartbeats {
            if heartbeat.node_id != template.node_id ||
              heartbeat.state != Active ||
              now - heartbeat.timestamp_unix_ms >
              self.global_settings.control_timing.heartbeat_timeout_ms {
              continue
            }
            for endpoint in heartbeat.runtime_endpoints.unwrap_or([]) {
              if operation.assignment_ids.contains(endpoint.assignment_id) &&
                endpoint.deployment_id == operation.deployment_id &&
                endpoint.generation == operation.generation &&
                policy.allows(endpoint) &&
                assignments.any(assignment => {
                  assignment.node_id == template.node_id &&
                  endpoint.matches(assignment, now)
                }) {
                candidates.push(endpoint)
              }
            }
          }
          if candidates.length() != 1 {
            continue
          }
          let endpoint = candidates[0]
          origin = "http://" +
            endpoint.address +
            ":" +
            endpoint.port.to_string()
          instance_id = Some(endpoint.instance_id)
        }
        result.push({
          deployment_id: operation.deployment_id,
          deployment_generation: operation.generation,
          node_id: template.node_id,
          origin,
          bearer: template.bearer,
          profile: template.profile,
          instance_id,
        })
      }
    }
  }
  result
}

///|
fn ApiService::configure_media(
  self : ApiService,
  jobs : @media_jobs.JobStore,
  bindings : Array[MediaBinding],
  templates : Array[MediaTemplateBinding],
) -> ApiService raise {
  if bindings.length() > 128 {
    raise Failure("too many media bindings")
  }
  let identities : Map[String, Bool] = Map([])
  for binding in bindings {
    if !@contracts.valid_identifier(binding.deployment_id) ||
      !@contracts.valid_identifier(binding.node_id) ||
      binding.deployment_generation <= 0L ||
      identities.contains(binding.identity()) {
      raise Failure("invalid media binding")
    }
    ignore(binding.provider())
    identities[binding.identity()] = true
  }
  let runtime = @media_runtime.VideoRuntime::new(
    jobs,
    identity => {
      guard self
        .media_all_bindings(bindings, templates)
        .filter(binding => binding.identity() == identity)
        .get(0)
        is Some(binding) else {
        raise Failure("media binding unavailable")
      }
      binding.provider()
    },
    (owner, model, identity) => {
      if !self.media_owner_authorized(owner, model) {
        return false
      }
      let context = self.media_execution_context(
        jobs, bindings, templates, identity,
      )
      if !self.media_order_matches(owner, context) {
        return false
      }
      self.media_execution_authorized(model, context)
    },
    job => {
      let context = self.media_execution_context(
        jobs,
        bindings,
        templates,
        job.deployment_id,
      )
      self.settle_media_job(job, context.node_id)
    },
  )
  { ..self, media: Some({ jobs, runtime, bindings, templates, }), }
}

///|
async fn ApiService::media_owner_authorized(
  self : ApiService,
  owner : @media_jobs.Owner,
  model : String,
) -> Bool {
  if self.reconciliation_only || !self.store.current_epoch_is_durable() {
    raise @media_runtime.RuntimeError::AuthorityUnavailable
  }
  let now = @async.now()
  match owner.authority {
    PrivateWorkspace(lease_id) => {
      guard self.private_cloud_workspace_access &&
        self.workspace_directory is Some(directory) else {
        return false
      }
      let authorized = directory.authorize_subject_for_tenant(
        owner.subject_ref,
        owner.tenant_ref,
        Developer,
        now,
      ) catch {
        _ => return false
      }
      if authorized.lease.lease_id != lease_id {
        return false
      }
    }
    DedicatedOrder(order_id) => {
      guard self.machine_commerce_store is Some(machine) &&
        machine.order(order_id) is Some(order) &&
        order.offering_kind == DedicatedEndpoint &&
        order.state == Active &&
        order.tenant_ref == owner.tenant_ref &&
        order.organization_id == owner.organization_id &&
        order.project_id == owner.project_id &&
        order.purchaser_subject_ref == owner.subject_ref &&
        order.requested_model_selector == Some(model) &&
        order.target_deployment_ref is Some(_) &&
        order.active_started_unix_ms.map_or(false, started => {
          now < started + order.duration_seconds * 1000L
        }) else {
        return false
      }
    }
  }
  guard self.account_store is Some(accounts) &&
    accounts
    .views()
    .any(account => {
      account.subject_ref == owner.subject_ref &&
      account.state == Active &&
      @account.role_allows(account.roles, EnterpriseUser)
    }) else {
    return false
  }
  guard self.portal_store is Some(portal) else { return false }
  if owner.authority is DedicatedOrder(_) {
    guard self.contract_document_store is Some(contracts) &&
      contracts.has_effective_master_lease(
        owner.tenant_ref,
        owner.subject_ref,
        now,
      ) else {
      return false
    }
  }
  guard self.workspace_directory is Some(directory) else { return false }
  try {
    let workspace = directory.authorize_subject_for_tenant(
      owner.subject_ref,
      owner.tenant_ref,
      Developer,
      now,
    )
    if !workspace.lease.limits.capabilities.any(limit => {
        limit.capability == VideoGenerate &&
        limit.max_concurrent_requests >= 1 &&
        limit.max_requests_per_hour >= 1
      }) {
      return false
    }
    let view = portal.self_view_for_organization(
      owner.subject_ref,
      owner.organization_id,
    )
    view.membership.tenant_ref == owner.tenant_ref &&
    view.membership.active &&
    @portal.role_allows(view.membership.roles, Developer)
  } catch {
    _ => false
  }
}

///|
async fn ApiService::media_execution_authorized(
  self : ApiService,
  model : String,
  context : @media_jobs.ExecutionContext,
) -> Bool {
  guard self.deployment_store is Some(deployments) &&
    deployments.deployment(context.deployment_id) is Some(operation) &&
    operation.generation == context.generation &&
    operation.plan.template.map_or(false, template => {
      template.capability == VideoGenerate && template.model_selector == model
    }) &&
    operation.plan.replicas.length() == 1 &&
    operation.plan.replicas[0].node_id == context.node_id else {
    return false
  }
  // Desired authority survives readiness loss. Actual provider access still
  // requires fresh endpoint evidence matching the original instance identity.
  [@deployment.DeploymentOperationState::Ready, Degraded, Reconciling].contains(
    operation.state,
  )
}

///|
async fn ApiService::media_authorized(
  self : ApiService,
  owner : @media_jobs.Owner,
  model : String,
  binding : MediaBinding,
) -> Bool {
  if model != binding.profile.model ||
    !self.media_owner_authorized(owner, model) {
    return false
  }
  if !self.media_order_matches(owner, binding.execution_context()) {
    return false
  }
  guard self.deployment_store is Some(deployments) &&
    deployments.deployment(binding.deployment_id) is Some(operation) &&
    operation.state == Ready else {
    return false
  }
  self.media_execution_authorized(model, binding.execution_context())
}

///|
async fn ApiService::media_order_matches(
  self : ApiService,
  owner : @media_jobs.Owner,
  context : @media_jobs.ExecutionContext,
) -> Bool {
  match owner.authority {
    PrivateWorkspace(_) => true
    DedicatedOrder(order_id) =>
      match self.machine_commerce_store {
        None => false
        Some(machine) =>
          machine
          .order(order_id)
          .map_or(false, order => {
            order.target_deployment_ref == Some(context.deployment_id)
          })
      }
  }
}

///|
async fn ApiService::settle_media_job(
  self : ApiService,
  job : @media_jobs.StoredJob,
  node_id : String,
) -> String {
  guard job.execution_terminal && job.terminal_unix_ms is Some(terminal) else {
    raise Failure("media job is not terminal")
  }
  // Count requests with distinct private/prepaid meters. Neither path invents
  // GPU time or creates a second payable token/accelerator charge.
  let event_id = "media-usage-" + digest_hex(job.job_id)
  let observation : @commercial.UsageObservation = {
    event_id,
    organization_id: job.owner.organization_id,
    project_id: job.owner.project_id,
    actor_ref: job.owner.subject_ref,
    workload_id: job.job_id,
    node_id,
    lease_epoch: 0L,
    meter: match job.owner.authority {
      DedicatedOrder(_) => "prepaid-video-job"
      PrivateWorkspace(_) => "private-workspace-video-job"
    },
    quantity: 1L,
    unit: "job",
    started_unix_ms: job.created_unix_ms,
    ended_unix_ms: terminal.max(job.created_unix_ms + 1L),
    observed_unix_ms: terminal.max(job.created_unix_ms + 1L),
  }
  self.commercial_mutex.acquire()
  defer self.commercial_mutex.release()
  let before = self.commercial_store.durable_snapshot()
  errdefer ignore(self.commercial_store.replace_from_durable_snapshot(before))
  ignore(self.commercial_store.ingest_usage(observation))
  self.persist_commercial_state()
  event_id
}

///|
async fn ApiService::media_owner(
  self : ApiService,
  headers : Map[String, String],
) -> (@media_jobs.Owner, @machinecommerce.MachineOrder?)? {
  guard self.api_key_authorization(headers, Inference, false) is Some(authority) else {
    return None
  }
  let (order, denied) = self.dedicated_order_binding(
    authority,
    None,
    @async.now(),
  )
  guard denied is None else { return None }
  guard order is Some(order) else {
    guard self.private_workspace_key_authorized(
        authority.key_id,
        authority.tenant_ref,
        authority.subject_ref,
        @async.now(),
      ) &&
      self.workspace_directory is Some(directory) else {
      return None
    }
    let workspace = directory.authorize_subject_for_tenant(
      authority.subject_ref,
      authority.tenant_ref,
      Developer,
      @async.now(),
    ) catch {
      _ => return None
    }
    return Some(
      (
        {
          tenant_ref: authority.tenant_ref,
          subject_ref: authority.subject_ref,
          organization_id: authority.organization_id,
          project_id: authority.project_id,
          authority: PrivateWorkspace(workspace.lease.lease_id),
        },
        None,
      ),
    )
  }
  guard order.requested_model_selector is Some(model) &&
    self.api_key_authorization(headers, Inference, model~, false) is Some(_) else {
    return None
  }
  Some(
    (
      {
        tenant_ref: authority.tenant_ref,
        subject_ref: authority.subject_ref,
        organization_id: authority.organization_id,
        project_id: authority.project_id,
        authority: DedicatedOrder(order.order_id),
      },
      Some(order),
    ),
  )
}

///|
fn media_failure(error : Error) -> HttpReply {
  match error {
    @media_jobs.JobError::NotFound =>
      api_error(404, "VideoNotFound", "video is unavailable", false)
    @media_jobs.JobError::Conflict =>
      api_error(
        409, "IdempotencyConflict", "request key was already used with different settings",
        false,
      )
    @media_jobs.JobError::Busy =>
      api_error(
        409, "VideoCapacityBusy", "the authorized resource has an unfinished or unreconciled job",
        true,
      )
    @media_jobs.JobError::CapacityExceeded =>
      api_error(
        503, "VideoHistoryFull", "video history requires operator maintenance", false,
      )
    @media_provider.ProviderError::InvalidRequest =>
      api_error(
        400, "InvalidVideoRequest", "video settings are outside the approved profile",
        false,
      )
    @media_runtime.RuntimeError::Unauthorized =>
      api_error(403, "VideoAccessEnded", "video authority has ended", false)
    @media_runtime.RuntimeError::AuthorityUnavailable =>
      api_error(
        503, "VideoAuthorityUnavailable", "video authority could not be confirmed; retain the same request key",
        true,
      )
    @media_runtime.RuntimeError::ContentUnavailable =>
      api_error(
        409, "VideoContentUnavailable", "video is incomplete or expired", false,
      )
    _ =>
      api_error(
        503, "VideoUnavailable", "video operation could not be confirmed; do not resubmit with a new request key",
        true,
      )
  }
}

///|
async fn ApiService::handle_media(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.media is Some(media) else {
    return api_error(
      503, "MediaNotConfigured", "a qualified video deployment is not configured",
      false,
    )
  }
  guard self.media_owner(headers) is Some((owner, order)) else {
    return api_error(
      403, "VideoEntitlementRequired", "an administrator-granted private workspace or active paid model order and scoped API key are required",
      false,
    )
  }
  try {
    if path == "/v1/videos" && verb == Post {
      guard header(headers, "idempotency-key") is Some(key) &&
        @contracts.valid_identifier(key) else {
        return api_error(
          400, "IdempotencyKeyRequired", "provide a stable Idempotency-Key for this generation",
          false,
        )
      }
      let candidates = self
        .media_all_bindings(media.bindings, media.templates)
        .filter(binding => {
          order.map_or(true, order => {
            order.target_deployment_ref == Some(binding.deployment_id) &&
            order.requested_model_selector == Some(binding.profile.model)
          })
        })
      let active : Array[MediaBinding] = []
      let mut request_matches = order is Some(_)
      for binding in candidates {
        if order is None {
          let matches = try {
            ignore(
              @media_provider.VideoRequest::decode(
                binding.profile,
                header(headers, "content-type").unwrap_or("application/json"),
                body,
              ),
            )
            true
          } catch {
            _ => false
          }
          if !matches {
            continue
          }
          request_matches = true
        }
        if self.api_key_authorization(
            headers,
            Inference,
            model=binding.profile.model,
            false,
          )
          is Some(_) &&
          self.media_authorized(owner, binding.profile.model, binding) {
          active.push(binding)
        }
      }
      if !request_matches && candidates.length() > 0 {
        return api_error(
          400, "InvalidVideoRequest", "video settings are outside the approved profiles",
          false,
        )
      }
      guard active.length() == 1 else {
        if active.is_empty() {
          return api_error(
            503, "VideoUnavailable", "no authorized ready video runtime is currently available; retain the same request key",
            true,
          )
        }
        return api_error(
          503, "MediaProfileUnavailable", "the selected model does not have exactly one authorized active media profile",
          false,
        )
      }
      let binding = active[0]
      let request = @media_provider.VideoRequest::decode(
        binding.profile,
        header(headers, "content-type").unwrap_or("application/json"),
        body,
      )
      guard self.workspace_directory is Some(directory) else {
        raise @media_runtime.RuntimeError::Unauthorized
      }
      let workspace = directory.authorize_subject_for_tenant(
        owner.subject_ref,
        owner.tenant_ref,
        Developer,
        @async.now(),
      )
      guard workspace.lease.limits.capabilities
        .filter(limit => limit.capability == VideoGenerate)
        .get(0)
        is Some(limit) &&
        request.within_workspace_budget(
          limit.max_input_units_per_request,
          limit.max_output_units_per_request,
        ) else {
        return api_error(
          403, "WorkspaceVideoBudgetExceeded", "video exceeds the workspace capability budget",
          false,
        )
      }
      if !self.commercial_project_exists(
          owner.organization_id,
          owner.project_id,
        ) {
        return api_error(
          409, "CommercialAttributionRequired", "video usage requires an active project",
          false,
        )
      }
      match
        self.api_key_check(
          headers,
          Inference,
          None,
          Some(request.model()),
          true,
        ) {
        KeyAuthorized(_) => ()
        KeyQuotaExceeded =>
          return api_error(
            429, "QuotaExceeded", "request quota is exhausted", false,
          )
        KeyDenied =>
          return api_error(
            403, "VideoAccessEnded", "video authority has ended", false,
          )
      }
      let now = @async.now()
      let expires = order.map_or(workspace.lease.expires_unix_ms, order => {
        (order.active_started_unix_ms.unwrap() + order.duration_seconds * 1000L).min(
          workspace.lease.expires_unix_ms,
        )
      })
      let deadline = (now + 7200000L).min(expires)
      let job = media.runtime.submit(
        owner,
        key,
        request,
        binding.identity(),
        deadline,
        now + 86400000L,
        maximum_active=limit.max_concurrent_requests,
        maximum_per_hour=limit.max_requests_per_hour,
        execution_context=binding.execution_context(),
      )
      return json_reply(200, job.public_view(@async.now()))
    }
    if path.has_prefix("/v1/videos/") {
      let id = path["/v1/videos/".length():].to_owned()
      if !@contracts.valid_identifier(id) || !id.has_prefix("video-") {
        return api_error(404, "VideoNotFound", "video is unavailable", false)
      }
      let stored = media.jobs.get(id, owner)
      guard self.api_key_authorization(
          headers,
          Inference,
          model=stored.model,
          false,
        )
        is Some(_) else {
        return api_error(404, "VideoNotFound", "video is unavailable", false)
      }
      if verb == Get {
        return json_reply(
          200,
          media.runtime.get(id, owner).public_view(@async.now()),
        )
      }
      if verb == Delete {
        let job = media.runtime.cancel(id, owner)
        let deleted = job.state == Cancelled || job.state == Expired
        return json_reply(if deleted { 200 } else { 409 }, {
          "id": id,
          "object": "video.deleted",
          "deleted": deleted,
          "status": if deleted {
            "deleted"
          } else {
            "cancelling"
          },
        })
      }
    }
    api_error(404, "NotFound", "unknown video operation", false)
  } catch {
    error => media_failure(error)
  }
}

///|
async fn ApiService::serve_media_content(
  self : ApiService,
  request : @http.Request,
  connection : @http.ServerConnection,
) -> Unit {
  if self.reconciliation_only || !self.store.current_epoch_is_durable() {
    return send_listener_reply(
      connection,
      api_error(
        503, "MediaUnavailable", "controller is not serving media", true,
      ),
    )
  }
  guard self.media is Some(media) &&
    self.media_owner(request.headers) is Some((owner, _)) else {
    return send_listener_reply(
      connection,
      api_error(
        403, "VideoAccessEnded", "video authority is unavailable", false,
      ),
    )
  }
  let id = request.path["/v1/videos/".length():request.path.length() -
  "/content".length()].to_owned()
  let mut started = false
  try {
    let stored = media.jobs.get(id, owner)
    guard self.api_key_authorization(
        request.headers,
        Inference,
        model=stored.model,
        false,
      )
      is Some(_) else {
      raise @media_runtime.RuntimeError::Unauthorized
    }
    ignore(
      media.runtime.content(id, owner, 1073741824L, bytes => {
        if self.media_owner(request.headers) is None ||
          self.api_key_authorization(
            request.headers,
            Inference,
            model=stored.model,
            false,
          )
          is None {
          raise @media_runtime.RuntimeError::Unauthorized
        }
        if !started {
          connection.send_response(200, "OK", extra_headers={
            "content-type": "video/mp4",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
          })
          started = true
        }
        connection.write(bytes)
      }),
    )
    connection.end_response()
  } catch {
    error => {
      if started {
        raise Failure("media download interrupted")
      }
      send_listener_reply(connection, media_failure(error))
    }
  }
}

///|
pub async fn ApiService::reconcile_media_jobs(self : ApiService) -> (Int, Int) {
  guard self.media is Some(media) else { return (0, 0) }
  if self.reconciliation_only || !self.store.current_epoch_is_durable() {
    return (0, 1)
  }
  media.runtime.reconcile()
}

///|
priv struct MediaReconciliationIntent {
  provider_job_id : String
  expected_request_digest : String
  evidence_ref : String
} derive(FromJson)

///|
async fn ApiService::handle_media_operator(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator_id) else {
    return api_error(
      403, "OperatorRequired", "operator authority is required", false,
    )
  }
  guard self.media is Some(media) else {
    return api_error(
      503, "MediaNotConfigured", "media is not configured", false,
    )
  }
  try {
    let snapshot = media.jobs.snapshot()
    if verb == Get && path == "/v1/media/operator/jobs" {
      let pending = snapshot.jobs.filter(job => {
        !job.execution_terminal ||
        job.usage_receipt is None ||
        job.state == Cancelling
      })
      let page = pending
        .iter()
        .take(100)
        .map(job => {
          (
            {
              "id": job.job_id,
              "state": job.state.to_json(),
              "order_id": match job.owner.authority {
                DedicatedOrder(id) => id.to_json()
                PrivateWorkspace(_) => (null : Json)
              },
              "workspace_lease_id": match job.owner.authority {
                PrivateWorkspace(id) => id.to_json()
                DedicatedOrder(_) => (null : Json)
              },
              "request_digest": job.request_digest,
              "provider_binding": job.deployment_id,
            } : Json)
        })
        .to_array()
      return json_reply(200, {
        "data": page.to_json(),
        "truncated": pending.length() > 100,
      })
    }
    let prefix = "/v1/media/operator/jobs/"
    let suffix = ":reconcile"
    if verb == Post && path.has_prefix(prefix) && path.has_suffix(suffix) {
      let id = path[prefix.length():path.length() - suffix.length()].to_owned()
      guard snapshot.jobs.filter(job => job.job_id == id).get(0) is Some(job) else {
        return api_error(404, "VideoNotFound", "video is unavailable", false)
      }
      let intent : MediaReconciliationIntent = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "invalid reconciliation intent", false,
          )
      }
      if !@contracts.valid_identifier(intent.evidence_ref) ||
        intent.expected_request_digest != job.request_digest {
        return api_error(
          409, "MediaEvidenceMismatch", "the operator must attest the exact persisted request",
          false,
        )
      }
      self.operator_audit_as(
        operator_id,
        "media.reconciliation.requested",
        job.job_id,
        intent.evidence_ref,
      )
      let updated = media.runtime.reconcile_submission(
        job.job_id,
        job.owner,
        intent.provider_job_id,
      )
      self.operator_audit_as(
        operator_id,
        "media.reconciliation.attached",
        job.job_id,
        intent.evidence_ref,
      )
      return json_reply(200, updated.public_view(@async.now()))
    }
    api_error(404, "NotFound", "unknown media operator operation", false)
  } catch {
    error => media_failure(error)
  }
}
