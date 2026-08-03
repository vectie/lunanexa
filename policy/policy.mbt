///|
pub fn permits_training(policy : @contracts.DataPolicy) -> Bool {
  policy.allow_training_reuse && policy.retention is EvaluationCapture(_)
}
