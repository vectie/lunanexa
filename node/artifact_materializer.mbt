///|
pub(all) suberror ArtifactMaterializationError {
  InvalidConfiguration
  UnsupportedArtifactReference(String)
  ArtifactStoreDenied
  ArtifactTooLarge
  ArtifactFetchFailed
  ArtifactSizeMismatch
  ArtifactDigestMismatch
  ArtifactSignatureInvalid
} derive(Debug, Eq)

///|
pub struct MaterializedArtifact {
  digest : String
  host_path : String
  size_bytes : Int64
}

///|
pub fn MaterializedArtifact::digest(self : MaterializedArtifact) -> String {
  self.digest
}

///|
pub fn MaterializedArtifact::host_path(self : MaterializedArtifact) -> String {
  self.host_path
}

///|
pub fn MaterializedArtifact::size_bytes(self : MaterializedArtifact) -> Int64 {
  self.size_bytes
}

///|
pub(open) trait ArtifactSignatureVerifier {
  async fn verify(
    Self,
    artifact_path : String,
    signature_path : String,
    digest : String,
  ) -> Unit
}

///|
pub struct CosignArtifactSignatureVerifier {
  binary : String
  public_key_path : String
}

///|
struct S3SigV4Configuration {
  access_key_id : String
  secret_access_key : String
  region : String
  session_token : String?
}

///|
pub fn CosignArtifactSignatureVerifier::new(
  binary : String,
  public_key_path : String,
) -> CosignArtifactSignatureVerifier raise ArtifactMaterializationError {
  if !(binary == "/usr/bin/cosign" || binary == "/usr/local/bin/cosign") ||
    !safe_absolute_path(public_key_path) {
    raise InvalidConfiguration
  }
  { binary, public_key_path }
}

///|
pub impl ArtifactSignatureVerifier for CosignArtifactSignatureVerifier with fn verify(
  self,
  artifact_path,
  signature_path,
  digest,
) {
  if !safe_absolute_path(artifact_path) ||
    !safe_absolute_path(signature_path) ||
    !@contracts.valid_sha256_digest(digest) {
    raise ArtifactSignatureInvalid
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
    raise ArtifactSignatureInvalid
  }
}

///|
pub struct ArtifactMaterializer {
  cache_root : String
  endpoint : String
  credential : String
  node_id : String
  maximum_artifact_size_bytes : Int64
  io_chunk_bytes : Int
  signature_maximum_bytes : Int64
  allow_http_loopback : Bool
  s3_sigv4 : S3SigV4Configuration?
  verified : Map[String, Bool]
}

///|
fn safe_absolute_path(value : String) -> Bool {
  value.has_prefix("/") &&
  !value.contains("..") &&
  !value.contains_char('\n') &&
  !value.contains_char('\r')
}

///|
fn safe_transport_credential(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 4096 &&
  value.all(character => character >= '!' && character <= '~')
}

///|
fn safe_s3_credential(value : String, maximum_length : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum_length &&
  value.all(character => character >= '!' && character <= '~')
}

///|
fn safe_s3_region(value : String) -> Bool {
  value.length() >= 3 &&
  value.length() <= 64 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-'
  })
}

///|
fn safe_object_key(value : String) -> Bool {
  value != "" &&
  value.length() <= 2048 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("..") &&
  !value.contains("//") &&
  !value.contains_char('\n') &&
  !value.contains_char('\r') &&
  !value.contains_char('?') &&
  !value.contains_char('#') &&
  !value.contains_char('%') &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == '/'
  })
}

///|
fn s3_object_key(uri : String) -> String raise ArtifactMaterializationError {
  guard uri.has_prefix("s3://") else { raise UnsupportedArtifactReference(uri) }
  let object_key = uri[5:].to_owned()
  if !safe_object_key(object_key) || !object_key.contains_char('/') {
    raise UnsupportedArtifactReference(uri)
  }
  object_key
}

///|
fn signature_uri(
  artifact : @contracts.ArtifactRef,
) -> String raise ArtifactMaterializationError {
  if artifact.signature_ref.has_prefix("s3://") {
    artifact.signature_ref
  } else if @contracts.valid_identifier(
      artifact.signature_ref,
      maximum_length=256,
    ) {
    "\{artifact.uri}.sig"
  } else {
    raise UnsupportedArtifactReference(artifact.signature_ref)
  }
}

///|
fn digest_hex(digest : String) -> String raise ArtifactMaterializationError {
  if !@contracts.valid_sha256_digest(digest) {
    raise ArtifactDigestMismatch
  }
  digest[7:].to_owned()
}

///|
fn base_endpoint(endpoint : String) -> String {
  if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
}

///|
pub async fn ArtifactMaterializer::open(
  cache_root : String,
  endpoint : String,
  credential : String,
  node_id? : String = "",
  maximum_artifact_size_bytes? : Int64 = 1099511627776L,
  io_chunk_bytes? : Int = 1048576,
  signature_maximum_bytes? : Int64 = 1048576L,
  allow_http_loopback? : Bool = false,
) -> ArtifactMaterializer {
  let secure_endpoint = endpoint.has_prefix("https://")
  let loopback_endpoint = allow_http_loopback &&
    (
      endpoint.has_prefix("http://127.0.0.1:") ||
      endpoint.has_prefix("http://localhost:")
    )
  if !safe_absolute_path(cache_root) ||
    (!secure_endpoint && !loopback_endpoint) ||
    endpoint.contains("..") ||
    endpoint.contains_char('@') ||
    endpoint.contains_char('?') ||
    endpoint.contains_char('#') ||
    endpoint.contains_char(' ') ||
    endpoint.contains_char('\n') ||
    endpoint.contains_char('\r') ||
    (credential != "" && !safe_transport_credential(credential)) ||
    (node_id != "" && credential == "") ||
    (node_id != "" && !@contracts.valid_identifier(node_id, maximum_length=128)) ||
    maximum_artifact_size_bytes <= 0L ||
    io_chunk_bytes < 65536 ||
    io_chunk_bytes > 1048576 ||
    signature_maximum_bytes <= 0L ||
    signature_maximum_bytes > 16777216L {
    raise ArtifactMaterializationError::InvalidConfiguration
  }
  let content_root = "\{cache_root}/sha256"
  if !@fs.exists(content_root) {
    @fs.mkdir(content_root, permission=0o700, recursive=true)
  }
  {
    cache_root: content_root,
    endpoint: base_endpoint(endpoint),
    credential,
    node_id,
    maximum_artifact_size_bytes,
    io_chunk_bytes,
    signature_maximum_bytes,
    allow_http_loopback,
    s3_sigv4: None,
    verified: Map([]),
  }
}

///|
/// Opens a direct S3-compatible materializer. Credentials stay in the node
/// agent and are used only to sign the exact object referenced by its current
/// controller-signed assignment; they are never passed to the model runtime.
pub async fn ArtifactMaterializer::open_s3(
  cache_root : String,
  endpoint : String,
  node_id : String,
  access_key_id : String,
  secret_access_key : String,
  region : String,
  session_token : String?,
  maximum_artifact_size_bytes? : Int64 = 1099511627776L,
  io_chunk_bytes? : Int = 1048576,
  signature_maximum_bytes? : Int64 = 1048576L,
  allow_http_loopback? : Bool = false,
) -> ArtifactMaterializer {
  if !@contracts.valid_identifier(node_id, maximum_length=128) ||
    !safe_s3_credential(access_key_id, 128) ||
    !safe_s3_credential(secret_access_key, 256) ||
    !safe_s3_region(region) ||
    session_token.map_or(false, token => !safe_s3_credential(token, 4096)) {
    raise ArtifactMaterializationError::InvalidConfiguration
  }
  let base = ArtifactMaterializer::open(
    cache_root,
    endpoint,
    "",
    maximum_artifact_size_bytes~,
    io_chunk_bytes~,
    signature_maximum_bytes~,
    allow_http_loopback~,
  )
  {
    ..base,
    node_id,
    s3_sigv4: Some({ access_key_id, secret_access_key, region, session_token }),
  }
}

///|
fn decimal(value : Int, width : Int) -> String {
  let raw = value.to_string()
  if raw.length() >= width {
    raw
  } else {
    "0".repeat(width - raw.length()) + raw
  }
}

///|
fn sigv4_timestamp(
  now_unix_ms : Int64,
) -> (String, String) raise ArtifactMaterializationError {
  let instant = @time.ZonedDateTime::from_unix_second(
    now_unix_ms / 1000L,
    zone=@time.utc_zone,
  ) catch {
    _ => raise InvalidConfiguration
  }
  let date = "\{decimal(instant.year(), 4)}\{decimal(instant.month(), 2)}\{decimal(instant.day(), 2)}"
  let timestamp = "\{date}T\{decimal(instant.hour(), 2)}\{decimal(instant.minute(), 2)}\{decimal(instant.second(), 2)}Z"
  (date, timestamp)
}

///|
fn sha256_hex(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn hmac_sha256(key : FixedArray[Byte], value : String) -> FixedArray[Byte] {
  @crypto.hmac(
    @crypto.SHA256::new(),
    Bytes::from_array(key.view()).view(),
    @utf8.encode(value).view(),
  )
}

///|
fn endpoint_host(
  endpoint : String,
) -> String raise ArtifactMaterializationError {
  let remainder = if endpoint.has_prefix("https://") {
    endpoint["https://".length():].to_owned()
  } else if endpoint.has_prefix("http://") {
    endpoint["http://".length():].to_owned()
  } else {
    raise InvalidConfiguration
  }
  if remainder == "" ||
    remainder.contains_char('/') ||
    remainder.contains_char('@') ||
    remainder.contains_char('?') ||
    remainder.contains_char('#') {
    raise InvalidConfiguration
  }
  remainder.to_lower()
}

///|
fn ArtifactMaterializer::s3_headers(
  self : ArtifactMaterializer,
  uri : String,
  now_unix_ms : Int64,
) -> Map[String, String] raise ArtifactMaterializationError {
  guard self.s3_sigv4 is Some(config) else { return Map([]) }
  if !self.endpoint.has_prefix("https://") && !self.allow_http_loopback {
    raise InvalidConfiguration
  }
  let host = endpoint_host(self.endpoint)
  let canonical_uri = "/\{s3_object_key(uri)}"
  let (date, timestamp) = sigv4_timestamp(now_unix_ms)
  let payload_hash = "UNSIGNED-PAYLOAD"
  let mut canonical_headers = "host:\{host}\nx-amz-content-sha256:\{payload_hash}\nx-amz-date:\{timestamp}\n"
  let mut signed_headers = "host;x-amz-content-sha256;x-amz-date"
  let headers : Map[String, String] = {
    "Accept": "application/octet-stream",
    "Host": host,
    "X-Amz-Content-Sha256": payload_hash,
    "X-Amz-Date": timestamp,
  }
  match config.session_token {
    Some(token) => {
      canonical_headers = canonical_headers + "x-amz-security-token:\{token}\n"
      signed_headers = signed_headers + ";x-amz-security-token"
      headers["X-Amz-Security-Token"] = token
    }
    None => ()
  }
  let canonical_request = "GET\n\{canonical_uri}\n\n\{canonical_headers}\n\{signed_headers}\n\{payload_hash}"
  let scope = "\{date}/\{config.region}/s3/aws4_request"
  let string_to_sign = "AWS4-HMAC-SHA256\n\{timestamp}\n\{scope}\n\{sha256_hex(canonical_request)}"
  let date_key = hmac_sha256(
    @utf8.encode("AWS4\{config.secret_access_key}").to_fixedarray(),
    date,
  )
  let region_key = hmac_sha256(date_key, config.region)
  let service_key = hmac_sha256(region_key, "s3")
  let signing_key = hmac_sha256(service_key, "aws4_request")
  let signature = @crypto.bytes_to_hex_string(
    hmac_sha256(signing_key, string_to_sign),
  )
  headers["Authorization"] = "AWS4-HMAC-SHA256 Credential=\{config.access_key_id}/\{scope}, SignedHeaders=\{signed_headers}, Signature=\{signature}"
  headers
}

///|
fn ArtifactMaterializer::object_url(
  self : ArtifactMaterializer,
  uri : String,
) -> String raise ArtifactMaterializationError {
  "\{self.endpoint}/\{s3_object_key(uri)}"
}

///|
fn ArtifactMaterializer::artifact_path(
  self : ArtifactMaterializer,
  digest : String,
) -> String raise ArtifactMaterializationError {
  "\{self.cache_root}/\{digest_hex(digest)}.model"
}

///|
fn ArtifactMaterializer::signature_path(
  self : ArtifactMaterializer,
  digest : String,
) -> String raise ArtifactMaterializationError {
  "\{self.cache_root}/\{digest_hex(digest)}.sig"
}

///|
fn ArtifactMaterializer::ready_path(
  self : ArtifactMaterializer,
  digest : String,
) -> String raise ArtifactMaterializationError {
  "\{self.cache_root}/\{digest_hex(digest)}.ready"
}

///|
async fn digest_file(path : String, io_chunk_bytes : Int) -> (String, Int64) {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let digest = @crypto.SHA256::new()
  let mut size = 0L
  while file.read_some(max_len=io_chunk_bytes) is Some(chunk) {
    size += chunk.length().to_int64()
    digest.update(chunk)
  }
  ("sha256:\{@crypto.bytes_to_hex_string(digest.finalize())}", size)
}

///|
async fn remove_if_present(path : String) -> Unit {
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

///|
async fn quarantine_if_present(path : String) -> Unit {
  if @fs.exists(path) {
    @fs.rename(path, "\{path}.quarantine", replace=true)
  }
}

///|
async fn ArtifactMaterializer::download(
  self : ArtifactMaterializer,
  uri : String,
  partial_path : String,
  expected_size_bytes : Int64,
  maximum_size_bytes : Int64,
  assignment : @contracts.DesiredAssignment,
) -> (String, Int64) {
  let mut offset = 0L
  let digest = @crypto.SHA256::new()
  if @fs.exists(partial_path) {
    let (partial_digest, partial_size) = digest_file(
      partial_path,
      self.io_chunk_bytes,
    )
    ignore(partial_digest)
    if partial_size > 0L &&
      partial_size < maximum_size_bytes &&
      (expected_size_bytes <= 0L || partial_size < expected_size_bytes) {
      let existing = @fs.open(partial_path, mode=ReadOnly)
      defer existing.close()
      while existing.read_some(max_len=self.io_chunk_bytes) is Some(chunk) {
        digest.update(chunk)
      }
      offset = partial_size
    } else if expected_size_bytes > 0L && partial_size == expected_size_bytes {
      return (partial_digest, partial_size)
    } else {
      remove_if_present(partial_path)
    }
  }
  let headers : Map[String, String] = self.s3_headers(uri, @async.now())
  if self.s3_sigv4 is None && self.credential != "" {
    if self.node_id == "" {
      headers["Authorization"] = "Bearer \{self.credential}"
    } else {
      headers["Authorization"] = "Node \{self.credential}"
      headers["X-LunaNexa-Node-Id"] = self.node_id
      headers["X-LunaNexa-Assignment-Id"] = assignment.assignment_id
      headers["X-LunaNexa-Deployment-Id"] = assignment.deployment_id
      headers["X-LunaNexa-Model-Digest"] = assignment.artifact.digest
    }
  }
  if offset > 0L {
    headers["Range"] = "bytes=\{offset}-"
  }
  let (response, stream) = @http.get_stream(self.object_url(uri), headers~)
  defer stream.close()
  let append = offset > 0L && response.code == 206
  if response.code < 200 || response.code >= 300 {
    raise ArtifactFetchFailed
  }
  if offset > 0L && !append {
    offset = 0L
    digest.reset()
  }
  let file = @fs.open(
    partial_path,
    mode=WriteOnly,
    create_mode=if append { OpenOrCreate } else { CreateOrTruncate },
    permission=0o600,
    sync=NoSync,
    append~,
  )
  defer file.close()
  let mut size = offset
  while stream.read_some(max_len=self.io_chunk_bytes) is Some(chunk) {
    size += chunk.length().to_int64()
    if size > maximum_size_bytes ||
      (expected_size_bytes > 0L && size > expected_size_bytes) {
      raise ArtifactTooLarge
    }
    digest.update(chunk)
    file.write(chunk)
  }
  file.sync()
  if expected_size_bytes > 0L && size != expected_size_bytes {
    raise ArtifactSizeMismatch
  }
  ("sha256:\{@crypto.bytes_to_hex_string(digest.finalize())}", size)
}

///|
async fn[V : ArtifactSignatureVerifier] ArtifactMaterializer::verify_cached(
  self : ArtifactMaterializer,
  artifact : @contracts.ArtifactRef,
  verifier : V,
) -> MaterializedArtifact {
  let artifact_path = self.artifact_path(artifact.digest)
  let signature_path = self.signature_path(artifact.digest)
  let ready_path = self.ready_path(artifact.digest)
  if !@fs.exists(artifact_path) ||
    !@fs.exists(signature_path) ||
    !@fs.exists(ready_path) {
    raise ArtifactFetchFailed
  }
  let (actual_digest, actual_size) = digest_file(
    artifact_path,
    self.io_chunk_bytes,
  )
  if actual_size != artifact.size_bytes {
    raise ArtifactSizeMismatch
  }
  if actual_digest != artifact.digest {
    raise ArtifactDigestMismatch
  }
  ArtifactSignatureVerifier::verify(
    verifier,
    artifact_path,
    signature_path,
    artifact.digest,
  )
  self.verified[artifact.digest] = true
  { digest: artifact.digest, host_path: artifact_path, size_bytes: actual_size }
}

///|
pub async fn[V : ArtifactSignatureVerifier] ArtifactMaterializer::materialize(
  self : ArtifactMaterializer,
  assignment : @contracts.DesiredAssignment,
  verifier : V,
) -> MaterializedArtifact {
  let artifact = assignment.artifact
  if !assignment.network.allow_artifact_store {
    raise ArtifactStoreDenied
  }
  ignore(s3_object_key(artifact.uri))
  let detached_signature_uri = signature_uri(artifact)
  ignore(s3_object_key(detached_signature_uri))
  if artifact.size_bytes <= 0L ||
    artifact.size_bytes > self.maximum_artifact_size_bytes {
    raise ArtifactTooLarge
  }
  let artifact_path = self.artifact_path(artifact.digest)
  let signature_path = self.signature_path(artifact.digest)
  let ready_path = self.ready_path(artifact.digest)
  if self.verified.get(artifact.digest).unwrap_or(false) &&
    @fs.exists(artifact_path) &&
    @fs.exists(signature_path) &&
    @fs.exists(ready_path) {
    return {
      digest: artifact.digest,
      host_path: artifact_path,
      size_bytes: artifact.size_bytes,
    }
  }
  if @fs.exists(artifact_path) ||
    @fs.exists(signature_path) ||
    @fs.exists(ready_path) {
    try self.verify_cached(artifact, verifier) catch {
      _ => {
        quarantine_if_present(artifact_path)
        quarantine_if_present(signature_path)
        quarantine_if_present(ready_path)
      }
    } noraise {
      cached => return cached
    }
  }
  let artifact_partial = "\{artifact_path}.partial"
  let signature_partial = "\{signature_path}.partial"
  let (actual_digest, actual_size) = self.download(
    artifact.uri,
    artifact_partial,
    artifact.size_bytes,
    self.maximum_artifact_size_bytes,
    assignment,
  )
  if actual_size != artifact.size_bytes {
    raise ArtifactSizeMismatch
  }
  if actual_digest != artifact.digest {
    quarantine_if_present(artifact_partial)
    raise ArtifactDigestMismatch
  }
  ignore(
    self.download(
      detached_signature_uri,
      signature_partial,
      0L,
      self.signature_maximum_bytes,
      assignment,
    ),
  )
  ArtifactSignatureVerifier::verify(
    verifier,
    artifact_partial,
    signature_partial,
    artifact.digest,
  ) catch {
    _ => {
      quarantine_if_present(artifact_partial)
      quarantine_if_present(signature_partial)
      raise ArtifactSignatureInvalid
    }
  }
  @fs.rename(artifact_partial, artifact_path, replace=true)
  @fs.rename(signature_partial, signature_path, replace=true)
  let ready_partial = "\{ready_path}.partial"
  @fs.write_file(
    ready_partial,
    artifact.digest,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(ready_partial, ready_path, replace=true)
  self.verified[artifact.digest] = true
  { digest: artifact.digest, host_path: artifact_path, size_bytes: actual_size }
}

///|
pub async fn ArtifactMaterializer::prune_unassigned(
  self : ArtifactMaterializer,
  desired_digests : Array[String],
) -> Unit {
  let desired_hex = [ for digest in desired_digests => digest_hex(digest) ]
  for entry in @fs.readdir(self.cache_root, include_hidden=true) {
    let keep = desired_hex.any(hex => entry.has_prefix("\{hex}."))
    if !keep {
      remove_if_present("\{self.cache_root}/\{entry}")
    }
  }
  let stale = [
    for digest, _ in self.verified if !desired_digests.any(value => {
      value == digest
    }) => digest
  ]
  for digest in stale {
    ignore(self.verified.remove(digest))
  }
}
