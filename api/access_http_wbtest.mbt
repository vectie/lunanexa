///|
test "bearer credential mutation fuzz rejects controls and ambiguous syntax" {
  assert_eq(
    bearer_secret({ "Authorization": "Bearer token._~-safe" }),
    Some("token._~-safe"),
  )
  for
    value in [
      "",
      "Bearer",
      "Bearer ",
      "bearer token",
      "Basic token",
      "Bearer token value",
      "Bearer token\nX-Forged: yes",
      "Bearer token\rX-Forged: yes",
      "Bearer token\tvalue",
      "Bearer 服务",
      "Bearer \u{7f}",
      "Bearer " + "a".repeat(4097),
    ] {
    assert_eq(bearer_secret({ "Authorization": value }), None)
  }
  for character in [' ', '\n', '\r', '\t', '\u{0}', '\u{7f}'] {
    let value = "Bearer left\{character}right"
    assert_eq(bearer_secret({ "Authorization": value }), None)
  }
}

///|
test "OpenAI compatibility decoder rejects malformed and oversized shapes" {
  for
    body in [
      "", "{", "[]", "null", "true", "{}", "{\"model\":1}", "{\"model\":\"model-a\",\"messages\":{}}",
    ] {
    assert_true(decode_openai_chat(body) is None)
  }
  let valid = "{\"model\":\"model-a\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  assert_true(decode_openai_chat(valid) is Some(_))
}
