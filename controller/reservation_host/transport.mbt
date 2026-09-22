///|
async fn bounded(reader : &@io.Reader, limit : Int) -> Bytes {
  let result = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise ReservationHostError::InvalidObservation
    }
    result.write_bytes(bytes)
  }
  result.to_bytes()
}

///|
pub fn authenticated_transport(
  origin : String,
  token_file : String,
  ca_file : String,
) -> Transport raise ReservationHostError {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    origin.contains("@") ||
    origin.contains("?") ||
    origin.contains("#") ||
    !token_file.has_prefix("/") ||
    !ca_file.has_prefix("/") {
    raise InvalidConfiguration
  }
  (operation, path, body) => {
    @async.with_timeout(10000, () => {
      let verb : @http.RequestMethod = match operation {
        "GET" => Get
        "PATCH" if path.has_prefix("/api/v1/nodes/") => Patch
        _ => raise InvalidConfiguration
      }
      if !path.has_prefix("/api/v1/nodes/") &&
        !path.has_prefix("/api/v1/pods?fieldSelector=spec.nodeName%3D") {
        raise InvalidConfiguration
      }
      let file = @fs.open(token_file, mode=ReadOnly)
      defer file.close()
      let token = @utf8.decode(bounded(file, 16384)).trim().to_owned()
      if token.length() < 32 || !token.all(c => c >= '!' && c <= '~') {
        raise InvalidConfiguration
      }
      let client = @http.Client(origin, trust=CustomPemFile(ca_file))
      defer client.close()
      client.request(verb, path, extra_headers={
        "authorization": "Bearer " + token,
        "content-type": "application/json-patch+json",
      })
      if body is Some(value) {
        client.write(value)
      }
      let response = client.end_request()
      if response.code < 200 || response.code >= 300 {
        (response.code, Json::null())
      } else {
        (response.code, @json.parse(@utf8.decode(bounded(client, 4194304))))
      }
    })
  }
}
