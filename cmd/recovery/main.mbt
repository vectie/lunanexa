///|
fn environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
fn state_path(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
async fn read_required(path : String) -> String {
  if !@fs.exists(path) {
    raise Failure::Failure("required state snapshot does not exist: \{path}")
  }
  @fs.read_file(path).text()
}

///|
async fn write_atomic(path : String, value : String) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    value,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn validate_snapshots(bundle : @store.FullBackupBundle) -> Unit raise {
  let control = @store.MemoryStore::restore(bundle.controller_snapshot)
  if !@store.validate_audit_chain(control.audit_events()) {
    raise Failure::Failure("controller audit chain is invalid")
  }
  ignore(@registry.ModelRegistry::restore(bundle.registry_snapshot))
  ignore(@node.EnrollmentService::restore(bundle.enrollment_snapshot))
  let scheduler : @scheduler.SchedulerSnapshot = @json.from_json(
    @json.parse(bundle.scheduler_snapshot),
  )
  if scheduler.schema_version != "lunanexa.scheduler.v2" ||
    scheduler.capacity <= 0 {
    raise Failure::Failure("scheduler snapshot is invalid")
  }
  let telemetry : @telemetry.TelemetrySnapshot = @json.from_json(
    @json.parse(bundle.telemetry_snapshot),
  )
  if telemetry.schema_version != "lunanexa.telemetry.v1" {
    raise Failure::Failure("telemetry snapshot is invalid")
  }
}

///|
async fn export_bundle(output : String, signature_ref : String) -> Unit {
  let controller_snapshot = read_required(
    state_path("LUNANEXA_STATE_PATH", "lunanexa-state.json"),
  )
  let registry_snapshot = read_required(
    state_path("LUNANEXA_REGISTRY_PATH", "lunanexa-registry.json"),
  )
  let enrollment_snapshot = read_required(
    state_path("LUNANEXA_ENROLLMENT_PATH", "lunanexa-enrollment.json"),
  )
  let scheduler_snapshot = read_required(
    state_path("LUNANEXA_SCHEDULER_PATH", "lunanexa-scheduler.json"),
  )
  let telemetry_snapshot = read_required(
    state_path("LUNANEXA_TELEMETRY_PATH", "lunanexa-telemetry.json"),
  )
  let control = @store.MemoryStore::restore(controller_snapshot)
  if !@store.validate_audit_chain(control.audit_events()) {
    raise Failure::Failure("controller audit chain is invalid")
  }
  let audit_tail_hash = control
    .audit_events()
    .last()
    .map(event => event.event_hash)
    .unwrap_or("genesis")
  let value = @store.create_full_backup(
    controller_snapshot,
    registry_snapshot,
    enrollment_snapshot,
    scheduler_snapshot,
    telemetry_snapshot,
    audit_tail_hash,
    signature_ref,
    @async.now(),
  )
  validate_snapshots(@store.inspect_full_backup(value))
  write_atomic(output, value)
  println("backup exported; sign the exact bundle before restore: \{output}")
}

///|
async fn restore_bundle(
  bundle_path : String,
  signature_path : String,
  destination : String,
) -> Unit {
  if !destination.has_prefix("/") ||
    destination == "/" ||
    destination.contains("..") {
    raise Failure::Failure(
      "restore destination must be a narrow absolute directory",
    )
  }
  let value = read_required(bundle_path)
  let digest = "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))}"
  let verifier = @registry.CosignVerifier::new(
    environment("LUNANEXA_COSIGN_BINARY"),
    environment("LUNANEXA_COSIGN_PUBLIC_KEY_PATH"),
  )
  ignore(verifier.verify_blob(bundle_path, signature_path, digest))
  let bundle = @store.inspect_full_backup(value)
  if bundle.signature_ref != signature_path {
    raise Failure::Failure(
      "verified signature path does not match the backup manifest",
    )
  }
  validate_snapshots(bundle)
  @fs.mkdir(destination, permission=0o700, recursive=true)
  let paths = [
    "\{destination}/control.json",
    "\{destination}/registry.json",
    "\{destination}/enrollment.json",
    "\{destination}/scheduler.json",
    "\{destination}/telemetry.json",
  ]
  for path in paths {
    if @fs.exists(path) {
      raise Failure::Failure(
        "restore destination is not clean; refusing to replace \{path}",
      )
    }
  }
  write_atomic(paths[0], bundle.controller_snapshot)
  write_atomic(paths[1], bundle.registry_snapshot)
  write_atomic(paths[2], bundle.enrollment_snapshot)
  write_atomic(paths[3], bundle.scheduler_snapshot)
  write_atomic(paths[4], bundle.telemetry_snapshot)
  println("verified backup restored into clean destination: \{destination}")
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 4 && args[1] == "export" {
    export_bundle(args[2], args[3])
  } else if args.length() == 5 && args[1] == "restore" {
    restore_bundle(args[2], args[3], args[4])
  } else {
    raise Failure::Failure(
      "usage: lunanexa-recovery export BUNDLE SIGNATURE_REF | restore BUNDLE SIGNATURE_FILE CLEAN_DIRECTORY",
    )
  }
}
