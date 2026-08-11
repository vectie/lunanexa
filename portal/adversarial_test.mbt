///|
fn adversarial_submission() -> @portal.LeaseRequestSubmission {
  {
    request_id: "request-fuzz",
    idempotency_key: "submit-fuzz",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    unix_username: "alice",
    starts_unix_ms: 1000L,
    expires_unix_ms: 2000L,
    requested_model_ids: ["model-a"],
    justification: "Bounded evaluation",
  }
}

///|
fn submission_is_valid(candidate : @portal.LeaseRequestSubmission) -> Bool {
  try @portal.validate_submission(candidate) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "deterministic fuzz exhausts portal identifier and collection bounds" {
  let base = adversarial_submission()
  for length in 0..<=300 {
    let value = "a".repeat(length)
    let expected = length > 0 && length <= 256
    assert_eq(submission_is_valid({ ..base, request_id: value }), expected)
    assert_eq(submission_is_valid({ ..base, idempotency_key: value }), expected)
    assert_eq(submission_is_valid({ ..base, tenant_ref: value }), expected)
    assert_eq(submission_is_valid({ ..base, organization_id: value }), expected)
    assert_eq(submission_is_valid({ ..base, project_id: value }), expected)
    assert_eq(
      submission_is_valid({ ..base, requested_model_ids: [value] }),
      expected,
    )
  }
  for count in 0..<=34 {
    let models = [ for _ in 0..<count => "model-a" ]
    assert_eq(
      submission_is_valid({ ..base, requested_model_ids: models }),
      count >= 1 && count <= 32,
    )
  }
}

///|
test "mutation fuzz rejects injection bytes at every portal identifier position" {
  let base = adversarial_submission()
  let mutations = [
    "/", "\\", " ", "\n", "\r", "\u0000", "<", ">", "%", "?", "'", "\"", ";", "服务",
  ]
  for position in 0..<=256 {
    for mutation in mutations {
      let candidate = "a".repeat(position) +
        mutation +
        "b".repeat(256 - position)
      assert_false(submission_is_valid({ ..base, idempotency_key: candidate }))
      assert_false(
        submission_is_valid({ ..base, requested_model_ids: [candidate] }),
      )
    }
  }
}

///|
test "free text fuzz is bounded before trimming and rejects controls" {
  let base = adversarial_submission()
  for length in 0..<=1050 {
    let justification = "x".repeat(length)
    assert_eq(
      submission_is_valid({ ..base, justification, }),
      length >= 1 && length <= 1000,
    )
  }
  for
    hostile in [
      "safe\nforged-audit",
      "safe\rforged-audit",
      "safe\u0000hidden",
      " ".repeat(1000) + "x",
    ] {
    assert_false(submission_is_valid({ ..base, justification: hostile }))
  }
}

///|
test "portal time and unix account boundary mutations fail closed" {
  let base = adversarial_submission()
  for
    username in [
      "root",
      "daemon",
      "lunanexa",
      "Alice",
      "-alice",
      "alice/../../root",
      "alice\u0000root",
      "a".repeat(33),
    ] {
    assert_false(submission_is_valid({ ..base, unix_username: username }))
  }
  for starts in [-9223372036854775807L, -1L, 0L] {
    assert_false(submission_is_valid({ ..base, starts_unix_ms: starts }))
  }
  for expires in [-1L, 0L, 999L, 1000L] {
    assert_false(submission_is_valid({ ..base, expires_unix_ms: expires }))
  }
}
