///|
priv struct HelperRequest {
  action : String
  lease_id : String
  username : String
  credential_ref : String
  expires_unix_ms : Int64
  generation : Int64
  authorization : String
}

///|
priv struct HostConfig {
  state_root : String
  home_root : String
  credential_root : String
  quarantine_root : String
  id_program : String
  useradd_program : String
  usermod_program : String
  userdel_program : String
  getent_program : String
  loginctl_program : String
  pkill_program : String
  pgrep_program : String
  runuser_program : String
  container_program : String
  chown_program : String
}

///|
fn absolute_program(name : String, fallback : String) -> String raise {
  let value = @env.get_env_var(name).unwrap_or(fallback)
  if !value.has_prefix("/") ||
    value.length() > 512 ||
    value.any(character => {
      !character.is_printable() || character.is_whitespace()
    }) {
    raise Failure::Failure("lease helper program path is invalid")
  }
  value
}

///|
fn host_root(name : String, fallback : String) -> String raise {
  let value = @env.get_env_var(name).unwrap_or(fallback)
  if !@leasehelper.valid_host_root(value) {
    raise Failure::Failure("lease helper root is invalid")
  }
  value
}

///|
fn host_config() -> HostConfig raise {
  {
    state_root: host_root(
      "LUNANEXA_LEASE_STATE_ROOT", "/var/lib/lunanexa/exclusive-leases",
    ),
    home_root: host_root(
      "LUNANEXA_LEASE_HOME_ROOT", "/var/lib/lunanexa/lease-homes",
    ),
    credential_root: host_root(
      "LUNANEXA_LEASE_CREDENTIAL_ROOT", "/run/lunanexa/lease-credentials",
    ),
    quarantine_root: host_root(
      "LUNANEXA_LEASE_QUARANTINE_ROOT", "/var/lib/lunanexa/quarantine",
    ),
    id_program: absolute_program("LUNANEXA_ID_PROGRAM", "/usr/bin/id"),
    useradd_program: absolute_program(
      "LUNANEXA_USERADD_PROGRAM", "/usr/sbin/useradd",
    ),
    usermod_program: absolute_program(
      "LUNANEXA_USERMOD_PROGRAM", "/usr/sbin/usermod",
    ),
    userdel_program: absolute_program(
      "LUNANEXA_USERDEL_PROGRAM", "/usr/sbin/userdel",
    ),
    getent_program: absolute_program(
      "LUNANEXA_GETENT_PROGRAM", "/usr/bin/getent",
    ),
    loginctl_program: absolute_program(
      "LUNANEXA_LOGINCTL_PROGRAM", "/usr/bin/loginctl",
    ),
    pkill_program: absolute_program("LUNANEXA_PKILL_PROGRAM", "/usr/bin/pkill"),
    pgrep_program: absolute_program("LUNANEXA_PGREP_PROGRAM", "/usr/bin/pgrep"),
    runuser_program: absolute_program(
      "LUNANEXA_RUNUSER_PROGRAM", "/usr/sbin/runuser",
    ),
    container_program: absolute_program(
      "LUNANEXA_CONTAINER_PROGRAM", "/usr/bin/podman",
    ),
    chown_program: absolute_program("LUNANEXA_CHOWN_PROGRAM", "/usr/bin/chown"),
  }
}

///|
fn argument_value(args : Array[String], name : String) -> String? {
  for index in 2..<(args.length() - 1) {
    if args[index] == name {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn parse_request(args : Array[String]) -> HelperRequest raise {
  guard args.length() >= 2 else {
    raise Failure::Failure("lease helper action is required")
  }
  let action = args[1]
  let lease_id = argument_value(args, "--lease-id").unwrap_or("")
  let username = argument_value(args, "--username").unwrap_or("")
  let credential_ref = argument_value(args, "--credential-ref").unwrap_or("")
  let expires_unix_ms = @string.parse_int64(
    argument_value(args, "--expires-unix-ms").unwrap_or("0"),
  ) catch {
    _ => raise Failure::Failure("lease helper expiry is invalid")
  }
  let generation = @string.parse_int64(
    argument_value(args, "--generation").unwrap_or("0"),
  ) catch {
    _ => raise Failure::Failure("lease helper generation is invalid")
  }
  let authorization = argument_value(args, "--authorization").unwrap_or("")
  let request : HelperRequest = {
    action,
    lease_id,
    username,
    credential_ref,
    expires_unix_ms,
    generation,
    authorization,
  }
  if !@leasehelper.valid_helper_request(
      action,
      lease_id,
      username,
      generation,
      expires_unix_ms,
      @async.now(),
    ) ||
    (
      action == "provision" &&
      !@nodelease.valid_access_credential_ref(credential_ref)
    ) {
    raise Failure::Failure("lease helper request is invalid")
  }
  request
}

///|
fn safe_process_environment() -> Map[String, String] {
  {
    "PATH": "/usr/sbin:/usr/bin:/sbin:/bin",
    "HOME": "/root",
    "LANG": "C",
    "LC_ALL": "C",
  }
}

///|
async fn collect(program : String, args : Array[String]) -> (Int, String) {
  let (status, stdout) = @process.collect_stdout(
    program,
    args,
    extra_env=safe_process_environment(),
    inherit_env=false,
  )
  (status, stdout.text().trim().to_owned())
}

///|
async fn run_required(program : String, args : Array[String]) -> Unit {
  let status = @process.run(
    program,
    args,
    extra_env=safe_process_environment(),
    inherit_env=false,
  )
  if status != 0 {
    raise Failure::Failure("required lease host action failed")
  }
}

///|
async fn require_root(config : HostConfig) -> Unit {
  let (status, output) = collect(config.id_program, ["-u"])
  if status != 0 || output != "0" {
    raise Failure::Failure("lease helper must run as root")
  }
}

///|
async fn account_exists(config : HostConfig, username : String) -> Bool {
  let (status, _) = collect(config.getent_program, ["passwd", username])
  match status {
    0 => true
    2 => false
    _ => raise Failure::Failure("tenant account lookup failed")
  }
}

///|
async fn processes_absent(config : HostConfig, username : String) -> Bool {
  if !account_exists(config, username) {
    return true
  }
  let (status, _) = collect(config.pgrep_program, ["-u", username])
  match status {
    0 => false
    1 => true
    _ => raise Failure::Failure("tenant process inventory failed")
  }
}

///|
async fn runtime_objects(
  config : HostConfig,
  username : String,
  kind : String,
) -> Array[String] {
  if !account_exists(config, username) {
    return []
  }
  let runtime_args = if kind == "container" {
    [config.container_program, "ps", "-aq"]
  } else {
    [config.container_program, "volume", "ls", "-q"]
  }
  let (status, output) = collect(
    config.runuser_program,
    ["--user", username, "--", ..runtime_args],
  )
  if status != 0 {
    raise Failure::Failure("tenant container inventory failed")
  }
  let values : Array[String] = []
  for line in output.split("\n") {
    let value = line.trim().to_owned()
    if value != "" {
      if !@leasehelper.valid_runtime_object_id(value) {
        raise Failure::Failure("tenant runtime returned an unsafe object ID")
      }
      values.push(value)
    }
  }
  values
}

///|
async fn stop_tenant_containers(config : HostConfig, username : String) -> Unit {
  let containers = runtime_objects(config, username, "container")
  if containers.length() > 0 {
    run_required(
      config.runuser_program,
      [
        "--user",
        username,
        "--",
        config.container_program,
        "stop",
        "--time",
        "10",
        ..containers,
      ],
    )
  }
}

///|
async fn remove_tenant_runtime(config : HostConfig, username : String) -> Unit {
  let containers = runtime_objects(config, username, "container")
  if containers.length() > 0 {
    run_required(
      config.runuser_program,
      [
        "--user",
        username,
        "--",
        config.container_program,
        "rm",
        "--force",
        ..containers,
      ],
    )
  }
  let volumes = runtime_objects(config, username, "volume")
  if volumes.length() > 0 {
    run_required(
      config.runuser_program,
      [
        "--user",
        username,
        "--",
        config.container_program,
        "volume",
        "rm",
        "--force",
        ..volumes,
      ],
    )
  }
}

///|
async fn marker_matches(path : String, expected : String) -> Bool {
  @fs.exists(path) && @fs.read_file(path).text().trim() == expected
}

///|
async fn lease_generation_marker(
  config : HostConfig,
  request : HelperRequest,
) -> String? {
  let lease_path = @leasehelper.scoped_host_path(
    config.state_root,
    request.lease_id,
  ).unwrap()
  let home_path = @leasehelper.scoped_host_path(
    config.home_root,
    request.username,
    maximum_identifier_length=32,
  ).unwrap()
  let generation_marker = "\{lease_path}/generation"
  let has_account = account_exists(config, request.username)
  if !@fs.exists(generation_marker) {
    if has_account || @fs.exists(home_path) || @fs.exists(lease_path) {
      raise Failure::Failure(
        "lease generation marker is missing for existing tenant state",
      )
    }
    return None
  }
  let recorded = @fs.read_file(generation_marker).text().trim().to_owned()
  let prefix = "\{request.lease_id}:"
  if !recorded.has_prefix(prefix) || recorded.length() == prefix.length() {
    raise Failure::Failure("lease generation marker is misbound")
  }
  let generation = @string.parse_int64(recorded[prefix.length():]) catch {
    _ => raise Failure::Failure("lease generation marker is invalid")
  }
  if generation <= 0L {
    raise Failure::Failure("lease generation marker is invalid")
  }
  if request.generation < generation {
    raise Failure::Failure("lease generation marker is newer than request")
  }
  if has_account || @fs.exists(home_path) {
    if !@fs.exists(home_path) ||
      !marker_matches("\{home_path}/.lunanexa-lease", recorded) {
      raise Failure::Failure("tenant home is not owned by this exclusive lease")
    }
  }
  if request.generation > generation {
    // main verifies the controller-issued full-action MAC before any action
    // reaches this function. Advancing both markers therefore records exactly
    // that authorized lifecycle generation; an argv-only higher generation
    // cannot cross this boundary.
    let advanced = "\{request.lease_id}:\{request.generation}"
    @fs.write_file(
      generation_marker,
      advanced,
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    if @fs.exists(home_path) {
      @fs.write_file(
        "\{home_path}/.lunanexa-lease",
        advanced,
        create_mode=CreateOrTruncate,
        permission=0o600,
        sync=Full,
      )
    }
    Some(advanced)
  } else {
    Some(recorded)
  }
}

///|
async fn ensure_directory(
  path : String,
  permission : Int,
  recursive? : Bool = true,
) -> Unit {
  if !@fs.exists(path) {
    @fs.mkdir(path, permission~, recursive~)
  }
}

///|
async fn provision(config : HostConfig, request : HelperRequest) -> Unit {
  let lease_path = @leasehelper.scoped_host_path(
    config.state_root,
    request.lease_id,
  ).unwrap()
  let home_path = @leasehelper.scoped_host_path(
    config.home_root,
    request.username,
    maximum_identifier_length=32,
  ).unwrap()
  let credential_path = @leasehelper.scoped_host_path(
    config.credential_root,
    "\{request.lease_id}.authorized_keys",
    maximum_identifier_length=160,
  ).unwrap()
  let marker = "\{request.lease_id}:\{request.generation}"
  ensure_directory(config.state_root, 0o700)
  ensure_directory(config.home_root, 0o711)
  if !@fs.exists(credential_path) {
    raise Failure::Failure("lease credential material is unavailable")
  }
  let credential = @fs.read_file(credential_path).text().trim().to_owned()
  if credential.length() < 32 ||
    credential.length() > 16384 ||
    credential.contains_char('\n') ||
    !credential.has_prefix("ssh-") {
    raise Failure::Failure("lease credential material is invalid")
  }
  if account_exists(config, request.username) {
    if !marker_matches("\{home_path}/.lunanexa-lease", marker) {
      raise Failure::Failure(
        "existing account is not owned by this lease generation",
      )
    }
  } else {
    run_required(config.useradd_program, [
      "--create-home",
      "--home-dir",
      home_path,
      "--shell",
      "/bin/bash",
      "--user-group",
      request.username,
    ])
  }
  ensure_directory(lease_path, 0o700)
  ensure_directory("\{home_path}/.ssh", 0o700)
  @fs.write_file(
    "\{lease_path}/generation",
    marker,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.write_file(
    "\{home_path}/.lunanexa-lease",
    marker,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.write_file(
    "\{home_path}/.ssh/authorized_keys",
    "\{credential}\n",
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  run_required(config.chown_program, [
    "--recursive",
    "\{request.username}:\{request.username}",
    home_path,
  ])
}

///|
async fn revoke(config : HostConfig, request : HelperRequest) -> Unit {
  if lease_generation_marker(config, request) is None {
    return
  }
  if account_exists(config, request.username) {
    run_required(config.usermod_program, ["--lock", request.username])
    let login_status = @process.run(
      config.loginctl_program,
      ["terminate-user", request.username],
      extra_env=safe_process_environment(),
      inherit_env=false,
    )
    if login_status != 0 && login_status != 1 {
      raise Failure::Failure("tenant session termination failed")
    }
    stop_tenant_containers(config, request.username)
    let kill_status = @process.run(
      config.pkill_program,
      ["-KILL", "-u", request.username],
      extra_env=safe_process_environment(),
      inherit_env=false,
    )
    if kill_status != 0 && kill_status != 1 {
      raise Failure::Failure("tenant process termination failed")
    }
  }
  if !processes_absent(config, request.username) {
    raise Failure::Failure("tenant processes remain after revocation")
  }
}

///|
async fn sanitize(config : HostConfig, request : HelperRequest) -> Unit {
  let lease_path = @leasehelper.scoped_host_path(
    config.state_root,
    request.lease_id,
  ).unwrap()
  let home_path = @leasehelper.scoped_host_path(
    config.home_root,
    request.username,
    maximum_identifier_length=32,
  ).unwrap()
  let credential_path = @leasehelper.scoped_host_path(
    config.credential_root,
    "\{request.lease_id}.authorized_keys",
    maximum_identifier_length=160,
  ).unwrap()
  guard lease_generation_marker(config, request) is Some(_) else {
    if @fs.exists(credential_path) {
      @fs.remove(credential_path)
    }
    if @fs.exists(credential_path) {
      raise Failure::Failure("lease access material remains after cleanup")
    }
    return
  }
  revoke(config, request)
  remove_tenant_runtime(config, request.username)
  let no_processes = processes_absent(config, request.username)
  let containers_absent = runtime_objects(config, request.username, "container").length() ==
    0
  let volumes_absent = runtime_objects(config, request.username, "volume").length() ==
    0
  if !containers_absent || !volumes_absent {
    raise Failure::Failure("tenant runtime objects remain after cleanup")
  }
  if account_exists(config, request.username) {
    let status = @process.run(
      config.userdel_program,
      ["--remove", request.username],
      extra_env=safe_process_environment(),
      inherit_env=false,
    )
    if status != 0 {
      raise Failure::Failure("tenant account removal failed")
    }
  }
  if @fs.exists(home_path) {
    @fs.rmdir(home_path, recursive=true)
  }
  if @fs.exists(credential_path) {
    @fs.remove(credential_path)
  }
  @fs.rmdir(lease_path, recursive=true)
  let evidence : @leasehelper.CleanupEvidence = {
    account_absent: !account_exists(config, request.username),
    processes_absent: no_processes,
    containers_absent,
    volumes_absent,
    home_absent: !@fs.exists(home_path),
    lease_state_absent: !@fs.exists(lease_path),
    access_material_absent: !@fs.exists(credential_path),
  }
  if !evidence.verified() {
    raise Failure::Failure("tenant cleanup verification failed")
  }
}

///|
async fn quarantine(config : HostConfig, request : HelperRequest) -> Unit {
  let mut lockdown_error : Error? = None
  try revoke(config, request) catch {
    error => lockdown_error = Some(error)
  } noraise {
    _ => ()
  }
  ensure_directory(config.quarantine_root, 0o700)
  let marker = @leasehelper.scoped_host_path(
    config.quarantine_root,
    "\{request.lease_id}-g\{request.generation}.quarantined",
    maximum_identifier_length=180,
  ).unwrap()
  @fs.write_file(
    marker,
    "lease=\{request.lease_id}\ngeneration=\{request.generation}\n",
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  if lockdown_error is Some(error) {
    raise error
  }
}

///|
fn action_contract(request : HelperRequest) -> @nodelease.LeaseAgentAction {
  match request.action {
    "provision" =>
      ProvisionAccess(
        lease_id=request.lease_id,
        username=request.username,
        credential_ref=request.credential_ref,
        expires_unix_ms=request.expires_unix_ms,
        generation=request.generation,
      )
    "revoke" =>
      RevokeAccess(
        lease_id=request.lease_id,
        username=request.username,
        generation=request.generation,
      )
    "sanitize" =>
      SanitizeLease(
        lease_id=request.lease_id,
        username=request.username,
        generation=request.generation,
      )
    "quarantine" =>
      QuarantineNode(
        lease_id=request.lease_id,
        username=request.username,
        generation=request.generation,
      )
    _ => NoAction
  }
}

///|
async fn main {
  if @env.get_env_var("LUNANEXA_LEASE_HELPER_ENABLE") != Some("1") &&
    !@fs.exists("/etc/lunanexa/lease-helper.enabled") {
    raise Failure::Failure("lease helper is disabled")
  }
  let config = host_config()
  require_root(config)
  let request = parse_request(@env.args())
  let receipt_secret_path = @env.get_env_var(
    "LUNANEXA_LEASE_HELPER_RECEIPT_SECRET_PATH",
  ).unwrap_or("/etc/lunanexa-root/lease-helper-receipt-key")
  if !receipt_secret_path.has_prefix("/") || !@fs.exists(receipt_secret_path) {
    raise Failure::Failure("lease helper receipt authority is unavailable")
  }
  let receipt_secret = @fs.read_file(receipt_secret_path)
    .text()
    .trim()
    .to_owned()
  if receipt_secret.length() < 32 {
    raise Failure::Failure("lease helper receipt authority is too short")
  }
  let action = action_contract(request)
  if !@nodelease.valid_helper_authorization(
      action,
      request.authorization,
      receipt_secret,
      @async.now(),
    ) {
    raise Failure::Failure(
      "lease helper action authority is invalid or expired",
    )
  }
  match request.action {
    "provision" => provision(config, request)
    "revoke" => revoke(config, request)
    "sanitize" => sanitize(config, request)
    "quarantine" => quarantine(config, request)
    _ => raise Failure::Failure("unsupported lease helper action")
  }
  println(
    @nodelease.signed_helper_receipt(action, @async.now(), receipt_secret),
  )
}
