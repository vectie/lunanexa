///|
pub(all) enum OperatorCommand {
  EnrollNode
  RegisterModel
  VerifyModel
  EvaluateModel
  ApproveModel
  DeployModel
  MarkReady
  InvokeRequest
  CompleteRequest
  DrainNode
  ObserveReroute
  RollbackModel
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror WorkflowError {
  InvalidSequence(OperatorCommand)
} derive(Debug, Eq)

///|
pub(all) struct OperatorWorkflow {
  node_state : @contracts.NodeState
  model_state : @contracts.ModelState
  deployment_state : @contracts.DeploymentState
  workload_state : @contracts.WorkloadState
  rerouted : Bool
  receipts : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn OperatorWorkflow::initial() -> OperatorWorkflow {
  {
    node_state: Enrolling,
    model_state: Candidate,
    deployment_state: Pending,
    workload_state: Submitted,
    rerouted: false,
    receipts: [],
  }
}

///|
pub fn OperatorWorkflow::apply(
  self : OperatorWorkflow,
  command : OperatorCommand,
) -> OperatorWorkflow raise WorkflowError {
  let mut next = self
  match command {
    EnrollNode if self.node_state == Enrolling =>
      next = { ..self, node_state: Active }
    RegisterModel if self.model_state == Candidate => ()
    VerifyModel if self.model_state == Candidate =>
      next = { ..self, model_state: Verified }
    EvaluateModel if self.model_state == Verified =>
      next = { ..self, model_state: Evaluated }
    ApproveModel if self.model_state == Evaluated =>
      next = { ..self, model_state: Approved }
    DeployModel if self.model_state == Approved && self.node_state == Active =>
      next = { ..self, deployment_state: Preparing }
    MarkReady if self.deployment_state == Preparing =>
      next = { ..self, deployment_state: Ready }
    InvokeRequest if self.deployment_state == Ready =>
      next = { ..self, workload_state: Running }
    CompleteRequest if self.workload_state == Running =>
      next = { ..self, workload_state: Succeeded }
    DrainNode if self.node_state == Active =>
      next = { ..self, node_state: Draining, deployment_state: Draining }
    ObserveReroute if self.node_state == Draining =>
      next = { ..self, rerouted: true }
    RollbackModel if self.model_state == Approved => ()
    _ => raise InvalidSequence(command)
  }
  let receipt = "ui:\{next.receipts.length() + 1}:\{to_repr(command)}"
  { ..next, receipts: next.receipts + [receipt] }
}
