///|
test "cache affinity is soft and cannot impose a concurrency limit" {
  let router = @event_trial.Router::new()
  let nodes = ["a", "b", "c", "d"]
  assert_eq(
    router.reserve("warm", nodes, 0, prefix="tenant-model-prefix", now=1L),
    Some("a"),
  )
  router.release("warm")
  assert_eq(
    router.reserve("repeat", nodes, 0, prefix="tenant-model-prefix", now=2L),
    Some("a"),
  )
  let counts : Map[String, Int32] = { "a": 1 }
  for i in 1..<32 {
    let node = router
      .reserve("load-\{i}", nodes, 0, prefix="tenant-model-prefix", now=3L)
      .unwrap()
    counts[node] = counts.get(node).unwrap_or(0) + 1
  }
  assert_eq(counts.values().fold(init=0, (a, b) => a + b), 32)
  assert_true(counts.values().all(n => n >= 7 && n <= 9))
}

///|
test "expired or unavailable cache preference never prevents healthy fallback" {
  let router = @event_trial.Router::new()
  assert_eq(
    router.reserve("warm", ["a", "b"], 0, prefix="p", now=1L),
    Some("a"),
  )
  router.release("warm")
  assert_eq(
    router.reserve("expired", ["a", "b"], 0, prefix="p", now=300002L),
    Some("b"),
  )
  assert_eq(
    router.reserve("fallback", ["c"], 0, prefix="p", now=300003L),
    Some("c"),
  )
}
