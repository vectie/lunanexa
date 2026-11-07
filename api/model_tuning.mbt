///|
fn cache_usage_only(output : Json) -> Json? {
  match output {
    { "cached_input_tokens": Number(n, ..), .. } if n >= 0.0 && n == n.round() =>
      Some({ "cached_input_tokens": Json(n) })
    _ => None
  }
}

///|
/// Only a bounded prefix digest is retained in process memory. Tenant and
/// generation scope prevent affinity reuse across tenants or model restarts.
fn ApiService::event_prefix_key(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
) -> String {
  guard self.model_pool is Some(pool) &&
    pool.active() &&
    pool.tuning().cache_aware_routing &&
    (
      request.data_policy.allow_cache ||
      request.payload is { "runtime_prefix_cache": true, .. }
    ) else {
    return ""
  }
  let text = match request.payload {
    {
      "messages": Array(
        [{ "role": String(role), "content": String(text), .. }, ..]
      ),
      ..
    } => role + ":" + text
    { "input": String(text), .. }
    | { "prompt": String(text), .. }
    | String(text) => text
    _ => ""
  }
  if text.length() < 1024 {
    return ""
  }
  sha256_digest(
    Json([
      request.tenant_ref,
      request.model_selector,
      pool.generation().to_string(),
      text[:text.length().min(4096)].to_owned(),
    ]).stringify(),
  )
}

///|
async fn ApiService::apply_model_tuning(
  self : ApiService,
  pool : @model_pool.Pool,
  body : String,
) -> Unit {
  guard pool.selection() is Some(selection) else {
    fail("请先切换目标模型")
  }
  let tuning : @model_pool.Tuning = @json.from_json(@json.parse(body))
  for target in pool.selected_targets() {
    if !self.pool_cache_ready(target.node_id, selection.artifact.digest) {
      fail("请等待选中节点权重全部校验完成")
    }
  }
  let previous = pool.tuning()
  pool.set_tuning(tuning)
  // Routing-only changes do not restart model workers or discard warm caches.
  let runtime_changed = previous.prefix_caching != tuning.prefix_caching ||
    previous.chunked_prefill != tuning.chunked_prefill ||
    previous.max_num_batched_tokens != tuning.max_num_batched_tokens
  for target in pool.selected_targets() {
    // Retry an interrupted selected-replica update even when intent is unchanged.
    if runtime_changed || !pool.configuration(target.node_id).ready {
      pool.switch_replica(target.node_id)
    }
  }
}
