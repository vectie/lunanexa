///|
test "provider callback identity fuzz excludes framing and delimiter injection" {
  for length in 0..<=300 {
    assert_eq(
      valid_callback_identity("a".repeat(length)),
      length > 0 && length <= 256,
    )
  }
  for position in 0..<=64 {
    for mutation in ["|", " ", "\n", "\r", "\t", "\\", "?", "#", "%", "服务"] {
      let candidate = "a".repeat(position) +
        mutation +
        "b".repeat(64 - position)
      assert_false(valid_callback_identity(candidate))
    }
  }
}

///|
test "provider callback signature mutation fuzz binds every authenticated fact" {
  let secret = "provider-callback-test-secret-32-bytes-minimum"
  let signature = provider_callback_signature(
    "provider-a", "sandbox", "event-a", 1700000000000L, "{\"record_id\":\"record-a\"}",
    secret,
  )
  assert_eq(signature.length(), 64)
  assert_true(callback_constant_time_equal(signature, signature))
  for position in 0..<signature.length() {
    let replacement = if signature[position] == '0' { "1" } else { "0" }
    let mutated = signature[:position].to_owned() +
      replacement +
      signature[position + 1:].to_owned()
    assert_false(callback_constant_time_equal(signature, mutated))
  }
  for
    rebound in [
      provider_callback_signature(
        "provider-b", "sandbox", "event-a", 1700000000000L, "{\"record_id\":\"record-a\"}",
        secret,
      ),
      provider_callback_signature(
        "provider-a", "production", "event-a", 1700000000000L, "{\"record_id\":\"record-a\"}",
        secret,
      ),
      provider_callback_signature(
        "provider-a", "sandbox", "event-b", 1700000000000L, "{\"record_id\":\"record-a\"}",
        secret,
      ),
      provider_callback_signature(
        "provider-a", "sandbox", "event-a", 1700000000001L, "{\"record_id\":\"record-a\"}",
        secret,
      ),
      provider_callback_signature(
        "provider-a", "sandbox", "event-a", 1700000000000L, "{\"record_id\":\"record-b\"}",
        secret,
      ),
    ] {
    assert_false(callback_constant_time_equal(signature, rebound))
  }
}

///|
test "provider callback secret configuration fuzz rejects ambiguous keys" {
  let secret = "a".repeat(32)
  assert_true(
    valid_provider_callback_secret_entry("provider-a|sandbox", secret),
  )
  for
    key in [
      "", "|", "provider-a|", "|sandbox", "provider-a|sandbox|extra", "provider a|sandbox",
      "provider-a|sand\nbox", "provider-a/sandbox",
    ] {
    assert_false(valid_provider_callback_secret_entry(key, secret))
  }
  for
    candidate in [
      "",
      "a".repeat(31),
      "a".repeat(4097),
      "a".repeat(31) + "\n",
      "a".repeat(31) + "\r",
      "a".repeat(31) + " ",
      "服务".repeat(16),
    ] {
    assert_false(
      valid_provider_callback_secret_entry("provider-a|sandbox", candidate),
    )
  }
}
