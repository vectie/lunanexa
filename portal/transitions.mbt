///|
pub fn PortalAgreement::request_signature(
  self : PortalAgreement,
  signer_subject_ref : String,
  signature_request_receipt : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> PortalAgreement raise PortalError {
  if self.generation != expected_generation {
    raise StaleGeneration
  }
  if self.state != ReviewRequired {
    raise InvalidTransition("agreement is not awaiting review")
  }
  if !@contracts.valid_identifier(signer_subject_ref) ||
    !@contracts.valid_identifier(signature_request_receipt, maximum_length=512) ||
    now_unix_ms < self.updated_unix_ms {
    raise InvalidInput("invalid signature request evidence")
  }
  {
    ..self,
    state: SignatureRequested,
    generation: self.generation + 1L,
    signer_subject_ref: Some(signer_subject_ref),
    signature_request_receipt: Some(signature_request_receipt),
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn PortalAgreement::record_execution(
  self : PortalAgreement,
  execution : AgreementExecution,
  now_unix_ms : Int64,
) -> PortalAgreement raise PortalError {
  if self.agreement_id != execution.agreement_id ||
    self.generation != execution.expected_generation {
    raise StaleGeneration
  }
  if self.state != SignatureRequested ||
    self.signer_subject_ref != Some(execution.signer_subject_ref) {
    raise InvalidTransition("signature execution does not match the request")
  }
  if !@contracts.valid_identifier(
      execution.executed_artifact_hash,
      maximum_length=512,
    ) ||
    !@contracts.valid_identifier(execution.evidence_receipt, maximum_length=512) ||
    now_unix_ms < self.updated_unix_ms {
    raise InvalidInput("invalid executed agreement evidence")
  }
  {
    ..self,
    state: Executed,
    generation: self.generation + 1L,
    executed_artifact_hash: Some(execution.executed_artifact_hash),
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn EnterpriseLeaseRequest::review(
  self : EnterpriseLeaseRequest,
  review : LeaseReview,
  exclusive_lease_id : String?,
  now_unix_ms : Int64,
) -> EnterpriseLeaseRequest raise PortalError {
  if self.submission.request_id != review.request_id {
    raise InvalidInput("lease review targets the wrong request")
  }
  if self.generation != review.expected_generation {
    raise StaleGeneration
  }
  if self.state != Submitted {
    raise InvalidTransition("lease request is no longer pending")
  }
  if !@contracts.valid_identifier(review.evidence_receipt, maximum_length=512) ||
    now_unix_ms < self.updated_unix_ms {
    raise InvalidInput("invalid lease review evidence")
  }
  match review.decision {
    Approve => {
      guard review.node_id is Some(node_id) &&
        exclusive_lease_id is Some(lease_id) &&
        @contracts.valid_identifier(node_id, maximum_length=128) &&
        @contracts.valid_identifier(lease_id) else {
        raise InvalidInput("approval requires a node and exclusive lease")
      }
      {
        ..self,
        state: Approved,
        generation: self.generation + 1L,
        assigned_node_id: Some(node_id),
        exclusive_lease_id: Some(lease_id),
        decision_receipt: Some(review.evidence_receipt),
        updated_unix_ms: now_unix_ms,
      }
    }
    Reject => {
      if review.node_id is Some(_) || exclusive_lease_id is Some(_) {
        raise InvalidInput("rejection cannot assign a node")
      }
      {
        ..self,
        state: Rejected,
        generation: self.generation + 1L,
        decision_receipt: Some(review.evidence_receipt),
        updated_unix_ms: now_unix_ms,
      }
    }
  }
}
