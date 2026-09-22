///|
async test "idle cache survives restart and pressure never evicts active or pinned revisions" {
  let root = @fs.tmpdir(prefix="lunanexa-cache-lifecycle-")
  defer @fs.rmdir(root, recursive=true)
  let cache = @node.ArtifactMaterializer::open(
    root,
    "http://127.0.0.1:1",
    "artifact-token",
    allow_http_loopback=true,
  )
  let old = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let active = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let pinned = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let recent = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  for hex in [old, active, pinned] {
    @fs.mkdir("\{root}/sha256/\{hex}.revision")
    @fs.write_file(
      "\{root}/sha256/\{hex}.revision/model.bin",
      "weights",
      create_mode=CreateOrTruncate,
    )
  }
  @fs.write_file(
    "\{root}/sha256/operator-note",
    "not a model",
    create_mode=CreateOrTruncate,
  )
  cache.prune_unassigned([], now_unix_ms=1000L)
  let restarted = @node.ArtifactMaterializer::open(
    root,
    "http://127.0.0.1:1",
    "artifact-token",
    allow_http_loopback=true,
  )
  @fs.write_file(
    "\{root}/sha256/\{recent}.model.partial",
    "partial",
    create_mode=CreateOrTruncate,
  )
  restarted.prune_unassigned(
    ["sha256:\{active}"],
    now_unix_ms=2000L,
    idle_retention_ms=1500L,
    pinned_digests=["sha256:\{pinned}"],
  )
  assert_true(@fs.exists("\{root}/sha256/\{old}.revision/model.bin"))
  restarted.prune_unassigned(
    ["sha256:\{active}"],
    now_unix_ms=2600L,
    idle_retention_ms=1500L,
    pinned_digests=["sha256:\{pinned}"],
  )
  assert_false(@fs.exists("\{root}/sha256/\{old}.revision"))
  assert_true(@fs.exists("\{root}/sha256/\{recent}.model.partial"))
  restarted.prune_unassigned(
    ["sha256:\{active}"],
    now_unix_ms=2700L,
    high_watermark_bytes=1L,
    low_watermark_bytes=0L,
    pinned_digests=["sha256:\{pinned}"],
  )
  assert_false(@fs.exists("\{root}/sha256/\{recent}.model.partial"))
  assert_true(@fs.exists("\{root}/sha256/\{active}.revision/model.bin"))
  assert_true(@fs.exists("\{root}/sha256/\{pinned}.revision/model.bin"))
  assert_true(@fs.exists("\{root}/sha256/operator-note"))
}
