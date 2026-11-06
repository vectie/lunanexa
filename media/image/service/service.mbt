///|
/// Internal, single-model adapter behind authenticated model consumers. All
/// application/UI code stays above this provider-neutral component.
pub(all) struct Config {
  origin : String
  model : String
  node_id : String
  artifact_digest : String
  profile : @provider.Profile
  state_dir : String
  bearer_file : String
  qualification_file : String
  qualification_sha256 : String
  maximum_requests : Int32
} derive(FromJson)

///|
pub extend Config with FromJson::{from_json}

///|
enum JobState {
  Dispatching
  Running
  Completed
  Failed
  NeedsReconcile
} derive(Eq, ToJson, FromJson)

///|
pub extend JobState with Eq::{not_equal, equal}

///|
pub extend JobState with ToJson::{to_json}

///|
pub extend JobState with FromJson::{from_json}

///|
struct Job {
  id : String
  digest : String
  state : JobState
  prompt_id : String
  created_ms : UInt64
} derive(ToJson, FromJson)

///|
pub extend Job with ToJson::{to_json}

///|
pub extend Job with FromJson::{from_json}

///|
pub struct Service {
  config : Config
  provider : @provider.Provider
  binding : String
}

///|
struct Journal {
  binding : String
  jobs : Array[Job]
} derive(ToJson, FromJson)

///|
pub extend Journal with ToJson::{to_json}

///|
pub extend Journal with FromJson::{from_json}

///|
fn hex(value : String) -> Bool {
  value.length() == 64 && value.all(c => c is ('a'..<='f' | '0'..<='9'))
}

///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
pub async fn Service::new(config : Config) -> Service {
  guard config.state_dir.has_prefix("/") &&
    config.maximum_requests > 0 &&
    config.maximum_requests <= 10000 &&
    config.bearer_file.has_prefix("/") &&
    config.qualification_file.has_prefix("/") &&
    hex(config.qualification_sha256) &&
    config.artifact_digest.has_prefix("sha256:") &&
    hex(config.artifact_digest[7:].to_owned()) &&
    !config.node_id.is_empty() &&
    !config.model.is_empty() else {
    fail("Invalid image adapter configuration")
  }
  let evidence = @fs.read_file(config.qualification_file).binary()
  guard digest(evidence) == config.qualification_sha256 &&
    @json.parse(@utf8.decode(evidence))
    is {
      "approved": True,
      "runtime_origin": String(origin),
      "node_id": String(node),
      "artifact_digest": String(artifact),
      "workflow": String("z-image-turbo-v1"),
      ..
    } &&
    origin == config.origin &&
    node == config.node_id &&
    artifact == config.artifact_digest else {
    fail("Image runtime qualification does not match deployment")
  }
  if !@fs.exists(config.state_dir) {
    @fs.mkdir(config.state_dir, permission=0o700, recursive=true)
  }
  guard @fs.kind(config.state_dir, follow_symlink=false) is Directory else {
    fail("Image adapter state must be a real directory")
  }
  @fs.chmod(config.state_dir, 0o700)
  let binding = digest(
    @utf8.encode(
      (
        {
          "origin": config.origin,
          "model": config.model,
          "node": config.node_id,
          "artifact_digest": config.artifact_digest,
          "profile": config.profile.to_json(),
          "workflow": "z-image-turbo-v1",
        } : Json).stringify(),
    ),
  )
  {
    config,
    provider: @provider.Provider::new(config.origin, config.profile),
    binding,
  }
}

///|
async fn bounded(reader : &@io.Reader, max : Int32) -> Bytes {
  let bytes = FixedArray::make(max + 1, b'\x00')
  let mut size = 0
  while size <= max {
    let n = reader.read(bytes, offset=size, max_len=max + 1 - size)
    if n == 0 {
      return bytes.unsafe_reinterpret_as_bytes()[:size].to_owned()
    }
    size += n
  }
  fail("Image adapter body is too large")
}

///|
async fn reply(
  conn : @http.ServerConnection,
  status : Int32,
  value : Json,
) -> Unit {
  conn.send_response(status, "", extra_headers={
    "content-type": "application/json",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  })
  conn.write(value.stringify())
  conn.end_response()
}

///|
async fn Service::authorized(self : Service, request : @http.Request) -> Bool {
  let token = @fs.read_file(self.config.bearer_file).text().trim().to_owned()
  if token.length() < 32 || token.length() > 4096 {
    return false
  }
  let expected = @utf8.encode("Bearer " + token)
  let actual = @utf8.encode(request.headers.get("authorization").unwrap_or(""))
  if actual.length() != expected.length() {
    return false
  }
  let mut difference = 0
  for i in 0..<expected.length() {
    difference = difference | (expected[i].to_int() ^ actual[i].to_int())
  }
  difference == 0
}

///|
async fn Service::lock(self : Service) -> @fs.File {
  let path = self.config.state_dir + "/jobs.lock"
  if @fs.exists(path) && !(@fs.kind(path, follow_symlink=false) is Regular) {
    fail("Invalid image adapter lock")
  }
  let file = @fs.open(
    path,
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  file.lock(Exclusive)
  file
}

///|
async fn Service::read(self : Service) -> Array[Job] {
  let path = self.config.state_dir + "/jobs.json"
  if !@fs.exists(path) {
    return []
  }
  guard @fs.kind(path, follow_symlink=false) is Regular else {
    fail("Invalid image adapter state")
  }
  let journal : Journal = @json.from_json(
    @json.parse(@fs.read_file(path).text()),
  )
  guard journal.binding == self.binding else {
    fail(
      "Image adapter binding changed; retain the original runtime to reconcile its jobs",
    )
  }
  journal.jobs
}

///|
async fn Service::save(self : Service, jobs : Array[Job]) -> Unit {
  let path = self.config.state_dir + "/jobs.next"
  if @fs.exists(path) && !(@fs.kind(path, follow_symlink=false) is Regular) {
    fail("Invalid image adapter state")
  }
  @fs.write_file(
    path,
    ({ binding: self.binding, jobs, } : Journal).to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(path, self.config.state_dir + "/jobs.json", replace=true)
}

///|
async fn Service::update(self : Service, job : Job) -> Unit {
  let lock = self.lock()
  defer lock.close()
  defer lock.unlock()
  self.save(
    self
    .read()
    .map(previous => {
      if previous.id == job.id && ![Completed, Failed].contains(previous.state) {
        job
      } else {
        previous
      }
    }),
  )
}

///|
async fn Service::output(
  self : Service,
  id : String,
  conn : @http.ServerConnection,
) -> Unit {
  self.reconcile(id)
  let jobs = {
    let lock = self.lock()
    defer lock.close()
    defer lock.unlock()
    self.read()
  }
  guard jobs.iter().find_first(job => job.id == id) is Some(job) else {
    return reply(conn, 404, { "error": "not_found" })
  }
  if job.state != Completed {
    return reply(conn, 202, {
      "id": id,
      "status": match job.state {
        Dispatching => "dispatching"
        Running => "running"
        Completed => "completed"
        Failed => "failed"
        NeedsReconcile => "needs_reconcile"
      },
    })
  }
  let file = self.config.state_dir + "/" + id + ".png"
  guard @fs.kind(file, follow_symlink=false) is Regular else {
    return reply(conn, 503, { "error": "content_unavailable" })
  }
  let bytes = @fs.read_file(file).binary()
  reply(conn, 200, {
    "id": id,
    "model": self.config.model,
    "data": [{ "b64_json": @base64.encode(bytes) }],
  })
}

///|
pub async fn Service::reconcile(self : Service, id : String) -> Unit {
  guard hex(id) else { return }
  let jobs = {
    let lock = self.lock()
    defer lock.close()
    defer lock.unlock()
    self.read()
  }
  guard jobs
    .iter()
    .find_first(job => {
      job.id == id && [Dispatching, Running, NeedsReconcile].contains(job.state)
    })
    is Some(previous) else {
    return
  }
  let prompt_id = if previous.prompt_id.is_empty() {
    self.provider.lookup(id).unwrap_or("")
  } else {
    previous.prompt_id
  }
  if prompt_id.is_empty() {
    return
  }
  let observation = self.provider.observe(prompt_id, id)
  // Re-read under the lock so a late original response cannot be overwritten.
  let lock = self.lock()
  defer lock.close()
  defer lock.unlock()
  let current = self.read()
  guard current
    .iter()
    .find_first(job => {
      job.id == id && job.state != Completed && job.state != Failed
    })
    is Some(job) else {
    return
  }
  let next = match observation {
    Pending => { ..job, state: Running, prompt_id, }
    Failed => { ..job, state: Failed, prompt_id, }
    Complete(filename) => {
      let bytes = self.provider.content(filename)
      let file = self.config.state_dir + "/" + id + ".png"
      if !@fs.exists(file) {
        @fs.write_file(
          file,
          bytes,
          create_mode=CreateNew,
          permission=0o600,
          sync=Full,
        )
      }
      { ..job, state: Completed, prompt_id, }
    }
  }
  self.save(current.map(job => if job.id == id { next } else { job }))
}

///|
async fn Service::generate(
  self : Service,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let input = @json.parse(@utf8.decode(bounded(body, 16384)))
  guard input
    is {
      "model": String(model),
      "prompt": String(prompt),
      "n": Number(1, ..),
      "size": String("1024x1024"),
      "response_format": String("b64_json"),
      ..
    } &&
    model == self.config.model &&
    !prompt.trim().is_empty() &&
    prompt.length() <= 2000 else {
    return reply(conn, 400, { "error": "invalid_image_request" })
  }
  let id = request.headers.get("idempotency-key").unwrap_or("")
  guard hex(id) else {
    return reply(conn, 400, { "error": "idempotency_key_required" })
  }
  let fingerprint = digest(
    @utf8.encode(
      ({ "model": model, "prompt": prompt, "size": "1024x1024" } : Json).stringify(),
    ),
  )
  let existing = {
    let lock = self.lock()
    defer lock.close()
    defer lock.unlock()
    let jobs = self.read()
    match jobs.iter().find_first(job => job.id == id) {
      Some(job) => Some(job)
      None => {
        if jobs.length() >= self.config.maximum_requests {
          return reply(conn, 429, { "error": "model_grant_quota_exhausted" })
        }
        if jobs.any(job => {
            [Dispatching, Running, NeedsReconcile].contains(job.state)
          }) {
          return reply(conn, 429, { "error": "runtime_busy" })
        }
        let job : Job = {
          id,
          digest: fingerprint,
          state: Dispatching,
          prompt_id: "",
          created_ms: @env.now(),
        }
        jobs.push(job)
        self.save(jobs)
        None
      }
    }
  }
  if existing is Some(job) {
    if job.digest != fingerprint {
      return reply(conn, 409, { "error": "idempotency_conflict" })
    }
    return self.output(id, conn)
  }
  let seed_bytes = @crypto.sha256(@utf8.encode(id))
  let seed = (seed_bytes[0].to_uint() << 24) |
    (seed_bytes[1].to_uint() << 16) |
    (seed_bytes[2].to_uint() << 8) |
    seed_bytes[3].to_uint()
  let mut job : Job = {
    id,
    digest: fingerprint,
    state: Dispatching,
    prompt_id: "",
    created_ms: @env.now(),
  }
  // The durable dispatching intent is committed before the only POST upstream.
  try {
    let prompt_id = self.provider.submit(prompt, seed, id)
    job = { ..job, state: Running, prompt_id, }
    self.update(job)
    @async.with_timeout(240000, () => {
      while true {
        match self.provider.observe(prompt_id, id) {
          Pending => @async.sleep(1000)
          Failed => {
            job = { ..job, state: Failed, }
            self.update(job)
            return reply(conn, 502, { "error": "generation_failed" })
          }
          Complete(filename) => {
            let bytes = self.provider.content(filename)
            @fs.write_file(
              self.config.state_dir + "/" + id + ".png",
              bytes,
              create_mode=CreateNew,
              permission=0o600,
              sync=Full,
            )
            job = { ..job, state: Completed, }
            self.update(job)
            return self.output(id, conn)
          }
        }
      }
    })
  } catch {
    _ => {
      let current = {
        let lock = self.lock()
        defer lock.close()
        defer lock.unlock()
        self.read()
      }
      if !current.any(value => value.id == job.id && value.state == Completed) {
        self.update({ ..job, state: NeedsReconcile, })
      }
      reply(conn, 503, { "id": id, "error": "generation_needs_reconcile" })
    }
  }
}

///|
pub async fn Service::handle(
  self : Service,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  if request.path == "/health" && request.meth == Get {
    return reply(conn, 200, {
      "status": "ok",
      "component": "qualified-image-adapter",
    })
  }
  if !self.authorized(request) {
    return reply(conn, 401, { "error": "invalid_model_grant" })
  }
  if request.path == "/v1/images/generations" && request.meth == Post {
    if request.headers
      .get("content-type")
      .unwrap_or("")
      .split(";")
      .next()
      .unwrap_or("")
      .trim() !=
      "application/json" {
      return reply(conn, 415, { "error": "json_required" })
    }
    return self.generate(request, body, conn)
  }
  let prefix = "/v1/images/generations/"
  if request.path.has_prefix(prefix) && request.meth == Get {
    let id = request.path[prefix.length():].to_owned()
    if !hex(id) {
      return reply(conn, 404, { "error": "not_found" })
    }
    return self.output(id, conn)
  }
  reply(conn, 404, { "error": "not_found" })
}
