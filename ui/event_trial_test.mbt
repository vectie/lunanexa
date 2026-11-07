///|
test "event controls disclose draft capacity and no privilege elevation" {
  let state = {
    ..@ui.default_state(),
    route: Users,
    operator_authenticated: true,
    event_trial: { ..@ui.empty_event_trial_panel(), events: Some([]), },
  }
  let html = @ui.render(state)
  assert_true(html.contains("Event trial mode"))
  assert_true(html.contains("Save draft (registration closed)"))
  assert_true(html.contains("Beijing"))
  assert_true(html.contains("Saving does not change concurrency"))
  assert_true(html.contains("SSH, admin roles or machine access"))
  assert_true(html.contains("0/4 selected"))
  assert_true(html.contains("event-starts"))
  assert_true(html.contains("0 = no event cap"))
  assert_true(html.contains("Input payload bytes (not tokens; max 65536)"))
  assert_eq(state.event_trial.draft.max_input_bytes, "8192")
  assert_eq(state.event_trial.draft.per_node_concurrency, "0")
}

///|
test "two-node event uses actual denominator and publishes only the public registration URL" {
  let base = @ui.default_state()
  let policy : @event_trial.Policy = {
    event_id: "test-two-node",
    title: "Weekend trial",
    starts_unix_ms: 1L,
    expires_unix_ms: 100000L,
    maximum_users: 30,
    maximum_requests: 200L,
    max_input_bytes: Some(8192),
    max_output_tokens: None,
    allowed_models: ["text.qwen"],
    node_ids: ["node-a", "node-b"],
    per_node_concurrency: 0,
    registration_open: false,
  }
  let state = {
    ..base,
    route: Users,
    operator_authenticated: true,
    event_trial: {
      ..@ui.empty_event_trial_panel(),
      public_origin: "https://example.test:8443",
      now_unix_ms: 100L,
      events: Some([
        {
          policy,
          registered_users: 0,
          ready_nodes: ["node-a", "node-b"],
          blockers: [],
        },
      ]),
    },
  }
  let html = @ui.render(state)
  assert_true(html.contains("2/2 replicas ready"))
  assert_false(html.contains("2/4 replicas ready"))
  assert_true(html.contains("https://example.test:8443/user/?trial=event"))
  assert_true(html.contains("Public event registration QR"))
  assert_false(html.contains("api_key"))
  assert_false(html.contains("?trial=wifi"))
  let editing = {
    ..state,
    event_trial: {
      ..state.event_trial,
      editing: true,
      draft: { ..state.event_trial.draft, event_id: policy.event_id, },
    },
  }
  assert_true(
    @ui.render(editing).contains("Save changes (keep registration state)"),
  )
}
