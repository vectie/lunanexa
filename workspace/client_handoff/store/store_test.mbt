///|
async test "handoff lifecycle write failures roll back both authority maps and allow retry" {
  let directory = @fs.tmpdir(prefix="lunanexa-handoff-rollback-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/handoffs.json"
  let store = test_store(path)
  let now = 100000L
  let intent = handoff_intent(now)
  let mut code = ""
  let mut secret = ""
  let mut id = ""
  for stage in 0..<4 {
    let before = store.snapshot()
    let disk = @fs.read_file(path).text()
    @fs.mkdir(path + ".next")
    for _ in 0..<2 {
      try {
        match stage {
          0 => ignore(store.issue(intent, now))
          1 => ignore(store.redeem(code, "desktop-client", now + 1L))
          2 =>
            ignore(
              store.authorize(
                secret,
                Inference,
                model="model-a",
                now + 2L,
                true,
              ),
            )
          _ =>
            ignore(
              store.revoke_for_subject(id, "tenant-1", "subject-1", now + 3L),
            )
        }
      } catch {
        _ => ()
      } noraise {
        _ => fail("handoff lifecycle write unexpectedly succeeded")
      }
      assert_eq(@async.with_timeout(1000, () => store.snapshot()), before)
      assert_eq(@fs.read_file(path).text(), disk)
    }
    @fs.rmdir(path + ".next")
    @async.with_timeout(1000, () => {
      match stage {
        0 => {
          let issued = store.issue(intent, now)
          code = issued.handoff_code
          id = issued.handoff_id
          assert_eq(store.issue(intent, now).handoff_code, code)
        }
        1 => secret = store.redeem(code, "desktop-client", now + 1L).api_secret
        2 =>
          ignore(
            store.authorize(secret, Inference, model="model-a", now + 2L, true),
          )
        _ =>
          ignore(
            store.revoke_for_subject(id, "tenant-1", "subject-1", now + 3L),
          )
      }
      assert_eq(test_store(path).snapshot(), store.snapshot())
      let recovered = test_store(path)
      let snapshot = recovered.snapshot()
      assert_eq(snapshot.handoffs.length(), 1)
      assert_eq(snapshot.credentials.length(), 1)
      assert_eq(
        snapshot.credentials[0].consumed_requests,
        if stage >= 2 {
          1L
        } else {
          0L
        },
      )
      if stage == 1 {
        try recovered.redeem(code, "desktop-client", now + 2L) catch {
          @handoff.ClientHandoffError::AlreadyRedeemed => ()
          error => fail("unexpected replay error: \{Repr(error)}")
        } noraise {
          _ => fail("redeemed handoff could be replayed after reopen")
        }
      }
    })
    let persisted = @fs.read_file(path).text()
    assert_false(persisted.contains(code))
    if secret != "" {
      assert_false(persisted.contains(secret))
    }
  }
  let reopened = test_store(path)
  try reopened.authorize(secret, ModelList, now + 4L, false) catch {
    @handoff.ClientHandoffError::Unauthorized => ()
    error => fail("unexpected authorization error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked handoff credential survived reopen")
  }
}

///|
fn handoff_intent(
  now : Int64,
  request_id? : String = "request-1",
) -> @handoff.ClientHandoffIssueIntent {
  {
    request_id,
    client_id: "desktop-client",
    tenant_ref: "tenant-1",
    subject_ref: "subject-1",
    organization_id: "organization-1",
    project_id: "project-1",
    display_name: "Desktop workspace",
    allowed_models: ["model-a"],
    handoff_expires_unix_ms: now + 120000L,
    credential_expires_unix_ms: now + 3600000L,
    maximum_requests: 2L,
  }
}

///|
async fn test_store(path : String) -> @store.ClientHandoffStore {
  @store.ClientHandoffStore::open(
    path, "client-handoff-test-secret-with-at-least-thirty-two-bytes",
  )
}

///|
async test "client handoff is restart safe, single use, and secret free at rest" {
  let directory = @fs.tmpdir(prefix="lunanexa-client-handoff-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/handoffs.json"
  let now = @async.now()
  let store = test_store(path)
  let issued = store.issue(handoff_intent(now), now)
  assert_true(issued.handoff_code.has_prefix("lnxc_"))
  let persisted = @fs.read_file(path).text()
  assert_false(persisted.contains(issued.handoff_code))
  assert_false(persisted.contains("lnx_"))
  let reopened = test_store(path)
  let redemption = reopened.redeem(
    issued.handoff_code,
    "desktop-client",
    now + 1L,
  )
  assert_true(redemption.api_secret.has_prefix("lnx_"))
  assert_eq(redemption.allowed_models, ["model-a"])
  let after_redeem = @fs.read_file(path).text()
  assert_false(after_redeem.contains(redemption.api_secret))
  try {
    ignore(reopened.redeem(issued.handoff_code, "desktop-client", now + 2L))
    fail("replayed handoff was accepted")
  } catch {
    @handoff.ClientHandoffError::AlreadyRedeemed => ()
    _ => fail("unexpected replay error")
  }
}

///|
async test "client handoff rejects wrong client, expiry, and idempotency drift" {
  let directory = @fs.tmpdir(prefix="lunanexa-client-handoff-negative-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/handoffs.json"
  let now = @async.now()
  let store = test_store(path)
  let intent = handoff_intent(now)
  let issued = store.issue(intent, now)
  let repeated = store.issue(intent, now)
  assert_eq(repeated.handoff_code, issued.handoff_code)
  try {
    ignore(store.issue({ ..intent, display_name: "Changed", }, now))
    fail("idempotency drift was accepted")
  } catch {
    @handoff.ClientHandoffError::IdempotencyConflict => ()
    _ => fail("unexpected idempotency error")
  }
  try {
    ignore(store.redeem(issued.handoff_code, "other-client", now + 1L))
    fail("wrong client was accepted")
  } catch {
    @handoff.ClientHandoffError::ClientMismatch => ()
    _ => fail("unexpected client mismatch error")
  }
  try {
    ignore(
      store.redeem(
        issued.handoff_code,
        "desktop-client",
        intent.handoff_expires_unix_ms,
      ),
    )
    fail("expired handoff was accepted")
  } catch {
    @handoff.ClientHandoffError::Expired => ()
    _ => fail("unexpected expiry error")
  }
}

///|
async test "redeemed desktop credential enforces model, quota, and revocation" {
  let directory = @fs.tmpdir(prefix="lunanexa-client-credential-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/handoffs.json"
  let now = @async.now()
  let store = test_store(path)
  let issued = store.issue(handoff_intent(now), now)
  let redeemed = store.redeem(issued.handoff_code, "desktop-client", now + 1L)
  let authorized = store.authorize(
    redeemed.api_secret,
    Inference,
    model="model-a",
    now + 2L,
    true,
  )
  assert_eq(authorized.subject_ref, "subject-1")
  try {
    ignore(
      store.authorize(
        redeemed.api_secret,
        Inference,
        model="model-b",
        now + 3L,
        true,
      ),
    )
    fail("unapproved model was accepted")
  } catch {
    @handoff.ClientHandoffError::Unauthorized => ()
    _ => fail("unexpected model authorization error")
  }
  ignore(
    store.authorize(
      redeemed.api_secret,
      Inference,
      model="model-a",
      now + 4L,
      true,
    ),
  )
  try {
    ignore(
      store.authorize(
        redeemed.api_secret,
        Inference,
        model="model-a",
        now + 5L,
        true,
      ),
    )
    fail("exhausted credential was accepted")
  } catch {
    @handoff.ClientHandoffError::QuotaExceeded => ()
    _ => fail("unexpected quota error")
  }
  let revoked = store.revoke_for_subject(
    redeemed.handoff_id,
    "tenant-1",
    "subject-1",
    now + 6L,
  )
  assert_true(revoked.revoked_unix_ms is Some(_))
  try {
    ignore(store.authorize(redeemed.api_secret, ModelList, now + 7L, false))
    fail("revoked credential was accepted")
  } catch {
    @handoff.ClientHandoffError::Unauthorized => ()
    _ => fail("unexpected revocation error")
  }
}
