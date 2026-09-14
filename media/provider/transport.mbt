///|
fn valid_id(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 128 &&
  value.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_'
  })
}

///|
pub fn Provider::new(
  origin : String,
  profile : Profile,
  bearer? : String,
  timeout_ms? : Int = 30000,
) -> Provider raise ProviderError {
  let offset = if origin.has_prefix("https://") {
    8
  } else if origin.has_prefix("http://") {
    7
  } else {
    raise InvalidConfiguration
  }
  let authority = origin[offset:]
  if !valid_profile(profile) ||
    timeout_ms < 100 ||
    timeout_ms > 120000 ||
    authority.is_empty() ||
    authority.length() > 253 ||
    !authority.all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '.' ||
      c == '-' ||
      c == ':'
    }) ||
    bearer.map_or(false, token => {
      token.is_empty() ||
      token.length() > 4096 ||
      !token.all(c => c >= '!' && c <= '~')
    }) {
    raise InvalidConfiguration
  }
  { origin, profile, bearer, timeout_ms, }
}

///|
async fn limited(reader : &@io.Reader, limit : Int) -> Bytes {
  let output = Buffer()
  let mut size = 0
  while reader.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > limit {
      raise InvalidResponse
    }
    output.write_bytes(bytes)
  }
  output.to_bytes()
}

///|
fn Provider::headers(self : Provider) -> Map[String, String] {
  let headers = {
    "content-type": "application/x-www-form-urlencoded",
    "accept": "application/json",
  }
  if self.bearer is Some(token) {
    headers["authorization"] = "Bearer " + token
  }
  headers
}

///|
async fn Provider::request(
  self : Provider,
  verb : @http.RequestMethod,
  path : String,
  body : String?,
) -> (Int, Json) {
  @async.with_timeout(self.timeout_ms, () => {
    let client = @http.Client(self.origin)
    defer client.close()
    client.request(verb, path, extra_headers=self.headers())
    if body is Some(text) {
      client.write(text)
    }
    let response = client.end_request()
    // Do not follow redirects or expose provider bodies in errors.
    if response.code >= 300 && response.code < 400 {
      raise InvalidResponse
    }
    let bytes = limited(client, 262144)
    let value = @json.parse(@utf8.decode(bytes)) catch {
      _ => raise InvalidResponse
    }
    (response.code, value)
  })
}

///|
/// Never return provider prompts, filesystem paths, endpoint URLs or traceback.
fn observation(
  value : Json,
  expected_id : String?,
  expected_model : String,
) -> Observation raise ProviderError {
  guard value is { "id": String(id), "status": String(status), .. } &&
    valid_id(id) &&
    expected_id.map_or(true, expected => expected == id) else {
    raise InvalidResponse
  }
  if value is { "model": String(model), .. } && model != expected_model {
    raise InvalidResponse
  }
  let state : @jobs.State = match status {
    "queued" => Queued
    "in_progress" => Running
    "completed" => Completed
    "failed" => Failed
    _ => raise InvalidResponse
  }
  let progress = match value {
    { "progress": Number(n, ..), .. } => {
      if n < 0.0 || n > 100.0 || n.to_int().to_double() != n {
        raise InvalidResponse
      }
      Some(n.to_int())
    }
    { "progress": Null, .. } => None
    { "progress": _, .. } => raise InvalidResponse
    _ => None
  }
  { id, state, progress, }
}

///|
pub async fn Provider::submit(
  self : Provider,
  request : VideoRequest,
) -> Observation {
  if request.model != self.profile.model {
    raise InvalidRequest
  }
  // Revalidate against this deployment, not just the profile used by a caller.
  let checked = VideoRequest::decode(
    self.profile,
    "application/x-www-form-urlencoded",
    request.form(),
  )
  checked.fields["model"] = self.profile.provider_model
  let (code, value) = self.request(Post, "/v1/videos", Some(checked.form()))
  if code < 200 || code >= 300 {
    raise Unavailable
  }
  observation(value, None, self.profile.provider_model)
}

///|
pub async fn Provider::poll(self : Provider, id : String) -> Observation {
  if !valid_id(id) {
    raise InvalidRequest
  }
  let (code, value) = self.request(Get, "/v1/videos/" + id, None)
  // vLLM-Omni returns the failed job object with a non-2xx HTTP status.
  let result = observation(value, Some(id), self.profile.provider_model)
  if (code < 200 || code >= 300) && result.state != Failed {
    raise Unavailable
  }
  result
}

///|
pub async fn Provider::delete(self : Provider, id : String) -> Bool {
  if !valid_id(id) {
    raise InvalidRequest
  }
  let (code, value) = self.request(Delete, "/v1/videos/" + id, None)
  if code == 409 {
    return false
  }
  // A 404 after a worker restart is NOT proof that an accelerator stopped.
  code >= 200 &&
  code < 300 &&
  value is { "id": String(returned), "deleted": True, .. } &&
  returned == id
}

///|
/// Bounded streaming sink; callers must recheck tenant authority in write_chunk.
/// No buffering of an entire video and no provider content-disposition headers.
pub async fn Provider::content(
  self : Provider,
  id : String,
  maximum_bytes : Int64,
  write_chunk : async (Bytes) -> Unit,
) -> Int64 {
  if !valid_id(id) || maximum_bytes <= 0L || maximum_bytes > 2147483648L {
    raise InvalidRequest
  }
  @async.with_timeout(300000, () => {
    let client = @http.Client(self.origin)
    defer client.close()
    client.request(
      Get,
      "/v1/videos/" + id + "/content",
      extra_headers=self.headers(),
    )
    let response = client.end_request()
    if response.code != 200 {
      raise ContentUnavailable
    }
    let media_type = response.headers
      .iter()
      .filter(pair => pair.0.to_lower() == "content-type")
      .to_array()
    if media_type.length() != 1 ||
      media_type[0].1.split(";").next() != Some("video/mp4") {
      raise InvalidResponse
    }
    let mut size = 0L
    while client.read_some(max_len=65536) is Some(bytes) {
      size += bytes.length().to_int64()
      if size > maximum_bytes {
        raise InvalidResponse
      }
      write_chunk(bytes)
    }
    if size == 0L {
      raise InvalidResponse
    }
    size
  })
}
