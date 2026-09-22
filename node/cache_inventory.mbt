///|
/// Digest-only locality hints. Revision reuse verifies the manifest digest and
/// file sizes, not a fresh hash of every large weight on every heartbeat.
/// Flat blobs are advertised only after verification in this agent process.
pub async fn ArtifactMaterializer::verified_cache_digests(
  self : ArtifactMaterializer,
) -> Array[String] {
  let result : Array[String] = []
  for entry in @fs.readdir(self.cache_root, sort=true) {
    if result.length() >= 64 {
      break
    }
    let revision = entry.has_suffix(".revision.ready")
    if !revision && !entry.has_suffix(".ready") {
      continue
    }
    let suffix = if revision { ".revision.ready" } else { ".ready" }
    let digest = "sha256:" + entry[:entry.length() - suffix.length()].to_owned()
    if !@contracts.valid_sha256_digest(digest) {
      continue
    }
    let valid = try {
      if revision {
        let root = self.revision_root(digest)
        let bytes = @fs.read_file(
          "\{root}/\{@contracts.model_store_manifest_name}",
        ).binary()
        let manifest : ManagedRevisionManifest = @json.from_json(
          @json.parse(@utf8.decode(bytes)),
        )
        if managed_revision_manifest_errors(manifest) {
          false
        } else {
          let mut size = 0L
          for file in manifest.files {
            size += file.size
          }
          ignore(
            verify_materialized_revision(
              root,
              { digest, uri: "", size_bytes: size, signature_ref: "", },
              self.revision_ready_path(digest),
            ),
          )
          true
        }
      } else if self.verified.get(digest).unwrap_or(false) &&
        @fs.read_file(self.ready_path(digest)).text() == digest &&
        @fs.exists(self.artifact_path(digest)) &&
        @fs.exists(self.signature_path(digest)) {
        true
      } else {
        false
      }
    } catch {
      _ => false
    }
    if valid {
      result.push(digest)
    }
  }
  result
}

///|
pub async fn ArtifactMaterializer::cache_inventory(
  self : ArtifactMaterializer,
  inventory : @contracts.NodeInventory,
) -> @contracts.NodeInventory {
  let labels = inventory.labels.copy()
  labels["lunanexa.io/verified-artifact-digests"] = self
    .verified_cache_digests()
    .to_json()
    .stringify()
  { ..inventory, labels, }
}
