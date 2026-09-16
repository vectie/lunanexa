///|
fn valid_profile(profile : Profile) -> Bool {
  @contracts.valid_identifier(profile.model) &&
  profile.provider_model.length() >= 1 &&
  profile.provider_model.length() <= 256 &&
  profile.provider_model.all(c => c >= '!' && c <= '~') &&
  !profile.widths.is_empty() &&
  profile.widths.length() <= 32 &&
  !profile.heights.is_empty() &&
  profile.heights.length() <= 32 &&
  profile.widths.all(n => n >= 64 && n <= 4096 && n % 8 == 0) &&
  profile.heights.all(n => n >= 64 && n <= 4096 && n % 8 == 0) &&
  profile.maximum_frames >= 1 &&
  profile.maximum_frames <= 4096 &&
  profile.maximum_fps >= 1 &&
  profile.maximum_fps <= 120 &&
  profile.maximum_steps >= 1 &&
  profile.maximum_steps <= 1000
}

///|
fn decode_component(value : String) -> String raise {
  let bytes = Buffer()
  let encoded = @utf8.encode(value)
  let mut index = 0
  while index < encoded.length() {
    let byte = encoded[index]
    if byte == b'%' {
      if index + 2 >= encoded.length() {
        raise InvalidRequest
      }
      let high = hex_digit(encoded[index + 1])
      let low = hex_digit(encoded[index + 2])
      bytes.write_byte((high * 16 + low).to_byte())
      index += 3
    } else {
      bytes.write_byte(if byte == b'+' { b' ' } else { byte })
      index += 1
    }
  }
  @utf8.decode(bytes.to_bytes())
}

///|
fn hex_digit(byte : Byte) -> Int raise ProviderError {
  if byte >= b'0' && byte <= b'9' {
    byte.to_int() - 48
  } else if byte >= b'a' && byte <= b'f' {
    byte.to_int() - 87
  } else if byte >= b'A' && byte <= b'F' {
    byte.to_int() - 55
  } else {
    raise InvalidRequest
  }
}

///|
fn encode_component(value : String) -> String {
  let result = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      [45, 46, 95, 126].contains(n) {
      result.write_char(n.unsafe_to_char())
    } else {
      result.write_char('%')
      result.write_char(hex[n / 16].to_int().unsafe_to_char())
      result.write_char(hex[n % 16].to_int().unsafe_to_char())
    }
  }
  result.to_string()
}

///|
/// Text-only first profile: file paths, external references, LoRA and arbitrary
/// extra_params are rejected, not forwarded into a privileged model worker.
pub fn VideoRequest::decode(
  profile : Profile,
  content_type : String,
  body : String,
) -> VideoRequest raise ProviderError {
  if !valid_profile(profile) {
    raise InvalidConfiguration
  }
  if @utf8.encode(body).length() > 65536 {
    raise InvalidRequest
  }
  let fields : Map[String, String] = Map([])
  try {
    if content_type == "application/x-www-form-urlencoded" {
      for part in body.split("&") {
        guard part.find("=") is Some(separator) else { raise InvalidRequest }
        let name = decode_component(part[:separator].to_owned())
        if fields.contains(name) {
          raise InvalidRequest
        }
        fields[name] = decode_component(part[separator + 1:].to_owned())
      }
    } else if content_type == "application/json" {
      if !unique_json_fields(body) {
        raise InvalidRequest
      }
      guard @json.parse(body) is Object(object) else { raise InvalidRequest }
      for name, value in object {
        fields[name] = match value {
          String(text) => text
          Number(_, ..) | True | False => value.stringify()
          _ => raise InvalidRequest
        }
      }
    } else {
      raise InvalidRequest
    }
    let allowed = [
      "model", "prompt", "negative_prompt", "width", "height", "num_frames", "fps",
      "num_inference_steps", "seed", "generate_sound",
    ]
    if fields.keys().any(key => !allowed.contains(key)) ||
      fields.get("model") != Some(profile.model) {
      raise InvalidRequest
    }
    guard fields.get("prompt") is Some(prompt) &&
      !prompt.trim().is_empty() &&
      prompt.length() <= 16384 else {
      raise InvalidRequest
    }
    if fields
      .get("negative_prompt")
      .map_or(false, value => value.length() > 16384) ||
      fields.values().any(value => value.contains("\u0000")) {
      raise InvalidRequest
    }
    for name in ["width", "height", "num_frames", "fps"] {
      guard fields.get(name) is Some(value) else { raise InvalidRequest }
      let n = @string.parse_int(value)
      let valid = match name {
        "width" => profile.widths.contains(n)
        "height" => profile.heights.contains(n)
        "num_frames" => n >= 1 && n <= profile.maximum_frames
        _ => n >= 1 && n <= profile.maximum_fps
      }
      if !valid {
        raise InvalidRequest
      }
      fields[name] = n.to_string()
    }
    if fields.get("num_inference_steps") is Some(value) {
      let n = @string.parse_int(value)
      if n < 1 || n > profile.maximum_steps {
        raise InvalidRequest
      }
      fields["num_inference_steps"] = n.to_string()
    }
    if fields.get("seed") is Some(value) {
      let n = @string.parse_int64(value)
      if n < 0L {
        raise InvalidRequest
      }
      fields["seed"] = n.to_string()
    }
    if fields.get("generate_sound") is Some(value) {
      if (value != "true" && value != "false") ||
        (value == "true" && !profile.sound_supported) {
        raise InvalidRequest
      }
    }
    { model: profile.model, fields, }
  } catch {
    _ => raise InvalidRequest
  }
}

///|
pub fn VideoRequest::model(self : VideoRequest) -> String {
  self.model
}

///|
pub fn VideoRequest::within_workspace_budget(
  self : VideoRequest,
  maximum_input : Int,
  maximum_output : Int,
) -> Bool {
  self.fields["prompt"].length() +
  self.fields.get("negative_prompt").unwrap_or("").length() <=
  maximum_input &&
  (@string.parse_int(self.fields["num_frames"]) catch {
    _ => maximum_output + 1
  }) <=
  maximum_output
}

///|
fn VideoRequest::form(self : VideoRequest) -> String {
  let keys = self.fields.keys().to_array()
  keys.sort()
  keys
  .map(key => encode_component(key) + "=" + encode_component(self.fields[key]))
  .join("&")
}

///|
pub fn VideoRequest::digest(self : VideoRequest) -> String {
  "sha256:" +
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(self.form())))
}

///|
/// core/json uses last-key-wins. Reject duplicate decoded field names before
/// normalization so different parsers cannot disagree on an authorization field.
fn unique_json_fields(body : String) -> Bool {
  let seen : Map[String, Bool] = Map([])
  let mut index = 0
  while index < body.length() {
    if body[index] != '"' {
      index += 1
      continue
    }
    let start = index
    index += 1
    while index < body.length() && body[index] != '"' {
      if body[index] == '\\' {
        index += 1
      }
      index += 1
    }
    if index >= body.length() {
      return false
    }
    index += 1
    let end = index
    while index < body.length() &&
          [' ', '\n', '\r', '\t'].contains(
            body[index].to_int().unsafe_to_char(),
          ) {
      index += 1
    }
    if index < body.length() && body[index] == ':' {
      let key = @json.parse(body[start:end]) catch { _ => return false }
      guard key is String(name) else { return false }
      if seen.contains(name) {
        return false
      }
      seen[name] = true
    }
  }
  true
}
