///|
pub(all) suberror StorageError {
  DigestNotPinned(String)
  EmptyObjectKey
  UntrustedEndpoint
  ArtifactTooLarge
  DigestMismatch
  ArtifactFetchFailed
} derive(Debug, Eq)

///|
pub(all) struct S3ArtifactStore {
  endpoint_ref : String
  bucket : String
  credential_ref : String
  require_tls : Bool
} derive(Debug, Eq)

///|
pub fn S3ArtifactStore::new(
  endpoint_ref : String,
  bucket : String,
  credential_ref : String,
  require_tls? : Bool = true,
) -> S3ArtifactStore raise StorageError {
  if endpoint_ref == "" || !require_tls {
    raise UntrustedEndpoint
  }
  { endpoint_ref, bucket, credential_ref, require_tls }
}

///|
pub(all) struct VerifiedArtifactDownload {
  digest : String
  size_bytes : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct S3HttpVerifier {
  endpoint : String
  credential_value : String
}

///|
pub fn S3HttpVerifier::new(
  endpoint : String,
  credential_value : String,
  allow_http_loopback? : Bool = false,
) -> S3HttpVerifier raise StorageError {
  let secure = endpoint.has_prefix("https://")
  let loopback = allow_http_loopback &&
    (
      endpoint.has_prefix("http://127.0.0.1:") ||
      endpoint.has_prefix("http://localhost:")
    )
  if !secure && !loopback {
    raise UntrustedEndpoint
  }
  { endpoint, credential_value }
}

///|
fn artifact_url(
  endpoint : String,
  object_key : String,
) -> String raise StorageError {
  if object_key == "" ||
    object_key.contains("..") ||
    object_key.contains_char('\n') {
    raise EmptyObjectKey
  }
  let base = if endpoint.has_suffix("/") {
    endpoint[:-1].to_owned()
  } else {
    endpoint
  }
  "\{base}/\{object_key}"
}

///|
pub async fn S3HttpVerifier::verify(
  self : S3HttpVerifier,
  object_key : String,
  expected_digest : String,
  maximum_size_bytes : Int64,
) -> VerifiedArtifactDownload {
  if !@contracts.valid_sha256_digest(expected_digest) {
    raise DigestNotPinned(expected_digest)
  }
  let headers : Map[String, String] = { "Accept": "application/octet-stream" }
  if self.credential_value != "" {
    headers["Authorization"] = "Bearer \{self.credential_value}"
  }
  let (response, stream) = @http.get_stream(
    artifact_url(self.endpoint, object_key),
    headers~,
  )
  if response.code < 200 || response.code >= 300 {
    stream.close()
    raise ArtifactFetchFailed
  }
  let digest = @crypto.SHA256::new()
  let mut size = 0L
  while stream.read_some(max_len=65536) is Some(chunk) {
    size += chunk.length().to_int64()
    if maximum_size_bytes <= 0L || size > maximum_size_bytes {
      stream.close()
      raise ArtifactTooLarge
    }
    digest.update(chunk)
  }
  stream.close()
  let actual = "sha256:\{@crypto.bytes_to_hex_string(digest.finalize())}"
  if actual != expected_digest {
    raise DigestMismatch
  }
  { digest: actual, size_bytes: size }
}

///|
pub fn S3ArtifactStore::artifact_ref(
  self : S3ArtifactStore,
  object_key : String,
  digest : String,
  size_bytes : Int64,
  signature_ref : String,
) -> @contracts.ArtifactRef raise StorageError {
  if object_key == "" {
    raise EmptyObjectKey
  }
  if !@contracts.valid_sha256_digest(digest) {
    raise DigestNotPinned(digest)
  }
  {
    digest,
    uri: "s3://\{self.bucket}/\{object_key}",
    size_bytes,
    signature_ref,
  }
}

///|
pub(all) struct OciRuntimeRegistry {
  registry_ref : String
  credential_ref : String
  require_signature : Bool
} derive(Debug, Eq)

///|
pub fn OciRuntimeRegistry::runtime_spec(
  self : OciRuntimeRegistry,
  name : String,
  image_digest : String,
  version : String,
  architectures : Array[String],
  capabilities : Array[@contracts.Capability],
  supports_batching? : Bool = false,
  supports_multi_node? : Bool = false,
) -> @contracts.RuntimeSpec raise StorageError {
  if self.registry_ref == "" || !self.require_signature {
    raise UntrustedEndpoint
  }
  if !@contracts.valid_sha256_digest(image_digest) {
    raise DigestNotPinned(image_digest)
  }
  {
    name,
    image_digest,
    version,
    architectures,
    capabilities,
    supports_batching,
    supports_multi_node,
  }
}
