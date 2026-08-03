///|
pub(all) enum Role {
  Administrator
  Operator
  Auditor
  InferenceCaller
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Permission {
  EnrollNode
  ManageModel
  ManageDeployment
  ChangePolicy
  ReadAudit
  InvokeModel
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn authorized(role : Role, permission : Permission) -> Bool {
  match (role, permission) {
    (Administrator, _) => true
    (Operator, EnrollNode | ManageModel | ManageDeployment) => true
    (Auditor, ReadAudit) => true
    (InferenceCaller, InvokeModel) => true
    _ => false
  }
}

///|
pub(all) struct SecretReference {
  name : String
  version : Int64
  provider_ref : String
  rotated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn SecretReference::rotate(
  self : SecretReference,
  provider_ref : String,
  now_unix_ms : Int64,
) -> SecretReference {
  {
    ..self,
    version: self.version + 1L,
    provider_ref,
    rotated_unix_ms: now_unix_ms,
  }
}

///|
pub(all) struct SignedSubject {
  digest : String
  signer : String
  signature_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TrustPolicy {
  allowed_signers : Array[String]
  require_sha256 : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn trusted(subject : SignedSubject, policy : TrustPolicy) -> Bool {
  (!policy.require_sha256 || @contracts.valid_sha256_digest(subject.digest)) &&
  subject.signature_ref != "" &&
  policy.allowed_signers.any(signer => signer == subject.signer)
}

///|
pub fn strict_runtime_network_policy() -> @contracts.NetworkPolicy {
  { allow_controller: true, allow_artifact_store: true, allowed_egress: [] }
}

///|
pub(all) struct RequestLog {
  workload_id : String
  tenant_ref : String
  capability : @contracts.Capability
  model_selector : String
  classification : @contracts.DataClass
  trace_token : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn redacted_request_log(
  request : @contracts.WorkloadEnvelope,
) -> RequestLog {
  {
    workload_id: request.workload_id,
    tenant_ref: request.tenant_ref,
    capability: request.capability,
    model_selector: request.model_selector,
    classification: request.data_policy.classification,
    trace_token: request.trace_token,
  }
}

///|
pub(all) struct RetentionRecord {
  workload_id : String
  expires_unix_ms : Int64
  consent_receipt : String
  encrypted_object_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeletionReceipt {
  workload_id : String
  deleted_unix_ms : Int64
  object_ref_hash : String
  policy_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror RetentionError {
  RetentionNotPermitted
  ConsentRequired
} derive(Debug, Eq)

///|
pub struct RetentionLedger {
  records : Map[String, RetentionRecord]
  receipts : Array[DeletionReceipt]
}

///|
pub fn RetentionLedger::new() -> RetentionLedger {
  { records: Map([]), receipts: [] }
}

///|
pub fn RetentionLedger::retain(
  self : RetentionLedger,
  workload_id : String,
  policy : @contracts.RetentionPolicy,
  encrypted_object_ref : String,
) -> Unit raise RetentionError {
  match policy {
    Ephemeral => raise RetentionNotPermitted
    RetainUntil(expiry) =>
      self.records[workload_id] = {
        workload_id,
        expires_unix_ms: expiry,
        consent_receipt: "retention-policy",
        encrypted_object_ref,
      }
    EvaluationCapture(consent_receipt="") => raise ConsentRequired
    EvaluationCapture(consent_receipt~) =>
      self.records[workload_id] = {
        workload_id,
        expires_unix_ms: 0L,
        consent_receipt,
        encrypted_object_ref,
      }
  }
}

///|
pub fn RetentionLedger::expire(
  self : RetentionLedger,
  now_unix_ms : Int64,
) -> Array[DeletionReceipt] {
  let expired = [
    for workload_id, record in self.records if record.expires_unix_ms > 0L &&
    record.expires_unix_ms <= now_unix_ms => workload_id
  ]
  let created : Array[DeletionReceipt] = []
  for workload_id in expired {
    let record = self.records[workload_id]
    let object_ref_hash = @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(record.encrypted_object_ref)),
    )
    let receipt : DeletionReceipt = {
      workload_id,
      deleted_unix_ms: now_unix_ms,
      object_ref_hash: "sha256:\{object_ref_hash}",
      policy_receipt: record.consent_receipt,
    }
    ignore(self.records.remove(workload_id))
    self.receipts.push(receipt)
    created.push(receipt)
  }
  created
}

///|
pub fn RetentionLedger::active_count(self : RetentionLedger) -> Int {
  self.records.length()
}

///|
pub fn RetentionLedger::deletion_receipts(
  self : RetentionLedger,
) -> Array[DeletionReceipt] {
  self.receipts.copy()
}
