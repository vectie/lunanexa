///|
/// The ingress must overwrite X-Real-IP with its observed client address and
/// must be the only caller of this gateway. IPv6 and malformed input fail closed.
fn parse_wifi_ipv4(value : String) -> Int64? {
  let parts = value.split(".").to_array()
  if parts.length() != 4 {
    return None
  }
  let mut address = 0L
  for part in parts {
    if part.length() == 0 ||
      part.length() > 3 ||
      (part.length() > 1 && part.has_prefix("0")) ||
      !part.iter().all(c => c >= '0' && c <= '9') {
      return None
    }
    let octet = @string.parse_int(part) catch { _ => return None }
    if octet > 255 {
      return None
    }
    address = address * 256L + octet.to_int64()
  }
  Some(address)
}

///|
fn parse_wifi_cidr(value : String) -> (Int64, Int64)? {
  let parts = value.split("/").to_array()
  guard parts is [address_raw, prefix_raw] &&
    parse_wifi_ipv4(address_raw.to_owned()) is Some(address) &&
    prefix_raw.length() > 0 &&
    prefix_raw.length() <= 2 &&
    prefix_raw.iter().all(c => c >= '0' && c <= '9') else {
    return None
  }
  let prefix = @string.parse_int(prefix_raw) catch { _ => return None }
  if prefix < 24 || prefix > 32 {
    return None
  }
  let mut block = 1L
  for _ in 0..<(32 - prefix) {
    block = block * 2L
  }
  Some((address / block * block, block))
}

///|
fn wifi_trial_source_allowed(
  config : GatewayConfig,
  headers : @http.Headers,
) -> Bool {
  guard config.wifi_trial_source_cidrs.length() > 0 &&
    header(headers, "X-Real-IP") is Some(raw) &&
    parse_wifi_ipv4(raw) is Some(address) else {
    return false
  }
  config.wifi_trial_source_cidrs.any(cidr => {
    match parse_wifi_cidr(cidr) {
      Some((lower, block)) => address >= lower && address < lower + block
      None => false
    }
  })
}

///|
fn wifi_trial_assertion_headers(
  secret : String,
  bearer : String,
  now : Int64,
) -> @http.Headers {
  let issued = now.to_string()
  let canonical = "lunanexa.wifi-trial.v1\n\{bearer}\n\{issued}"
  let digest = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).exact_view(),
      @utf8.encode(canonical).exact_view(),
    ),
  )
  {
    "X-LunaNexa-Wifi-Trial-Issued-At": issued,
    "X-LunaNexa-Wifi-Trial-Signature": "sha256:\{digest}",
  }
}
