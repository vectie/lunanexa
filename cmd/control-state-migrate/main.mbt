///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure::Failure("required environment reference is missing: \{name}")
  }
  value
}

///|
async fn required_file(name : String) -> String {
  let path = required_environment(name)
  if !@fs.exists(path) {
    raise Failure::Failure(
      "required control-plane snapshot is missing: \{name}",
    )
  }
  path
}

///|
async fn main {
  let database = @database.PostgresDatabase::open(
    required_environment("LUNANEXA_DATABASE_URL"),
  )
  let domains = [
    ("control", "lunanexa.store.v1"),
    ("model_registry", "lunanexa.registry.v1"),
    ("node_enrollment", "lunanexa.enrollment.v2"),
    ("scheduler", "lunanexa.scheduler.v2"),
    ("telemetry", "lunanexa.telemetry.v1"),
    ("deployments", "lunanexa.deployments.v2"),
  ]
  for domain in domains {
    if database.load_snapshot(domain.0, domain.1) is Some(_) {
      raise Failure::Failure(
        "target PostgreSQL control-plane domain is not empty: \{domain.0}",
      )
    }
  }
  let control = @store.FileStore::open(required_file("LUNANEXA_STATE_PATH"))
  let registry = @registry.FileRegistry::open(
    required_file("LUNANEXA_REGISTRY_PATH"),
  )
  let enrollment = @node.FileEnrollmentService::open(
    required_file("LUNANEXA_ENROLLMENT_PATH"),
  )
  let scheduler = @scheduler.FileScheduler::open(
    required_file("LUNANEXA_SCHEDULER_PATH"),
    1,
  )
  let telemetry = @telemetry.FileTelemetry::open(
    required_file("LUNANEXA_TELEMETRY_PATH"),
  )
  let deployments = @deployment_store.FileDeploymentStore::open(
    required_file("LUNANEXA_DEPLOYMENT_PATH"),
    required_environment("LUNANEXA_CATALOG_SIGNING_SECRET"),
  )
  database.save_opaque_snapshots([
    ("control", "lunanexa.store.v1", control.backup_snapshot()),
    (
      "model_registry",
      "lunanexa.registry.v1",
      registry.snapshot().to_json().stringify(),
    ),
    ("node_enrollment", "lunanexa.enrollment.v2", enrollment.snapshot()),
    (
      "scheduler",
      "lunanexa.scheduler.v2",
      scheduler.snapshot().to_json().stringify(),
    ),
    (
      "telemetry",
      "lunanexa.telemetry.v1",
      telemetry.snapshot().to_json().stringify(),
    ),
    (
      "deployments",
      "lunanexa.deployments.v2",
      deployments.snapshot().to_json().stringify(),
    ),
  ])
  database.close()
  println(
    "six validated control-plane snapshots migrated atomically to PostgreSQL",
  )
}
