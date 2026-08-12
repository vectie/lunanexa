///|
test "enterprise lease model input is trimmed and empty entries are ignored" {
  assert_eq(
    requested_models(" text.default,embedding.default ,, image.default "),
    ["text.default", "embedding.default", "image.default"],
  )
  assert_eq(requested_models(" , , "), [])
}
