///|
test "artifact verifier uses explicit trust without bypass flags" {
  let args = artifact_cosign_arguments(
    "/trust/key.pub",
    Some("/trust/trusted-root.json"),
    "--bundle",
    "/cache/model.sig",
    "/cache/model",
  )
  assert_eq(args, [
    "verify-blob", "--key", "/trust/key.pub", "--trusted-root", "/trust/trusted-root.json",
    "--bundle", "/cache/model.sig", "/cache/model",
  ])
  assert_eq(
    artifact_cosign_arguments(
      "/trust/key.pub",
      None,
      "--signature",
      "/cache/model.sig",
      "/cache/model",
    ),
    [
      "verify-blob", "--key", "/trust/key.pub", "--signature", "/cache/model.sig",
      "/cache/model",
    ],
  )
  ignore(
    CosignArtifactSignatureVerifier::new(
      "/usr/bin/cosign",
      "/trust/key.pub",
      trusted_root_path="/trust/trusted-root.json",
    ),
  )
  try
    CosignArtifactSignatureVerifier::new(
      "/usr/bin/cosign",
      "/trust/key.pub",
      trusted_root_path="../untrusted.json",
    )
  catch {
    InvalidConfiguration => ()
    _ => fail("wrong error for invalid trust reference")
  } noraise {
    _ => fail("relative trust reference accepted")
  }
}
