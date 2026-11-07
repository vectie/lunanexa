///|
async fn bounded(reader : &@io.Reader, limit : Int32) -> Bytes {
  let result = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise PoolError::InvalidDeployment
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
  namespace_name : String,
  targets : Array[Target],
) -> Transport raise PoolError {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    origin.contains("@") ||
    origin.contains("?") ||
    origin.contains("#") ||
    !token_file.has_prefix("/") ||
    !ca_file.has_prefix("/") ||
    !resource_name(namespace_name) ||
    targets.is_empty() ||
    targets.any(t => !resource_name(t.deployment)) {
    raise InvalidConfiguration
  }
  let allowed = targets.map(t => {
    "/apis/apps/v1/namespaces/\{namespace_name}/deployments/\{t.deployment}"
  })
  let pods_path = "/api/v1/namespaces/\{namespace_name}/pods"
  (operation, path, body) => {
    if !allowed.contains(path) && !(operation == "GET" && path == pods_path) {
      raise PoolError::OutsideScope
    }
    let verb : @http.RequestMethod = match operation {
      "GET" => Get
      "PATCH" => Patch
      _ => raise PoolError::OutsideScope
    }
    @async.with_timeout(10000, () => {
      let file = @fs.open(token_file, mode=ReadOnly)
      defer file.close()
      let token = @utf8.decode(bounded(file, 16384)).trim().to_owned()
      if token.length() < 32 || !token.all(c => c >= '!' && c <= '~') {
        raise PoolError::InvalidConfiguration
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
