///|
fn valid_intent() -> @access.ApiKeyIssueIntent {
  {
    key_id: "key-fuzz",
    tenant_ref: "tenant-fuzz",
    subject_ref: "subject-fuzz",
    display_name: "Fuzz key",
    scopes: [ModelList, Inference],
    allowed_models: ["model-fuzz"],
    expires_unix_ms: 200000L,
    maximum_requests: 100L,
  }
}

///|
fn rejected(intent : @access.ApiKeyIssueIntent) -> Bool {
  try @access.validate_api_key_intent(intent, 100000L) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "deterministic API-key mutation fuzz rejects 10k boundary and injection variants" {
  let forbidden = [
    "<", ">", "/", " ", "\n", "\u0000", "\u202e", "\\", "%", "\"", ";", "?", "#",
  ]
  let envelope = "a".repeat(256)
  let mut mutations = 0
  for attack in forbidden {
    for position in 0..<256 {
      let injected = "\{envelope[:position]}\{attack}\{envelope[position + 1:]}"
      assert_true(rejected({ ..valid_intent(), key_id: injected }))
      assert_true(rejected({ ..valid_intent(), tenant_ref: injected }))
      assert_true(rejected({ ..valid_intent(), subject_ref: injected }))
      mutations += 3
    }
  }
  for length in 0..<=400 {
    let value = "a".repeat(length)
    let expected_rejection = length == 0 || length > 256
    assert_eq(rejected({ ..valid_intent(), key_id: value }), expected_rejection)
    mutations += 1
  }
  assert_true(rejected({ ..valid_intent(), maximum_requests: 0L }))
  assert_true(rejected({ ..valid_intent(), maximum_requests: 1000000001L }))
  assert_true(rejected({ ..valid_intent(), expires_unix_ms: 100000L }))
  assert_true(mutations > 10000)
}
