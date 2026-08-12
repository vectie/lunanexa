///|
test "Responses input translation accepts canonical text payload shapes" {
  assert_eq(responses_input({ "input": "hello" }).stringify(), "\"hello\"")
  assert_eq(responses_input({ "prompt": "hello" }).stringify(), "\"hello\"")
  assert_eq(
    responses_input({ "messages": [{ "role": "user", "content": "hello" }] }).stringify(),
    "[{\"role\":\"user\",\"content\":\"hello\"}]",
  )
}

///|
test "Responses input translation rejects nested object input" {
  try responses_input({ "input": { "text": "hello" } }) catch {
    InvalidUpstreamResponse(message) =>
      assert_true(message.contains("string or message array"))
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("nested object input was accepted")
  }
}
