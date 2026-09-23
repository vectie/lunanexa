///|
pub(all) suberror SignatureVerificationError {
  InvalidVerifierConfiguration
  UnsafeVerificationSubject
  SubjectDigestMismatch
  SignatureVerificationFailed
} derive(Debug, Eq)

///|
pub extend SignatureVerificationError with Debug::{to_repr}

///|
pub extend SignatureVerificationError with Eq::{not_equal, equal}

///|
pub(all) struct SignatureVerificationReceipt {
  subject : String
  digest : String
  verifier : String
  verified : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend SignatureVerificationReceipt with Debug::{to_repr}

///|
pub extend SignatureVerificationReceipt with Eq::{not_equal, equal}

///|
pub extend SignatureVerificationReceipt with ToJson::{to_json}

///|
pub extend SignatureVerificationReceipt with FromJson::{from_json}

///|
pub struct CosignVerifier {
  binary : String
  public_key_path : String
  offline_public_key_paths : Array[String]
  trusted_root_path : String?
}

///|
pub fn CosignVerifier::new(
  binary : String,
  public_key_path : String,
  trusted_root_path? : String? = None,
  offline_public_key_paths? : Array[String] = [],
) -> CosignVerifier raise SignatureVerificationError {
  if !(binary == "/usr/bin/cosign" || binary == "/usr/local/bin/cosign") ||
    ![public_key_path, ..offline_public_key_paths].all(path => {
      path.has_prefix("/") && !path.contains("..") && !path.contains_char('\n')
    }) ||
    offline_public_key_paths.contains(public_key_path) ||
    (
      trusted_root_path is Some(path) &&
      (!path.has_prefix("/") || path.contains("..") || path.contains_char('\n'))
    ) {
    raise InvalidVerifierConfiguration
  }
  { binary, public_key_path, offline_public_key_paths, trusted_root_path, }
}

///|
fn CosignVerifier::trusted_root_args(self : CosignVerifier) -> Array[String] {
  match self.trusted_root_path {
    Some(path) => ["--trusted-root", path]
    None => []
  }
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
  for public_key_path in [self.public_key_path, ..self.offline_public_key_paths] {
    let args = ["verify", "--key", public_key_path, "--output", "json"]
    if public_key_path != self.public_key_path {
      // Internal, explicitly pinned keys sign in a disconnected registry.
      // The pre-existing primary key keeps transparency-log verification.
      args.push("--insecure-ignore-tlog")
    }
    for arg in self.trusted_root_args() {
      args.push(arg)
    }
    args.push(subject)
    let (status, _, _) = @process.collect_output(
      self.binary,
      args,
      inherit_env=false,
    )
    if status == 0 {
      return {
        subject,
        digest,
        verifier: "cosign-key:\{public_key_path}",
        verified: true,
      }
    }
  }
  raise SignatureVerificationFailed
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
  let material_flag = @signature.cosign_material_flag(signature_path)
  for public_key_path in [self.public_key_path, ..self.offline_public_key_paths] {
    let args = ["verify-blob", "--key", public_key_path]
    if public_key_path != self.public_key_path {
      args.push("--insecure-ignore-tlog")
    }
    for arg in self.trusted_root_args() {
      args.push(arg)
    }
    args.push(material_flag)
    args.push(signature_path)
    args.push(artifact_path)
    let (status, _, _) = @process.collect_output(
      self.binary,
      args,
      inherit_env=false,
    )
    if status == 0 {
      return {
        subject: artifact_path,
        digest,
        verifier: "cosign-key:\{public_key_path}",
        verified: true,
      }
    }
  }
  raise SignatureVerificationFailed
}
