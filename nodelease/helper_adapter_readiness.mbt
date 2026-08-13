///|
pub let helper_adapter_readiness_contract_version : String = "lunanexa.machine-helper-adapter-readiness.v1"

///|
/// Retained evidence that a deployment-owned privileged helper adapter was
/// exercised on the declared node scope. Repository code or a socket path alone
/// is never treated as proof that privileged lifecycle actions work.
pub(all) struct MachineHelperAdapterReadinessEvidence {
  version : String
  adapter_id : String
  node_scope : String
  covered_node_ids : Array[String]
  evidence_ref : String
  checked_unix_ms : Int64
  expires_unix_ms : Int64
  provision_verified : Bool
  revoke_verified : Bool
  sanitize_verified : Bool
  quarantine_verified : Bool
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn machine_helper_adapter_evidence_ready(
  evidence : MachineHelperAdapterReadinessEvidence,
  now_unix_ms : Int64,
) -> Bool {
  let covered : Map[String, Unit] = Map([])
  for node_id in evidence.covered_node_ids {
    if !@contracts.valid_identifier(node_id, maximum_length=128) ||
      covered.contains(node_id) {
      return false
    }
    covered[node_id] = ()
  }
  evidence.version == helper_adapter_readiness_contract_version &&
  @contracts.valid_identifier(evidence.adapter_id, maximum_length=128) &&
  @contracts.valid_identifier(evidence.node_scope, maximum_length=128) &&
  @contracts.valid_identifier(evidence.evidence_ref, maximum_length=256) &&
  evidence.covered_node_ids.length() > 0 &&
  evidence.covered_node_ids.length() <= 1024 &&
  evidence.checked_unix_ms > 0L &&
  evidence.expires_unix_ms > evidence.checked_unix_ms &&
  evidence.expires_unix_ms - evidence.checked_unix_ms <= 86400000L &&
  now_unix_ms >= evidence.checked_unix_ms &&
  now_unix_ms < evidence.expires_unix_ms &&
  evidence.provision_verified &&
  evidence.revoke_verified &&
  evidence.sanitize_verified &&
  evidence.quarantine_verified &&
  evidence.signature.length() == 64 &&
  evidence.signature.all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
fn machine_helper_adapter_material(
  evidence : MachineHelperAdapterReadinessEvidence,
) -> String {
  { ..evidence, signature: "" }.to_json().stringify()
}

///|
pub fn machine_helper_adapter_signature(
  evidence : MachineHelperAdapterReadinessEvidence,
  secret : String,
) -> String {
  if secret.length() < 32 || secret.length() > 4096 {
    return ""
  }
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(machine_helper_adapter_material(evidence)).view(),
    ),
  )
}

///|
pub fn valid_machine_helper_adapter_evidence_signature(
  evidence : MachineHelperAdapterReadinessEvidence,
  secret : String,
) -> Bool {
  let expected = machine_helper_adapter_signature(evidence, secret)
  if expected.length() != evidence.signature.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<expected.length() {
    difference = difference |
      (expected[index].to_int() ^ evidence.signature[index].to_int())
  }
  difference == 0
}
