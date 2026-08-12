///|
pub fn health(version : String) -> @contracts.HealthResponse {
  @contracts.health("node", version)
}

///|
pub(all) suberror NodeError {
  InvalidBootstrapToken
  BootstrapTokenExpired
  AssignmentSignatureInvalid
  StaleControllerEpoch
  StaleGeneration
  LeaseExpired
  InvalidCertificateLifetime
  InvalidStateSchema
} derive(Debug, Eq)

///|
pub(all) struct BootstrapToken {
  token_id : String
  secret : String
  expires_unix_ms : Int64
  used : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeCertificate {
  node_id : String
  serial : Int64
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  public_key_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeAuthority {
  node_id : String
  secret_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct EnrollmentService {
  tokens : Map[String, BootstrapToken]
  certificates : Map[String, NodeCertificate]
  authorities : Map[String, NodeAuthority]
}

///|
pub(all) struct EnrollmentSnapshot {
  schema_version : String
  tokens : Array[BootstrapToken]
  certificates : Array[NodeCertificate]
  authorities : Array[NodeAuthority]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn secret_digest(secret : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(secret)))
}

///|
pub fn EnrollmentService::new() -> EnrollmentService {
  { tokens: Map([]), certificates: Map([]), authorities: Map([]) }
}

///|
pub fn EnrollmentService::issue_token(
  self : EnrollmentService,
  token_id : String,
  secret : String,
  expires_unix_ms : Int64,
) -> BootstrapToken {
  let stored : BootstrapToken = {
    token_id,
    secret: secret_digest(secret),
    expires_unix_ms,
    used: false,
  }
  self.tokens[token_id] = stored
  { ..stored, secret, }
}

///|
pub fn EnrollmentService::enroll(
  self : EnrollmentService,
  node_id : String,
  token_id : String,
  secret : String,
  node_auth_secret : String,
  public_key_ref : String,
  now_unix_ms : Int64,
  certificate_lifetime_ms? : Int64 = 3600000L,
) -> NodeCertificate raise NodeError {
  if certificate_lifetime_ms <= 0L || certificate_lifetime_ms > 86400000L {
    raise InvalidCertificateLifetime
  }
  guard self.tokens.get(token_id) is Some(token) else {
    raise InvalidBootstrapToken
  }
  if token.used || token.secret != secret_digest(secret) {
    raise InvalidBootstrapToken
  }
  if token.expires_unix_ms <= now_unix_ms {
    raise BootstrapTokenExpired
  }
  if node_auth_secret == "" {
    raise InvalidBootstrapToken
  }
  self.tokens[token_id] = { ..token, used: true }
  let certificate : NodeCertificate = {
    node_id,
    serial: 1L,
    issued_unix_ms: now_unix_ms,
    expires_unix_ms: now_unix_ms + certificate_lifetime_ms,
    public_key_ref,
  }
  self.certificates[node_id] = certificate
  self.authorities[node_id] = {
    node_id,
    secret_digest: secret_digest(node_auth_secret),
  }
  certificate
}

///|
pub fn EnrollmentService::snapshot(self : EnrollmentService) -> String {
  let value : EnrollmentSnapshot = {
    schema_version: "lunanexa.enrollment.v2",
    tokens: [
      for _, token in self.tokens => token
    ],
    certificates: [
      for _, certificate in self.certificates => certificate
    ],
    authorities: [
      for _, authority in self.authorities => authority
    ],
  }
  value.to_json().stringify()
}

///|
pub fn EnrollmentService::restore(snapshot : String) -> EnrollmentService raise {
  let value : EnrollmentSnapshot = @json.from_json(@json.parse(snapshot))
  if value.schema_version != "lunanexa.enrollment.v2" {
    raise Failure::Failure("unsupported enrollment schema")
  }
  let service = EnrollmentService::new()
  for token in value.tokens {
    service.tokens[token.token_id] = token
  }
  for certificate in value.certificates {
    service.certificates[certificate.node_id] = certificate
  }
  for authority in value.authorities {
    service.authorities[authority.node_id] = authority
  }
  service
}

///|
pub fn EnrollmentService::authorized(
  self : EnrollmentService,
  node_id : String,
  secret : String,
  now_unix_ms : Int64,
) -> Bool {
  self.authorities.get(node_id) is Some(authority) &&
  authority.secret_digest == secret_digest(secret) &&
  self.certificates.get(node_id) is Some(certificate) &&
  certificate.expires_unix_ms > now_unix_ms
}

///|
pub fn EnrollmentService::rotate(
  self : EnrollmentService,
  node_id : String,
  public_key_ref : String,
  now_unix_ms : Int64,
  certificate_lifetime_ms? : Int64 = 3600000L,
) -> NodeCertificate raise NodeError {
  if certificate_lifetime_ms <= 0L || certificate_lifetime_ms > 86400000L {
    raise InvalidCertificateLifetime
  }
  guard self.certificates.get(node_id) is Some(current) else {
    raise InvalidBootstrapToken
  }
  let certificate : NodeCertificate = {
    node_id,
    serial: current.serial + 1L,
    issued_unix_ms: now_unix_ms,
    expires_unix_ms: now_unix_ms + certificate_lifetime_ms,
    public_key_ref,
  }
  self.certificates[node_id] = certificate
  certificate
}

///|
pub(open) trait AssignmentVerifier {
  fn verify(Self, @contracts.DesiredAssignment) -> Bool
}

///|
pub struct TestAssignmentVerifier {
  expected_signature : String
}

///|
pub struct SharedSecretAssignmentVerifier {
  secret : String
}

///|
pub fn SharedSecretAssignmentVerifier::new(
  secret : String,
) -> SharedSecretAssignmentVerifier {
  { secret, }
}

///|
pub fn assignment_signature(
  assignment : @contracts.DesiredAssignment,
  secret : String,
) -> String {
  let unsigned = { ..assignment, signature: "" }
  let key = @utf8.encode(secret)
  let material = @utf8.encode(
    "lunanexa.assignment-mac.v1|\{unsigned.to_json().stringify()}",
  )
  @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()),
  )
}

///|
pub fn heartbeat_signature(
  heartbeat : @contracts.NodeHeartbeat,
  secret : String,
) -> String {
  let unsigned = { ..heartbeat, signature: "" }
  let key = @utf8.encode(secret)
  let material = @utf8.encode(
    "lunanexa.heartbeat-mac.v1|\{unsigned.to_json().stringify()}",
  )
  @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()),
  )
}

///|
pub impl AssignmentVerifier for SharedSecretAssignmentVerifier with fn verify(
  self,
  assignment,
) {
  self.secret != "" &&
  assignment.signature == assignment_signature(assignment, self.secret)
}

///|
pub fn TestAssignmentVerifier::new(
  expected_signature : String,
) -> TestAssignmentVerifier {
  { expected_signature, }
}

///|
pub impl AssignmentVerifier for TestAssignmentVerifier with fn verify(
  self,
  assignment,
) {
  assignment.signature == self.expected_signature
}

///|
pub struct NodeAgent {
  node_id : String
  mut controller_epoch : Int64
  mut observed_generation : Int64
  mut state : @contracts.NodeState
  assignments : Map[String, @contracts.DesiredAssignment]
  ready_assignments : Map[String, Bool]
  mut directive_generation : Int64
}

///|
pub(all) struct NodeAgentSnapshot {
  schema_version : String
  node_id : String
  controller_epoch : Int64
  observed_generation : Int64
  state : @contracts.NodeState
  assignments : Array[@contracts.DesiredAssignment]
  ready_assignment_ids : Array[String]?
  directive_generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn NodeAgent::new(node_id : String) -> NodeAgent {
  {
    node_id,
    controller_epoch: 0L,
    observed_generation: 0L,
    state: Enrolling,
    assignments: Map([]),
    ready_assignments: Map([]),
    directive_generation: 0L,
  }
}

///|
pub fn NodeAgent::activate(self : NodeAgent) -> Unit {
  self.state = Active
}

///|
pub fn NodeAgent::cordon(self : NodeAgent) -> Unit {
  self.state = Cordoned
}

///|
pub fn NodeAgent::drain(self : NodeAgent) -> Unit {
  self.state = Draining
}

///|
pub fn NodeAgent::state(self : NodeAgent) -> @contracts.NodeState {
  self.state
}

///|
pub fn NodeAgent::assignment_count(self : NodeAgent) -> Int {
  self.assignments.length()
}

///|
pub fn NodeAgent::observed_generation(self : NodeAgent) -> Int64 {
  self.observed_generation
}

///|
pub fn NodeAgent::controller_epoch(self : NodeAgent) -> Int64 {
  self.controller_epoch
}

///|
pub fn NodeAgent::running_deployments(self : NodeAgent) -> Array[String] {
  [
    for assignment_id, assignment in self.assignments if self.ready_assignments
    .get(assignment_id)
    .unwrap_or(false) => assignment.deployment_id
  ]
}

///|
pub fn NodeAgent::observe_runtime(
  self : NodeAgent,
  assignment_id : String,
  state : @contracts.DeploymentState,
) -> Unit {
  if self.assignments.contains(assignment_id) {
    self.ready_assignments[assignment_id] = state == Ready
  }
}

///|
pub fn NodeAgent::apply_directive(
  self : NodeAgent,
  directive : @contracts.NodeDirective,
) -> Unit raise NodeError {
  if directive.node_id != self.node_id {
    raise AssignmentSignatureInvalid
  }
  if directive.generation <= self.directive_generation {
    return
  }
  match directive.desired_state {
    Active => self.activate()
    Cordoned => self.cordon()
    Draining => self.drain()
    _ => raise StaleGeneration
  }
  self.directive_generation = directive.generation
}

///|
pub fn NodeAgent::snapshot(self : NodeAgent) -> NodeAgentSnapshot {
  let ready_assignment_ids : Array[String] = []
  for assignment_id, ready in self.ready_assignments {
    if ready {
      ready_assignment_ids.push(assignment_id)
    }
  }
  {
    schema_version: "lunanexa.node-state.v2",
    node_id: self.node_id,
    controller_epoch: self.controller_epoch,
    observed_generation: self.observed_generation,
    state: self.state,
    assignments: [
      for _, assignment in self.assignments => assignment
    ],
    ready_assignment_ids: Some(ready_assignment_ids),
    directive_generation: self.directive_generation,
  }
}

///|
pub fn NodeAgent::from_snapshot(
  snapshot : NodeAgentSnapshot,
) -> NodeAgent raise NodeError {
  if snapshot.schema_version != "lunanexa.node-state.v1" &&
    snapshot.schema_version != "lunanexa.node-state.v2" {
    raise InvalidStateSchema
  }
  let assignments : Map[String, @contracts.DesiredAssignment] = Map([])
  for assignment in snapshot.assignments {
    assignments[assignment.assignment_id] = assignment
  }
  let ready_assignments : Map[String, Bool] = Map([])
  for assignment_id in snapshot.ready_assignment_ids.unwrap_or([]) {
    if assignments.contains(assignment_id) {
      ready_assignments[assignment_id] = true
    }
  }
  {
    node_id: snapshot.node_id,
    controller_epoch: snapshot.controller_epoch,
    observed_generation: snapshot.observed_generation,
    state: snapshot.state,
    assignments,
    ready_assignments,
    directive_generation: snapshot.directive_generation,
  }
}

///|
pub fn NodeAgent::reap_expired(
  self : NodeAgent,
  now_unix_ms : Int64,
) -> Array[String] {
  let expired = [
    for assignment_id, assignment in self.assignments if assignment.lease_expires_unix_ms <=
    now_unix_ms => assignment_id
  ]
  for assignment_id in expired {
    ignore(self.assignments.remove(assignment_id))
    ignore(self.ready_assignments.remove(assignment_id))
  }
  expired
}

///|
pub fn NodeAgent::remove_absent(
  self : NodeAgent,
  desired_assignment_ids : Array[String],
) -> Array[String] {
  let absent = [
    for assignment_id, _ in self.assignments if !desired_assignment_ids.any(desired => {
      desired == assignment_id
    }) => assignment_id
  ]
  for assignment_id in absent {
    ignore(self.assignments.remove(assignment_id))
    ignore(self.ready_assignments.remove(assignment_id))
  }
  absent
}

///|
pub fn[V : AssignmentVerifier] NodeAgent::reconcile(
  self : NodeAgent,
  assignment : @contracts.DesiredAssignment,
  verifier : V,
  now_unix_ms : Int64,
) -> Bool raise NodeError {
  if !AssignmentVerifier::verify(verifier, assignment) {
    raise AssignmentSignatureInvalid
  }
  if assignment.node_id != self.node_id {
    raise AssignmentSignatureInvalid
  }
  if assignment.controller_epoch < self.controller_epoch {
    raise StaleControllerEpoch
  }
  if assignment.generation < self.observed_generation {
    raise StaleGeneration
  }
  if assignment.lease_expires_unix_ms <= now_unix_ms {
    raise LeaseExpired
  }
  if self.state != Active &&
    !self.assignments.contains(assignment.assignment_id) {
    return false
  }
  self.controller_epoch = assignment.controller_epoch
  self.observed_generation = assignment.generation
  self.assignments[assignment.assignment_id] = assignment
  true
}

///|
pub fn[V : AssignmentVerifier] NodeAgent::recover(
  node_id : String,
  assignments : Array[@contracts.DesiredAssignment],
  verifier : V,
  now_unix_ms : Int64,
) -> NodeAgent raise NodeError {
  let agent = NodeAgent::new(node_id)
  agent.activate()
  for assignment in assignments {
    ignore(agent.reconcile(assignment, verifier, now_unix_ms))
  }
  agent
}
