///|
pub(all) enum ApiMethod {
  Get
  Post
  Put
  Delete
} derive(Debug, Eq)

///|
pub(all) struct HttpReply {
  status : Int
  body : String
  content_type : String
} derive(Debug, Eq)

///|
pub(all) struct CancellationReceipt {
  workload_id : String
  accepted : Bool
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct ApiService {
  global_settings : @settings.GlobalAdminSettings
  store : @store.FileStore
  account_store : @account.AccountStore?
  identity_assertion_secret : String
  access_store : @access.AccessStore?
  management_database : @database.PostgresDatabase?
  technical_store : @technical_store.TechnicalStore?
  commercial_store : @commercial.CommercialStore
  commercial_integrations : @commercial_integrations.IntegrationStore
  offline_commerce_store : @offline_store.OfflineCommerceStore?
  contract_document_store : @contractdoc_store.ContractDocumentStore?
  contract_document_worker_token : String
  // Four-eyes approval threshold in CNY minor units: operator execute/close on
  // a packet whose `lease.total_rent` exceeds it requires a second operator.
  contract_approval_threshold_minor_units : Int64?
  deployment_store : @deployment_store.FileDeploymentStore?
  exclusive_lease_store : @nodelease_store.FileExclusiveLeaseStore?
  credential_handoff_store : @credential_store.CredentialHandoffStore?
  client_handoff_store : @client_handoff_store.ClientHandoffStore?
  client_launch_config : @client_handoff.ClientLaunchConfig?
  lease_helper_receipt_secret : String
  machine_helper_adapter_evidence : @nodelease.MachineHelperAdapterReadinessEvidence?
  guide_diagnostics_token : String
  portal_store : @portal_store.FilePortalStore?
  notification_store : @notification_store.NotificationStore?
  observability_store : @observability.ObservabilityStore?
  notification_delivery_adapter_configured : Bool
  external_observability_collector_configured : Bool
  external_export_proof_token : String
  available_secret_refs : Array[String]
  registry : @registry.FileRegistry?
  enrollment : @node.FileEnrollmentService?
  scheduler : @scheduler.FileScheduler?
  telemetry : @telemetry.FileTelemetry?
  workspace_directory : @directory.FileWorkspaceDirectory?
  require_workspace_lease : Bool
  signature_verifier : @registry.CosignVerifier?
  reconciliation_only : Bool
  runtime : @runtimes.OpenAiTextRuntime
  operator_token : String
  // Token → operator identity map for contract-document operator routes,
  // where every mutation is attributed to the authenticated operator.
  operator_tokens : Map[String, String]
  inference_token : String
  audit_token : String
  monitoring_token : String
  assignment_signing_secret : String
  artifact_root : String?
  exclusive_lease_unit_price : @commercial.FixedMoney
  provider_callback_secrets : Map[String, String]
  artifact_worker_callback_token : String?
  artifact_scanner_callback_token : String?
  entitlement_authority_callback_token : String?
  offline_transfer_adapter_endpoint : String?
  offline_transfer_adapter_token : String?
  model_source_adapter_endpoint : String?
  model_source_adapter_token : String?
  offline_transfer_session_secret : String
  offline_commerce_capabilities : Array[
    @offline.OfflineCommerceCapabilityEvidence,
  ]
  offline_commerce_capabilities_expires_unix_ms : Int64
  node_token : String
  version : String
  active : Map[String, @async.Task[@runtimes.RuntimeInvocationResult]]
  active_mutex : @async.Mutex
  response_cache : Map[String, @contracts.WorkloadResponse]
  response_cache_order : Array[String]
  audit_mutex : @async.Mutex
  execution_slots : @async.Semaphore
}

///|
pub fn ApiService::new(
  store : @store.FileStore,
  runtime : @runtimes.OpenAiTextRuntime,
  operator_token : String,
  inference_token : String,
  node_token : String,
  version : String,
) -> ApiService {
  {
    global_settings: @settings.default_global_admin_settings(),
    store,
    account_store: None,
    identity_assertion_secret: "",
    access_store: None,
    management_database: None,
    technical_store: None,
    commercial_store: @commercial.CommercialStore::new(),
    commercial_integrations: @commercial_integrations.IntegrationStore::new(),
    offline_commerce_store: None,
    contract_document_store: None,
    contract_document_worker_token: "",
    contract_approval_threshold_minor_units: None,
    deployment_store: None,
    exclusive_lease_store: None,
    credential_handoff_store: None,
    client_handoff_store: None,
    client_launch_config: None,
    lease_helper_receipt_secret: "",
    machine_helper_adapter_evidence: None,
    guide_diagnostics_token: "",
    portal_store: None,
    notification_store: None,
    observability_store: None,
    notification_delivery_adapter_configured: false,
    external_observability_collector_configured: false,
    external_export_proof_token: "",
    available_secret_refs: [],
    registry: None,
    enrollment: None,
    scheduler: None,
    telemetry: None,
    workspace_directory: None,
    require_workspace_lease: false,
    signature_verifier: None,
    reconciliation_only: false,
    runtime,
    operator_token,
    operator_tokens: Map([(operator_token, "operator")]),
    inference_token,
    audit_token: operator_token,
    monitoring_token: operator_token,
    assignment_signing_secret: node_token,
    artifact_root: None,
    exclusive_lease_unit_price: { minor_units: 0L, currency: "CNY", scale: 2 },
    provider_callback_secrets: Map([]),
    artifact_worker_callback_token: None,
    artifact_scanner_callback_token: None,
    entitlement_authority_callback_token: None,
    offline_transfer_adapter_endpoint: None,
    offline_transfer_adapter_token: None,
    model_source_adapter_endpoint: None,
    model_source_adapter_token: None,
    offline_transfer_session_secret: "",
    offline_commerce_capabilities: [],
    offline_commerce_capabilities_expires_unix_ms: 0L,
    node_token,
    version,
    active: Map([]),
    active_mutex: Mutex(),
    response_cache: Map([]),
    response_cache_order: [],
    audit_mutex: Mutex(),
    execution_slots: Semaphore(128),
  }
}

///|
pub fn ApiService::with_registry(
  store : @store.FileStore,
  registry : @registry.FileRegistry,
  runtime : @runtimes.OpenAiTextRuntime,
  operator_token : String,
  inference_token : String,
  node_token : String,
  version : String,
) -> ApiService {
  {
    global_settings: @settings.default_global_admin_settings(),
    store,
    account_store: None,
    identity_assertion_secret: "",
    access_store: None,
    management_database: None,
    technical_store: None,
    commercial_store: @commercial.CommercialStore::new(),
    commercial_integrations: @commercial_integrations.IntegrationStore::new(),
    offline_commerce_store: None,
    contract_document_store: None,
    contract_document_worker_token: "",
    contract_approval_threshold_minor_units: None,
    deployment_store: None,
    exclusive_lease_store: None,
    credential_handoff_store: None,
    client_handoff_store: None,
    client_launch_config: None,
    lease_helper_receipt_secret: "",
    machine_helper_adapter_evidence: None,
    guide_diagnostics_token: "",
    portal_store: None,
    notification_store: None,
    observability_store: None,
    notification_delivery_adapter_configured: false,
    external_observability_collector_configured: false,
    external_export_proof_token: "",
    available_secret_refs: [],
    registry: Some(registry),
    enrollment: None,
    scheduler: None,
    telemetry: None,
    workspace_directory: None,
    require_workspace_lease: false,
    signature_verifier: None,
    reconciliation_only: false,
    runtime,
    operator_token,
    operator_tokens: Map([(operator_token, "operator")]),
    inference_token,
    audit_token: operator_token,
    monitoring_token: operator_token,
    assignment_signing_secret: node_token,
    artifact_root: None,
    exclusive_lease_unit_price: { minor_units: 0L, currency: "CNY", scale: 2 },
    provider_callback_secrets: Map([]),
    artifact_worker_callback_token: None,
    artifact_scanner_callback_token: None,
    entitlement_authority_callback_token: None,
    offline_transfer_adapter_endpoint: None,
    offline_transfer_adapter_token: None,
    model_source_adapter_endpoint: None,
    model_source_adapter_token: None,
    offline_transfer_session_secret: "",
    offline_commerce_capabilities: [],
    offline_commerce_capabilities_expires_unix_ms: 0L,
    node_token,
    version,
    active: Map([]),
    active_mutex: Mutex(),
    response_cache: Map([]),
    response_cache_order: [],
    audit_mutex: Mutex(),
    execution_slots: Semaphore(128),
  }
}

///|
pub fn ApiService::with_services(
  store : @store.FileStore,
  registry : @registry.FileRegistry,
  enrollment : @node.FileEnrollmentService,
  runtime : @runtimes.OpenAiTextRuntime,
  operator_token : String,
  inference_token : String,
  node_token : String,
  version : String,
) -> ApiService {
  {
    global_settings: @settings.default_global_admin_settings(),
    store,
    account_store: None,
    identity_assertion_secret: "",
    access_store: None,
    management_database: None,
    technical_store: None,
    commercial_store: @commercial.CommercialStore::new(),
    commercial_integrations: @commercial_integrations.IntegrationStore::new(),
    offline_commerce_store: None,
    contract_document_store: None,
    contract_document_worker_token: "",
    contract_approval_threshold_minor_units: None,
    deployment_store: None,
    exclusive_lease_store: None,
    credential_handoff_store: None,
    client_handoff_store: None,
    client_launch_config: None,
    lease_helper_receipt_secret: "",
    machine_helper_adapter_evidence: None,
    guide_diagnostics_token: "",
    portal_store: None,
    notification_store: None,
    observability_store: None,
    notification_delivery_adapter_configured: false,
    external_observability_collector_configured: false,
    external_export_proof_token: "",
    available_secret_refs: [],
    registry: Some(registry),
    enrollment: Some(enrollment),
    scheduler: None,
    telemetry: None,
    workspace_directory: None,
    require_workspace_lease: false,
    signature_verifier: None,
    reconciliation_only: false,
    runtime,
    operator_token,
    operator_tokens: Map([(operator_token, "operator")]),
    inference_token,
    audit_token: operator_token,
    monitoring_token: operator_token,
    assignment_signing_secret: node_token,
    artifact_root: None,
    exclusive_lease_unit_price: { minor_units: 0L, currency: "CNY", scale: 2 },
    provider_callback_secrets: Map([]),
    artifact_worker_callback_token: None,
    artifact_scanner_callback_token: None,
    entitlement_authority_callback_token: None,
    offline_transfer_adapter_endpoint: None,
    offline_transfer_adapter_token: None,
    model_source_adapter_endpoint: None,
    model_source_adapter_token: None,
    offline_transfer_session_secret: "",
    offline_commerce_capabilities: [],
    offline_commerce_capabilities_expires_unix_ms: 0L,
    node_token,
    version,
    active: Map([]),
    active_mutex: Mutex(),
    response_cache: Map([]),
    response_cache_order: [],
    audit_mutex: Mutex(),
    execution_slots: Semaphore(128),
  }
}

///|
pub fn ApiService::with_control_plane(
  store : @store.FileStore,
  registry : @registry.FileRegistry,
  enrollment : @node.FileEnrollmentService,
  scheduler : @scheduler.FileScheduler,
  telemetry : @telemetry.FileTelemetry,
  runtime : @runtimes.OpenAiTextRuntime,
  operator_token : String,
  inference_token : String,
  node_token : String,
  version : String,
) -> ApiService {
  {
    global_settings: @settings.default_global_admin_settings(),
    store,
    account_store: None,
    identity_assertion_secret: "",
    access_store: None,
    management_database: None,
    technical_store: None,
    commercial_store: @commercial.CommercialStore::new(),
    commercial_integrations: @commercial_integrations.IntegrationStore::new(),
    offline_commerce_store: None,
    contract_document_store: None,
    contract_document_worker_token: "",
    contract_approval_threshold_minor_units: None,
    deployment_store: None,
    exclusive_lease_store: None,
    credential_handoff_store: None,
    client_handoff_store: None,
    client_launch_config: None,
    lease_helper_receipt_secret: "",
    machine_helper_adapter_evidence: None,
    guide_diagnostics_token: "",
    portal_store: None,
    notification_store: None,
    observability_store: None,
    notification_delivery_adapter_configured: false,
    external_observability_collector_configured: false,
    external_export_proof_token: "",
    available_secret_refs: [],
    registry: Some(registry),
    enrollment: Some(enrollment),
    scheduler: Some(scheduler),
    telemetry: Some(telemetry),
    workspace_directory: None,
    require_workspace_lease: false,
    signature_verifier: None,
    reconciliation_only: false,
    runtime,
    operator_token,
    operator_tokens: Map([(operator_token, "operator")]),
    inference_token,
    audit_token: operator_token,
    monitoring_token: operator_token,
    assignment_signing_secret: node_token,
    artifact_root: None,
    exclusive_lease_unit_price: { minor_units: 0L, currency: "CNY", scale: 2 },
    provider_callback_secrets: Map([]),
    artifact_worker_callback_token: None,
    artifact_scanner_callback_token: None,
    entitlement_authority_callback_token: None,
    offline_transfer_adapter_endpoint: None,
    offline_transfer_adapter_token: None,
    model_source_adapter_endpoint: None,
    model_source_adapter_token: None,
    offline_transfer_session_secret: "",
    offline_commerce_capabilities: [],
    offline_commerce_capabilities_expires_unix_ms: 0L,
    node_token,
    version,
    active: Map([]),
    active_mutex: Mutex(),
    response_cache: Map([]),
    response_cache_order: [],
    audit_mutex: Mutex(),
    execution_slots: Semaphore(128),
  }
}

///|
/// Installs the token → operator-identity map used by every operator route,
/// replacing the legacy single-token check when the map is non-empty. The
/// default constructor seeds the map from the legacy token, so an empty list
/// leaves existing deployments compatible.
pub fn ApiService::with_operator_tokens(
  self : ApiService,
  tokens : Array[(String, String)],
) -> ApiService {
  if tokens.length() == 0 {
    self
  } else {
    let operator_tokens : Map[String, String] = Map([])
    for pair in tokens {
      operator_tokens[pair.1] = pair.0
    }
    { ..self, operator_tokens, }
  }
}

///|
/// Enables externally authenticated human accounts and short-lived browser
/// sessions. Passwords and upstream IdP tokens remain outside LunaNexa.
pub fn ApiService::with_account_store(
  self : ApiService,
  account_store : @account.AccountStore,
  identity_assertion_secret : String,
) -> ApiService {
  { ..self, account_store: Some(account_store), identity_assertion_secret }
}

///|
/// Enables durable workspace administration and, when requested, requires a
/// trusted-ingress subject assertion with an active grant and lease before a
/// new workload can be admitted.
pub fn ApiService::with_workspace_directory(
  self : ApiService,
  directory : @directory.FileWorkspaceDirectory,
  require_workspace_lease : Bool,
) -> ApiService {
  { ..self, workspace_directory: Some(directory), require_workspace_lease }
}

///|
/// Enables durable, hashed, tenant-scoped northbound API credentials. The
/// external identity provider still owns interactive authentication.
pub fn ApiService::with_access_store(
  self : ApiService,
  access_store : @access.AccessStore,
) -> ApiService {
  { ..self, access_store: Some(access_store) }
}

///|
/// Installs restart-restored commercial stores and their transactional
/// PostgreSQL persistence boundary.
pub fn ApiService::with_commercial_persistence(
  self : ApiService,
  commercial_store : @commercial.CommercialStore,
  commercial_integrations : @commercial_integrations.IntegrationStore,
  management_database : @database.PostgresDatabase,
) -> ApiService {
  {
    ..self,
    commercial_store,
    commercial_integrations,
    management_database: Some(management_database),
  }
}

///|
/// Enables the durable hybrid digital-to-offline order and evidence authority.
pub fn ApiService::with_offline_commerce_store(
  self : ApiService,
  offline_commerce_store : @offline_store.OfflineCommerceStore,
) -> ApiService {
  { ..self, offline_commerce_store: Some(offline_commerce_store) }
}

///|
/// Enables the durable, source-template-bound contract document authority.
pub fn ApiService::with_contract_document_store(
  self : ApiService,
  contract_document_store : @contractdoc_store.ContractDocumentStore,
) -> ApiService {
  { ..self, contract_document_store: Some(contract_document_store) }
}

///|
/// Installs the four-eyes approval threshold (CNY minor units). Operator
/// execute/close transitions on packets above it become durable approval
/// requests that a second operator must decide.
pub fn ApiService::with_contract_approval_threshold(
  self : ApiService,
  threshold_minor_units : Int64,
) -> ApiService {
  {
    ..self,
    contract_approval_threshold_minor_units: Some(threshold_minor_units),
  }
}

///| Installs a machine-only contract renderer identity. Human portal and

///|
/// operator tokens are never accepted on worker routes.
pub fn ApiService::with_contract_document_worker_token(
  self : ApiService,
  token : String,
) -> ApiService {
  if token.length() < 32 ||
    token == self.operator_token ||
    token == self.inference_token {
    self
  } else {
    { ..self, contract_document_worker_token: token }
  }
}

///|
/// Installs distinct machine identities for artifact-worker completion and
/// object-store/scanner callbacks. Human operator and customer tokens are never
/// accepted on those callback routes.
pub fn ApiService::with_offline_artifact_callback_tokens(
  self : ApiService,
  artifact_worker_callback_token : String,
  artifact_scanner_callback_token : String,
) -> ApiService {
  if artifact_worker_callback_token.length() < 32 ||
    artifact_scanner_callback_token.length() < 32 ||
    artifact_worker_callback_token == artifact_scanner_callback_token ||
    artifact_worker_callback_token == self.operator_token ||
    artifact_worker_callback_token == self.inference_token ||
    artifact_scanner_callback_token == self.operator_token ||
    artifact_scanner_callback_token == self.inference_token {
    self
  } else {
    {
      ..self,
      artifact_worker_callback_token: Some(artifact_worker_callback_token),
      artifact_scanner_callback_token: Some(artifact_scanner_callback_token),
    }
  }
}

///| Installs the separate machine identity used by the typed entitlement

///|
/// authority. Invalid or reused identities leave the authority unavailable.
pub fn ApiService::with_entitlement_authority_callback_token(
  self : ApiService,
  token : String,
) -> ApiService {
  if token.length() < 32 ||
    token == self.operator_token ||
    token == self.inference_token ||
    self.artifact_worker_callback_token == Some(token) ||
    self.artifact_scanner_callback_token == Some(token) {
    self
  } else {
    { ..self, entitlement_authority_callback_token: Some(token) }
  }
}

///|
fn offline_decimal_port(value : String) -> Bool {
  if value == "" ||
    value.length() > 5 ||
    !value.all(character => character >= '0' && character <= '9') {
    return false
  }
  let port = @string.parse_int64(value) catch { _ => return false }
  port > 0L && port <= 65535L
}

///|
fn offline_safe_host(value : String) -> Bool {
  value != "" &&
  value.length() <= 253 &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '.' ||
    character == '-'
  }) &&
  !value.has_prefix(".") &&
  !value.has_suffix(".") &&
  !value.contains("..") &&
  value
  .split(".")
  .all(label => label != "" && !label.has_prefix("-") && !label.has_suffix("-"))
}

///|
fn offline_safe_https_authority(authority : String) -> Bool {
  if authority == "" ||
    authority.contains("@") ||
    authority.contains("[") ||
    authority.contains("]") {
    return false
  }
  match authority.rev_find(":") {
    Some(colon) =>
      offline_safe_host(authority[:colon].to_owned()) &&
      offline_decimal_port(authority[colon + 1:].to_owned())
    None => offline_safe_host(authority)
  }
}

///|
fn offline_safe_loopback_authority(authority : String) -> Bool {
  if authority.has_prefix("127.0.0.1:") {
    offline_decimal_port(authority[10:].to_owned())
  } else if authority.has_prefix("localhost:") {
    offline_decimal_port(authority[10:].to_owned())
  } else if authority.has_prefix("[::1]:") {
    offline_decimal_port(authority[6:].to_owned())
  } else {
    false
  }
}

///|
fn safe_offline_transfer_endpoint(endpoint : String) -> Bool {
  if endpoint == "" ||
    endpoint != endpoint.trim().to_owned() ||
    endpoint.length() > 512 ||
    endpoint.contains("@") ||
    endpoint.contains("?") ||
    endpoint.contains("#") ||
    endpoint.contains("\\") ||
    endpoint.any(character => character.is_whitespace()) {
    return false
  }
  let (remainder, secure) = if endpoint.has_prefix("https://") {
    (endpoint[8:].to_owned(), true)
  } else if endpoint.has_prefix("http://") {
    (endpoint[7:].to_owned(), false)
  } else {
    return false
  }
  guard remainder.find("/") is Some(slash) else { return false }
  let authority = remainder[:slash].to_owned()
  let path = remainder[slash:].to_owned()
  path == "/v1/offline-transfers" &&
  (if secure {
    offline_safe_https_authority(authority)
  } else {
    offline_safe_loopback_authority(authority)
  })
}

///| Configures the provider-neutral object-transfer boundary. Invalid or

///|
/// partial input leaves it unavailable; cmd/control rejects partial startup.
pub fn ApiService::with_offline_transfer_adapter(
  self : ApiService,
  endpoint : String,
  adapter_token : String,
  session_secret : String,
) -> ApiService raise {
  if !safe_offline_transfer_endpoint(endpoint) ||
    adapter_token.length() < 32 ||
    adapter_token.length() > 4096 ||
    session_secret.length() < 32 ||
    session_secret.length() > 4096 ||
    adapter_token == session_secret ||
    adapter_token == self.operator_token ||
    adapter_token == self.inference_token ||
    session_secret == self.operator_token ||
    session_secret == self.inference_token {
    raise Failure::Failure("offline transfer adapter configuration is invalid")
  } else {
    {
      ..self,
      offline_transfer_adapter_endpoint: Some(endpoint),
      offline_transfer_adapter_token: Some(adapter_token),
      offline_transfer_session_secret: session_secret,
    }
  }
}

///|
pub fn ApiService::with_model_source_adapter(
  self : ApiService,
  endpoint : String,
  token : String,
) -> ApiService raise Failure {
  let trusted = endpoint == "http://lunanexa-model-source:8090" ||
    endpoint.has_prefix("http://127.0.0.1:") ||
    endpoint.has_prefix("http://localhost:")
  if !trusted ||
    endpoint.contains("?") ||
    endpoint.contains("#") ||
    endpoint.has_suffix("/") ||
    token.length() < 32 ||
    token.length() > 4096 {
    raise Failure("model-source adapter configuration is invalid")
  }
  {
    ..self,
    model_source_adapter_endpoint: Some(endpoint),
    model_source_adapter_token: Some(token),
  }
}

///| Supplies deployment-owned, retained verification evidence. The API never

///|
/// infers production readiness from the mere presence of repository code.
pub fn ApiService::with_offline_commerce_capabilities(
  self : ApiService,
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence],
  expires_unix_ms : Int64,
) -> ApiService {
  {
    ..self,
    offline_commerce_capabilities: capabilities,
    offline_commerce_capabilities_expires_unix_ms: expires_unix_ms,
  }
}

///|
pub fn ApiService::with_technical_store(
  self : ApiService,
  technical_store : @technical_store.TechnicalStore,
) -> ApiService {
  { ..self, technical_store: Some(technical_store) }
}

///|
/// Enables the durable management-plane catalog and deployment-intent API.
pub fn ApiService::with_deployment_store(
  self : ApiService,
  deployment_store : @deployment_store.FileDeploymentStore,
  available_secret_refs? : Array[String] = [],
) -> ApiService {
  { ..self, deployment_store: Some(deployment_store), available_secret_refs }
}

///|
/// Enables durable exclusive-node lease authority. A non-terminal lease is an
/// immediate managed-placement fence, independent of heartbeat propagation.
pub fn ApiService::with_exclusive_lease_store(
  self : ApiService,
  exclusive_lease_store : @nodelease_store.FileExclusiveLeaseStore,
) -> ApiService {
  { ..self, exclusive_lease_store: Some(exclusive_lease_store) }
}

///|
/// Enables restart-safe, one-time, subject-bound SSH credential handoffs.
pub fn ApiService::with_credential_handoff_store(
  self : ApiService,
  credential_handoff_store : @credential_store.CredentialHandoffStore,
) -> ApiService {
  { ..self, credential_handoff_store: Some(credential_handoff_store) }
}

///|
/// Enables provider-neutral desktop workspace handoffs. Product-specific
/// provider binding remains the responsibility of the local client adapter.
pub fn ApiService::with_client_handoff_store(
  self : ApiService,
  client_handoff_store : @client_handoff_store.ClientHandoffStore,
  client_launch_config : @client_handoff.ClientLaunchConfig,
) -> ApiService raise Failure {
  if !@client_handoff.valid_client_launch_config(client_launch_config) {
    raise Failure("client launch configuration is invalid")
  }
  {
    ..self,
    client_handoff_store: Some(client_handoff_store),
    client_launch_config: Some(client_launch_config),
  }
}

///|
/// Installs the independent root-helper receipt verifier. It is deliberately
/// distinct from operator, node-auth, assignment and lease-authority secrets.
pub fn ApiService::with_lease_helper_receipt_secret(
  self : ApiService,
  secret : String,
) -> ApiService raise Failure {
  if secret.length() < 32 {
    raise Failure("lease helper receipt secret must contain at least 32 bytes")
  }
  { ..self, lease_helper_receipt_secret: secret }
}

///|
/// Records the expiry of retained, deployment-owned proof that the node-side
/// privileged helper adapter is installed and was exercised successfully.
pub fn ApiService::with_machine_helper_adapter_evidence(
  self : ApiService,
  evidence : @nodelease.MachineHelperAdapterReadinessEvidence,
) -> ApiService raise Failure {
  if !@nodelease.machine_helper_adapter_evidence_ready(
      evidence,
      evidence.checked_unix_ms,
    ) {
    raise Failure("machine helper adapter evidence is invalid")
  }
  { ..self, machine_helper_adapter_evidence: Some(evidence) }
}

///|
/// Installs a read-only token scoped to the aggregate guide diagnostics route.
pub fn ApiService::with_guide_diagnostics_token(
  self : ApiService,
  token : String,
) -> ApiService raise Failure {
  if token.length() < 32 {
    raise Failure("guide diagnostics token must contain at least 32 bytes")
  }
  { ..self, guide_diagnostics_token: token }
}

///|
/// Enables the centralized enterprise portal authority used by both the
/// customer-facing site and the operator approval workflow.
pub fn ApiService::with_portal_store(
  self : ApiService,
  portal_store : @portal_store.FilePortalStore,
) -> ApiService {
  { ..self, portal_store: Some(portal_store) }
}

///|
/// Enables the durable operator alert center and tenant notification inbox.
pub fn ApiService::with_notification_store(
  self : ApiService,
  notification_store : @notification_store.NotificationStore,
) -> ApiService {
  { ..self, notification_store: Some(notification_store) }
}

///|
/// Enables bounded structured operational events and aggregate metrics.
pub fn ApiService::with_observability_store(
  self : ApiService,
  observability_store : @observability.ObservabilityStore,
) -> ApiService {
  { ..self, observability_store: Some(observability_store) }
}

///|
/// Installs only deployment evidence, never an adapter credential.
pub fn ApiService::with_notification_delivery_adapter_configured(
  self : ApiService,
  configured : Bool,
) -> ApiService {
  { ..self, notification_delivery_adapter_configured: configured }
}

///| Marks the external collector configured only after deployment explicitly

///|
/// attests that the collector/export path is installed.
pub fn ApiService::with_external_observability_collector_configured(
  self : ApiService,
  configured : Bool,
) -> ApiService {
  { ..self, external_observability_collector_configured: configured }
}

///| Installs the single-purpose collector-to-sink proof authority. Metrics and

///|
/// audit readers cannot use their role tokens to forge production readiness.
pub fn ApiService::with_external_export_proof_token(
  self : ApiService,
  token : String,
) -> ApiService {
  if token.length() < 32 || token.length() > 4096 {
    return self
  }
  { ..self, external_export_proof_token: token }
}

///|
pub fn ApiService::with_signature_verifier(
  self : ApiService,
  verifier : @registry.CosignVerifier,
) -> ApiService {
  { ..self, signature_verifier: Some(verifier) }
}

///|
pub fn ApiService::with_reconciliation_only(
  self : ApiService,
  enabled : Bool,
) -> ApiService {
  { ..self, reconciliation_only: enabled }
}

///|
pub fn ApiService::with_role_tokens(
  self : ApiService,
  audit_token : String,
  monitoring_token : String,
) -> ApiService {
  { ..self, audit_token, monitoring_token }
}

///|
pub fn ApiService::with_assignment_signing_secret(
  self : ApiService,
  secret : String,
) -> ApiService {
  { ..self, assignment_signing_secret: secret }
}

///|
/// Enables the management-node artifact gateway. The root is deployment owned
/// and every network read is additionally bound to a live signed assignment.
pub fn ApiService::with_artifact_root(
  self : ApiService,
  artifact_root : String,
) -> ApiService {
  { ..self, artifact_root: Some(artifact_root) }
}

///| Configures the fixed price per exclusive machine-second used for the

///| budget estimate at lease admission. The ledger remains the billing source

///|
/// of truth after observed usage is rated.
pub fn ApiService::with_exclusive_lease_unit_price(
  self : ApiService,
  unit_price : @commercial.FixedMoney,
) -> ApiService raise {
  if unit_price.minor_units < 0L {
    raise Failure::Failure("exclusive lease unit price cannot be negative")
  }
  ignore(
    @commercial.money(
      unit_price.minor_units,
      unit_price.currency,
      unit_price.scale,
    ),
  )
  { ..self, exclusive_lease_unit_price: unit_price }
}

///| Installs transport-authentication secrets keyed by `provider|environment`.

///|
/// Secrets remain deployment references and are never included in snapshots.
pub fn ApiService::with_provider_callback_secrets(
  self : ApiService,
  secrets : Map[String, String],
) -> ApiService raise {
  for key, secret in secrets {
    if !valid_provider_callback_secret_entry(key, secret) {
      raise Failure::Failure("invalid provider callback secret configuration")
    }
  }
  { ..self, provider_callback_secrets: secrets }
}

///|
pub fn ApiService::with_runtime_concurrency(
  self : ApiService,
  concurrency : Int,
) -> ApiService raise {
  if concurrency <= 0 || concurrency > 4096 {
    raise Failure::Failure("runtime concurrency must be positive and bounded")
  }
  let scheduler = {
    ..self.global_settings.scheduler,
    runtime_concurrency: concurrency,
  }
  {
    ..self,
    global_settings: { ..self.global_settings, scheduler, },
    execution_slots: Semaphore(concurrency),
  }
}

///|
/// Installs the management-node policy after validating every administrator
/// value against LunaNexa's non-configurable safety ceilings.
pub fn ApiService::with_global_admin_settings(
  self : ApiService,
  global_settings : @settings.GlobalAdminSettings,
) -> ApiService raise {
  @settings.validate_global_admin_settings(global_settings)
  {
    ..self,
    execution_slots: Semaphore(global_settings.scheduler.runtime_concurrency),
    global_settings,
  }
}

///|
async fn[X] ApiService::with_audit_lock(
  self : ApiService,
  operation : async () -> X,
) -> X {
  self.audit_mutex.acquire()
  try operation() catch {
    error => {
      self.audit_mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.audit_mutex.release()
      value
    }
  }
}

///|
async fn ApiService::cached_result(
  self : ApiService,
  idempotency_key : String,
) -> @contracts.WorkloadResponse? {
  self.active_mutex.acquire()
  let result = self.response_cache.get(idempotency_key)
  self.active_mutex.release()
  result
}

///|
async fn ApiService::cache_result(
  self : ApiService,
  idempotency_key : String,
  response : @contracts.WorkloadResponse,
) -> Unit {
  self.active_mutex.acquire()
  if !self.response_cache.contains(idempotency_key) {
    self.response_cache_order.push(idempotency_key)
  }
  self.response_cache[idempotency_key] = response
  while self.response_cache_order.length() >
        self.global_settings.request_budgets.response_cache_entries {
    let oldest = self.response_cache_order.remove(0)
    ignore(self.response_cache.remove(oldest))
  }
  self.active_mutex.release()
}

///|
priv struct PromotionRequest {
  alias_name : String
  model_id : String
  version : String
  stage : @registry.RolloutStage
  actor : String
} derive(FromJson)

///|
priv struct RollbackRequest {
  alias_name : String
  actor : String
} derive(FromJson)

///|
priv struct ApprovalRequest {
  model_id : String
  version : String
} derive(FromJson)

///|
priv struct TokenIssueRequest {
  token_id : String
  secret : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
priv struct EnrollmentRequest {
  node_id : String
  token_id : String
  secret : String
  node_auth_secret : String
  public_key_ref : String
} derive(FromJson)

///|
priv struct RotationRequest {
  node_id : String
  public_key_ref : String
  current_serial : Int64
} derive(FromJson)

///|
fn valid_public_key_ref(value : String) -> Bool {
  value != "" &&
  value.length() <= 512 &&
  !value.contains_char('\r') &&
  !value.contains_char('\n')
}

///|
priv struct CapacityRequest {
  instance_memory_mib : Int
} derive(FromJson)

///|
priv struct VerificationRequest {
  kind : String
  subject : String
  signature_path : String?
  digest : String
  provenance_verified : Bool
} derive(FromJson)

///|
fn json_reply(status : Int, value : Json) -> HttpReply {
  { status, body: value.stringify(), content_type: "application/json" }
}

///|
fn api_error(
  status : Int,
  code : String,
  message : String,
  retryable : Bool,
) -> HttpReply {
  json_reply(status, {
    "error": { "code": code, "message": message, "retryable": retryable },
  })
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  let wanted = name.to_lower()
  for key, value in headers {
    if key.to_lower() == wanted {
      return Some(value)
    }
  }
  None
}

///|
fn bearer_authorized(headers : Map[String, String], expected : String) -> Bool {
  expected != "" &&
  header(headers, "Authorization") == Some("Bearer \{expected}")
}

///|
/// Resolves the authenticated operator identity from the bearer token through
/// the token → identity map, or returns `None` when the credential is absent
/// or unknown. Contract-document operator routes attribute every store
/// mutation and audit entry to the resolved identity.
async fn ApiService::account_session_authorization(
  self : ApiService,
  headers : Map[String, String],
  required_role : @account.AccountRole,
) -> @account.AccountAuthorization? {
  guard self.account_store is Some(accounts) &&
    bearer_secret(headers) is Some(secret) &&
    secret.has_prefix("lnxs_") else {
    return None
  }
  Some(accounts.authorize(secret, @async.now(), required_role~)) catch {
    _ => None
  }
}

///|
async fn ApiService::operator_identity(
  self : ApiService,
  headers : Map[String, String],
) -> String? {
  guard header(headers, "Authorization") is Some(value) &&
    value.has_prefix("Bearer ") else {
    return self
      .account_session_authorization(headers, PlatformOperator)
      .map(value => value.account.subject_ref)
  }
  match self.operator_tokens.get(value["Bearer ".length():].to_owned()) {
    Some(identity) => Some(identity)
    None =>
      self
      .account_session_authorization(headers, PlatformOperator)
      .map(value => value.account.subject_ref)
  }
}

///|
/// All operator authorities use the same token-to-identity map. The default
/// constructor seeds the legacy token as `operator`, so existing deployments
/// remain compatible while multi-operator deployments gain one boundary.
async fn ApiService::operator_authorized(
  self : ApiService,
  headers : Map[String, String],
) -> Bool {
  self.operator_identity(headers) is Some(_)
}

///|
async fn ApiService::audit_authorized(
  self : ApiService,
  headers : Map[String, String],
) -> Bool {
  bearer_authorized(headers, self.audit_token) ||
  self.account_session_authorization(headers, AuditReader) is Some(_)
}

///|
async fn ApiService::enterprise_session_subject(
  self : ApiService,
  headers : Map[String, String],
) -> String? {
  self
  .account_session_authorization(headers, EnterpriseUser)
  .map(value => value.account.subject_ref)
}

///|
fn shared_node_authorized(
  headers : Map[String, String],
  expected_token : String,
  node_id : String,
) -> Bool {
  expected_token != "" &&
  header(headers, "Authorization") == Some("Node \{expected_token}") &&
  header(headers, "X-LunaNexa-Node-Id") == Some(node_id)
}

///|
fn node_credential(headers : Map[String, String]) -> String? {
  guard header(headers, "Authorization") is Some(value) &&
    value.has_prefix("Node ") else {
    return None
  }
  Some(value["Node ".length():].to_owned())
}

///|
async fn ApiService::node_authorized(
  self : ApiService,
  headers : Map[String, String],
  node_id : String,
) -> Bool {
  guard header(headers, "X-LunaNexa-Node-Id") == Some(node_id) &&
    node_credential(headers) is Some(credential) &&
    credential != "" else {
    return false
  }
  match self.enrollment {
    Some(enrollment) => enrollment.authorized(node_id, credential, @async.now())
    None => shared_node_authorized(headers, self.node_token, node_id)
  }
}

///|
fn digest_hex(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn idempotency_scope(request : @contracts.WorkloadEnvelope) -> String {
  digest_hex(
    "lunanexa.idempotency.v1|\{request.tenant_ref}|\{request.credential_scope}|\{request.idempotency_key}",
  )
}

///|
fn ephemeral_only(request : @contracts.WorkloadEnvelope) -> Bool {
  request.data_policy.retention is Ephemeral &&
  !request.data_policy.allow_cache &&
  !request.data_policy.allow_training_reuse
}

///|
async fn ApiService::next_audit(
  self : ApiService,
  actor : String,
  action : String,
  target : String,
  prior_state : String,
  next_state : String,
  result : String,
  receipt : String,
  now_unix_ms : Int64,
) -> @contracts.AuditEvent {
  let events = self.store.audit_events()
  let sequence = events.length() + 1
  let previous_hash = events
    .last()
    .map(event => event.event_hash)
    .unwrap_or("genesis")
  let material = "\{previous_hash}|\{sequence}|\{now_unix_ms}|\{actor}|\{action}|\{target}|\{prior_state}|\{next_state}|\{result}|\{receipt}"
  let event : @contracts.AuditEvent = {
    sequence: sequence.to_int64(),
    event_id: "audit:\{sequence}:\{digest_hex(material)}",
    timestamp_unix_ms: now_unix_ms,
    actor,
    policy_version: "policy-v1",
    action,
    target,
    prior_state,
    next_state,
    result,
    correlation_receipt: receipt,
    previous_hash,
    event_hash: "",
  }
  { ..event, event_hash: @store.audit_event_hash(event) }
}

///|
fn decode_assignment(body : String) -> @contracts.DesiredAssignment? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_heartbeat(body : String) -> @contracts.NodeHeartbeat? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_node_directive(body : String) -> @contracts.NodeDirective? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_workload(body : String) -> @contracts.WorkloadEnvelope? {
  try @contracts.decode_workload(body) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn label_values(labels : Map[String, String], name : String) -> Array[String] {
  match labels.get(name) {
    None => []
    Some(value) =>
      value.split(",").map(part => part.trim().to_owned()).collect()
  }
}

///|
fn numeric_label(
  labels : Map[String, String],
  name : String,
  fallback : Int,
) -> Int {
  guard labels.get(name) is Some(value) else { return fallback }
  @string.parse_int64(value).to_int() catch {
    _ => fallback
  }
}

///|
fn data_classes(labels : Map[String, String]) -> Array[@contracts.DataClass] {
  let classes : Array[@contracts.DataClass] = []
  for value in label_values(labels, "lunanexa.data-classes") {
    match value {
      "Public" => classes.push(Public)
      "Internal" => classes.push(Internal)
      "Confidential" => classes.push(Confidential)
      "Restricted" => classes.push(Restricted)
      _ => ()
    }
  }
  classes
}

///|
fn scheduler_node(
  heartbeat : @contracts.NodeHeartbeat,
  now_unix_ms : Int64,
  heartbeat_timeout_ms : Int64,
  ready_models? : Array[String]? = None,
) -> @scheduler.NodeSnapshot {
  let accelerators : Array[@contracts.AcceleratorInventory] = []
  for accelerator in heartbeat.inventory.accelerators {
    if accelerator.healthy {
      accelerators.push(accelerator)
    }
  }
  let mut memory_free_mib = 0
  for accelerator in accelerators {
    memory_free_mib += accelerator.memory_free_mib
  }
  let licensed_models = label_values(
    heartbeat.inventory.labels,
    "lunanexa.models",
  )
  {
    node_id: heartbeat.node_id,
    state: if now_unix_ms - heartbeat.timestamp_unix_ms > heartbeat_timeout_ms {
      Unreachable
    } else {
      heartbeat.state
    },
    architecture: accelerators
    .get(0)
    .map(value => value.architecture)
    .unwrap_or(""),
    memory_free_mib,
    runtimes: heartbeat.inventory.runtime_names,
    licensed_models,
    ready_models: ready_models.unwrap_or(licensed_models),
    allowed_data_classes: data_classes(heartbeat.inventory.labels),
    warm_models: label_values(
      heartbeat.inventory.labels,
      "lunanexa.warm-models",
    ),
    queue_depth: numeric_label(
      heartbeat.inventory.labels,
      "lunanexa.queue-depth",
      0,
    ),
    reliability_per_mille: numeric_label(
      heartbeat.inventory.labels,
      "lunanexa.reliability-per-mille",
      1000,
    ),
    accelerator_utilization_per_mille: numeric_label(
      heartbeat.inventory.labels,
      "lunanexa.accelerator-utilization-per-mille",
      0,
    ),
  }
}

///|
async fn ApiService::managed_scheduler_node(
  self : ApiService,
  heartbeat : @contracts.NodeHeartbeat,
  now_unix_ms : Int64,
  ready_models? : Array[String]? = None,
) -> @scheduler.NodeSnapshot {
  let snapshot = scheduler_node(
    heartbeat,
    now_unix_ms,
    self.global_settings.control_timing.heartbeat_timeout_ms,
    ready_models~,
  )
  match self.exclusive_lease_store {
    Some(leases) if leases.node_blocks_managed_placement(heartbeat.node_id) =>
      { ..snapshot, state: Cordoned }
    _ => snapshot
  }
}

///|
fn score_policy(
  settings : @settings.SchedulerPolicySettings,
) -> @scheduler.ScorePolicy {
  {
    version: "placement-v1",
    warm_model_weight: settings.warm_model_weight,
    headroom_weight: settings.headroom_weight,
    queue_weight: settings.queue_weight,
    reliability_weight: settings.reliability_weight,
    utilization_weight: settings.utilization_weight,
    validated_topology_profiles: [],
  }
}

///|
/// A request's maximum runtime is a safety ceiling, not an execution-time
/// prediction. Until a scheduling target carries a measured estimate, using
/// that ceiling as the estimate makes every generated OpenAI deadline
/// impossible after even one millisecond of admission work.
fn placement_runtime_estimate_ms(
  maximum_runtime_ms : Int64,
  measured_estimate_ms : Int64?,
) -> Int64 {
  match measured_estimate_ms {
    Some(value) => value.max(0L).min(maximum_runtime_ms)
    None => 0L
  }
}

///|
async fn ApiService::schedule_and_admit(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
) -> (HttpReply?, Array[String]) {
  let now = @async.now()
  let budgets = self.global_settings.request_budgets
  if request.deadline_unix_ms > now + budgets.openai_max_deadline_ms ||
    request.resource_ceiling.max_runtime_ms > budgets.openai_max_deadline_ms ||
    request.resource_ceiling.max_input_units > budgets.openai_max_input_units ||
    request.resource_ceiling.max_output_units > budgets.openai_max_output_units ||
    request.resource_ceiling.max_accelerator_memory_mib >
    budgets.openai_max_accelerator_memory_mib {
    return (
      Some(
        api_error(
          400, "RequestBudgetExceeded", "request exceeds the active administrator policy",
          false,
        ),
      ),
      [],
    )
  }
  guard self.scheduler is Some(scheduler) else { return (None, []) }
  guard self.registry is Some(registry) else {
    return (
      Some(
        api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        ),
      ),
      [],
    )
  }
  guard registry.scheduling_target(request.model_selector, request.capability)
    is Some(target) else {
    return (
      Some(
        api_error(
          409, "NoPlacement", "model selector has no approved schedulable target",
          false,
        ),
      ),
      [],
    )
  }
  if target.model.artifact.digest != self.runtime.artifact_digest() ||
    target.runtime.version != self.runtime.runtime_version() ||
    target.runtime.image_digest != self.runtime.image_digest() {
    return (
      Some(
        api_error(
          409, "NoPlacement", "approved target does not match the configured serving adapter",
          false,
        ),
      ),
      [],
    )
  }
  guard target.model.compatible_architectures.get(0) is Some(architecture) else {
    return (
      Some(
        api_error(
          409, "NoPlacement", "approved model has no compatible architecture", false,
        ),
      ),
      [],
    )
  }
  if target.model.minimum_memory_mib >
    request.resource_ceiling.max_accelerator_memory_mib {
    return (
      Some(
        api_error(
          409, "NoPlacement", "approved model exceeds the request accelerator-memory ceiling",
          false,
        ),
      ),
      [],
    )
  }
  let assignments = self.store.assignments()
  let nodes = [
    for heartbeat in self.store.heartbeats() => {
      let ready_models = if self.runtime.uses_direct_node_routing() {
        if assignments.any(assignment => {
            assignment.node_id == heartbeat.node_id &&
            assignment.artifact.digest == target.model.artifact.digest &&
            assignment.runtime.name == target.runtime.name &&
            assignment.runtime.version == target.runtime.version &&
            assignment.runtime.image_digest == target.runtime.image_digest &&
            assignment.lease_expires_unix_ms > now &&
            heartbeat.running_deployments.any(deployment_id => {
              deployment_id == assignment.deployment_id
            })
          }) {
          [target.model_key]
        } else {
          []
        }
      } else {
        label_values(heartbeat.inventory.labels, "lunanexa.models")
      }
      self.managed_scheduler_node(
        heartbeat,
        now,
        ready_models=Some(ready_models),
      )
    }
  ]
  let decision = scheduler.place(
    nodes,
    {
      workload_id: request.workload_id,
      model_key: target.model_key,
      architecture,
      // The request value is an upper safety ceiling, not memory demand. Once
      // the model is proven to fit below it, placement needs only the model's
      // approved minimum resident memory.
      memory_mib: target.model.minimum_memory_mib,
      runtime: target.runtime.name,
      data_class: request.data_policy.classification,
      deadline_unix_ms: request.deadline_unix_ms,
      now_unix_ms: now,
      estimated_runtime_ms: placement_runtime_estimate_ms(
        request.resource_ceiling.max_runtime_ms,
        None,
      ),
      multi_node: false,
      topology_profile: None,
    },
    score_policy(self.global_settings.scheduler),
  )
  guard decision.selected_node_id is Some(_) else {
    return (
      Some(
        json_reply(409, {
          "error": {
            "code": "NoPlacement",
            "message": "no node satisfies the workload requirements",
            "retryable": true,
          },
          "placement": decision,
        }),
      ),
      [],
    )
  }
  match scheduler.admit(request, now) {
    Rejected(reason~) =>
      (
        Some(
          json_reply(if reason == WorkloadAlreadyActive { 409 } else { 429 }, {
            "error": {
              "code": "\{Repr(reason)}",
              "message": "workload admission was rejected",
              "retryable": reason == WorkloadAlreadyActive ||
              reason == QuotaExceeded ||
              reason == AdmissionCapacityExceeded,
            },
            "placement": decision,
          }),
        ),
        [],
      )
    Accepted(_) =>
      (None, [ for candidate in decision.candidates => candidate.node_id ])
  }
}

///|
async fn ApiService::complete_admission(
  self : ApiService,
  workload_id : String,
  accelerator_ms : Int64,
) -> Unit {
  if self.scheduler is Some(scheduler) {
    scheduler.complete(workload_id, accelerator_ms)
  }
}

///|
fn retryable_runtime_error(error : Error) -> Bool {
  match error {
    @runtimes.RemoteRuntimeError::UpstreamRejected(status~, body=_) =>
      status >= 500
    @runtimes.RemoteRuntimeError::UpstreamFailed(code=_, retryable~) =>
      retryable
    @runtimes.RemoteRuntimeError::UnsupportedCapability
    | @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(_)
    | @runtimes.RemoteRuntimeError::InsecureEndpoint(_)
    | @runtimes.RemoteRuntimeError::InvalidNodeRouting(_) => false
    _ => true
  }
}

///|
async fn ApiService::invoke_with_bounded_retry(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  routing_nodes : Array[String],
) -> @runtimes.RuntimeInvocationResult {
  let primary = routing_nodes.get(0).unwrap_or("")
  let alternate = routing_nodes.get(1).unwrap_or(primary)
  self.runtime.invoke_at(request, primary) catch {
    error => {
      if @async.is_cancellation_error(error) ||
        !retryable_runtime_error(error) ||
        !@scheduler.retry_allowed(
          request.idempotency_key,
          1,
          self.global_settings.scheduler.retry_attempts,
          true,
        ) {
        raise error
      }
      self.runtime.invoke_at(request, alternate)
    }
  }
}

///|
async fn ApiService::invoke_stream_with_bounded_retry(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  routing_nodes : Array[String],
  on_chunk : async (Json) -> Unit,
) -> @runtimes.RuntimeInvocationResult {
  let primary = routing_nodes.get(0).unwrap_or("")
  let alternate = routing_nodes.get(1).unwrap_or(primary)
  let mut emitted = false
  self.runtime.invoke_stream_at(request, primary, output => {
    emitted = true
    on_chunk(output)
  }) catch {
    error => {
      if @async.is_cancellation_error(error) ||
        !retryable_runtime_error(error) ||
        !@scheduler.retry_allowed(
          request.idempotency_key,
          1,
          self.global_settings.scheduler.retry_attempts,
          !emitted,
        ) {
        raise error
      }
      self.runtime.invoke_stream_at(request, alternate, output => {
        emitted = true
        on_chunk(output)
      })
    }
  }
}

///|
fn decode_model(body : String) -> @contracts.ModelRecord? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_runtime_spec(body : String) -> @contracts.RuntimeSpec? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn valid_assignment_shape(
  assignment : @contracts.DesiredAssignment,
  now : Int64,
) -> Bool {
  @contracts.valid_identifier(assignment.assignment_id, maximum_length=96) &&
  @contracts.valid_identifier(assignment.deployment_id, maximum_length=96) &&
  @contracts.valid_identifier(assignment.node_id, maximum_length=128) &&
  assignment.generation > 0L &&
  assignment.controller_epoch > 0L &&
  assignment.lease_expires_unix_ms > now &&
  @contracts.valid_sha256_digest(assignment.artifact.digest) &&
  assignment.artifact.signature_ref != "" &&
  @contracts.valid_sha256_digest(assignment.runtime.image_digest) &&
  assignment.resources.accelerator_count > 0 &&
  assignment.resources.accelerator_memory_mib > 0 &&
  assignment.resources.cpu_millis > 0 &&
  assignment.resources.memory_mib > 0 &&
  assignment.network.allowed_egress.length() == 0 &&
  (
    !assignment.data_policy.allow_training_reuse ||
    assignment.data_policy.retention is EvaluationCapture(_)
  )
}

///|
fn decode_license(body : String) -> @registry.LicenseRecord? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_verification_request(body : String) -> VerificationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_evaluation(body : String) -> @registry.EvaluationRecord? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_promotion(body : String) -> PromotionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_rollback(body : String) -> RollbackRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_approval(body : String) -> ApprovalRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_token_issue(body : String) -> TokenIssueRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_enrollment(body : String) -> EnrollmentRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_rotation(body : String) -> RotationRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_quota(body : String) -> @scheduler.TenantQuota? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_capacity(body : String) -> CapacityRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_telemetry(body : String) -> @contracts.TelemetrySample? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_benchmark(body : String) -> @telemetry.BenchmarkRun? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
async fn ApiService::operator_audit(
  self : ApiService,
  action : String,
  target : String,
  receipt : String,
) -> Unit {
  self.operator_audit_as("operator", action, target, receipt)
}

///|
/// Records an operator audit event under an explicit operator identity so
/// multi-operator consoles keep per-operator attribution.
async fn ApiService::operator_audit_as(
  self : ApiService,
  operator : String,
  action : String,
  target : String,
  receipt : String,
) -> Unit {
  self.with_audit_lock(() => {
    let event = self.next_audit(
      operator,
      action,
      target,
      "previous",
      "updated",
      "accepted",
      receipt,
      @async.now(),
    )
    self.store.append_audit(event)
  })
}

///|
async fn ApiService::operator_transition_audit(
  self : ApiService,
  action : String,
  target : String,
  prior_state : String,
  next_state : String,
  receipt : String,
) -> Unit {
  self.with_audit_lock(() => {
    let event = self.next_audit(
      "operator",
      action,
      target,
      prior_state,
      next_state,
      "accepted",
      receipt,
      @async.now(),
    )
    self.store.append_audit(event)
  })
}

///|
async fn ApiService::stop_assignment(
  self : ApiService,
  assignment_id : String,
) -> HttpReply {
  if assignment_id == "" || self.store.assignment(assignment_id) is None {
    return api_error(404, "NotFound", "desired assignment was not found", false)
  }
  let receipt = "assignment-stop:\{assignment_id}:\{@async.now()}"
  let removed = self.with_audit_lock(() => {
    let audit = self.next_audit(
      "operator",
      "assignment.stop",
      assignment_id,
      "desired",
      "stopped",
      "accepted",
      receipt,
      @async.now(),
    )
    self.store.commit_assignment_removal(assignment_id, audit)
  })
  if !removed {
    return api_error(409, "Conflict", "assignment changed before removal", true)
  }
  json_reply(202, { "accepted": true, "receipt": receipt })
}

///|
async fn ApiService::invoke_workload(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
) -> HttpReply {
  let idempotency_key = idempotency_scope(request)
  match self.cached_result(idempotency_key) {
    Some(response) => return json_reply(200, response.to_json())
    None => ()
  }
  match self.store.idempotent_result(idempotency_key) {
    Some(response) => return json_reply(200, response.to_json())
    None => ()
  }
  let (admission_error, routing_nodes) = self.schedule_and_admit(request)
  if admission_error is Some(reply) {
    return reply
  }
  let accepted = @async.now()
  let mut started = 0L
  let runtime_result = try
    @async.with_task_group(group => {
      self.active_mutex.acquire()
      if self.active.contains(request.workload_id) {
        self.active_mutex.release()
        raise Failure::Failure("duplicate active workload")
      }
      let task = group.spawn(() => {
        let queue_deadline = (request.deadline_unix_ms - accepted)
          .clamp(min=1L, max=86400000L)
          .to_int()
        @async.with_timeout(queue_deadline, () => {
          self.execution_slots.acquire()
          defer self.execution_slots.release()
          started = @async.now()
          if self.scheduler is Some(scheduler) {
            scheduler.mark_started(request.workload_id, started)
          }
          @async.with_timeout(
            request.resource_ceiling.max_runtime_ms.to_int(),
            () => self.invoke_with_bounded_retry(request, routing_nodes),
          )
        })
      })
      self.active[request.workload_id] = task
      self.active_mutex.release()
      try task.wait() catch {
        error => {
          self.active_mutex.acquire()
          ignore(self.active.remove(request.workload_id))
          self.active_mutex.release()
          raise error
        }
      } noraise {
        value => {
          self.active_mutex.acquire()
          ignore(self.active.remove(request.workload_id))
          self.active_mutex.release()
          value
        }
      }
    })
  catch {
    error => {
      let completed = @async.now()
      let effective_started = if started == 0L { completed } else { started }
      let timed_out = error is @async.TimeoutError
      let cancelled = !timed_out && @async.is_cancellation_error(error)
      let retryable = !timed_out && !cancelled && retryable_runtime_error(error)
      let receipt = if cancelled {
        "cancel:\{request.workload_id}:\{digest_hex(request.workload_id)}"
      } else if timed_out {
        "deadline:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
      } else {
        "failed:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
      }
      let response : @contracts.WorkloadResponse = {
        version: @contracts.contract_version,
        workload_id: request.workload_id,
        state: if cancelled {
          Cancelled
        } else {
          Failed
        },
        output: None,
        error: Some({
          code: if cancelled {
            CancelledByCaller
          } else if timed_out {
            DeadlineExceeded
          } else {
            RuntimeUnavailable
          },
          message: if cancelled {
            "workload cancelled by caller"
          } else if timed_out {
            "workload deadline or runtime ceiling was exceeded"
          } else {
            "the selected runtime could not complete the request"
          },
          retryable,
          correlation_receipt: receipt,
        }),
        usage: {
          input_units: 0,
          output_units: 0,
          accelerator_ms: completed - effective_started,
          queue_ms: effective_started - accepted,
        },
        artifact_digest: self.runtime.artifact_digest(),
        runtime_version: self.runtime.runtime_version(),
        timing: {
          accepted_unix_ms: accepted,
          started_unix_ms: effective_started,
          first_output_unix_ms: 0L,
          completed_unix_ms: completed,
        },
        retryable,
        audit_receipt: receipt,
      }
      self.cache_result(idempotency_key, response)
      self.with_audit_lock(() => {
        let audit = self.next_audit(
          "credential-scope:\{request.credential_scope}",
          if cancelled {
            "workload.cancel"
          } else if timed_out {
            "workload.deadline"
          } else {
            "workload.fail"
          },
          request.model_selector,
          if started == 0L {
            "queued"
          } else {
            "running"
          },
          if cancelled {
            "cancelled"
          } else {
            "failed"
          },
          "accepted",
          receipt,
          completed,
        )
        self.store.commit_workload(
          idempotency_key,
          { ..response, output: None },
          audit,
        )
      })
      self.complete_admission(
        request.workload_id,
        completed - effective_started,
      )
      return json_reply(200, response.to_json())
    }
  } noraise {
    value => value
  }
  let completed = @async.now()
  let effective_started = if started == 0L { accepted } else { started }
  let receipt = "workload:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
  let response : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: request.workload_id,
    state: Succeeded,
    output: Some(runtime_result.output),
    error: None,
    usage: {
      input_units: runtime_result.input_units,
      output_units: runtime_result.output_units,
      accelerator_ms: completed - effective_started,
      queue_ms: effective_started - accepted,
    },
    artifact_digest: runtime_result.artifact_digest,
    runtime_version: runtime_result.runtime_version,
    timing: {
      accepted_unix_ms: accepted,
      started_unix_ms: effective_started,
      first_output_unix_ms: completed,
      completed_unix_ms: completed,
    },
    retryable: false,
    audit_receipt: receipt,
  }
  self.cache_result(idempotency_key, response)
  self.with_audit_lock(() => {
    let audit = self.next_audit(
      "credential-scope:\{request.credential_scope}",
      "workload.invoke",
      request.model_selector,
      "admitted",
      "succeeded",
      "accepted",
      receipt,
      completed,
    )
    self.store.commit_workload(
      idempotency_key,
      { ..response, output: None },
      audit,
    )
  })
  self.complete_admission(request.workload_id, completed - effective_started)
  json_reply(200, response.to_json())
}

///|
async fn send_stream_event(
  connection : @http.ServerConnection,
  event : @contracts.WorkloadStreamEvent,
) -> Unit {
  connection.write_string("data: \{event.to_json().stringify()}\n\n")
  connection.flush()
}

///|
priv struct OpenAiStreamContext {
  id : String
  model : String
  created_unix_seconds : Int64
  tool_call_seen : Array[Bool]
}

///|
fn compatible_stream_delta(output : Json) -> Json {
  match output {
    Object(fields) =>
      match fields.get("text_delta") {
        Some(String(value)) => Json::object({ "content": Json::string(value) })
        _ =>
          match fields.get("tool_call_delta") {
            Some(value) => Json::object({ "tool_calls": Json::array([value]) })
            None =>
              Json::object({ "content": Json::string(output.stringify()) })
          }
      }
    String(value) => Json::object({ "content": Json::string(value) })
    value => Json::object({ "content": Json::string(value.stringify()) })
  }
}

///|
fn compatible_stream_chunks(output : Json?) -> Array[Json] {
  guard output is Some(Object(fields)) &&
    fields.get("chunks") is Some(Array(chunks)) else {
    return []
  }
  chunks
}

///|
fn compatible_stream_has_tool_calls(output : Json?) -> Bool {
  compatible_stream_chunks(output).any(chunk => {
    chunk is Object(fields) && fields.get("tool_call_delta") is Some(_)
  })
}

///|
async fn send_compatible_stream_event(
  connection : @http.ServerConnection,
  event : @contracts.WorkloadStreamEvent,
  openai : OpenAiStreamContext?,
) -> Unit {
  guard openai is Some(context) else {
    send_stream_event(connection, event)
    return
  }
  match event.kind {
    Chunk => {
      if event.output is Some(Object(fields)) &&
        fields.get("tool_call_delta") is Some(_) {
        context.tool_call_seen[0] = true
      }
      let delta = event.output
        .map(compatible_stream_delta)
        .unwrap_or(Json::object({}))
      let payload : Json = {
        "id": context.id,
        "object": "chat.completion.chunk",
        "created": context.created_unix_seconds.to_json(),
        "model": context.model,
        "choices": [
          {
            "index": 0,
            "delta": delta,
            "finish_reason": (None : String?).to_json(),
          },
        ],
      }
      connection.write_string("data: \{payload.stringify()}\n\n")
    }
    Completed => {
      let completed_output = match event.response {
        Some(response) => response.output
        None => None
      }
      if event.sequence == 1 {
        for chunk in compatible_stream_chunks(completed_output) {
          let replay_payload : Json = {
            "id": context.id,
            "object": "chat.completion.chunk",
            "created": context.created_unix_seconds.to_json(),
            "model": context.model,
            "choices": [
              {
                "index": 0,
                "delta": compatible_stream_delta(chunk),
                "finish_reason": (None : String?).to_json(),
              },
            ],
          }
          connection.write_string("data: \{replay_payload.stringify()}\n\n")
        }
      }
      let receipt = event.response
        .map(response => response.audit_receipt)
        .unwrap_or("")
      let completed_payload : Json = {
        "id": context.id,
        "object": "chat.completion.chunk",
        "created": context.created_unix_seconds.to_json(),
        "model": context.model,
        "choices": [
          {
            "index": 0,
            "delta": ({} : Json),
            "finish_reason": if context.tool_call_seen[0] ||
              compatible_stream_has_tool_calls(completed_output) {
              "tool_calls"
            } else {
              "stop"
            },
          },
        ],
        "lunanexa_receipt": receipt,
      }
      connection.write_string("data: \{completed_payload.stringify()}\n\n")
      connection.write_string("data: [DONE]\n\n")
    }
    Failed | Cancelled => {
      let error : Json = match event.response {
        Some(response) =>
          match response.error {
            Some(value) => value.to_json()
            None =>
              {
                "code": "RuntimeUnavailable",
                "message": "stream failed",
                "retryable": false,
              }
          }
        None =>
          {
            "code": "RuntimeUnavailable",
            "message": "stream failed",
            "retryable": false,
          }
      }
      let error_payload : Json = { "error": error }
      connection.write_string("data: \{error_payload.stringify()}\n\n")
      connection.write_string("data: [DONE]\n\n")
    }
  }
  connection.flush()
}

///|
async fn ApiService::stream_workload(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  connection : @http.ServerConnection,
  openai? : OpenAiStreamContext? = None,
) -> Unit {
  let idempotency_key = idempotency_scope(request)
  let replay = match self.cached_result(idempotency_key) {
    Some(response) => Some(response)
    None => self.store.idempotent_result(idempotency_key)
  }
  if replay is Some(response) {
    connection.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-store",
      "X-Accel-Buffering": "no",
    })
    send_compatible_stream_event(
      connection,
      {
        workload_id: request.workload_id,
        sequence: 1,
        kind: Completed,
        output: None,
        response: Some(response),
      },
      openai,
    )
    connection.end_response()
    return
  }
  let (admission_error, routing_nodes) = self.schedule_and_admit(request)
  if admission_error is Some(reply) {
    connection.send_response(reply.status, reason(reply.status), extra_headers={
      "Content-Type": reply.content_type,
      "Cache-Control": "no-store",
    })
    connection.write_string(reply.body)
    connection.end_response()
    return
  }
  connection.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-store",
    "X-Accel-Buffering": "no",
  })
  let accepted = @async.now()
  let mut started = 0L
  let mut sequence = 0
  let mut first_output = 0L
  let runtime_result = try
    @async.with_task_group(group => {
      self.active_mutex.acquire()
      if self.active.contains(request.workload_id) {
        self.active_mutex.release()
        raise Failure::Failure("duplicate active workload")
      }
      let task = group.spawn(() => {
        let queue_deadline = (request.deadline_unix_ms - accepted)
          .clamp(min=1L, max=86400000L)
          .to_int()
        @async.with_timeout(queue_deadline, () => {
          self.execution_slots.acquire()
          defer self.execution_slots.release()
          started = @async.now()
          if self.scheduler is Some(scheduler) {
            scheduler.mark_started(request.workload_id, started)
          }
          @async.with_timeout(
            request.resource_ceiling.max_runtime_ms.to_int(),
            () => {
              self.invoke_stream_with_bounded_retry(request, routing_nodes, output => {
                sequence += 1
                if first_output == 0L {
                  first_output = @async.now()
                }
                send_compatible_stream_event(
                  connection,
                  {
                    workload_id: request.workload_id,
                    sequence,
                    kind: Chunk,
                    output: Some(output),
                    response: None,
                  },
                  openai,
                )
              })
            },
          )
        })
      })
      self.active[request.workload_id] = task
      self.active_mutex.release()
      try task.wait() catch {
        error => {
          self.active_mutex.acquire()
          ignore(self.active.remove(request.workload_id))
          self.active_mutex.release()
          raise error
        }
      } noraise {
        value => {
          self.active_mutex.acquire()
          ignore(self.active.remove(request.workload_id))
          self.active_mutex.release()
          value
        }
      }
    })
  catch {
    error => {
      let completed = @async.now()
      let effective_started = if started == 0L { completed } else { started }
      let timed_out = error is @async.TimeoutError
      let cancelled = !timed_out && @async.is_cancellation_error(error)
      let retryable = !timed_out && !cancelled && retryable_runtime_error(error)
      let receipt = if cancelled {
        "cancel:\{request.workload_id}:\{digest_hex(request.workload_id)}"
      } else if timed_out {
        "deadline:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
      } else {
        "failed:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
      }
      let response : @contracts.WorkloadResponse = {
        version: @contracts.contract_version,
        workload_id: request.workload_id,
        state: if cancelled {
          Cancelled
        } else {
          Failed
        },
        output: None,
        error: Some({
          code: if cancelled {
            CancelledByCaller
          } else if timed_out {
            DeadlineExceeded
          } else {
            RuntimeUnavailable
          },
          message: if cancelled {
            "workload cancelled by caller"
          } else if timed_out {
            "workload deadline or runtime ceiling was exceeded"
          } else {
            "the selected runtime could not complete the stream"
          },
          retryable,
          correlation_receipt: receipt,
        }),
        usage: {
          input_units: 0,
          output_units: 0,
          accelerator_ms: completed - effective_started,
          queue_ms: effective_started - accepted,
        },
        artifact_digest: self.runtime.artifact_digest(),
        runtime_version: self.runtime.runtime_version(),
        timing: {
          accepted_unix_ms: accepted,
          started_unix_ms: effective_started,
          first_output_unix_ms: first_output,
          completed_unix_ms: completed,
        },
        retryable,
        audit_receipt: receipt,
      }
      self.cache_result(idempotency_key, response)
      self.with_audit_lock(() => {
        let audit = self.next_audit(
          "credential-scope:\{request.credential_scope}",
          if cancelled {
            "workload.cancel"
          } else if timed_out {
            "workload.deadline"
          } else {
            "workload.fail"
          },
          request.model_selector,
          if started == 0L {
            "queued"
          } else {
            "streaming"
          },
          if cancelled {
            "cancelled"
          } else {
            "failed"
          },
          "accepted",
          receipt,
          completed,
        )
        self.store.commit_workload(idempotency_key, response, audit)
      })
      self.complete_admission(
        request.workload_id,
        completed - effective_started,
      )
      sequence += 1
      send_compatible_stream_event(
        connection,
        {
          workload_id: request.workload_id,
          sequence,
          kind: if cancelled {
            Cancelled
          } else {
            Failed
          },
          output: None,
          response: Some(response),
        },
        openai,
      ) catch {
        _ => ()
      }
      connection.end_response() catch {
        _ => ()
      }
      return
    }
  } noraise {
    value => value
  }
  let completed = @async.now()
  let effective_started = if started == 0L { accepted } else { started }
  let receipt = "workload:\{request.workload_id}:\{digest_hex(request.idempotency_key)}"
  let response : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: request.workload_id,
    state: Succeeded,
    output: Some(runtime_result.output),
    error: None,
    usage: {
      input_units: runtime_result.input_units,
      output_units: runtime_result.output_units,
      accelerator_ms: completed - effective_started,
      queue_ms: effective_started - accepted,
    },
    artifact_digest: runtime_result.artifact_digest,
    runtime_version: runtime_result.runtime_version,
    timing: {
      accepted_unix_ms: accepted,
      started_unix_ms: effective_started,
      first_output_unix_ms: first_output,
      completed_unix_ms: completed,
    },
    retryable: false,
    audit_receipt: receipt,
  }
  self.cache_result(idempotency_key, response)
  self.with_audit_lock(() => {
    let audit = self.next_audit(
      "credential-scope:\{request.credential_scope}",
      "workload.invoke.stream",
      request.model_selector,
      "streaming",
      "succeeded",
      "accepted",
      receipt,
      completed,
    )
    self.store.commit_workload(
      idempotency_key,
      { ..response, output: None },
      audit,
    )
  })
  self.complete_admission(request.workload_id, completed - effective_started)
  sequence += 1
  send_compatible_stream_event(
    connection,
    {
      workload_id: request.workload_id,
      sequence,
      kind: Completed,
      output: None,
      response: Some({ ..response, output: None }),
    },
    openai,
  )
  connection.end_response()
}

///|
async fn ApiService::dispatch_with_transport(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  if body.length() >
    self.global_settings.request_budgets.maximum_request_body_bytes {
    return api_error(
      413, "PayloadTooLarge", "request body exceeds the public contract limit", false,
    )
  }
  if path == "/v1/guide-diagnostics/aggregate" {
    return self.handle_guide_aggregate(verb, headers)
  }
  if verb != Get && !self.store.current_epoch_is_durable() {
    return api_error(
      409, "StaleControllerEpoch", "controller was fenced by a newer durable epoch",
      true,
    )
  }
  let reconciliation_write = verb != Get &&
    path != "/v1/nodes/heartbeat" &&
    path != "/v1/telemetry"
  if self.reconciliation_only && reconciliation_write {
    return api_error(
      503, "ReconciliationOnly", "controller mutations are disabled until recovery reconciliation is accepted",
      true,
    )
  }
  if deployment_management_path(path) {
    return self.handle_deployment_management(verb, path, headers, body)
  }
  if model_source_path(path) {
    return self.handle_model_source(verb, path, headers, body)
  }
  if account_path(path) {
    return self.handle_accounts(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if access_management_path(path) {
    return self.handle_access_management(verb, path, headers, body)
  }
  if openai_compatibility_path(path) {
    return self.handle_openai_compatibility(verb, path, headers, body)
  }
  if client_handoff_path(path) {
    return self.handle_client_handoff(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if enterprise_portal_path(path) {
    return self.handle_enterprise_portal(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if notification_path(path) {
    return self.handle_notifications(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if customer_machine_access_path(path) {
    if credential_handoff_path(path) {
      return self.handle_credential_handoff(
        verb, path, headers, body, allow_asserted_subject,
      )
    }
    return self.handle_customer_machine_access(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if credential_handoff_path(path) {
    return self.handle_credential_handoff(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if exclusive_lease_management_path(path) {
    return self.handle_exclusive_lease_management(verb, path, headers, body)
  }
  if offline_commerce_path(path) {
    return self.handle_offline_commerce(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if contract_document_path(path) {
    return self.handle_contract_documents(
      verb, path, headers, body, allow_asserted_subject,
    )
  }
  if contract_governance_path(path) {
    return self.handle_contract_governance(verb, path, headers, body)
  }
  if commercial_management_path(path) {
    return self.handle_commercial_management(verb, path, headers, body)
  }
  if provider_callback_path(path) {
    return self.handle_provider_callback(verb, path, headers, body)
  }
  if technical_management_path(path) {
    return self.handle_technical_management(verb, path, headers, body)
  }
  match (verb, path) {
    (Get, "/health") =>
      json_reply(200, @contracts.health("control", self.version).to_json())
    (Get, "/ready") => {
      let ready = self.internal_component_ready()
      json_reply(if ready { 200 } else { 503 }, { "ready": ready })
    }
    (Get, "/version") =>
      json_reply(200, {
        "product": "LunaNexa",
        "version": self.version,
        "contract": @contracts.contract_version,
        "mode": if self.reconciliation_only {
          "reconciliation-only"
        } else {
          "active"
        },
      })
    (Get, "/v1/readiness") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let readiness = self.management_readiness(@async.now())
      json_reply(if readiness.ready { 200 } else { 503 }, readiness.to_json())
    }
    (Get, "/v1/settings/effective") => {
      if !self.operator_authorized(headers) &&
        !bearer_authorized(headers, self.inference_token) &&
        self.api_key_authorization(headers, Inference, false) is None {
        return api_error(
          401, "Unauthenticated", "valid enterprise or operator authority is required",
          false,
        )
      }
      json_reply(
        200,
        @settings.public_settings_view(self.global_settings).to_json(),
      )
    }
    (Get, "/v1/settings/admin") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      json_reply(200, self.global_settings.to_json())
    }
    (Get, "/metrics") => {
      if !bearer_authorized(headers, self.monitoring_token) {
        return api_error(
          401, "Unauthenticated", "valid monitoring authority is required", false,
        )
      }
      let nodes = self.store.heartbeats()
      let assignments = self.store.assignments()
      let events = self.store.audit_events()
      let telemetry_samples = match self.telemetry {
        Some(telemetry) => telemetry.snapshot().samples.length()
        None => 0
      }
      let active_admissions = match self.scheduler {
        Some(scheduler) => scheduler.snapshot().active.length()
        None => 0
      }
      let (operational_counters_snapshot, operational_event_count) = match
        self.observability_store {
        Some(store) => store.metrics_snapshot()
        None => ([], 0)
      }
      let (
        pending_deliveries,
        dead_letter_deliveries,
        notification_worker_health,
      ) = match self.notification_store {
        Some(store) => store.delivery_metrics()
        None =>
          (
            0,
            0,
            {
              generation: 0L,
              last_heartbeat_unix_ms: None,
              last_attempt_unix_ms: None,
              last_success_unix_ms: None,
              last_failure_unix_ms: None,
              consecutive_failures: 0,
              last_error_code: None,
            },
          )
      }
      let notification_worker_heartbeat_age_seconds = notification_worker_health.last_heartbeat_unix_ms
        .map(value => (@async.now() - value).max(0L) / 1000L)
        .unwrap_or(1000000000L)
      let mut operational_counters = ""
      for counter in operational_counters_snapshot {
        operational_counters = operational_counters +
          "lunanexa_operational_events_total{event_code=\"\{counter.event_code}\",target_type=\"\{counter.target_type}\",outcome=\"\{counter.outcome}\",status_class=\"\{counter.status_class}\"} \{counter.value}\n"
      }
      let operational_latency = match self.observability_store {
        Some(store) => store.prometheus_latency_fragment()
        None => ""
      }
      {
        status: 200,
        content_type: "text/plain; version=0.0.4",
        body: "# TYPE lunanexa_nodes gauge\n" +
        "lunanexa_nodes \{nodes.length()}\n" +
        "# TYPE lunanexa_assignments gauge\n" +
        "lunanexa_assignments \{assignments.length()}\n" +
        "# TYPE lunanexa_audit_events counter\n" +
        "lunanexa_audit_events \{events.length()}\n" +
        "# TYPE lunanexa_active_admissions gauge\n" +
        "lunanexa_active_admissions \{active_admissions}\n" +
        "# TYPE lunanexa_telemetry_samples gauge\n" +
        "lunanexa_telemetry_samples \{telemetry_samples}\n" +
        "# TYPE lunanexa_notification_deliveries_pending gauge\n" +
        "lunanexa_notification_deliveries_pending \{pending_deliveries}\n" +
        "# TYPE lunanexa_notification_deliveries_dead_letter gauge\n" +
        "lunanexa_notification_deliveries_dead_letter \{dead_letter_deliveries}\n" +
        "# TYPE lunanexa_notification_worker_last_heartbeat_age_seconds gauge\n" +
        "lunanexa_notification_worker_last_heartbeat_age_seconds \{notification_worker_heartbeat_age_seconds}\n" +
        "# TYPE lunanexa_operational_event_history gauge\n" +
        "lunanexa_operational_event_history \{operational_event_count}\n" +
        "# TYPE lunanexa_operational_events_total counter\n" +
        operational_counters +
        operational_latency,
      }
    }
    (Get, "/v1/observability/readiness") => {
      if !bearer_authorized(headers, self.monitoring_token) &&
        !self.audit_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid monitoring or audit authority is required",
          false,
        )
      }
      match self.observability_readiness() {
        Some(readiness) => json_reply(200, readiness.to_json())
        None =>
          api_error(
            503, "ObservabilityUnavailable", "durable operational observability is unavailable",
            true,
          )
      }
    }
    (Post, "/v1/observability/export-proof") => {
      if self.external_export_proof_token == "" ||
        !bearer_authorized(headers, self.external_export_proof_token) {
        return api_error(
          401, "Unauthenticated", "valid export-proof authority is required", false,
        )
      }
      let proof : @observability.ExternalExportProof = @json.from_json(
        @json.parse(body),
      ) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "valid external export proof is required", false,
          )
      }
      json_reply(
        202,
        self.record_external_export_proof(proof, @async.now()).to_json(),
      ) catch {
        _ =>
          api_error(
            409, "ExportProofRejected", "external export proof was rejected", false,
          )
      }
    }
    (Get, "/v1/observability/events") => {
      if !bearer_authorized(headers, self.monitoring_token) &&
        !self.audit_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid monitoring or audit authority is required",
          false,
        )
      }
      let events = match self.observability_store {
        Some(store) => store.snapshot().events
        None => []
      }
      json_reply(200, events.to_json())
    }
    (Get, "/v1/capabilities") => {
      if !bearer_authorized(headers, self.inference_token) &&
        self.api_key_authorization(headers, ModelList, false) is None {
        return api_error(
          401, "Unauthenticated", "valid inference authority is required", false,
        )
      }
      let selectors = match self.registry {
        Some(registry) =>
          [
            for alias_record in registry.snapshot().aliases => alias_record.name
          ]
        None => []
      }
      json_reply(200, {
        "contract_version": @contracts.contract_version,
        "capabilities": ["TextGenerate"],
        "selectors": selectors,
        "streaming": true,
        "cancellation": true,
        "retention_policies": ["Ephemeral"],
      })
    }
    (Get, "/v1/workspace") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      let snapshot = try directory.snapshot(@async.now()) catch {
        _ =>
          return api_error(
            503, "WorkspaceUnavailable", "durable workspace state could not be read",
            true,
          )
      } noraise {
        value => value
      }
      json_reply(200, snapshot.to_json())
    }
    (Get, "/v1/workspace/self") => {
      let subject_ref = match self.enterprise_session_subject(headers) {
        Some(subject) => Some(subject)
        None =>
          if bearer_authorized(headers, self.inference_token) {
            trusted_workspace_subject(headers, allow_asserted_subject)
          } else {
            None
          }
      }
      guard subject_ref is Some(subject_ref) else {
        return api_error(
          401, "Unauthenticated", "a verified auth-TLS identity or accepted loopback subject assertion is required",
          false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      let view = try directory.self_view(subject_ref, @async.now()) catch {
        _ =>
          return api_error(
            403, "WorkspaceAccessDenied", "the asserted workspace subject is not recognized",
            false,
          )
      } noraise {
        value => value
      }
      json_reply(200, view.to_json())
    }
    (Post, "/v1/workspace/users") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      guard decode_workspace_user(body) is Some(user) else {
        return api_error(
          400, "InvalidRequest", "invalid workspace user record", false,
        )
      }
      let persisted = try {
        match user.state {
          UserInvited => directory.invite_user(user)
          UserActive => directory.create_user(user)
          UserSuspended | UserRevoked =>
            return api_error(
              400, "InvalidRequest", "a new workspace user must be invited or active",
              false,
            )
        }
      } catch {
        _ =>
          return api_error(
            409, "WorkspaceRejected", "workspace user creation was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        if persisted.state == UserInvited {
          "workspace.user.invite"
        } else {
          "workspace.user.create"
        },
        persisted.user_id,
        persisted.identity_receipt,
      )
      json_reply(201, persisted.to_json())
    }
    (Post, _) if path.has_prefix("/v1/workspace/users/") &&
      path.has_suffix(":activate") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let prefix = "/v1/workspace/users/".length()
      let suffix = ":activate".length()
      let user_id = path[prefix:path.length() - suffix].to_owned()
      self.transition_workspace_user(
        user_id,
        UserActive,
        "workspace.user.activate",
      )
    }
    (Post, _) if path.has_prefix("/v1/workspace/users/") &&
      path.has_suffix(":suspend") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let prefix = "/v1/workspace/users/".length()
      let suffix = ":suspend".length()
      let user_id = path[prefix:path.length() - suffix].to_owned()
      self.transition_workspace_user(
        user_id,
        UserSuspended,
        "workspace.user.suspend",
      )
    }
    (Post, _) if path.has_prefix("/v1/workspace/users/") &&
      path.has_suffix(":revoke") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let prefix = "/v1/workspace/users/".length()
      let suffix = ":revoke".length()
      let user_id = path[prefix:path.length() - suffix].to_owned()
      self.transition_workspace_user(
        user_id,
        UserRevoked,
        "workspace.user.revoke",
      )
    }
    (Post, "/v1/workspace/access-grants") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      guard decode_workspace_access_grant(body) is Some(grant) else {
        return api_error(
          400, "InvalidRequest", "invalid workspace access grant", false,
        )
      }
      let persisted = try
        directory.issue_access_grant(grant, @async.now())
      catch {
        _ =>
          return api_error(
            409, "WorkspaceRejected", "workspace access grant was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "workspace.access.issue",
        persisted.grant_id,
        persisted.policy_receipt,
      )
      json_reply(201, persisted.to_json())
    }
    (Post, "/v1/workspace/leases") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      guard decode_workspace_lease(body) is Some(lease) else {
        return api_error(
          400, "InvalidRequest", "invalid workspace lease", false,
        )
      }
      let persisted = try directory.issue_lease(lease, @async.now()) catch {
        _ =>
          return api_error(
            409, "WorkspaceRejected", "workspace lease creation was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "workspace.lease.issue",
        persisted.lease_id,
        persisted.policy_receipt,
      )
      json_reply(201, persisted.to_json())
    }
    (Post, _) if path.has_prefix("/v1/workspace/access-grants/") &&
      path.has_suffix(":revoke") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      let prefix = "/v1/workspace/access-grants/".length()
      let suffix = ":revoke".length()
      let grant_id = path[prefix:path.length() - suffix].to_owned()
      if !@workspace.valid_identifier(grant_id) {
        return api_error(
          400, "InvalidRequest", "invalid workspace access grant identity", false,
        )
      }
      let persisted = try
        directory.revoke_access_grant(grant_id, @async.now())
      catch {
        _ =>
          return api_error(
            409, "WorkspaceRejected", "workspace access revocation was rejected",
            false,
          )
      } noraise {
        value => value
      }
      let receipt = "workspace-access-revoke:\{persisted.grant_id}:\{@async.now()}"
      self.operator_audit(
        "workspace.access.revoke",
        persisted.grant_id,
        receipt,
      )
      json_reply(200, { "access_grant": persisted, "receipt": receipt })
    }
    (Post, _) if path.has_prefix("/v1/workspace/leases/") &&
      path.has_suffix(":activate") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let prefix = "/v1/workspace/leases/".length()
      let suffix = ":activate".length()
      let lease_id = path[prefix:path.length() - suffix].to_owned()
      self.activate_workspace_lease(lease_id)
    }
    (Post, _) if path.has_prefix("/v1/workspace/leases/") &&
      path.has_suffix(":end") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.workspace_directory is Some(directory) else {
        return api_error(
          503, "WorkspaceUnavailable", "durable workspace state is unavailable",
          true,
        )
      }
      let prefix = "/v1/workspace/leases/".length()
      let suffix = ":end".length()
      let lease_id = path[prefix:path.length() - suffix].to_owned()
      if !@workspace.valid_identifier(lease_id) {
        return api_error(
          400, "InvalidRequest", "invalid workspace lease identity", false,
        )
      }
      let persisted = try directory.revoke_lease(lease_id, @async.now()) catch {
        _ =>
          return api_error(
            409, "WorkspaceRejected", "workspace lease termination was rejected",
            false,
          )
      } noraise {
        value => value
      }
      let receipt = "workspace-lease-end:\{persisted.lease_id}:\{@async.now()}"
      self.operator_audit("workspace.lease.end", persisted.lease_id, receipt)
      json_reply(200, { "lease": persisted, "receipt": receipt })
    }
    (Get, "/v1/scheduler") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.scheduler is Some(scheduler) else {
        return api_error(
          503, "SchedulerUnavailable", "durable scheduler is unavailable", true,
        )
      }
      json_reply(200, scheduler.snapshot().to_json())
    }
    (Get, "/v1/recovery/plan") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let desired = self.store.assignments()
      let heartbeats = self.store.heartbeats()
      let observed_assignment_ids = [
        for assignment in desired if heartbeats.any(heartbeat => {
          heartbeat.running_deployments.any(deployment_id => {
            deployment_id == assignment.deployment_id
          })
        }) => assignment.assignment_id
      ]
      let plan = @controller.recovery_plan(
        self.store.controller_epoch(),
        desired,
        observed_assignment_ids,
        @async.now(),
      )
      let actions = plan.actions.copy()
      let now = @async.now()
      for heartbeat in heartbeats {
        if @controller.node_unreachable(
            heartbeat.timestamp_unix_ms,
            now,
            self.global_settings.control_timing.heartbeat_timeout_ms,
          ) {
          actions.push(MarkNodeUnreachable(heartbeat.node_id))
        }
      }
      json_reply(200, { ..plan, actions, }.to_json())
    }
    (Put, "/v1/quotas") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.scheduler is Some(scheduler) else {
        return api_error(
          503, "SchedulerUnavailable", "durable scheduler is unavailable", true,
        )
      }
      guard decode_quota(body) is Some(quota) else {
        return api_error(400, "InvalidRequest", "invalid tenant quota", false)
      }
      try scheduler.set_quota(quota) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "tenant quota limits are invalid", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "quota:\{digest_hex(quota.tenant_ref)}"
      self.operator_audit("quota.update", quota.tenant_ref, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/capacity:forecast") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard decode_capacity(body) is Some(request) &&
        request.instance_memory_mib > 0 else {
        return api_error(
          400, "InvalidRequest", "positive instance memory is required", false,
        )
      }
      let now = @async.now()
      let nodes = [
        for heartbeat in self.store.heartbeats() => {
          self.managed_scheduler_node(heartbeat, now)
        }
      ]
      json_reply(
        200,
        @scheduler.forecast(nodes, request.instance_memory_mib).to_json(),
      )
    }
    (Put, "/v1/telemetry") => {
      guard decode_telemetry(body) is Some(sample) else {
        return api_error(
          400, "InvalidRequest", "invalid telemetry sample", false,
        )
      }
      if !self.node_authorized(headers, sample.node_id) {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      guard self.telemetry is Some(telemetry) else {
        return api_error(
          503, "TelemetryUnavailable", "durable telemetry is unavailable", true,
        )
      }
      try telemetry.record_sample(sample) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "payload-shaped telemetry is forbidden", false,
          )
      } noraise {
        _ => ()
      }
      json_reply(202, { "accepted": true })
    }
    (Get, "/v1/telemetry") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.telemetry is Some(telemetry) else {
        return api_error(
          503, "TelemetryUnavailable", "durable telemetry is unavailable", true,
        )
      }
      json_reply(200, telemetry.snapshot().to_json())
    }
    (Post, "/v1/benchmarks") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.telemetry is Some(telemetry) else {
        return api_error(
          503, "TelemetryUnavailable", "durable telemetry is unavailable", true,
        )
      }
      guard decode_benchmark(body) is Some(run) else {
        return api_error(
          400, "InvalidRequest", "invalid benchmark evidence", false,
        )
      }
      let summary = try telemetry.record_benchmark(run) catch {
        _ =>
          return api_error(
            400, "InvalidRequest", "benchmark evidence is invalid", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "benchmark.record",
        run.run_id,
        "benchmark:\{run.run_id}",
      )
      json_reply(201, summary.to_json())
    }
    (Get, "/v1/nodes") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      json_reply(200, self.store.heartbeats().to_json())
    }
    (Post, "/v1/enrollment/tokens") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.enrollment is Some(enrollment) else {
        return api_error(
          503, "EnrollmentUnavailable", "durable enrollment is unavailable", true,
        )
      }
      guard decode_token_issue(body) is Some(issue) else {
        return api_error(
          400, "InvalidRequest", "invalid bootstrap token request", false,
        )
      }
      let now = @async.now()
      if issue.token_id == "" ||
        issue.secret.length() < 20 ||
        issue.expires_unix_ms <= now ||
        issue.expires_unix_ms >
        now +
        self.global_settings.control_timing.bootstrap_token_max_lifetime_ms {
        return api_error(
          400, "InvalidRequest", "bootstrap token must be strong and expire within the administrator limit",
          false,
        )
      }
      let token = enrollment.issue_token(
        issue.token_id,
        issue.secret,
        issue.expires_unix_ms,
      )
      self.operator_audit(
        "node.bootstrap.issue",
        issue.token_id,
        "bootstrap:\{issue.token_id}",
      )
      json_reply(201, token.to_json())
    }
    (Post, "/v1/enrollment") => {
      guard self.enrollment is Some(enrollment) else {
        return api_error(
          503, "EnrollmentUnavailable", "durable enrollment is unavailable", true,
        )
      }
      guard decode_enrollment(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid enrollment request", false,
        )
      }
      if !@contracts.valid_identifier(request.node_id, maximum_length=128) ||
        request.node_auth_secret.length() < 20 ||
        !valid_public_key_ref(request.public_key_ref) {
        return api_error(
          400, "InvalidRequest", "node identity or authority is invalid", false,
        )
      }
      let certificate = try
        enrollment.enroll(
          request.node_id,
          request.token_id,
          request.secret,
          request.node_auth_secret,
          request.public_key_ref,
          @async.now(),
          certificate_lifetime_ms=self.global_settings.control_timing.node_certificate_lifetime_ms,
        )
      catch {
        _ =>
          return api_error(
            401, "Unauthenticated", "bootstrap authority was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "node.enroll",
        request.node_id,
        "enrollment:\{request.node_id}:\{certificate.serial}",
      )
      json_reply(201, certificate.to_json())
    }
    (Post, "/v1/enrollment/rotate") => {
      guard self.enrollment is Some(enrollment) else {
        return api_error(
          503, "EnrollmentUnavailable", "durable enrollment is unavailable", true,
        )
      }
      guard decode_rotation(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid rotation request", false,
        )
      }
      guard header(headers, "X-LunaNexa-Node-Id") == Some(request.node_id) &&
        node_credential(headers) is Some(credential) &&
        credential != "" else {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      if !valid_public_key_ref(request.public_key_ref) ||
        request.current_serial <= 0L {
        return api_error(
          400, "InvalidRequest", "certificate rotation request is invalid", false,
        )
      }
      let certificate = try
        enrollment.renew(
          request.node_id,
          credential,
          request.public_key_ref,
          request.current_serial,
          @async.now(),
          certificate_lifetime_ms=self.global_settings.control_timing.node_certificate_lifetime_ms,
          renewal_grace_ms=86400000L,
        )
      catch {
        _ =>
          return api_error(
            401, "Unauthenticated", "certificate rotation was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "node.certificate.rotate",
        request.node_id,
        "rotation:\{request.node_id}:\{certificate.serial}",
      )
      json_reply(200, certificate.to_json())
    }
    (Put, "/v1/nodes/heartbeat") => {
      guard decode_heartbeat(body) is Some(heartbeat) else {
        return api_error(400, "InvalidRequest", "invalid node heartbeat", false)
      }
      if !@contracts.valid_identifier(heartbeat.node_id, maximum_length=128) {
        return api_error(400, "InvalidRequest", "invalid node identity", false)
      }
      let credential = node_credential(headers).unwrap_or("")
      if !self.node_authorized(headers, heartbeat.node_id) ||
        heartbeat.signature != @node.heartbeat_signature(heartbeat, credential) {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      let now = @async.now()
      if heartbeat.timestamp_unix_ms <
        now - self.global_settings.control_timing.heartbeat_replay_window_ms ||
        heartbeat.timestamp_unix_ms >
        now + self.global_settings.control_timing.heartbeat_replay_window_ms {
        return api_error(
          409, "StaleGeneration", "heartbeat timestamp is outside the replay window",
          false,
        )
      }
      let mut previous : @contracts.NodeHeartbeat? = None
      for current in self.store.heartbeats() {
        if current.node_id == heartbeat.node_id {
          previous = Some(current)
        }
      }
      if previous is Some(current) &&
        (
          heartbeat.timestamp_unix_ms <= current.timestamp_unix_ms ||
          heartbeat.observed_generation < current.observed_generation ||
          heartbeat.controller_epoch < current.controller_epoch
        ) {
        return api_error(
          409, "StaleGeneration", "heartbeat replay was rejected", false,
        )
      }
      self.store.put_heartbeat(heartbeat)
      self.refresh_node_health_notifications(now)
      self.refresh_deployment_operations()
      json_reply(202, { "accepted": true, "node_id": heartbeat.node_id })
    }
    (Post, _) if path.has_prefix("/v1/nodes/") &&
      path.has_suffix("/exclusive-lease:observe") => {
      let prefix = "/v1/nodes/".length()
      let suffix = "/exclusive-lease:observe".length()
      let node_id = path[prefix:path.length() - suffix].to_owned()
      self.observe_node_lease_action(node_id, headers, body)
    }
    (Put, "/v1/nodes/directive") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard decode_node_directive(body) is Some(directive) else {
        return api_error(400, "InvalidRequest", "invalid node directive", false)
      }
      if !@contracts.valid_identifier(directive.node_id, maximum_length=128) ||
        directive.generation <= 0L ||
        directive.receipt == "" ||
        !(directive.desired_state == Active ||
        directive.desired_state == Cordoned ||
        directive.desired_state == Draining) {
        return api_error(
          400, "InvalidRequest", "node directive state or generation is invalid",
          false,
        )
      }
      if self.store.node_directive(directive.node_id) is Some(current) &&
        directive.generation <= current.generation {
        return api_error(
          409, "StaleGeneration", "node directive generation is stale", false,
        )
      }
      self.with_audit_lock(() => {
        let audit = self.next_audit(
          "operator",
          "node.state",
          directive.node_id,
          "previous",
          "\{Repr(directive.desired_state)}",
          "accepted",
          directive.receipt,
          @async.now(),
        )
        self.store.commit_node_directive(directive, audit)
      })
      json_reply(202, { "accepted": true, "receipt": directive.receipt })
    }
    (Get, _) if path.has_prefix("/v1/nodes/") && path.has_suffix("/directive") => {
      let prefix = "/v1/nodes/".length()
      let suffix = "/directive".length()
      let node_id = path[prefix:path.length() - suffix].to_owned()
      if !self.node_authorized(headers, node_id) {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      match self.store.node_directive(node_id) {
        Some(directive) => json_reply(200, directive.to_json())
        None =>
          api_error(404, "NotFound", "node directive was not found", false)
      }
    }
    (Get, _) if path.has_prefix("/v1/nodes/") &&
      path.has_suffix("/exclusive-lease") => {
      let prefix = "/v1/nodes/".length()
      let suffix = "/exclusive-lease".length()
      let node_id = path[prefix:path.length() - suffix].to_owned()
      if !@contracts.valid_identifier(node_id, maximum_length=128) ||
        !self.node_authorized(headers, node_id) {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      guard self.exclusive_lease_store is Some(leases) else {
        return api_error(
          503, "ExclusiveLeaseUnavailable", "exclusive lease authority is unavailable",
          true,
        )
      }
      self.reconcile_expired_exclusive_leases()
      match leases.lease_for_node(node_id) {
        Some(lease) => {
          let reconciled = self.begin_exclusive_provisioning_if_drained(lease)
          let credential = node_credential(headers).unwrap_or("")
          json_reply(
            200,
            @nodelease.node_transport_lease_with_helper_authorizations(
              reconciled,
              node_id,
              credential,
              self.lease_helper_receipt_secret,
              @async.now(),
            ).to_json(),
          )
        }
        None => api_error(404, "NotFound", "node has no exclusive lease", false)
      }
    }
    (Get, "/v1/assignments") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      json_reply(200, self.store.assignments().to_json())
    }
    (Get, _) if path.has_prefix("/v1/nodes/") && path.has_suffix("/assignments") => {
      let prefix = "/v1/nodes/".length()
      let suffix = "/assignments".length()
      let node_id = path[prefix:path.length() - suffix].to_owned()
      if !self.node_authorized(headers, node_id) {
        return api_error(
          401, "Unauthenticated", "valid node authority is required", false,
        )
      }
      json_reply(
        200,
        [
          for assignment in self.store.assignments() if assignment.node_id ==
          node_id &&
          assignment.lease_expires_unix_ms > @async.now() => assignment
        ].to_json(),
      )
    }
    (Put, "/v1/assignments") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard decode_assignment(body) is Some(assignment) else {
        return api_error(
          400, "InvalidRequest", "invalid desired assignment", false,
        )
      }
      if assignment.signature != "" {
        return api_error(
          400, "InvalidRequest", "operators submit unsigned desired state; the controller owns assignment signing",
          false,
        )
      }
      if self.assignment_signing_secret == "" {
        return api_error(
          503, "SignerUnavailable", "assignment signing authority is unavailable",
          true,
        )
      }
      let now = @async.now()
      if !valid_assignment_shape(assignment, now) {
        return api_error(
          400, "InvalidRequest", "assignment security, resource, or lease constraints are invalid",
          false,
        )
      }
      if self.exclusive_lease_store is Some(leases) &&
        leases.node_blocks_managed_placement(assignment.node_id) {
        return api_error(
          409, "NodeExclusiveLease", "node is reserved for an exclusive lease", false,
        )
      }
      let signed_assignment = {
        ..assignment,
        signature: @node.assignment_signature(
          assignment,
          self.assignment_signing_secret,
        ),
      }
      if signed_assignment.controller_epoch != self.store.controller_epoch() {
        return api_error(
          409, "StaleControllerEpoch", "assignment controller epoch is not current",
          false,
        )
      }
      if self.store.assignment(signed_assignment.assignment_id) is Some(current) &&
        signed_assignment.generation <= current.generation {
        return api_error(
          409, "StaleGeneration", "assignment generation is stale", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      if !registry.deployment_allowed(
          signed_assignment.artifact.digest,
          signed_assignment.runtime,
        ) {
        return api_error(
          409, "RegistryRejected", "artifact or runtime is not approved for deployment",
          false,
        )
      }
      let receipt = "assignment:\{signed_assignment.assignment_id}:\{signed_assignment.generation}"
      self.with_audit_lock(() => {
        let audit = self.next_audit(
          "operator",
          "assignment.publish",
          signed_assignment.assignment_id,
          "unknown",
          "desired",
          "accepted",
          receipt,
          now,
        )
        self.store.commit_assignment(signed_assignment, audit)
      })
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Delete, _) if path.has_prefix("/v1/assignments/") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let assignment_id = path["/v1/assignments/".length():].to_owned()
      self.stop_assignment(assignment_id)
    }
    (Post, _) if path.has_prefix("/v1/assignments/") && path.has_suffix("/stop") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      let prefix = "/v1/assignments/".length()
      let suffix = "/stop".length()
      let assignment_id = path[prefix:path.length() - suffix].to_owned()
      self.stop_assignment(assignment_id)
    }
    (Get, "/v1/registry") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      json_reply(200, registry.snapshot().to_json())
    }
    (Post, "/v1/models") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_model(body) is Some(model) else {
        return api_error(400, "InvalidRequest", "invalid model record", false)
      }
      try registry.register_model(model) catch {
        _ =>
          return api_error(
            409, "RegistryRejected", "model registration was rejected", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "model:\{model.model_id}:\{model.version}"
      self.operator_audit("model.register", model.model_id, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/runtimes") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_runtime_spec(body) is Some(runtime) else {
        return api_error(
          400, "InvalidRequest", "invalid runtime specification", false,
        )
      }
      try registry.register_runtime(runtime) catch {
        _ =>
          return api_error(
            409, "RegistryRejected", "runtime registration was rejected", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "runtime:\{runtime.name}:\{runtime.version}"
      self.operator_audit("runtime.register", runtime.name, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/licenses") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_license(body) is Some(license) else {
        return api_error(400, "InvalidRequest", "invalid license record", false)
      }
      try registry.record_license(license) catch {
        _ =>
          return api_error(
            400, "RegistryRejected", "license metadata was rejected", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "license:\{license.license_id}"
      self.operator_audit("license.record", license.model_id, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/verifications") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_verification_request(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid signature verification request", false,
        )
      }
      guard self.signature_verifier is Some(verifier) else {
        return api_error(
          503, "VerifierUnavailable", "the configured signature verifier is unavailable",
          true,
        )
      }
      let verification_receipt = try {
        if request.kind == "image" {
          verifier.verify_image(request.subject, request.digest)
        } else if request.kind == "blob" &&
          request.signature_path is Some(signature_path) {
          verifier.verify_blob(request.subject, signature_path, request.digest)
        } else {
          return api_error(
            400, "InvalidRequest", "verification kind or signature path is invalid",
            false,
          )
        }
      } catch {
        _ =>
          return api_error(
            409, "SignatureRejected", "signature verification failed", false,
          )
      } noraise {
        value => value
      }
      let verification : @registry.ArtifactVerification = {
        digest: verification_receipt.digest,
        signature_verified: verification_receipt.verified,
        provenance_verified: request.provenance_verified,
        verified_unix_ms: @async.now(),
        verifier: verification_receipt.verifier,
      }
      try registry.record_verification(verification) catch {
        _ =>
          return api_error(
            400, "RegistryRejected", "verification metadata was rejected", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "verification:\{verification.digest}"
      self.operator_audit("artifact.verify", verification.digest, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/evaluations") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_evaluation(body) is Some(evaluation) else {
        return api_error(
          400, "InvalidRequest", "invalid evaluation record", false,
        )
      }
      try registry.record_evaluation(evaluation) catch {
        _ =>
          return api_error(
            400, "RegistryRejected", "evaluation metadata was rejected", false,
          )
      } noraise {
        _ => ()
      }
      let receipt = "evaluation:\{evaluation.evaluation_id}"
      self.operator_audit("model.evaluate", evaluation.model_id, receipt)
      json_reply(202, { "accepted": true, "receipt": receipt })
    }
    (Post, "/v1/models/approve") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_approval(body) is Some(approval) else {
        return api_error(
          400, "InvalidRequest", "invalid approval request", false,
        )
      }
      let approved = try
        registry.approve(approval.model_id, approval.version, @async.now())
      catch {
        _ =>
          return api_error(
            409, "RegistryRejected", "model approval prerequisites were not met",
            false,
          )
      } noraise {
        value => value
      }
      let receipt = "approval:\{approval.model_id}:\{approval.version}"
      self.operator_audit("model.approve", approval.model_id, receipt)
      json_reply(200, approved.to_json())
    }
    (Post, "/v1/aliases/promote") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_promotion(body) is Some(promotion) else {
        return api_error(
          400, "InvalidRequest", "invalid promotion request", false,
        )
      }
      let receipt = try
        registry.promote(
          promotion.alias_name,
          promotion.model_id,
          promotion.version,
          promotion.stage,
          promotion.actor,
          @async.now(),
        )
      catch {
        _ =>
          return api_error(
            409, "RegistryRejected", "model promotion was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "alias.promote",
        promotion.alias_name,
        receipt.receipt_id,
      )
      json_reply(200, receipt.to_json())
    }
    (Post, "/v1/aliases/rollback") => {
      if !self.operator_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid operator authority is required", false,
        )
      }
      guard self.registry is Some(registry) else {
        return api_error(
          503, "RegistryUnavailable", "durable registry is unavailable", true,
        )
      }
      guard decode_rollback(body) is Some(rollback) else {
        return api_error(
          400, "InvalidRequest", "invalid rollback request", false,
        )
      }
      let receipt = try
        registry.rollback(rollback.alias_name, rollback.actor, @async.now())
      catch {
        _ =>
          return api_error(
            409, "RegistryRejected", "alias rollback was rejected", false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "alias.rollback",
        rollback.alias_name,
        receipt.receipt_id,
      )
      json_reply(200, receipt.to_json())
    }
    (Post, "/v1/workloads") => {
      guard decode_workload(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid canonical workload", false,
        )
      }
      if !bearer_authorized(headers, self.inference_token) {
        match
          self.api_key_check(
            headers,
            Inference,
            Some(request.tenant_ref),
            Some(request.model_selector),
            true,
          ) {
          KeyAuthorized(_) => ()
          KeyQuotaExceeded =>
            return api_error(
              429, "QuotaExceeded", "API key request quota is exhausted", false,
            )
          KeyDenied =>
            return api_error(
              401, "Unauthenticated", "valid tenant-scoped inference authority is required",
              false,
            )
        }
      }
      if !ephemeral_only(request) {
        return api_error(
          503, "RetentionUnavailable", "this deployment has no configured encrypted retention provider",
          false,
        )
      }
      let (workspace_error, reserved) = self.workspace_admit(
        headers, request, allow_asserted_subject,
      )
      if workspace_error is Some(reply) {
        return reply
      }
      try self.invoke_workload(request) catch {
        error => {
          self.release_workspace_admission(request, reserved)
          raise error
        }
      } noraise {
        reply => {
          self.release_workspace_admission(request, reserved)
          reply
        }
      }
    }
    (Get, _) if path.has_prefix("/v1/workloads/") => {
      if !bearer_authorized(headers, self.inference_token) {
        return api_error(
          401, "Unauthenticated", "valid inference authority is required", false,
        )
      }
      let workload_id = path["/v1/workloads/".length():].to_owned()
      if !@contracts.valid_identifier(workload_id) {
        return api_error(
          400, "InvalidRequest", "invalid workload identity", false,
        )
      }
      if self.workspace_workload_access_error(
          headers, workload_id, allow_asserted_subject,
        )
        is Some(reply) {
        return reply
      }
      match self.store.workload_result(workload_id) {
        Some(response) => json_reply(200, response.to_json())
        None => {
          let admission = match self.scheduler {
            Some(scheduler) => scheduler.admission(workload_id)
            None => None
          }
          match admission {
            Some(active) => {
              let now = @async.now()
              let started = active.started_unix_ms.unwrap_or(0L)
              let status : @contracts.WorkloadResponse = {
                version: @contracts.contract_version,
                workload_id,
                state: if active.started_unix_ms is Some(_) {
                  Running
                } else {
                  Queued
                },
                output: None,
                error: None,
                usage: {
                  input_units: 0,
                  output_units: 0,
                  accelerator_ms: if started == 0L {
                    0L
                  } else {
                    now - started
                  },
                  queue_ms: if started == 0L {
                    now - active.accepted_unix_ms
                  } else {
                    started - active.accepted_unix_ms
                  },
                },
                artifact_digest: self.runtime.artifact_digest(),
                runtime_version: self.runtime.runtime_version(),
                timing: {
                  accepted_unix_ms: active.accepted_unix_ms,
                  started_unix_ms: started,
                  first_output_unix_ms: 0L,
                  completed_unix_ms: 0L,
                },
                retryable: false,
                audit_receipt: "pending:\{digest_hex(workload_id)}",
              }
              json_reply(200, status.to_json())
            }
            None =>
              api_error(
                404, "NotFound", "workload receipt was not found", false,
              )
          }
        }
      }
    }
    (Post, _) if path.has_prefix("/v1/workloads/") && path.has_suffix("/cancel") => {
      if !bearer_authorized(headers, self.inference_token) {
        return api_error(
          401, "Unauthenticated", "valid inference authority is required", false,
        )
      }
      let prefix = "/v1/workloads/".length()
      let suffix = "/cancel".length()
      let workload_id = path[prefix:path.length() - suffix].to_owned()
      if !@contracts.valid_identifier(workload_id) {
        return api_error(
          400, "InvalidRequest", "invalid workload identity", false,
        )
      }
      if self.workspace_workload_access_error(
          headers, workload_id, allow_asserted_subject,
        )
        is Some(reply) {
        return reply
      }
      self.active_mutex.acquire()
      let active = self.active.get(workload_id)
      if active is Some(task) {
        task.cancel()
      }
      self.active_mutex.release()
      if active is None {
        return api_error(
          404, "NotFound", "active workload was not found", false,
        )
      }
      if self.scheduler is Some(scheduler) {
        ignore(scheduler.cancel(workload_id))
      }
      let receipt : CancellationReceipt = {
        workload_id,
        accepted: true,
        receipt: "cancel:\{workload_id}:\{digest_hex(workload_id)}",
      }
      json_reply(202, receipt.to_json())
    }
    (Get, "/v1/audit") => {
      if !self.audit_authorized(headers) {
        return api_error(
          401, "Unauthenticated", "valid audit authority is required", false,
        )
      }
      json_reply(200, self.store.audit_events().to_json())
    }
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}

///|
fn api_method_label(verb : ApiMethod) -> String {
  match verb {
    Get => "get"
    Post => "post"
    Put => "put"
    Delete => "delete"
  }
}

///|
fn operational_target_type(path : String) -> String {
  if path == "/health" || path == "/version" {
    "health"
  } else if path == "/metrics" {
    "metrics"
  } else if path.has_prefix("/v1/workloads") ||
    path == "/v1/chat/completions" ||
    path == "/v1/responses" {
    "workload"
  } else if path.has_prefix("/v1/nodes") {
    "node"
  } else if path.has_prefix("/v1/notifications") {
    "notification"
  } else if path.has_prefix("/v1/portal") {
    "enterprise_portal"
  } else if path.has_prefix("/v1/exclusive-node-leases") {
    "exclusive_lease"
  } else if path.has_prefix("/v1/offline-commerce") {
    "commercial"
  } else if path.has_prefix("/v1/contract-documents") {
    "contract_document"
  } else if path.has_prefix("/v1/contract-governance") {
    "contract_governance"
  } else if path.has_prefix("/v1/commercial") {
    "commercial"
  } else if path.has_prefix("/v1/workspace") {
    "workspace"
  } else if path.has_prefix("/v1/catalog") ||
    path.has_prefix("/v1/service-deployments") {
    "deployment"
  } else if path.has_prefix("/v1/telemetry") {
    "telemetry"
  } else {
    "api"
  }
}

///|
async fn ApiService::operational_actor_class(
  self : ApiService,
  headers : Map[String, String],
  path : String,
) -> @observability.OperationalActorClass {
  if self.operator_authorized(headers) ||
    self.audit_authorized(headers) ||
    bearer_authorized(headers, self.monitoring_token) {
    Operator
  } else if node_credential(headers) is Some(_) {
    NodeAgent
  } else if path.has_prefix("/v1/provider-callbacks") {
    Provider
  } else if self.external_export_proof_token != "" &&
    bearer_authorized(headers, self.external_export_proof_token) {
    Provider
  } else if bearer_authorized(headers, self.inference_token) ||
    self.api_key_authorization(headers, Inference, false) is Some(_) {
    Customer
  } else {
    Anonymous
  }
}

///|
async fn ApiService::record_operational_request(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  reply : HttpReply,
  started_unix_ms : Int64,
  allow_asserted_subject : Bool,
) -> Unit {
  guard self.observability_store is Some(store) else { return }
  let completed = @async.now()
  let generated = "request-\{digest_hex("\{api_method_label(verb)}|\{path}|\{started_unix_ms}")[:32]}"
  let correlation_id = match header(headers, "X-Request-Id") {
    Some(value) if @contracts.valid_identifier(value) =>
      "request-external-\{digest_hex(value)[:32]}"
    _ => generated
  }
  let tenant_hash = self.trusted_operational_tenant_hash(
    headers, allow_asserted_subject,
  )
  let outcome = if reply.status >= 500 {
    "error"
  } else if reply.status >= 400 {
    "rejected"
  } else {
    "accepted"
  }
  ignore(
    store.record_generated({
      version: @observability.contract_version,
      event_id: "event-pending",
      timestamp_unix_ms: completed,
      severity: if reply.status >= 500 {
        Error
      } else if reply.status >= 400 {
        Warning
      } else {
        Information
      },
      component: "controller",
      event_code: "ApiRequestCompleted",
      correlation_id,
      actor_class: self.operational_actor_class(headers, path),
      tenant_hash,
      target_type: operational_target_type(path),
      outcome,
      status_code: reply.status,
      duration_ms: (completed - started_unix_ms).max(0L),
    }),
  )
  guard self.notification_store is Some(notifications) else { return }
  let recent_rate_rejections = store.snapshot().events.count_if(event => {
    event.target_type == "workload" &&
    event.actor_class == Customer &&
    (event.status_code == 409 || event.status_code == 429) &&
    event.timestamp_unix_ms >= completed - 300000L
  })
  let deduplication_key = "workload-admission-rejections"
  let existing = notifications.record_by_deduplication_key(
    deduplication_key,
    PlatformOperators,
  )
  if recent_rate_rejections >= 5 {
    match existing {
      Some(record) if record.lifecycle != Resolved => ()
      _ =>
        ignore(
          notifications.enqueue({
            version: @notifications.contract_version,
            notification_id: "alert-workload-admission-\{completed}",
            deduplication_key,
            source_receipt: "observability:workload-429:\{completed}",
            topic: WorkloadAdmission,
            code: "WorkloadAdmissionRejected",
            severity: Warning,
            audience: PlatformOperators,
            title_key: "alerts.workload_admission.title",
            body_key: "alerts.workload_admission.body",
            parameters: {
              "window": "5m",
              "count": recent_rate_rejections.to_string(),
            },
            created_unix_ms: completed,
            expires_unix_ms: None,
          }),
        )
    }
  } else {
    match existing {
      Some(record) if record.lifecycle != Resolved =>
        ignore(
          notifications.resolve_operator({
            notification_id: record.event.notification_id,
            expected_generation: record.generation,
            actor_ref: "controller-reconciler",
            now_unix_ms: completed,
          }),
        )
      _ => ()
    }
  }
}

///|
async fn ApiService::handle_with_transport(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  let started = @async.now()
  let reply = self.dispatch_with_transport(
    verb, path, headers, body, allow_asserted_subject,
  )
  self.record_operational_request(
    verb, path, headers, reply, started, allow_asserted_subject,
  )
  reply
}

///|
/// Trusted in-process request adapter. Network listeners use transport-aware
/// dispatch so asserted subjects are accepted only from a proved loopback TCP
/// peer; callers of this method are part of the controller trust boundary.
pub async fn ApiService::handle(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  self.handle_with_transport(verb, path, headers, body, true)
}

///|
fn api_method(request_method : @http.RequestMethod) -> ApiMethod? {
  match request_method {
    Get => Some(Get)
    Post => Some(Post)
    Put => Some(Put)
    Delete => Some(Delete)
    _ => None
  }
}

///|
priv enum BoundedRequestBody {
  RequestBody(String)
  RequestBodyTooLarge
  RequestBodyInvalidUtf8
}

/// Read at most one byte beyond the public body limit. This keeps an attacker
/// from forcing the native listener to buffer an unbounded request before the
/// ordinary contract-size check runs.

///|
async fn read_bounded_request_body(
  reader : &@io.Reader,
  maximum_bytes : Int,
) -> BoundedRequestBody {
  let buffer = @buffer.Buffer(size_hint=maximum_bytes.min(65536))
  for total = 0 {
    let remaining = maximum_bytes - total + 1
    match reader.read_some(max_len=remaining.min(65536)) {
      None =>
        try @utf8.decode(buffer.to_bytes()) catch {
          _ => return RequestBodyInvalidUtf8
        } noraise {
          value => return RequestBody(value)
        }
      Some(chunk) => {
        let next = total + chunk.length()
        if next > maximum_bytes {
          return RequestBodyTooLarge
        }
        buffer.write_bytes(chunk)
        continue next
      }
    }
  }
}

///|
fn reason(status : Int) -> String {
  match status {
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    206 => "Partial Content"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    409 => "Conflict"
    413 => "Payload Too Large"
    416 => "Range Not Satisfiable"
    429 => "Too Many Requests"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "Response"
  }
}

///|
async fn send_listener_reply(
  connection : @http.ServerConnection,
  reply : HttpReply,
) -> Unit {
  connection.send_response(reply.status, reason(reply.status), extra_headers={
    "Content-Type": reply.content_type,
    "Cache-Control": "no-store",
  })
  connection.write_string(reply.body)
  connection.end_response()
}

///|
fn loopback_client(address : @socket.Addr) -> Bool {
  let rendered = address.to_string()
  rendered.has_prefix("127.") ||
  rendered.has_prefix("[::1]:") ||
  rendered.has_prefix("::1:")
}

///|
pub async fn ApiService::serve_on(
  self : ApiService,
  server : @http.Server,
) -> Unit {
  self.refresh_deployment_operations()
  server.run_forever(allow_failure=true) <| ((request, reader, connection) => {
    let allow_asserted_subject = loopback_client(connection.client_addr())
    if self.serve_artifact(request, connection) {
      return
    }
    if request.meth == Post && request.path == "/v1/chat/completions" {
      let request_body = match
        read_bounded_request_body(
          reader,
          self.global_settings.request_budgets.maximum_request_body_bytes,
        ) {
        RequestBody(value) => value
        RequestBodyTooLarge => {
          send_listener_reply(
            connection,
            api_error(
              413, "PayloadTooLarge", "request body exceeds the public contract limit",
              false,
            ),
          )
          return
        }
        RequestBodyInvalidUtf8 => {
          send_listener_reply(
            connection,
            api_error(
              400, "InvalidRequest", "request body is not valid UTF-8", false,
            ),
          )
          return
        }
      }
      guard decode_openai_chat(request_body) is Some(value) &&
        @contracts.valid_identifier(value.model) &&
        value.messages.length() > 0 &&
        value.messages.length() <= 256 &&
        valid_openai_request_budget(value, self.global_settings.request_budgets) else {
        send_listener_reply(
          connection,
          api_error(
            400, "InvalidRequest", "invalid OpenAI-compatible chat request", false,
          ),
        )
        return
      }
      if !value.stream.unwrap_or(false) {
        send_listener_reply(
          connection,
          self.handle_with_transport(
            Post,
            request.path,
            request.headers,
            request_body,
            allow_asserted_subject,
          ),
        )
        return
      }
      if !self.store.current_epoch_is_durable() {
        send_listener_reply(
          connection,
          api_error(
            409, "StaleControllerEpoch", "controller was fenced by a newer durable epoch",
            true,
          ),
        )
        return
      }
      if self.reconciliation_only {
        send_listener_reply(
          connection,
          api_error(
            503, "ReconciliationOnly", "controller mutations are disabled until recovery reconciliation is accepted",
            true,
          ),
        )
        return
      }
      let key_check = self.api_key_check(
        request.headers,
        Inference,
        None,
        Some(value.model),
        true,
      )
      let authority : @access.ApiAuthorization = match key_check {
        KeyAuthorized(authority) => authority
        KeyQuotaExceeded => {
          send_listener_reply(
            connection,
            api_error(
              429, "QuotaExceeded", "API key request quota is exhausted", false,
            ),
          )
          return
        }
        KeyDenied => {
          if !bearer_authorized(request.headers, self.inference_token) {
            send_listener_reply(
              connection,
              api_error(
                401, "Unauthenticated", "valid scoped inference API key is required",
                false,
              ),
            )
            return
          }
          {
            key_id: "static-inference-authority",
            tenant_ref: header(request.headers, "x-lunanexa-tenant").unwrap_or(
              "default-tenant",
            ),
            subject_ref: "static-inference-subject",
          }
        }
      }
      let now = @async.now()
      let (workload, request_digest) = openai_workload(
        value,
        authority,
        request.headers,
        true,
        now,
        self.global_settings.request_budgets,
      )
      try @contracts.validate_workload(workload) catch {
        _ => {
          send_listener_reply(
            connection,
            api_error(
              400, "InvalidRequest", "chat request violates the canonical workload contract",
              false,
            ),
          )
          return
        }
      } noraise {
        _ => ()
      }
      let workspace_headers = request.headers.copy()
      workspace_headers["X-LunaNexa-Subject"] = authority.subject_ref
      let (workspace_error, reserved) = self.workspace_admit(
        workspace_headers, workload, true,
      )
      if workspace_error is Some(reply) {
        send_listener_reply(connection, reply)
        return
      }
      try
        self.stream_workload(
          workload,
          connection,
          openai=Some({
            id: "chatcmpl-\{request_digest[:32]}",
            model: value.model,
            created_unix_seconds: now / 1000L,
            tool_call_seen: [false],
          }),
        )
      catch {
        error => {
          self.release_workspace_admission(workload, reserved)
          raise error
        }
      } noraise {
        _ => self.release_workspace_admission(workload, reserved)
      }
      return
    }
    if request.meth == Post && request.path == "/v1/workloads:stream" {
      if !self.store.current_epoch_is_durable() {
        let reply = api_error(
          409, "StaleControllerEpoch", "controller was fenced by a newer durable epoch",
          true,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      if self.reconciliation_only {
        let reply = api_error(
          503, "ReconciliationOnly", "controller mutations are disabled until recovery reconciliation is accepted",
          true,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      if !bearer_authorized(request.headers, self.inference_token) {
        let reply = api_error(
          401, "Unauthenticated", "valid inference authority is required", false,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      let request_body = match
        read_bounded_request_body(
          reader,
          self.global_settings.request_budgets.maximum_request_body_bytes,
        ) {
        RequestBody(value) => value
        RequestBodyTooLarge => {
          let reply = api_error(
            413, "PayloadTooLarge", "request body exceeds the public contract limit",
            false,
          )
          connection.send_response(reply.status, reason(reply.status), extra_headers={
            "Content-Type": reply.content_type,
            "Cache-Control": "no-store",
          })
          connection.write_string(reply.body)
          connection.end_response()
          return
        }
        RequestBodyInvalidUtf8 => {
          let reply = api_error(
            400, "InvalidRequest", "request body is not valid UTF-8", false,
          )
          connection.send_response(reply.status, reason(reply.status), extra_headers={
            "Content-Type": reply.content_type,
            "Cache-Control": "no-store",
          })
          connection.write_string(reply.body)
          connection.end_response()
          return
        }
      }
      if request_body.length() >
        self.global_settings.request_budgets.maximum_request_body_bytes {
        let reply = api_error(
          413, "PayloadTooLarge", "request body exceeds the public contract limit",
          false,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      guard decode_workload(request_body) is Some(workload) else {
        let reply = api_error(
          400, "InvalidRequest", "invalid canonical workload", false,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      if !ephemeral_only(workload) {
        let reply = api_error(
          503, "RetentionUnavailable", "this deployment has no configured encrypted retention provider",
          false,
        )
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      let (workspace_error, reserved) = self.workspace_admit(
        request.headers,
        workload,
        allow_asserted_subject,
      )
      if workspace_error is Some(reply) {
        connection.send_response(reply.status, reason(reply.status), extra_headers={
          "Content-Type": reply.content_type,
          "Cache-Control": "no-store",
        })
        connection.write_string(reply.body)
        connection.end_response()
        return
      }
      try self.stream_workload(workload, connection) catch {
        error => {
          self.release_workspace_admission(workload, reserved)
          raise error
        }
      } noraise {
        _ => self.release_workspace_admission(workload, reserved)
      }
      return
    }
    guard api_method(request.meth) is Some(verb) else {
      connection.send_response(405, "Method Not Allowed")
      return
    }
    let body = match verb {
      Post | Put =>
        match
          read_bounded_request_body(
            reader,
            self.global_settings.request_budgets.maximum_request_body_bytes,
          ) {
          RequestBody(value) => value
          RequestBodyTooLarge => {
            let reply = api_error(
              413, "PayloadTooLarge", "request body exceeds the public contract limit",
              false,
            )
            connection.send_response(reply.status, reason(reply.status), extra_headers={
              "Content-Type": reply.content_type,
              "Cache-Control": "no-store",
            })
            connection.write_string(reply.body)
            connection.end_response()
            return
          }
          RequestBodyInvalidUtf8 => {
            let reply = api_error(
              400, "InvalidRequest", "request body is not valid UTF-8", false,
            )
            connection.send_response(reply.status, reason(reply.status), extra_headers={
              "Content-Type": reply.content_type,
              "Cache-Control": "no-store",
            })
            connection.write_string(reply.body)
            connection.end_response()
            return
          }
        }
      _ => ""
    }
    let reply = self.handle_with_transport(
      verb,
      request.path,
      request.headers,
      body,
      allow_asserted_subject,
    )
    connection.send_response(reply.status, reason(reply.status), extra_headers={
      "Content-Type": reply.content_type,
      "Cache-Control": "no-store",
    })
    connection.write_string(reply.body)
    connection.end_response()
  })
}

///|
pub async fn ApiService::serve(self : ApiService, address : String) -> Unit {
  let server = @http.Server(@socket.Addr::parse(address), reuse_addr=true)
  self.serve_on(server)
}
