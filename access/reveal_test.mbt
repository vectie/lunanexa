///|
async test "owners can retrieve their actual key repeatedly after restart until expiry or revocation" {
  let path = "/tmp/lunanexa-key-reveal-" + @async.now().to_string() + ".json"
  let issuer = "reveal-test-issuer-secret-more-than-thirty-two-bytes"
  let store = @access.AccessStore::open(path, issuer)
  let issued = store.issue(
    {
      key_id: "key-reveal",
      tenant_ref: "tenant-owner",
      subject_ref: "subject-owner",
      organization_id: "org-owner",
      project_id: "project-owner",
      display_name: "Owner key",
      scopes: [ModelList, Inference],
      allowed_models: ["model-one"],
      expires_unix_ms: 200000L,
      maximum_requests: 10L,
    },
    100000L,
  )
  assert_eq(
    store.secret_for_subject(
      "key-reveal", "tenant-owner", "subject-owner", 100001L,
    ),
    issued.secret,
  )
  let reopened = @access.AccessStore::open(path, issuer)
  assert_eq(
    reopened.secret_for_subject(
      "key-reveal", "tenant-owner", "subject-owner", 100002L,
    ),
    issued.secret,
  )
  assert_eq(
    reopened.secret_for_subject(
      "key-reveal", "tenant-owner", "subject-owner", 100003L,
    ),
    issued.secret,
  )
  for
    (tenant, subject, now) in [
      ("tenant-other", "subject-owner", 100004L),
      ("tenant-owner", "subject-other", 100004L),
      ("tenant-owner", "subject-owner", 200000L),
    ] {
    try {
      let _ = reopened.secret_for_subject("key-reveal", tenant, subject, now)
      fail("unauthorized reveal")
    } catch {
      @access.AccessError::Unauthorized => ()
      other => raise other
    }
  }
  let rotated = @access.AccessStore::open(
    path, "different-issuer-secret-more-than-thirty-two-bytes",
  )
  try {
    let _ = rotated.secret_for_subject(
      "key-reveal", "tenant-owner", "subject-owner", 100004L,
    )
    fail("unverified secret")
  } catch {
    @access.AccessError::Unauthorized => ()
    other => raise other
  }
  ignore(reopened.revoke("key-reveal", 100005L))
  try {
    let _ = reopened.secret_for_subject(
      "key-reveal", "tenant-owner", "subject-owner", 100006L,
    )
    fail("revoked reveal")
  } catch {
    @access.AccessError::Unauthorized => ()
    other => raise other
  }
  let snapshot = @fs.read_file(path).text()
  assert_false(snapshot.contains(issued.secret))
  @fs.remove(path)
}
