///|
/// Read one explicitly selected ordinary file with bounded working memory.
/// All declarations are validated before acquisition; nothing is written until
/// the complete existing Candidate draft is ready.
async fn read_local_artifact(
  path : String,
  metadata : @model_intake.ArtifactMetadata,
) -> @model_intake.Draft {
  if @fs.kind(path) != Regular {
    fail("local artifact must be a regular file")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    fail("local artifact must be a regular file")
  }
  let size = file.size()
  if size <= 0L || size > metadata.maximum_artifact_bytes {
    fail("local artifact must be nonempty and within maximum_artifact_bytes")
  }
  let modified = file.mtime()
  let changed = file.ctime()
  let digest = @crypto.SHA256::new()
  for consumed = 0L; consumed < size; {
    let remaining = size - consumed
    let count = if remaining > 65536L { 65536 } else { remaining.to_int() }
    let bytes = file.read_exactly(count)
    digest.update(bytes)
    continue consumed + count.to_int64()
  }
  if file.read_some(max_len=1) is Some(_) ||
    file.size() != size ||
    file.mtime() != modified ||
    file.ctime() != changed {
    fail("local artifact changed while reading; retry with a stable file")
  }
  @model_intake.artifact_draft(
    metadata,
    "sha256:" + @crypto.bytes_to_hex_string(digest.finalize()),
    size,
  )
}
