///|
/// Convert the pinned editor's bounded multipart form into JSON. Reference
/// images are data, never host paths or external URLs; the provider's qualified
/// profile still decides whether that model may accept one.
fn multipart_fields(
  content_type : String,
  payload : Bytes,
) -> Map[String, String]? {
  try {
    let prefix = "multipart/form-data; boundary="
    if !content_type.has_prefix(prefix) || payload.length() > 1048576 {
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
    let first = @utf8.encode("--" + boundary + "\r\n")
    let marker = @utf8.encode("\r\n--" + boundary)
    if !payload.has_prefix(first) ||
      !payload.has_suffix(@utf8.encode("--" + boundary + "--\r\n")) {
      return None
    }
    let fields : Map[String, String] = Map([])
    let mut offset = first.length()
    while offset < payload.length() {
      if fields.length() >= 32 {
        return None
      }
      let rest = payload[offset:]
      guard rest.find(marker) is Some(end) else { return None }
      let part = rest[:end]
      guard part.find(b"\r\n\r\n") is Some(separator) && separator <= 1024 else {
        return None
      }
      let lines = @utf8.decode(part[:separator]).split("\r\n").to_array()
      let disposition = "Content-Disposition: form-data; name=\""
      // MIME header order is not significant. aiohttp writes Content-Type
      // before Content-Disposition when a reference image makes the form MIME.
      if lines.length() == 2 && lines[1].has_prefix(disposition) {
        let first_line = lines[0]
        lines[0] = lines[1]
        lines[1] = first_line
      }
      if lines.length() < 1 ||
        lines.length() > 2 ||
        !lines[0].has_prefix(disposition) {
        return None
      }
      let attrs = lines[0][disposition.length():]
      guard attrs.find("\"") is Some(close) else { return None }
      let name = attrs[:close].to_owned()
      let suffix = attrs[close + 1:]
      if name.is_empty() ||
        !name.all(c => (c >= 'a' && c <= 'z') || c == '_') ||
        fields.contains(name) {
        return None
      }
      let value = part[separator + 4:]
      if !suffix.is_empty() {
        guard name == "input_reference" &&
          suffix.has_prefix("; filename=\"") &&
          suffix.has_suffix("\"") &&
          suffix.length() <= 160 &&
          !suffix.contains("\r") &&
          !suffix.contains("\n") &&
          lines.length() == 2 &&
          lines[1] == "Content-Type: image/png" &&
          value.has_prefix(b"\x89PNG\r\n\x1a\n") else {
          return None
        }
        let filename = suffix["; filename=\"".length():suffix.length() - 1]
        if filename.is_empty() ||
          !filename.all(c => {
            (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            ['.', '-', '_'].contains(c)
          }) {
          return None
        }
        fields[name] = "data:image/png;base64," + @base64.encode(value)
      } else {
        if value.length() >
          (if name == "audio_reference" { 524288 } else { 65535 }) ||
          (
            lines.length() == 2 &&
            ![
              "Content-Type: text/plain", "Content-Type: text/plain; charset=utf-8",
            ].contains(lines[1].to_owned())
          ) {
          return None
        }
        fields[name] = @utf8.decode(value)
      }
      offset += end + marker.length()
      if payload[offset:].has_prefix(b"--\r\n") {
        if offset + 4 != payload.length() {
          return None
        }
        return if normalize_editor_sampling(fields) {
          Some(fields)
        } else {
          None
        }
      }
      if !payload[offset:].has_prefix(b"\r\n") {
        return None
      }
      offset += 2
    }
    None
  } catch {
    _ => None
  }
}

///|
fn normalize_editor_sampling(fields : Map[String, String]) -> Bool {
  // Python's str(bool) is capitalized; model parameters use JSON booleans.
  // Omit only identity values. Unsupported effective overrides still fail.
  for
    (name, neutral) in [
      ("n", ["1"]),
      ("guidance_scale", ["1", "1.0"]),
      ("true_cfg_scale", ["1", "1.0"]),
      ("vae_use_slicing", ["false", "False"]),
      ("vae_use_tiling", ["false", "False"]),
    ] {
    if fields.get(name) is Some(value) {
      if !neutral.contains(value) {
        return false
      }
      fields.remove(name)
    }
  }
  true
}

///|
fn urlencoded_video_fields(payload : Bytes) -> Map[String, String]? {
  try {
    if payload.length() > 65536 {
      return None
    }
    let fields : Map[String, String] = Map([])
    for part in @utf8.decode(payload).split("&") {
      guard fields.length() < 32 && part.find("=") is Some(separator) else {
        return None
      }
      let name = decode_component(part[:separator].to_owned())
      guard !name.is_empty() &&
        name.all(c => (c >= 'a' && c <= 'z') || c == '_') &&
        !fields.contains(name) else {
        return None
      }
      fields[name] = decode_component(part[separator + 1:].to_owned())
    }
    if normalize_editor_sampling(fields) {
      Some(fields)
    } else {
      None
    }
  } catch {
    _ => None
  }
}
