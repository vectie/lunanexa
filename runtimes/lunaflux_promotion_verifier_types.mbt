///|
/// One deployment-approved authority identifier for one fixed promotion
/// subject. This policy is inert input; it cannot mint routing authority.
pub(all) struct LunaFluxPromotionVerifierAuthority {
  subject : LunaFluxPromotionAuthoritySubject
  authority_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Public non-secret policy for one rollout-scoped verifier. The constructor
/// independently copies and validates this policy before accepting key bytes.
pub(all) struct LunaFluxPromotionVerifierPolicy {
  schema_version : String
  rollout_digest : String
  verifier_key_id : String
  authorities : Array[LunaFluxPromotionVerifierAuthority]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Caller-constructible signed evidence remains inert until an opaque verifier
/// authenticates all ten fixed subjects against its deployment-owned policy.
pub(all) struct LunaFluxSignedEvidenceApproval {
  schema_version : String
  subject : LunaFluxPromotionAuthoritySubject
  rollout_digest : String
  evidence_digest : String
  approval_receipt_digest : String
  authority_id : String
  verifier_key_id : String
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror LunaFluxPromotionVerifierError {
  UnsupportedPromotionVerifierPolicySchema
  InvalidPromotionVerifierRolloutDigest
  InvalidPromotionVerifierKeyId
  InvalidPromotionVerifierSecret
  InvalidPromotionVerifierAuthorityCount(Int)
  MissingPromotionVerifierAuthority(LunaFluxPromotionAuthoritySubject)
  DuplicatePromotionVerifierAuthority(LunaFluxPromotionAuthoritySubject)
  InvalidPromotionVerifierAuthority(LunaFluxPromotionAuthoritySubject)
} derive(Debug, Eq)

///|
/// Opaque rollout-scoped verifier. It is deliberately nonserializable and
/// retains a private mutable copy of deployment-injected key bytes so `close`
/// can wipe them deterministically.
pub struct LunaFluxPromotionVerifier {
  priv policy : LunaFluxPromotionVerifierPolicy
  priv key_bytes : FixedArray[Byte]
  priv mut closed : Bool
}
