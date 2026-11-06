///|
async fn main {
  guard @env.args() is [_, origin, root, id] &&
    root.has_prefix("/") &&
    id.has_prefix("image-qualification-") &&
    id.length() < 80 &&
    id.all(c => c is ('a'..<='z' | '0'..<='9' | '-')) else {
    fail(
      "image-probe PRIVATE_COMFY_ORIGIN NEW_PRIVATE_OUTPUT_DIR image-qualification-ID",
    )
  }
  let provider = @provider.Provider::new(origin, {
    diffusion: "z_image_turbo_bf16.safetensors",
    text_encoder: "qwen_3_4b.safetensors",
    vae: "ae.safetensors",
  })
  let prompt = "一只圆滚滚的奶油白咖啡杯，困倦的橙色小猫趴在杯沿，轻柔的晨光，半醒咖啡主题，温暖的纸质拼贴插画，墨绿色背景，简洁构图，无文字，无水印"
  if !@fs.exists(root) {
    @fs.mkdir(root, permission=0o700, recursive=true)
  }
  let intent = root + "/intent.json"
  let seed_bytes = @crypto.sha256(@utf8.encode(id))
  let seed = (seed_bytes[0].to_uint() << 24) |
    (seed_bytes[1].to_uint() << 16) |
    (seed_bytes[2].to_uint() << 8) |
    seed_bytes[3].to_uint()
  let started = @async.now()
  let prompt_id = if @fs.exists(intent) {
    match provider.lookup(id) {
      Some(found) => found
      None =>
        fail(
          "Existing probe acceptance is uncertain; inspect runtime, never resubmit",
        )
    }
  } else {
    @fs.write_file(
      intent,
      (
        {
          "request_id": id,
          "origin": origin,
          "started_ms": started.to_string(),
        } : Json).stringify(),
      create_mode=CreateNew,
      permission=0o600,
      sync=Full,
    )
    provider.submit(prompt, seed, id)
  }
  println("Accepted qualification graph: " + prompt_id)
  for _ in 0..<300 {
    match provider.observe(prompt_id, id) {
      Complete(filename) => {
        let bytes = provider.content(filename)
        @fs.write_file(
          root + "/qualification.png",
          bytes,
          create_mode=CreateOrTruncate,
          permission=0o600,
          sync=Full,
        )
        let evidence : Json = {
          "request_id": id,
          "prompt_id": prompt_id,
          "elapsed_ms": (@async.now() - started).to_string(),
          "size_bytes": bytes.length(),
          "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
          "runtime_origin": origin,
        }
        @fs.write_file(
          root + "/probe-result.json",
          evidence.stringify(indent=2),
          create_mode=CreateOrTruncate,
          permission=0o600,
          sync=Full,
        )
        println(evidence.stringify())
        return
      }
      Failed => fail("Qualification graph failed; inspect runtime logs")
      Pending => @async.sleep(2000)
    }
  }
  fail(
    "Probe is still running; inspect with reads before any further submission",
  )
}
