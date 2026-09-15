///|
/// Selects only the transport format. Cosign remains the signature authority;
/// malformed JSON never falls back to the legacy signature verifier.
fn flag_for_prefix(prefix : Bytes) -> String {
  for byte in prefix {
    if byte == b' ' || byte == b'\t' || byte == b'\r' || byte == b'\n' {
      continue
    }
    return if byte == b'{' { "--bundle" } else { "--signature" }
  }
  "--bundle"
}

///|
/// Bounded format sniffing also works for content-addressed `.sig` cache files.
pub async fn cosign_material_flag(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  match file.read_some(max_len=4096) {
    Some(prefix) => flag_for_prefix(prefix)
    None => "--bundle"
  }
}
