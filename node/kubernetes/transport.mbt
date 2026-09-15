///|
async fn limited(reader : &@io.Reader, limit : Int) -> Bytes {
  let buffer = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise LifecycleError::InvalidResource
    }
    buffer.write_bytes(bytes)
  }
  buffer.to_bytes()
}

///|
/// Use a deployment-owned CA and a rotating, file-mounted service account token.
/// No kubeconfig shell execution, containerd socket, insecure TLS, or Secret API
/// access is needed. Each request reloads the token to support projected tokens.
pub fn authenticated_transport(
  origin : String,
  token_file : String,
  ca_file : String,
) -> Transport raise LifecycleError {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    origin.contains("@") ||
    origin.contains("?") ||
    origin.contains("#") ||
    !token_file.has_prefix("/") ||
    !ca_file.has_prefix("/") {
    raise InvalidResource
  }
  (verb, path, body) => {
    @async.with_timeout(10000, () => {
      // Only the Pod lifecycle API is exposed by this adapter.
      let segments = path.split("/").collect()
      if (segments.length() != 6 && segments.length() != 7) ||
        segments[0] != "" ||
        segments[1] != "api" ||
        segments[2] != "v1" ||
        segments[3] != "namespaces" ||
        !dns_label(segments[4].to_owned()) ||
        segments[5] != "pods" ||
        (segments.length() == 7 && !dns_label(segments[6].to_owned())) {
        raise LifecycleError::InvalidResource
      }
      let request_method : @http.RequestMethod = match verb {
        "GET" => Get
        "POST" => Post
        "DELETE" => Delete
        _ => raise LifecycleError::InvalidResource
      }
      let file = @fs.open(token_file, mode=ReadOnly)
      defer file.close()
      let token = @utf8.decode(limited(file, 16384)).trim().to_owned()
      if token.length() < 32 || !token.all(c => c >= '!' && c <= '~') {
        raise LifecycleError::InvalidResource
      }
      let client = @http.Client(
        origin,
        trust=@tls.TrustedRoot::CustomPemFile(ca_file),
      )
      defer client.close()
      client.request(request_method, path, extra_headers={
        "authorization": "Bearer " + token,
        "content-type": "application/json",
      })
      if body is Some(value) {
        client.write(value)
      }
      let response = client.end_request()
      // Error bodies may echo submitted data. Never parse or expose them.
      if response.code < 200 || response.code >= 300 {
        (response.code, Json::null())
      } else {
        (response.code, @json.parse(@utf8.decode(limited(client, 4194304))))
      }
    })
  }
}
