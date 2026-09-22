///|
/// The canonical material hashed for an external identity.
///
/// The control plane and the operator console both hash this exact string, so
/// the console can show an operator the reference the platform will derive
/// before the request is sent.
fn subject_material(issuer : String, subject : String) -> String {
  "lunanexa.external-identity.v1\n\{issuer}\n\{subject}"
}

///|
/// The full digest of an external identity, in the `sha256:<hex>` form the
/// account store persists as `identity_subject_sha256`.
pub fn subject_digest(issuer : String, subject : String) -> String {
  let material = subject_material(issuer, subject)
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(material)))}"
}

///|
/// The 96-bit reference the platform derives from an external identity. This is
/// the suffix of every `subject-…` and `account-…` identifier.
pub fn subject_fingerprint(issuer : String, subject : String) -> String {
  subject_digest(issuer, subject)[7:31].to_owned()
}

///|
pub fn subject_reference(issuer : String, subject : String) -> String {
  "subject-\{subject_fingerprint(issuer, subject)}"
}

///|
pub fn account_identifier(issuer : String, subject : String) -> String {
  "account-\{subject_fingerprint(issuer, subject)}"
}
