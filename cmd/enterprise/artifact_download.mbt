///|
/// HTTP browser profiles lack WebCrypto.subtle; integrity must still be checked.
fn offline_download_digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes.to_fixedarray()))
}
