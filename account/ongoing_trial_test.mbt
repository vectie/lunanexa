///|
async test "ongoing trial admits over thirty people counts over two hundred requests and never renews" {
  let directory = @fs.tmpdir(prefix="ongoing-trial-test-")
  let secret = "ongoing-trial-secret-at-least-thirty-two-bytes"
  let store = @account.AccountStore::open(directory + "/accounts.json", secret)
  let policy : @event_trial.Policy = {
    event_id: "ongoing",
    title: "Seven days",
    starts_unix_ms: 1000L,
    expires_unix_ms: 0L,
    maximum_users: 0,
    maximum_requests: 0L,
    allowed_models: ["text.default"],
    node_ids: ["a", "b"],
    per_node_concurrency: 0,
    max_input_bytes: None,
    max_output_tokens: None,
    registration_open: true,
  }
  ignore(store.put_event(policy))
  for i in 0..<32 {
    let now = 1001L + i.to_int64()
    let registration = store.register_open(
      "https://identity.example",
      "visitor-\{i}",
      "assertion-\{i}",
      "Visitor \{i}",
      "visitor-\{i}@example.invalid",
      60000L,
      now,
    )
    let intent : @account.TrialEntitlementIntent = {
      trial_id: "trial-\{i}",
      account_id: registration.account.account_id,
      organization_id: "org-\{i}",
      tenant_ref: "tenant-\{i}",
      project_id: "project-\{i}",
      allowed_models: policy.allowed_models,
      maximum_requests: 0L,
      expires_unix_ms: policy.grant_expires(now),
    }
    let grant = store.ensure_trial(intent, now, event_id=policy.event_id)
    assert_eq(grant.expires_unix_ms - grant.starts_unix_ms, 604800000L)
    assert_eq(
      store.ensure_trial(
        { ..intent, expires_unix_ms: policy.grant_expires(now + 100L), },
        now + 100L,
        event_id=policy.event_id,
      ),
      grant,
    )
  }
  for i in 0..<201 {
    assert_true(
      store.consume_trial_request("trial-0", 0L, 2000L + i.to_int64()),
    )
  }
  let reopened = @account.AccountStore::open(
    directory + "/accounts.json",
    secret,
  )
  let snapshot = reopened.snapshot().trials.unwrap()
  assert_eq(snapshot.length(), 32)
  let first = snapshot.iter().find_first(t => t.trial_id == "trial-0").unwrap()
  assert_eq(first.consumed_requests, Some(201L))
  let enlarged = { ..policy, max_output_tokens: Some(8192), }
  ignore(reopened.put_event(enlarged))
  assert_eq(reopened.snapshot().trials.unwrap(), snapshot)
  assert_eq(reopened.event_for_tenant(first.tenant_ref), Some(enlarged))
  try reopened.put_event({ ..enlarged, per_node_concurrency: 1, }) catch {
    @account.AccountError::AlreadyExists(_) => ()
    _ => fail("unexpected immutable scope error")
  } noraise {
    _ => fail("output update changed concurrency")
  }
  try
    reopened.consume_trial_request("trial-0", 0L, first.expires_unix_ms)
  catch {
    @account.AccountError::Unauthorized => ()
    _ => fail("wrong expiry error")
  } noraise {
    _ => fail("expired trial admitted")
  }
  @fs.rmdir(directory, recursive=true)
}
