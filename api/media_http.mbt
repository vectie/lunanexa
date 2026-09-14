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
  "media-" +
  digest_hex(
    (
      {
        "deployment": self.deployment_id,
        "generation": self.deployment_generation.to_json(),
        "node": self.node_id,
        "origin": self.origin,
        "profile": self.profile.to_json(),
      } : Json).stringify(),
  )
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
    let probe : MediaBinding = {
      deployment_id: "validation",
      deployment_generation: 1L,
      node_id: template.node_id,
      origin: template.origin,
      bearer: template.bearer,
      profile: template.profile,
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
        result.push({
          deployment_id: operation.deployment_id,
          deployment_generation: operation.generation,
          node_id: template.node_id,
          origin: template.origin,
          bearer: template.bearer,
          profile: template.profile,
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
      guard self
        .media_all_bindings(bindings, templates)
        .filter(binding => binding.identity() == identity)
        .get(0)
        is Some(binding) else {
        return false
      }
      self.media_authorized(owner, model, binding)
    },
    job => {
      guard self
        .media_all_bindings(bindings, templates)
        .filter(binding => binding.identity() == job.deployment_id)
        .get(0)
        is Some(binding) else {
        raise Failure("media binding unavailable")
      }
      self.settle_media_job(job, binding)
    },
  )
  { ..self, media: Some({ jobs, runtime, bindings, templates, }), }
}

///|
async fn ApiService::media_authorized(
  self : ApiService,
  owner : @media_jobs.Owner,
  model : String,
  binding : MediaBinding,
) -> Bool {
  if self.reconciliation_only || !self.store.current_epoch_is_durable() {
    return false
  }
  let now = @async.now()
  guard self.machine_commerce_store is Some(machine) &&
    machine.order(owner.order_id) is Some(order) &&
    order.offering_kind == DedicatedEndpoint &&
    order.state == Active &&
    order.tenant_ref == owner.tenant_ref &&
    order.organization_id == owner.organization_id &&
    order.project_id == owner.project_id &&
    order.purchaser_subject_ref == owner.subject_ref &&
    order.requested_model_selector == Some(model) &&
    model == binding.profile.model &&
    order.target_deployment_ref == Some(binding.deployment_id) &&
    order.active_started_unix_ms.map_or(false, started => {
      now < started + order.duration_seconds * 1000L
    }) else {
    return false
  }
  guard self.deployment_store is Some(deployments) &&
    deployments.deployment(binding.deployment_id) is Some(operation) &&
    operation.state == Ready &&
    operation.generation == binding.deployment_generation &&
    operation.plan.template.map_or(false, template => {
      template.capability == VideoGenerate
    }) &&
    operation.plan.replicas.length() == 1 &&
    operation.plan.replicas[0].node_id == binding.node_id else {
    return false
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
  guard self.portal_store is Some(portal) &&
    self.contract_document_store is Some(contracts) &&
    contracts.has_effective_master_lease(
      owner.tenant_ref,
      owner.subject_ref,
      now,
    ) else {
    return false
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
async fn ApiService::settle_media_job(
  self : ApiService,
  job : @media_jobs.StoredJob,
  binding : MediaBinding,
) -> String {
  guard job.execution_terminal && job.terminal_unix_ms is Some(terminal) else {
    raise Failure("media job is not terminal")
  }
  // This counts requests on already-paid capacity. It neither invents GPU time
  // nor rates it again as shared token/accelerator usage.
  let event_id = "media-usage-" + digest_hex(job.job_id)
  let observation : @commercial.UsageObservation = {
    event_id,
    organization_id: job.owner.organization_id,
    project_id: job.owner.project_id,
    actor_ref: job.owner.subject_ref,
    workload_id: job.job_id,
    node_id: binding.node_id,
    lease_epoch: 0L,
    meter: "prepaid-video-job",
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
) -> (@media_jobs.Owner, @machinecommerce.MachineOrder)? {
  guard self.api_key_authorization(headers, Inference, false) is Some(authority) else {
    return None
  }
  let (order, denied) = self.dedicated_order_binding(
    authority,
    None,
    @async.now(),
  )
  guard denied is None && order is Some(order) else { return None }
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
        order_id: order.order_id,
      },
      order,
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
        409, "VideoCapacityBusy", "the dedicated order has an unfinished or unreconciled job",
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
      403, "DedicatedVideoOrderRequired", "an active paid model order and scoped API key are required",
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
          order.target_deployment_ref == Some(binding.deployment_id) &&
          order.requested_model_selector == Some(binding.profile.model)
        })
      let active : Array[MediaBinding] = []
      for binding in candidates {
        if self.media_authorized(owner, binding.profile.model, binding) {
          active.push(binding)
        }
      }
      guard active.length() == 1 else {
        return api_error(
          503, "MediaProfileUnavailable", "the paid deployment does not have exactly one active media profile",
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
          409, "CommercialAttributionRequired", "the order requires an active commercial project",
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
      let expires = order.active_started_unix_ms.unwrap() +
        order.duration_seconds * 1000L
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
      )
      return json_reply(200, job.public_view(@async.now()))
    }
    if path.has_prefix("/v1/videos/") {
      let id = path["/v1/videos/".length():].to_owned()
      if !@contracts.valid_identifier(id) || !id.has_prefix("video-") {
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
    ignore(
      media.runtime.content(id, owner, 1073741824L, bytes => {
        if self.media_owner(request.headers) is None {
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
              "order_id": job.owner.order_id,
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
