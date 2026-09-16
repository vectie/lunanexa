///|
/// Convert the pinned editor's text-only multipart form to the provider's
/// JSON contract. Files, duplicate fields and ambiguous framing fail closed.
fn multipart_fields(
  content_type : String,
  payload : Bytes,
) -> Map[String, String]? {
  try {
    let prefix = "multipart/form-data; boundary="
    if !content_type.has_prefix(prefix) || payload.length() > 65536 {
      return None
    }
    let boundary = content_type[prefix.length():].to_owned()
    if boundary.is_empty() ||
      boundary.length() > 70 ||
      !boundary.all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-' ||
        c == '_'
      }) {
      return None
    }
    let text = @utf8.decode(payload)
    if !text.has_prefix("--" + boundary + "\r\n") ||
      !text.has_suffix("--" + boundary + "--\r\n") {
      return None
    }
    let parts = text.split("--" + boundary).to_array()
    if parts.length() < 3 || parts.length() > 34 {
      return None
    }
    let fields : Map[String, String] = Map([])
    for index in 1..<(parts.length() - 1) {
      let part = parts[index]
      guard part.has_prefix("\r\n") &&
        part.has_suffix("\r\n") &&
        part.find("\r\n\r\n") is Some(separator) else {
        return None
      }
      let lines = part[2:separator].split("\r\n").to_array()
      let disposition = "Content-Disposition: form-data; name=\""
      if lines.length() < 1 ||
        lines.length() > 2 ||
        !lines[0].has_prefix(disposition) ||
        !lines[0].has_suffix("\"") {
        return None
      }
      let name = lines[0][disposition.length():lines[0].length() - 1].to_owned()
      if name.is_empty() ||
        !name.all(c => (c >= 'a' && c <= 'z') || c == '_') ||
        fields.contains(name) {
        return None
      }
      if lines.length() == 2 &&
        !["Content-Type: text/plain", "Content-Type: text/plain; charset=utf-8"].contains(
          lines[1].to_owned(),
        ) {
        return None
      }
      fields[name] = part[separator + 4:part.length() - 2].to_owned()
    }
    Some(fields)
  } catch {
    _ => None
  }
}
