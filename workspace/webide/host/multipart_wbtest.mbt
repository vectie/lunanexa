///|
test "text multipart normalization rejects files duplicate fields and ambiguous framing" {
  let header = "multipart/form-data; boundary=fixture"
  let field = "\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvideo.h3\r\n"
  let valid = "--fixture" + field + "--fixture--\r\n"
  assert_true(
    multipart_fields(header, @utf8.encode(valid)) is Some(fields) &&
    fields["model"] == "video.h3",
  )
  for
    body in [
      "--fixture" + field + "--fixture" + field + "--fixture--\r\n",
      "--fixture\r\nContent-Disposition: form-data; name=\"image\"; filename=\"x.png\"\r\n\r\nx\r\n--fixture--\r\n",
      "--fixture\r\nContent-Disposition: form-data; name=\"prompt\"\r\nContent-Type: text/plain-evil\r\n\r\nx\r\n--fixture--\r\n",
      "prefix" + valid,
      valid + "suffix",
      valid + valid,
      "--fixture\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\n" +
      "x".repeat(65536) +
      "\r\n--fixture--\r\n",
    ] {
    assert_eq(multipart_fields(header, @utf8.encode(body)), None)
  }
  assert_eq(
    multipart_fields("multipart/form-data; boundary=other", @utf8.encode(valid)),
    None,
  )
}

///|
test "editor neutral sampler defaults normalize while non-neutral overrides fail" {
  let header = "multipart/form-data; boundary=sampler"
  for
    (name, value, valid) in [
      ("n", "1", true),
      ("n", "2", false),
      ("guidance_scale", "1.0", true),
      ("guidance_scale", "6.0", false),
      ("true_cfg_scale", "1", true),
      ("true_cfg_scale", "0", false),
      ("vae_use_slicing", "false", true),
      ("vae_use_slicing", "true", false),
      ("vae_use_tiling", "false", true),
      ("vae_use_tiling", "true", false),
    ] {
    let body = "--sampler\r\nContent-Disposition: form-data; name=\"" +
      name +
      "\"\r\n\r\n" +
      value +
      "\r\n--sampler--\r\n"
    if valid {
      guard multipart_fields(header, @utf8.encode(body)) is Some(fields) else {
        fail("neutral editor default was rejected")
      }
      assert_false(fields.contains(name))
    } else {
      assert_eq(multipart_fields(header, @utf8.encode(body)), None)
    }
  }
}

///|
test "editor text-only form normalizes Python defaults without accepting ambiguous or effective overrides" {
  guard urlencoded_video_fields(
      b"model=video.h3&prompt=Ocean+sunrise&width=512&height=512&num_frames=25&fps=24&num_inference_steps=8&seed=1&n=1&guidance_scale=1.0&true_cfg_scale=1.0&vae_use_slicing=False&vae_use_tiling=False",
    )
    is Some(fields) else {
    fail("pinned editor text form was rejected")
  }
  assert_eq(fields["prompt"], "Ocean sunrise")
  assert_eq(fields["seed"], "1")
  assert_false(fields.contains("vae_use_slicing"))
  assert_false(fields.contains("n"))
  for
    body in [
      b"model=video.h3&%6dodel=evil", b"model=%GG", b"model=video.h3&n=2", b"model=video.h3&vae_use_tiling=True",
      b"model=video.h3&guidance_scale=7.0",
    ] {
    assert_eq(urlencoded_video_fields(body), None)
  }
}

///|
test "reference multipart preserves binary PNG bytes and rejects unqualified file fields" {
  let header = "multipart/form-data; boundary=reference"
  let image = b"\x89PNG\r\n\x1a\n\xff\x00\xfe"
  let body = Buffer()
  body.write_bytes(
    b"--reference\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nRef2VA\r\n--reference\r\nContent-Disposition: form-data; name=\"input_reference\"; filename=\"image.png\"\r\nContent-Type: image/png\r\n\r\n",
  )
  body.write_bytes(image)
  body.write_bytes(b"\r\n--reference--\r\n")
  guard multipart_fields(header, body.to_bytes()) is Some(fields) else {
    fail("binary reference was lost")
  }
  assert_eq(fields["model"], "Ref2VA")
  assert_eq(
    fields["input_reference"],
    "data:image/png;base64," + @base64.encode(image),
  )
  let mime = Buffer()
  mime.write_bytes(
    b"--reference\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nRef2VA\r\n--reference\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Disposition: form-data; name=\"vae_use_slicing\"\r\n\r\nFalse\r\n--reference\r\nContent-Type: image/png\r\nContent-Disposition: form-data; name=\"input_reference\"; filename=\"image.png\"\r\n\r\n",
  )
  mime.write_bytes(image)
  mime.write_bytes(b"\r\n--reference--\r\n")
  guard multipart_fields(header, mime.to_bytes()) is Some(mime_fields) else {
    fail("pinned aiohttp header order was rejected")
  }
  assert_eq(mime_fields["input_reference"], fields["input_reference"])
  assert_false(mime_fields.contains("vae_use_slicing"))
  assert_eq(
    multipart_fields(
      header,
      @utf8.encode(
        "--reference\r\nContent-Disposition: form-data; name=\"input_reference\"; filename=\"image.png\"\r\nContent-Type: application/octet-stream\r\n\r\nx\r\n--reference--\r\n",
      ),
    ),
    None,
  )
}
