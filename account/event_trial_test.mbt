///|
async test "event grants are atomic capped fixed expiry durable and distinct from normal trials" {
  let directory = @fs.tmpdir(prefix="event-policy-test-")
  let secret = "event-account-test-secret-at-least-32-bytes"
  let store = @account.AccountStore::open("\{directory}/accounts.json", secret)
  let event : @event_trial.Policy = {
    event_id: "weekend",
    title: "Weekend",
    starts_unix_ms: 100000L,
    expires_unix_ms: 300000L,
    maximum_users: 1,
    maximum_requests: 2L,
    allowed_models: ["text.default"],
    node_ids: ["a", "b", "c", "d"],
    per_node_concurrency: 1,
    max_input_bytes: None,
    max_output_tokens: None,
    registration_open: true,
  }
  ignore(store.put_event({ ..event, registration_open: false, }))
  assert_eq(store.snapshot().event_mode_selected, Some(false))
  ignore(store.put_event(event))
  assert_eq(store.snapshot().event_mode_selected, Some(true))
  let first = store.register_open(
    "https://identity.example", "one", "assertion-one", "One", "one@example.invalid",
    60000L, 100001L,
  )
  let second = store.register_open(
    "https://identity.example", "two", "assertion-two", "Two", "two@example.invalid",
    60000L, 100002L,
  )
  let intent : @account.TrialEntitlementIntent = {
    trial_id: "trial-one",
    account_id: first.account.account_id,
    organization_id: "org-one",
    tenant_ref: "tenant-one",
    project_id: "project-one",
    allowed_models: event.allowed_models,
    maximum_requests: event.maximum_requests,
    expires_unix_ms: event.expires_unix_ms,
  }
  let trial = store.ensure_trial(intent, 100010L, event_id="weekend")
  guard Json(trial) is Object(legacy_trial) else {
    fail("expected trial object")
  }
  ignore(legacy_trial.remove("event_id"))
  let legacy : @account.TrialEntitlement = @json.from_json(
    Json::object(legacy_trial),
  )
  assert_eq(legacy.event_id, None)
  assert_eq(trial.expires_unix_ms, 300000L)
  assert_eq(store.ensure_trial(intent, 100020L, event_id="weekend"), trial)
  try
    store.ensure_trial(
      {
        ..intent,
        trial_id: "trial-two",
        account_id: second.account.account_id,
      },
      100030L,
      event_id="weekend",
    )
  catch {
    @account.AccountError::InvalidInput(_) => ()
    _ => fail("unexpected cap failure")
  } noraise {
    _ => fail("participant cap bypassed")
  }
  try store.put_event({ ..event, maximum_requests: 3L, }) catch {
    @account.AccountError::AlreadyExists(_) => ()
    _ => fail("unexpected immutable policy failure")
  } noraise {
    _ => fail("existing policy was widened")
  }
  ignore(store.put_event({ ..event, registration_open: false, }))
  assert_eq(store.ensure_trial(intent, 100040L, event_id="weekend"), trial)
  try store.ensure_trial(intent, 100050L) catch {
    @account.AccountError::AlreadyExists(_) => ()
    _ => fail("unexpected mode conflict")
  } noraise {
    _ => fail("event silently converted to ordinary trial")
  }
  assert_true(store.consume_trial_request(trial.trial_id, 0L, 100050L))
  assert_true(store.consume_trial_request(trial.trial_id, 0L, 100060L))
  assert_false(store.consume_trial_request(trial.trial_id, 0L, 100070L))
  let reopened = @account.AccountStore::open(
    "\{directory}/accounts.json",
    secret,
  )
  assert_eq(
    reopened.event_for_tenant("tenant-one"),
    Some({ ..event, registration_open: false, }),
  )
  assert_eq(
    reopened.active_trial_for_subject(first.account.subject_ref, 300000L),
    None,
  )
  assert_eq(reopened.snapshot().trials.unwrap().length(), 1)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operator can invite a past participant to another event without renewing self service" {
  let directory = @fs.tmpdir(prefix="repeat-event-test-")
  let secret = "repeat-event-test-secret-more-than-32-bytes"
  let store = @account.AccountStore::open(directory + "/accounts.json", secret)
  let user = store.register_open(
    "https://identity.example", "repeat", "assertion", "Repeat", "repeat@example.invalid",
    60000L, 100L,
  )
  let first : @event_trial.Policy = {
    event_id: "event-first",
    title: "First",
    starts_unix_ms: 100L,
    expires_unix_ms: 10000L,
    maximum_users: 32,
    maximum_requests: 100L,
    allowed_models: ["a3b"],
    node_ids: ["a", "b", "c", "d"],
    per_node_concurrency: 0,
    max_input_bytes: None,
    max_output_tokens: None,
    registration_open: false,
  }
  let second = {
    ..first,
    event_id: "event-second",
    starts_unix_ms: 200L,
    expires_unix_ms: 20000L,
  }
  ignore(store.put_event(first))
  ignore(store.put_event(second))
  let intent : @account.TrialEntitlementIntent = {
    trial_id: "trial-first",
    account_id: user.account.account_id,
    organization_id: "org-first",
    tenant_ref: "tenant-first",
    project_id: "project-first",
    allowed_models: first.allowed_models,
    maximum_requests: first.maximum_requests,
    expires_unix_ms: first.expires_unix_ms,
  }
  ignore(
    store.ensure_trial(
      intent,
      110L,
      event_id=first.event_id,
      operator_enrollment=true,
    ),
  )
  let later = {
    ..intent,
    trial_id: "trial-second",
    tenant_ref: "tenant-second",
    expires_unix_ms: second.expires_unix_ms,
  }
  try
    store.ensure_trial(
      later,
      210L,
      event_id=second.event_id,
      operator_enrollment=true,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("active access was replaced")
  }
  ignore(store.revoke_trial_for_account(user.account.account_id, 220L))
  try store.ensure_trial(later, 230L, event_id=second.event_id) catch {
    _ => ()
  } noraise {
    _ => fail("self-registration renewed a used trial")
  }
  let trial = store.ensure_trial(
    later,
    230L,
    event_id=second.event_id,
    operator_enrollment=true,
  )
  assert_eq(store.trial_for_account(user.account.account_id), Some(trial))
  let restored = @account.AccountStore::open(
    directory + "/accounts.json",
    secret,
  )
  assert_eq(restored.snapshot().trials.unwrap().length(), 2)
  assert_eq(restored.trial_for_account(user.account.account_id), Some(trial))
  assert_eq(
    restored.revoke_trial_for_account(user.account.account_id, 240L).trial_id,
    trial.trial_id,
  )
  @fs.rmdir(directory, recursive=true)
}
