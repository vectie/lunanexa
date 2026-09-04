///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn base64url(bytes : BytesView) -> String {
  let encoded = @base64.encode(bytes, url_safe=true)
  for end = encoded.length(); end > 0 && encoded[end - 1] == '='; {
    continue end - 1
  } nobreak {
    encoded[:end].to_owned()
  }
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    (value + '0').unsafe_to_char()
  } else {
    (value - 10 + 'A').unsafe_to_char()
  }
}

///|
fn form_encode(value : String) -> String {
  let output = StringBuilder()
  for byte in @utf8.encode(value) {
    let value = byte.to_int()
    if (value >= 'a' && value <= 'z') ||
      (value >= 'A' && value <= 'Z') ||
      (value >= '0' && value <= '9') ||
      value == '-' ||
      value == '.' ||
      value == '_' ||
      value == '~' {
      output.write_char(value.unsafe_to_char())
    } else {
      output.write_char('%')
      output.write_char(hex_digit((value >> 4) & 15))
      output.write_char(hex_digit(value & 15))
    }
  }
  output.to_string()
}

///|
fn hex_value(value : UInt16) -> Int? {
  if value >= '0' && value <= '9' {
    Some(value.to_int() - '0')
  } else if value >= 'A' && value <= 'F' {
    Some(value.to_int() - 'A' + 10)
  } else if value >= 'a' && value <= 'f' {
    Some(value.to_int() - 'a' + 10)
  } else {
    None
  }
}

///|
fn form_decode(value : StringView) -> String raise {
  let bytes : Array[Byte] = []
  for index = 0; index < value.length(); {
    let unit = value[index]
    if unit == '+' {
      bytes.push(b' ')
      continue index + 1
    }
    if unit == '%' {
      guard index + 2 < value.length() &&
        hex_value(value[index + 1]) is Some(high) &&
        hex_value(value[index + 2]) is Some(low) else {
        raise Failure("invalid form encoding")
      }
      bytes.push(((high << 4) | low).to_byte())
      continue index + 3
    }
    guard unit <= 0x7f else { raise Failure("non-ASCII query encoding") }
    bytes.push(unit.to_byte())
    continue index + 1
  }
  @utf8.decode(Bytes::from_array(bytes))
}

///|
fn parse_query(request_target : String) -> Map[String, String] raise {
  guard request_target.find("?") is Some(start) else { return Map([]) }
  let raw = request_target[start + 1:]
  let result : Map[String, String] = Map([])
  if raw == "" {
    return result
  }
  for part in raw.split("&") {
    guard part.find("=") is Some(separator) else {
      raise Failure("invalid query parameter")
    }
    let key = form_decode(part[:separator])
    let value = form_decode(part[separator + 1:])
    guard key != "" && !result.contains(key) else {
      raise Failure("duplicate query parameter")
    }
    result[key] = value
  }
  result
}

///|
fn request_path(request_target : String) -> String {
  match request_target.find("?") {
    Some(index) => request_target[:index].to_owned()
    None => request_target
  }
}

///|
fn canonical_api_path(request_target : String) -> String? {
  let path = request_path(request_target)
  if !path.has_prefix("/v1/") ||
    path.contains("%") ||
    path.contains("\\") ||
    path.contains("\u0000") ||
    path.contains("//") ||
    path.split("/").any(segment => segment == "." || segment == "..") {
    return None
  }
  for unit in path {
    let code = unit.to_int()
    let alphanumeric = (code >= 'a' && code <= 'z') ||
      (code >= 'A' && code <= 'Z') ||
      (code >= '0' && code <= '9')
    if code > 0x7f || !(alphanumeric || unit is ('/' | '_' | '-' | '.' | ':')) {
      return None
    }
  }
  Some(path)
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  match headers.get(name) {
    Some(value) => Some(value)
    None => headers.get(name.to_lower())
  }
}

///|
fn cookie_value(headers : Map[String, String], name : String) -> String? {
  guard header(headers, "Cookie") is Some(raw) else { return None }
  for part in raw.split(";") {
    let trimmed = part.trim()
    if trimmed.find("=") is Some(index) && trimmed[:index] == name {
      return Some(trimmed[index + 1:].to_owned())
    }
  }
  None
}

///|
async fn secure_random(length : Int) -> Bytes {
  let source = @fs.open("/dev/urandom", mode=ReadOnly)
  defer source.close()
  source.read_exactly(length)
}

///|
fn encode_cookie_reference(id : String, secret : String) -> String {
  let mac = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode("lunanexa.identity-gateway.cookie-reference.v1\n\{id}").view(),
    ),
  )
  "v1.\{id}.\{mac}"
}

///|
fn decode_cookie_reference(value : String, secret : String) -> String? {
  guard value.length() <= 256 &&
    value.split(".").collect() is ["v1", id, _] &&
    id.length() >= 32 &&
    id.length() <= 128 else {
    return None
  }
  if constant_time_equal(value, encode_cookie_reference(id.to_owned(), secret)) {
    Some(id.to_owned())
  } else {
    None
  }
}

///|
async fn random_token(bytes : Int) -> String {
  base64url(secure_random(bytes).view())
}
