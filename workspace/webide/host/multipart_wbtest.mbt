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
