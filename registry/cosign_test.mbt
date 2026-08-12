///|
async test "cosign adapter rejects executable injection and unsafe subjects before launch" {
  try
    @registry.CosignVerifier::new("/tmp/cosign", "/etc/lunanexa/cosign.pub")
  catch {
    InvalidVerifierConfiguration => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unapproved verifier executable was accepted")
  }
  let verifier = @registry.CosignVerifier::new(
    "/usr/bin/cosign", "/etc/lunanexa/cosign.pub",
  )
  try
    verifier.verify_image(
      "-malicious", "sha256:dededededededededededededededededededededededededededededededede",
    )
  catch {
    @registry.SignatureVerificationError::UnsafeVerificationSubject => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unsafe image subject was accepted")
  }
}

///|
async test "blob verification binds the claimed digest before launching cosign" {
  let directory = @fs.tmpdir(prefix="lunanexa-cosign-digest-")
  let artifact = "\{directory}/artifact.bin"
  let signature = "\{directory}/artifact.sig"
  @fs.write_file(artifact, "signed bytes", create_mode=CreateOrTruncate)
  @fs.write_file(signature, "signature", create_mode=CreateOrTruncate)
  let verifier = @registry.CosignVerifier::new(
    "/usr/bin/cosign", "/etc/lunanexa/cosign.pub",
  )
  try
    verifier.verify_blob(
      artifact, signature, "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    )
  catch {
    @registry.SignatureVerificationError::SubjectDigestMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("mismatched blob digest reached signature acceptance")
  }
  @fs.rmdir(directory, recursive=true)
}
