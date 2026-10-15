///|
async test "unlimited keys count requests across restart and retain access boundaries" {
  let root = @fs.tmpdir(prefix="lunanexa-unlimited-key-")
  defer @fs.rmdir(root, recursive=true)
  let path = root + "/keys.json"
  let issuer = "unlimited-key-test-issuer-more-than-thirty-two-bytes"
  let store = AccessStore::open(path, issuer)
  let issued = store.issue(
    {
      key_id: "private-key",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      organization_id: "organization-a",
      project_id: "project-a",
      display_name: "Private model",
      scopes: [Inference],
      allowed_models: ["private.model"],
      expires_unix_ms: 200000L,
      maximum_requests: 0L,
    },
    100000L,
  )
  for _ in 0..<3 {
    ignore(
      store.authorize(
        issued.secret,
        Inference,
        model="private.model",
        tenant_ref="tenant-a",
        100001L,
        true,
      ),
    )
  }
  let reopened = AccessStore::open(path, issuer)
  assert_eq(
    reopened.snapshot().credentials[0].maximum_requests,
    9223372036854775807L,
  )
  assert_eq(reopened.views()[0].maximum_requests, 0L)
  assert_eq(reopened.snapshot().credentials[0].consumed_requests, 3L)
  ignore(reopened.authorize(issued.secret, Inference, 100002L, true))
  for
    (tenant, model, scope, now) in [
      ("tenant-b", "private.model", Inference, 100003L),
      ("tenant-a", "another.model", Inference, 100003L),
      ("tenant-a", "private.model", ModelList, 100003L),
      ("tenant-a", "private.model", Inference, 200000L),
    ] {
    let denied = try {
      ignore(
        reopened.authorize(
          issued.secret,
          scope,
          tenant_ref=tenant,
          model~,
          now,
          true,
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(denied)
  }
  // An unlimited usage counter saturates rather than wrapping on overflow.
  reopened.credentials[issued.credential.key_id] = {
    ..reopened.credentials[issued.credential.key_id],
    consumed_requests: 9223372036854775807L,
  }
  ignore(reopened.authorize(issued.secret, Inference, 100004L, true))
  assert_eq(
    reopened.snapshot().credentials[0].consumed_requests,
    9223372036854775807L,
  )
  ignore(reopened.revoke(issued.credential.key_id, 100005L))
  let revoked = try {
    ignore(reopened.authorize(issued.secret, Inference, 100006L, true))
    false
  } catch {
    _ => true
  }
  assert_true(revoked)
}
