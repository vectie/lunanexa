///|
priv struct ModelPoolConfig {
  kubernetes_origin : String
  token_file : String
  ca_file : String
  namespace_name : String
  targets : Array[@model_pool.Target]
  state_path : String
  runtime_image : String
  profiles : Array[@model_pool.RuntimeProfile]?
} derive(FromJson)

///|
fn supported_pool_model(
  pool : @model_pool.Pool,
  model : @contracts.ModelRecord,
) -> Bool {
  pool.supports_artifact(model.artifact.digest, model.compatible_architectures) &&
  model.artifact.uri.has_prefix("modelstore://") &&
  model.state == Approved
}

///|
pub async fn ApiService::with_model_pool_json(
  self : ApiService,
  raw : String?,
) -> ApiService {
  guard raw is Some(raw) else { return self }
  let config : ModelPoolConfig = @json.from_json(@json.parse(raw))
  let transport = @model_pool.authenticated_transport(
    config.kubernetes_origin,
    config.token_file,
    config.ca_file,
    config.namespace_name,
    config.targets,
  )
  if !config.runtime_image.contains("@sha256:") ||
    !self.event_text_routes.all(r => {
      config.runtime_image.has_suffix("@" + r.runtime.image_digest())
    }) {
    raise Failure(
      "model pool runtime must use the already configured pinned runtime image",
    )
  }
  let pool = @model_pool.Pool::open(
    transport,
    config.namespace_name,
    config.targets,
    config.state_path,
    runtime_image=config.runtime_image,
    profiles=config.profiles.unwrap_or([]),
  )
  if self.event_text_routes.length() != config.targets.length() ||
    !pool
    .targets()
    .all(t => self.event_text_routes.any(r => r.node_id == t.node_id)) {
    raise Failure("managed model pool must match the configured replicas")
  }
  if !pool.adopted() {
    pool.adopt()
  }
  { ..self, model_pool: Some(pool), }
}

///|
fn ApiService::selected_pool_route(
  self : ApiService,
  route : ExternalTextRoute,
  selection : @model_pool.Selection,
) -> ExternalTextRoute raise {
  let configured = self.with_external_text_route(
    selection.model_alias,
    route.tenant_ref,
    route.node_id,
    route.origin,
    selection.served_model,
    route.runtime.runtime_version(),
    route.runtime.image_digest(),
    selection.artifact.digest,
    credential=route.credential,
  )
  let selected = configured.external_text_route.unwrap()
  {
    ..selected,
    runtime: selected.runtime
    .with_thinking_disabled()
    .with_prefix_cache_isolation(),
  }
}

///|
fn ApiService::active_event_routes(
  self : ApiService,
) -> Array[ExternalTextRoute] raise {
  let routes = match self.model_pool {
    Some(pool) =>
      self.event_text_routes.filter(r => {
        pool.selected_targets().any(t => t.node_id == r.node_id)
      })
    None => self.event_text_routes
  }
  if self.model_pool is Some(pool) &&
    pool.active() &&
    pool.selection() is Some(selection) {
    routes.map(r => self.selected_pool_route(r, selection))
  } else {
    routes
  }
}

///|
async fn ApiService::pool_cache_ready(
  self : ApiService,
  node_id : String,
  digest : String,
) -> Bool {
  let now = @async.now()
  self.store
  .heartbeats()
  .any(h => {
    h.node_id == node_id &&
    h.state == Active &&
    event_heartbeat_time_blocker(
      h.timestamp_unix_ms,
      now,
      self.global_settings.control_timing,
    )
    is None &&
    (try {
      let values : Array[String] = @json.from_json(
        @json.parse(
          h.inventory.labels
          .get("lunanexa.io/verified-artifact-digests")
          .unwrap_or("[]"),
        ),
      )
      values.contains(digest)
    } catch {
      _ => false
    })
  })
}

///|
async fn ApiService::model_pool_view(
  self : ApiService,
  pool : @model_pool.Pool,
) -> Json {
  let replicas : Array[Json] = []
  let heartbeats = self.store.heartbeats()
  for target in pool.targets() {
    let selected = pool.selected_targets().contains(target)
    let configuration = pool.configuration(target.node_id) catch {
      _ => { speculative_tokens: -1, ready: false, }
    }
    let mut bytes = 0.0
    let mut total = 0.0
    let mut stage = 0.0
    if self.telemetry is Some(telemetry) {
      for sample in telemetry.snapshot().samples {
        if sample.node_id == target.node_id &&
          sample.deployment_id == "pool-cache-" + target.node_id {
          match sample.metric {
            "artifact_bytes_present" => bytes = sample.value
            "artifact_bytes_total" => total = sample.value
            "artifact_preparation_stage" => stage = sample.value
            _ => ()
          }
        }
      }
    }
    let capable = heartbeats.any(h => {
      h.node_id == target.node_id &&
      h.inventory.labels.get("lunanexa.io/artifact-preparation-v1") ==
      Some("true")
    })
    let (cached, ready) = match pool.selection() {
      Some(selection) => {
        let cached = self.pool_cache_ready(
          target.node_id,
          selection.artifact.digest,
        )
        let ready = if selected &&
          self.event_text_routes
          .iter()
          .find_first(r => r.node_id == target.node_id)
          is Some(route) {
          self.external_route_observation(
            self.selected_pool_route(route, selection),
          ).0
        } else {
          false
        }
        (cached, ready)
      }
      None => (false, false)
    }
    replicas.push({
      "node_id": target.node_id,
      "display_name": pool.node_name(target.node_id),
      "selected": selected,
      "paused": if selected {
        false
      } else {
        pool.paused(target.node_id) catch {
          _ => false
        }
      },
      "deployment": target.deployment,
      "can_prepare": capable,
      "cache_ready": cached,
      "switched": pool.switched().contains(target.node_id),
      "ready": ready && configuration.ready,
      "configuration_ready": configuration.ready,
      "speculative_tokens": configuration.speculative_tokens,
      "progress": if total > 0.0 {
        (if stage == 4.0 {
          "权重准备失败 · "
        } else if stage == 3.0 {
          "校验完成 · "
        } else {
          "正在准备 · "
        }) +
        "\{((bytes / total * 1000.0).round() / 10.0)}% · \{((bytes / 1073741824.0 * 10.0).round() / 10.0)}/\{((total / 1073741824.0 * 10.0).round() / 10.0)} GiB"
      } else {
        "等待节点上报准备进度"
      },
    })
  }
  let models : Array[String] = if self.registry is Some(registry) {
    let snapshot = registry.snapshot()
    snapshot.aliases
    .filter(a => {
      snapshot.models.any(m => {
        m.model_id == a.model_id &&
        m.version == a.version &&
        supported_pool_model(pool, m)
      })
    })
    .map(a => a.name)
  } else {
    []
  }
  {
    "adopted": pool.adopted(),
    "active": pool.active(),
    "generation": pool.generation(),
    "speculative_tokens": pool.speculative_tokens(),
    "tuning": Json(pool.tuning()),
    "model": pool.selection().map_or("", s => s.model_alias),
    "models": Json(models),
    "replicas": Json(replicas),
    "benchmark": Json(self.model_benchmark.map(b => b.report)),
    "baseline_benchmark": Json(
      self.model_benchmark.map_or(None, b => b.baseline),
    ),
  }
}

///|
/// Reuses the existing signed artifact gateway and node cache. No runtime is
/// launched and no GPU is allocated by this reserved preparation adapter.
async fn ApiService::prepare_model_pool(
  self : ApiService,
  pool : @model_pool.Pool,
) -> Unit {
  guard pool.selection() is Some(selection) &&
    self.registry is Some(registry) &&
    self.assignment_signing_secret != "" &&
    self.scheduler is Some(scheduler) else {
    raise Failure("model pool selection or node authority unavailable")
  }
  let now = @async.now()
  let heartbeats = self.store.heartbeats()
  let snapshot = registry.snapshot()
  guard snapshot.models.any(m => {
    m.model_id == selection.model_id &&
    m.version == selection.version &&
    m.artifact == selection.artifact &&
    m.state == Approved
  }) else {
    raise Failure("selected model is no longer approved")
  }
  for target in pool.selected_targets() {
    if self.exclusive_lease_store is Some(leases) &&
      leases.node_blocks_managed_placement(target.node_id) {
      raise Failure("a pool node has an active exclusive lease")
    }
    guard !scheduler.node_is_reserved(target.node_id) &&
      heartbeats.any(h => {
        h.node_id == target.node_id &&
        h.state == Active &&
        h.inventory.labels.get("lunanexa.io/artifact-preparation-v1") ==
        Some("true") &&
        event_heartbeat_time_blocker(
          h.timestamp_unix_ms,
          now,
          self.global_settings.control_timing,
        )
        is None
      }) else {
      raise Failure("selected agents must be ready for cache preparation")
    }
  }
  let assignments = self.store.assignments()
  let mut generation = 1L
  for a in assignments {
    generation = generation.max(a.generation + 1L)
  }
  for h in heartbeats {
    generation = generation.max(h.observed_generation + 1L)
  }
  for target in pool.selected_targets() {
    let id = "pool-cache-" + target.node_id
    if assignments.any(a => {
        a.assignment_id == id &&
        a.artifact.digest == selection.artifact.digest &&
        a.lease_expires_unix_ms > now + 43200000L
      }) {
      continue
    }
    let unsigned : @contracts.DesiredAssignment = {
      assignment_id: id,
      deployment_id: id,
      node_id: target.node_id,
      artifact: selection.artifact,
      runtime: {
        name: "lunanexa-artifact-preparation",
        version: "v1",
        image_digest: selection.artifact.digest,
        architectures: ["nvidia-sm121"],
        capabilities: [],
        supports_batching: false,
        supports_multi_node: false,
      },
      resources: {
        accelerator_count: 0,
        accelerator_memory_mib: 0,
        cpu_millis: 1000,
        memory_mib: 512,
      },
      devices: [],
      network: {
        allow_controller: true,
        allow_artifact_store: true,
        allowed_egress: [],
      },
      health: {
        readiness_path: "/health",
        interval_ms: 5000,
        failure_threshold: 3,
        termination_grace_ms: 5000,
      },
      data_policy: {
        classification: Internal,
        retention: Ephemeral,
        allow_cache: true,
        allow_training_reuse: false,
      },
      generation,
      controller_epoch: self.store.controller_epoch(),
      lease_expires_unix_ms: now + 86400000L,
      group: None,
      reservation: None,
      signature: "",
    }
    let signed = {
      ..unsigned,
      signature: @node.assignment_signature(
        unsigned,
        self.assignment_signing_secret,
      ),
    }
    self.with_audit_lock(() => {
      let audit = self.next_audit(
        "management-plane",
        "model-pool.prepare",
        id,
        "pending",
        "preparing",
        "accepted",
        "pool-cache:\{generation}",
        now,
      )
      self.store.commit_assignment(signed, audit)
    })
  }
}

///|
pub async fn ApiService::reconcile_model_pool(self : ApiService) -> Unit {
  guard self.model_pool is Some(pool) && pool.selection() is Some(_) else {
    return
  }
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  // Existing cache assignments pin the weights used by adopted live services.
  // Renewal uses the same authority; failures do not alter runtime deployments.
  self.prepare_model_pool(pool) catch {
    _ => ()
  }
}

///|
async fn ApiService::handle_model_pool(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !self.operator_authorized(headers) {
    return api_error(
      401, "Unauthenticated", "operator authority required", false,
    )
  }
  guard self.model_pool is Some(pool) else {
    return api_error(
      503, "PoolUnavailable", "model pool control is not configured", false,
    )
  }
  if verb == Get && path == "/v1/model-pool" {
    return json_reply(200, self.model_pool_view(pool))
  }
  if verb != Post {
    return api_error(405, "MethodNotAllowed", "unsupported pool action", false)
  }
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  let result : String? = try {
    if self.model_benchmark is Some(benchmark) &&
      ["queued", "running"].contains(benchmark.report.status) {
      raise Failure("测速运行中，请完成后再修改模型池")
    }
    match path {
      "/v1/model-pool:scope" => {
        guard @json.parse(body) is { "node_ids": nodes, "names": names, .. } else {
          fail("请选择参与节点并填写显示名称")
        }
        let nodes : Array[String] = @json.from_json(nodes)
        let names : Map[String, String] = @json.from_json(names)
        self.claim_pool_services(pool, nodes, true)
        pool.select_nodes(nodes, names)
        let excluded = pool.targets().filter(t => !nodes.contains(t.node_id))
        if excluded.any(t => self.event_trial_router.in_flight(t.node_id) > 0) {
          fail(
            "路由范围已更新；退出节点仍有请求执行，待其结束后再次应用以释放模型。不会中断回答。",
          )
        }
        for target in excluded {
          self.claim_pool_services(pool, [target.node_id], false)
          pool.pause_excluded(target.node_id)
        }
      }
      "/v1/model-pool:tuning" => {
        self.claim_pool_services(
          pool,
          pool.selected_targets().map(t => t.node_id),
          true,
        )
        self.apply_model_tuning(pool, body)
      }
      "/v1/model-pool:benchmark" => {
        let profile = match @json.parse(body) {
          { "profile": String(p), .. } => p
          _ => "short"
        }
        self.start_model_benchmark(profile~)
      }
      "/v1/model-pool:speculative" => {
        self.claim_pool_services(
          pool,
          pool.selected_targets().map(t => t.node_id),
          true,
        )
        guard @json.parse(body) is { "speculative_tokens": Number(n, ..), .. } &&
          n >= 0.0 &&
          n <= 5.0 &&
          n == n.round() else {
          raise Failure("请选择关闭或 1–5 个 MTP 草稿 token")
        }
        guard pool.selection() is Some(selection) else {
          raise Failure("请先准备并切换目标模型")
        }
        for target in pool.selected_targets() {
          if !self.pool_cache_ready(target.node_id, selection.artifact.digest) {
            raise Failure("请等待选中节点权重全部校验完成")
          }
        }
        pool.set_speculative_tokens(n.to_int())
        for target in pool.selected_targets() {
          pool.switch_replica(target.node_id)
        }
      }
      "/v1/model-pool:adopt" => pool.adopt()
      "/v1/model-pool:prepare" => {
        guard @json.parse(body) is { "model": String(name), .. } &&
          self.registry is Some(registry) else {
          raise Failure("select an approved model alias")
        }
        let snapshot = registry.snapshot()
        guard snapshot.aliases.iter().find_first(a => a.name == name)
          is Some(alias_record) &&
          snapshot.models
          .iter()
          .find_first(m => {
            m.model_id == alias_record.model_id &&
            m.version == alias_record.version &&
            supported_pool_model(pool, m)
          })
          is Some(model) else {
          raise Failure("approved model alias and runtime profile unavailable")
        }
        pool.select({
          model_id: model.model_id,
          version: model.version,
          model_alias: name,
          served_model: name,
          artifact: model.artifact,
        })
        self.prepare_model_pool(pool)
      }
      "/v1/model-pool:switch" => {
        self.claim_pool_services(
          pool,
          pool.selected_targets().map(t => t.node_id),
          true,
        )
        guard pool.selection() is Some(selection) else {
          raise Failure("prepare model weights first")
        }
        for target in pool.selected_targets() {
          if !self.pool_cache_ready(target.node_id, selection.artifact.digest) {
            raise Failure("wait for verified weights on selected nodes")
          }
        }
        for target in pool.selected_targets() {
          pool.switch_replica(target.node_id)
        }
      }
      "/v1/model-pool:activate" => {
        guard pool.selection() is Some(selection) else {
          raise Failure("no selected model")
        }
        for
          route in self.event_text_routes.filter(r => {
            pool.selected_targets().any(t => t.node_id == r.node_id)
          }) {
          if !pool.configuration(route.node_id).ready ||
            !self.external_route_observation(
              self.selected_pool_route(route, selection),
            ).0 {
            raise Failure("wait for selected new model endpoints")
          }
        }
        pool.activate()
      }
      "/v1/model-pool:rollback" => {
        self.claim_pool_services(
          pool,
          pool.selected_targets().map(t => t.node_id),
          true,
        )
        pool.rollback()
      }
      _ => raise Failure("unsupported pool action")
    }
    None
  } catch {
    Failure(message) => Some(message)
    @model_pool.PoolError::InvalidDeployment =>
      Some(
        "existing deployment shape does not match the configured vLLM adapter",
      )
    @model_pool.PoolError::Unavailable =>
      Some("Kubernetes model-service update unavailable; refresh and retry")
    _ => Some("model pool operation did not complete; refresh before retrying")
  }
  if result is Some(message) {
    return api_error(409, "PoolNotReady", message, true)
  }
  self.operator_audit_as(
    self.operator_identity(headers).unwrap(),
    path,
    "model-replicas:" + pool.selected_targets().map(t => t.node_id).join(","),
    "pool:\{pool.generation()}",
  )
  json_reply(200, self.model_pool_view(pool))
}
