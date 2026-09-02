///|
async test "bootstrap enrollment is one-use durable and secret-hashed at rest" {
  let directory = @fs.tmpdir(prefix="lunanexa-enrollment-test-")
  let path = "\{directory}/enrollment.json"
  let enrollment = @node.FileEnrollmentService::open(path)
  ignore(enrollment.issue_token("token-1", "one-use-secret", 1000L))
  assert_false(@fs.read_file(path).text().contains("one-use-secret"))
  let reopened = @node.FileEnrollmentService::open(path)
  let certificate = reopened.enroll(
    "node-1", "token-1", "one-use-secret", "node-specific-auth-secret", "host-ref:node-1-public-key",
    10L,
  )
  assert_eq(certificate.node_id, "node-1")
  assert_false(@fs.read_file(path).text().contains("node-specific-auth-secret"))
  let after_enroll = @node.FileEnrollmentService::open(path)
  try
    after_enroll.enroll(
      "node-2", "token-1", "one-use-secret", "other-node-auth-secret", "host-ref:node-2-public-key",
      11L,
    )
  catch {
    @node.NodeError::InvalidBootstrapToken => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("one-use token was accepted twice")
  }
  let rotated = after_enroll.rotate(
    "node-1", "host-ref:node-1-rotated-public-key", 20L,
  )
  assert_eq(rotated.serial, 2L)
  assert_true(
    after_enroll.authorized("node-1", "node-specific-auth-secret", 20L),
  )
  assert_false(after_enroll.authorized("node-1", "other-node-auth-secret", 20L))
  assert_false(
    after_enroll.authorized("node-1", "node-specific-auth-secret", 3620020L),
  )
  let recovered = after_enroll.renew(
    "node-1", "node-specific-auth-secret", "host-ref:node-1-recovered-public-key",
    2L, 3620020L,
  )
  assert_eq(recovered.serial, 3L)
  assert_true(
    after_enroll.authorized("node-1", "node-specific-auth-secret", 3620020L),
  )
  let replayed = after_enroll.renew(
    "node-1", "node-specific-auth-secret", "host-ref:node-1-recovered-public-key",
    2L, 3620021L,
  )
  assert_eq(replayed.serial, 3L)
  try
    after_enroll.renew(
      "node-1", "other-node-auth-secret", "host-ref:node-1-attacker-key", 3L, 3620022L,
    )
  catch {
    @node.NodeError::InvalidCertificateRenewal => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("wrong node authority renewed a certificate")
  }
  let reopened_after_recovery = @node.FileEnrollmentService::open(path)
  assert_true(
    reopened_after_recovery.authorized(
      "node-1", "node-specific-auth-secret", 3620022L,
    ),
  )
  @fs.rmdir(directory, recursive=true)
}
