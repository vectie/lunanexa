///|
test "signature format selection never downgrades JSON bundles" {
  assert_eq(
    flag_for_prefix(
      b"{\"mediaType\":\"application/vnd.dev.sigstore.bundle.v0.3+json\"}",
    ),
    "--bundle",
  )
  assert_eq(flag_for_prefix(b" \r\n\t{invalid"), "--bundle")
  assert_eq(flag_for_prefix(b"MEUCIQ=="), "--signature")
  assert_eq(flag_for_prefix(b""), "--bundle")
  assert_eq(flag_for_prefix(b" \t\r\n"), "--bundle")
}
