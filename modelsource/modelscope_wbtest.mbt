///|
test "official ModelScope catalog shape decodes without lossy coercion" {
  let value = @json.parse(
    (
      #|{"id":"OpenBMB/MiniCPM5-1B","display_name":"MiniCPM5-1B","description":"","downloads":237671,"likes":61,"license":"apache-2.0","tasks":["text-generation"],"created_at":"2026-05-22T03:05:53Z","last_modified":"2026-08-17T12:33:04Z","file_size":2171355326,"params":1080632832,"tags":["license:apache-2.0"],"private":false,"gated":false}
    ),
  )
  let model = decode_catalog_model(value)
  assert_eq(model.id, "OpenBMB/MiniCPM5-1B")
  assert_eq(model.file_size, 2171355326L)
}

///|
test "ModelScope LFS redirects remain inside the HTTPS provider boundary" {
  assert_true(
    trusted_modelscope_download_redirect(
      "https://cdn-lfs-cn-1.modelscope.cn/prod/lfs-objects/aa?auth_key=redacted",
    ),
  )
  assert_true(
    trusted_modelscope_download_redirect(
      "https://modelscope.cn/models/OpenBMB/MiniCPM5-1B",
    ),
  )
  for
    value in [
      "http://cdn-lfs-cn-1.modelscope.cn/object", "https://modelscope.cn.evil.example/object",
      "https://evilmodelscope.cn/object", "https://user@cdn-lfs-cn-1.modelscope.cn/object",
      "https://cdn-lfs-cn-1.modelscope.cn:443/object", "https://%40.modelscope.cn/object",
      "https://cdn-lfs-cn-1.modelscope.cn/object#fragment", "/relative/object",
    ] {
    assert_false(trusted_modelscope_download_redirect(value))
  }
}

///|
test "large ModelScope objects are partitioned below the HTTP Int boundary" {
  let file_size = 2161290912L
  assert_eq(modelscope_download_chunk_end(file_size, 0L), 67108863L)
  assert_eq(modelscope_download_chunk_end(file_size, 67108864L), 134217727L)
  let last_start = 2147483648L
  assert_eq(
    modelscope_download_chunk_end(file_size, last_start),
    file_size - 1L,
  )
  assert_true(file_size - last_start <= ModelScopeDownloadChunkBytes)
}

///|
async test "ModelScope retry reuses an already verified file without network" {
  let directory = @fs.tmpdir(prefix="lunanexa-modelscope-reuse-")
  let destination = "\{directory}/model.bin"
  @fs.write_file(
    destination,
    "artifact-bytes",
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  let client = ModelScopeClient::new()
  let progress = Ref(0L)
  client.download_file(
    "OpenBMB/MiniCPM5-1B",
    "revision",
    {
      path: "model.bin",
      revision: "revision",
      sha256: "6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c",
      size: 14L,
      lfs: true,
    },
    destination,
    delta => progress.val += delta,
    () => false,
  )
  assert_eq(progress.val, 14L)
  assert_eq(@fs.read_file(destination).text(), "artifact-bytes")
  @fs.rmdir(directory, recursive=true)
}
