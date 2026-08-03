///|
pub(all) suberror SignatureVerificationError {
  InvalidVerifierConfiguration
  UnsafeVerificationSubject
  SubjectDigestMismatch
  SignatureVerificationFailed
} derive(Debug, Eq)

///|
pub(all) struct SignatureVerificationReceipt {
  subject : String
  digest : String
  verifier : String
  verified : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct CosignVerifier {
  binary : String
  public_key_path : String
}

///|
pub fn CosignVerifier::new(
  binary : String,
  public_key_path : String,
) -> CosignVerifier raise SignatureVerificationError {
  if !(binary == "/usr/bin/cosign" || binary == "/usr/local/bin/cosign") ||
    !public_key_path.has_prefix("/") ||
    public_key_path.contains("..") ||
    public_key_path.contains_char('\n') {
    raise InvalidVerifierConfiguration
  }
  { binary, public_key_path }
}

///|
fn safe_subject(value : String) -> Bool {
  value != "" &&
  !value.contains_char('\n') &&
  !value.contains_char('\r') &&
  !value.contains_char(' ') &&
  !value.has_prefix("-")
}

///|
async fn file_digest(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let digest = @crypto.SHA256::new()
  while file.read_some(max_len=65536) is Some(chunk) {
    digest.update(chunk)
  }
  "sha256:\{@crypto.bytes_to_hex_string(digest.finalize())}"
}

///|
pub async fn CosignVerifier::verify_image(
  self : CosignVerifier,
  image_ref : String,
  digest : String,
) -> SignatureVerificationReceipt {
  if !safe_subject(image_ref) ||
    image_ref.contains("@") ||
    !@contracts.valid_sha256_digest(digest) ||
    !safe_subject(digest) {
    raise UnsafeVerificationSubject
  }
  let subject = "\{image_ref}@\{digest}"
  let (status, _, _) = @process.collect_output(
    self.binary,
    ["verify", "--key", self.public_key_path, "--output", "json", subject],
    inherit_env=false,
  )
  if status != 0 {
    raise SignatureVerificationFailed
  }
  {
    subject,
    digest,
    verifier: "cosign-key:\{self.public_key_path}",
    verified: true,
  }
}

///|
pub async fn CosignVerifier::verify_blob(
  self : CosignVerifier,
  artifact_path : String,
  signature_path : String,
  digest : String,
) -> SignatureVerificationReceipt {
  if !artifact_path.has_prefix("/") ||
    !signature_path.has_prefix("/") ||
    artifact_path.contains("..") ||
    signature_path.contains("..") ||
    !safe_subject(artifact_path) ||
    !safe_subject(signature_path) ||
    !@contracts.valid_sha256_digest(digest) ||
    !safe_subject(digest) {
    raise UnsafeVerificationSubject
  }
  if file_digest(artifact_path) != digest {
    raise SubjectDigestMismatch
  }
  let (status, _, _) = @process.collect_output(
    self.binary,
    [
      "verify-blob",
      "--key",
      self.public_key_path,
      "--signature",
      signature_path,
      artifact_path,
    ],
    inherit_env=false,
  )
  if status != 0 {
    raise SignatureVerificationFailed
  }
  {
    subject: artifact_path,
    digest,
    verifier: "cosign-key:\{self.public_key_path}",
    verified: true,
  }
}
