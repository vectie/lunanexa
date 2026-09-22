///|
test "operator file integrity works on public HTTP without WebCrypto" {
  assert_eq(
    operator_download_digest(b"abc"),
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}
