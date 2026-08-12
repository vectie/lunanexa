///|
pub(all) enum RejectionReason {
  NoHealthyNode
  ArchitectureMismatch
  InsufficientMemory
  RuntimeUnsupported
  RuntimeNotReady
  LicenseDenied
  DataClassDenied
  QuotaExceeded
  AdmissionCapacityExceeded
  DeadlineImpossible
  WorkloadAlreadyActive
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeSnapshot {
  node_id : String
  state : @contracts.NodeState
  architecture : String
  memory_free_mib : Int
  runtimes : Array[String]
  licensed_models : Array[String]
  ready_models : Array[String]
  allowed_data_classes : Array[@contracts.DataClass]
  warm_models : Array[String]
  queue_depth : Int
  reliability_per_mille : Int
  accelerator_utilization_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlacementRequirements {
  workload_id : String
  model_key : String
  architecture : String
  memory_mib : Int
  runtime : String
  data_class : @contracts.DataClass
  deadline_unix_ms : Int64
  now_unix_ms : Int64
  estimated_runtime_ms : Int64
  multi_node : Bool
  topology_profile : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ScorePolicy {
  version : String
  warm_model_weight : Int
  headroom_weight : Int
  queue_weight : Int
  reliability_weight : Int
  utilization_weight : Int
  validated_topology_profiles : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CandidateScore {
  node_id : String
  total : Int
  warm_model : Int
  headroom : Int
  queue : Int
  reliability : Int
  utilization : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RejectedNode {
  node_id : String
  reasons : Array[RejectionReason]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlacementDecision {
  workload_id : String
  policy_version : String
  selected_node_id : String?
  candidates : Array[CandidateScore]
  rejected : Array[RejectedNode]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn contains_string(values : Array[String], expected : String) -> Bool {
  values.any(value => value == expected)
}

///|
fn rejection_reasons(
  node : NodeSnapshot,
  requirements : PlacementRequirements,
  policy : ScorePolicy,
) -> Array[RejectionReason] {
  let reasons : Array[RejectionReason] = []
  if node.state != Active {
    reasons.push(NoHealthyNode)
  }
  if node.architecture != requirements.architecture {
    reasons.push(ArchitectureMismatch)
  }
  if node.memory_free_mib < requirements.memory_mib {
    reasons.push(InsufficientMemory)
  }
  if !contains_string(node.runtimes, requirements.runtime) {
    reasons.push(RuntimeUnsupported)
  }
  if !contains_string(node.licensed_models, requirements.model_key) {
    reasons.push(LicenseDenied)
  }
  if !contains_string(node.ready_models, requirements.model_key) {
    reasons.push(RuntimeNotReady)
  }
  if !node.allowed_data_classes.any(value => value == requirements.data_class) {
    reasons.push(DataClassDenied)
  }
  if requirements.now_unix_ms + requirements.estimated_runtime_ms >
    requirements.deadline_unix_ms {
    reasons.push(DeadlineImpossible)
  }
  if requirements.multi_node &&
    (
      requirements.topology_profile is None ||
      (
        requirements.topology_profile is Some(profile) &&
        !contains_string(policy.validated_topology_profiles, profile)
      )
    ) {
    reasons.push(RuntimeUnsupported)
  }
  reasons
}

///|
fn score_node(
  node : NodeSnapshot,
  requirements : PlacementRequirements,
  policy : ScorePolicy,
) -> CandidateScore {
  let warm = if contains_string(node.warm_models, requirements.model_key) {
    1
  } else {
    0
  }
  let headroom = node.memory_free_mib - requirements.memory_mib
  let queue = 1000 - node.queue_depth.clamp(min=0, max=1000)
  let reliability = node.reliability_per_mille.clamp(min=0, max=1000)
  let utilization = 1000 -
    node.accelerator_utilization_per_mille.clamp(min=0, max=1000)
  {
    node_id: node.node_id,
    total: warm * policy.warm_model_weight +
    headroom * policy.headroom_weight +
    queue * policy.queue_weight +
    reliability * policy.reliability_weight +
    utilization * policy.utilization_weight,
    warm_model: warm,
    headroom,
    queue,
    reliability,
    utilization,
  }
}

///|
pub fn place(
  nodes : Array[NodeSnapshot],
  requirements : PlacementRequirements,
  policy : ScorePolicy,
) -> PlacementDecision {
  let candidates : Array[CandidateScore] = []
  let rejected : Array[RejectedNode] = []
  for node in nodes {
    let reasons = rejection_reasons(node, requirements, policy)
    if reasons.length() == 0 {
      candidates.push(score_node(node, requirements, policy))
    } else {
      rejected.push({ node_id: node.node_id, reasons })
    }
  }
  candidates.sort_by((left, right) => {
    let by_score = right.total.compare(left.total)
    if by_score != 0 {
      by_score
    } else {
      left.node_id.compare(right.node_id)
    }
  })
  rejected.sort_by_key(item => item.node_id)
  {
    workload_id: requirements.workload_id,
    policy_version: policy.version,
    selected_node_id: candidates.get(0).map(item => item.node_id),
    candidates,
    rejected,
  }
}

///|
pub(all) struct TenantQuota {
  tenant_ref : String
  max_inflight : Int
  max_accelerator_ms : Int64
  window_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AdmissionResult {
  Accepted(queue_position~ : Int)
  Rejected(reason~ : RejectionReason)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn priority_capacity_limit(
  capacity : Int,
  priority : @contracts.Priority,
) -> Int {
  let bounded = capacity.max(1)
  match priority {
    Background => (bounded * 3 / 4).max(1)
    Normal => (bounded * 9 / 10).max(1)
    Interactive | Critical => bounded
  }
}

///|
pub fn priority_capacity_limit_with_policy(
  capacity : Int,
  priority : @contracts.Priority,
  background_percent : Int,
  normal_percent : Int,
) -> Int {
  let bounded = capacity.max(1)
  match priority {
    Background => (bounded * background_percent / 100).max(1)
    Normal => (bounded * normal_percent / 100).max(1)
    Interactive | Critical => bounded
  }
}

///|
pub struct AdmissionController {
  quotas : Map[String, TenantQuota]
  inflight : Map[String, Int]
  accelerator_ms : Map[String, Int64]
  window_started_unix_ms : Map[String, Int64]
  cancelled : Map[String, Bool]
  mut queue_depth : Int
  capacity : Int
}

///|
pub fn AdmissionController::new(capacity : Int) -> AdmissionController {
  {
    quotas: Map([]),
    inflight: Map([]),
    accelerator_ms: Map([]),
    window_started_unix_ms: Map([]),
    cancelled: Map([]),
    queue_depth: 0,
    capacity,
  }
}

///|
pub fn AdmissionController::set_quota(
  self : AdmissionController,
  quota : TenantQuota,
) -> Unit {
  self.quotas[quota.tenant_ref] = quota
}

///|
pub fn AdmissionController::admit(
  self : AdmissionController,
  request : @contracts.WorkloadEnvelope,
  now_unix_ms : Int64,
) -> AdmissionResult {
  if request.deadline_unix_ms <= now_unix_ms {
    return Rejected(reason=DeadlineImpossible)
  }
  guard self.quotas.get(request.tenant_ref) is Some(quota) else {
    return Rejected(reason=QuotaExceeded)
  }
  let inflight = self.inflight.get(request.tenant_ref).unwrap_or(0)
  let window_started = self.window_started_unix_ms
    .get(request.tenant_ref)
    .unwrap_or(now_unix_ms)
  if now_unix_ms >= window_started + quota.window_ms {
    self.accelerator_ms[request.tenant_ref] = 0L
    self.window_started_unix_ms[request.tenant_ref] = now_unix_ms
  } else if !self.window_started_unix_ms.contains(request.tenant_ref) {
    self.window_started_unix_ms[request.tenant_ref] = now_unix_ms
  }
  let used = self.accelerator_ms.get(request.tenant_ref).unwrap_or(0L)
  if inflight >= quota.max_inflight || used >= quota.max_accelerator_ms {
    return Rejected(reason=QuotaExceeded)
  }
  if self.queue_depth >=
    priority_capacity_limit(self.capacity, request.priority) {
    return Rejected(reason=AdmissionCapacityExceeded)
  }
  self.inflight[request.tenant_ref] = inflight + 1
  let position = self.queue_depth
  self.queue_depth += 1
  Accepted(queue_position=position)
}

///|
pub fn AdmissionController::cancel(
  self : AdmissionController,
  workload_id : String,
) -> Unit {
  self.cancelled[workload_id] = true
}

///|
pub fn AdmissionController::is_cancelled(
  self : AdmissionController,
  workload_id : String,
) -> Bool {
  self.cancelled.get(workload_id).unwrap_or(false)
}

///|
pub fn AdmissionController::complete(
  self : AdmissionController,
  tenant_ref : String,
  accelerator_ms : Int64,
) -> Unit {
  let inflight = self.inflight.get(tenant_ref).unwrap_or(0)
  self.inflight[tenant_ref] = (inflight - 1).max(0)
  self.accelerator_ms[tenant_ref] = self.accelerator_ms
    .get(tenant_ref)
    .unwrap_or(0L) +
    accelerator_ms
  self.queue_depth = (self.queue_depth - 1).max(0)
}

///|
pub fn retry_allowed(
  idempotency_key : String,
  attempt : Int,
  max_attempts : Int,
  before_first_output : Bool,
) -> Bool {
  idempotency_key != "" && attempt < max_attempts && before_first_output
}

///|
pub(all) struct CapacityForecast {
  schedulable_nodes : Int
  total_free_memory_mib : Int
  estimated_additional_instances : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn forecast(
  nodes : Array[NodeSnapshot],
  instance_memory_mib : Int,
) -> CapacityForecast {
  let mut schedulable_nodes = 0
  let mut total = 0
  for node in nodes {
    if node.state == Active {
      schedulable_nodes += 1
      total += node.memory_free_mib
    }
  }
  {
    schedulable_nodes,
    total_free_memory_mib: total,
    estimated_additional_instances: if instance_memory_mib <= 0 {
      0
    } else {
      total / instance_memory_mib
    },
  }
}
