///|
test "the digest carries the sha256 prefix and 64 hex characters" {
  let digest = @identity.subject_digest("https://id.example", "abc")
  assert_true(digest.has_prefix("sha256:"))
  assert_eq(digest.length(), 7 + 64)
  assert_true(digest[7:].all(character => character.is_ascii_hexdigit()))
}

///|
test "the digest is stable across the canonical material" {
  assert_eq(
    @identity.subject_digest("https://id.example", "abc"),
    "sha256:9515a0339daac43889c271ef08af0cc1aa7dfd564044d70c498c8e8bac5b89e1",
  )
}

///|
test "the derived identifiers share one fingerprint" {
  let issuer = "https://id.example"
  let subject = "abc"
  let fingerprint = @identity.subject_fingerprint(issuer, subject)
  assert_eq(fingerprint.length(), 24)
  assert_eq(
    @identity.subject_reference(issuer, subject),
    "subject-\{fingerprint}",
  )
  assert_eq(
    @identity.account_identifier(issuer, subject),
    "account-\{fingerprint}",
  )
}

///|
test "a different subject moves the fingerprint" {
  let issuer = "https://id.example"
  assert_true(
    @identity.subject_fingerprint(issuer, "abc") !=
    @identity.subject_fingerprint(issuer, "abd"),
  )
  assert_true(
    @identity.subject_fingerprint(issuer, "abc") !=
    @identity.subject_fingerprint("https://other.example", "abc"),
  )
}
