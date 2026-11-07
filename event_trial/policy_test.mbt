///|
fn policy() -> @event_trial.Policy {
  {
    event_id: "weekend",
    title: "Weekend trial",
    starts_unix_ms: 1000L,
    expires_unix_ms: 86401000L,
    maximum_users: 30,
    maximum_requests: 200L,
    allowed_models: ["text.default"],
    node_ids: ["a", "b", "c", "d"],
    per_node_concurrency: 2,
    max_input_bytes: None,
    max_output_tokens: None,
    registration_open: true,
  }
}

///|
test "legacy event without an input budget retains 8 KiB" {
  let value = Json(policy())
  if value is Object(fields) {
    fields.remove("max_input_bytes")
    fields.remove("max_output_tokens")
  }
  let restored : @event_trial.Policy = @json.from_json(value)
  assert_eq(restored.input_budget(), 8192)
  assert_eq(restored.output_budget(), 1024)
  assert_eq(
    { ..restored, max_output_tokens: Some(8192), }.output_budget(),
    8192,
  )
  assert_false({ ..restored, max_output_tokens: Some(0), }.valid())
  assert_false({ ..restored, max_output_tokens: Some(131073), }.valid())
}

///|
test "event policy has a bounded half open window and one to four distinct replicas" {
  let p = policy()
  assert_true(p.valid())
  assert_false(p.accepting(999L))
  assert_true(p.accepting(1000L))
  assert_false(p.accepting(p.expires_unix_ms))
  assert_false({ ..p, registration_open: false, }.accepting(2000L))
  assert_false({ ..p, node_ids: ["a", "b", "c", "c"], }.valid())
  assert_true({ ..p, node_ids: ["a", "b"], }.valid())
  assert_true({ ..p, node_ids: ["a", "b", "c"], }.valid())
  assert_false({ ..p, node_ids: [], }.valid())
  assert_false({ ..p, node_ids: ["a", "b", "c", "d", "e"], }.valid())
  assert_false({ ..p, allowed_models: ["text.default", "other"], }.valid())
  assert_true({ ..p, maximum_users: 0, }.valid())
  assert_true({ ..p, per_node_concurrency: 0, }.valid())
  assert_true({ ..p, per_node_concurrency: 32, }.valid())
  assert_false({ ..p, per_node_concurrency: -1, }.valid())
  assert_eq(p.input_budget(), 8192)
  assert_true({ ..p, max_input_bytes: Some(32768), }.valid())
  assert_false({ ..p, max_input_bytes: Some(65537), }.valid())
  assert_false(
    { ..p, expires_unix_ms: p.starts_unix_ms + 2592000001L, }.valid(),
  )
}

///|
test "uncapped event routing balances more than 32 active calls without inventing a ceiling" {
  let router = @event_trial.Router::new()
  let nodes = policy().node_ids
  for i in 0..<128 {
    assert_eq(router.reserve("call-\{i}", nodes, 0), Some(nodes[i % 4]))
  }
  assert_eq(router.reserve("call-0", nodes, 0), None)
  assert_eq(router.reserve("bad-limit", nodes, -1), None)
  assert_eq(router.reserve("empty", [], 0), None)
  router.release("call-1")
  assert_eq(router.reserve("replacement", nodes, 0), Some("b"))
  // An uncapped policy does not admit work to an unhealthy replica.
  for i in 0..<12 {
    let chosen = router.reserve("degraded-\{i}", ["b", "c", "d"], 0)
    assert_true(chosen is Some(_))
    assert_false(chosen == Some("a"))
  }
}

///|
test "ongoing enrollment has no artificial date or participant ceiling but each grant is seven days" {
  let p = {
    ..policy(),
    expires_unix_ms: 0L,
    maximum_users: 0,
    maximum_requests: 0L,
  }
  assert_true(p.valid())
  assert_true({ ..p, maximum_users: 100000, }.valid())
  assert_true(p.accepting(9000000000000L))
  assert_eq(p.grant_expires(1000L), 604801000L)
  assert_eq(p.grant_expires(2000L), 604802000L)
  assert_true(
    p.overlaps({
      ..policy(),
      starts_unix_ms: 9000000000000L,
      expires_unix_ms: 9000000001000L,
    }),
  )
  assert_false({ ..p, registration_open: false, }.accepting(2000L))
  assert_false({ ..p, maximum_users: -1, }.valid())
  assert_false({ ..p, maximum_requests: -1L, }.valid())
}

///|
test "least inflight balancing pins streams and bounds per replica capacity" {
  let router = @event_trial.Router::new()
  let nodes = policy().node_ids
  for i in 0..<8 {
    assert_eq(router.reserve("request-\{i}", nodes, 2), Some(nodes[i % 4]))
  }
  assert_eq(router.reserve("overflow", nodes, 2), None)
  assert_eq(router.reserve("request-0", nodes, 2), None)
  router.release("request-1")
  assert_eq(router.reserve("replacement", nodes, 2), Some("b"))
  router.release("request-0")
  // Unhealthy a is omitted: its free slot must not attract new work.
  assert_eq(router.reserve("no-fallback", ["b", "c", "d"], 2), None)
  router.release("replacement")
  router.release("replacement")
  assert_eq(router.reserve("resumed", ["b", "c", "d"], 2), Some("b"))
}
