///|
test "event form uses Beijing time independently of browser timezone" {
  assert_eq(event_time_ms("2026-10-25T00:00"), "1792857600000")
  assert_eq(event_local_time("1792857600000"), "2026-10-25T00:00")
  assert_eq(event_time_ms("invalid"), "")
  let draft = {
    ..@ui.empty_event_trial_panel().draft,
    starts: "2026-10-24T09:00",
    expires: "2026-10-25T23:59",
    model: "text.default",
    nodes: ["a", "b", "c", "d"],
  }
  let policy = event_draft_policy(draft)
  assert_true(policy.valid())
  assert_false(policy.registration_open)
  assert_eq(policy.maximum_users, 30)
  assert_eq(policy.per_node_concurrency, 0)
  assert_eq(policy.input_budget(), 8192)
  assert_eq(policy.output_budget(), 8192)
  assert_eq(
    event_draft_policy({ ..draft, max_output_tokens: "16384", }).output_budget(),
    16384,
  )
  assert_eq(
    event_draft_policy({ ..draft, max_input_bytes: "32768", }).input_budget(),
    32768,
  )
  assert_eq(event_draft_policy(draft).event_id, policy.event_id)
  let ongoing = event_draft_policy({
    ..draft,
    expires: "",
    maximum_users: "0",
    maximum_requests: "0",
  })
  assert_true(ongoing.valid())
  assert_eq(ongoing.expires_unix_ms, 0L)
  assert_eq(ongoing.grant_expires(1000L), 604801000L)
}
