///|
/// One deployment-approved authority identifier for one fixed promotion
/// subject. This policy is inert input; it cannot mint routing authority.
pub(all) struct LunaFluxPromotionVerifierAuthority {
  subject : LunaFluxPromotionAuthoritySubject
  authority_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LunaFluxPromotionVerifierAuthority with Debug::{to_repr}

///|
pub extend LunaFluxPromotionVerifierAuthority with Eq::{not_equal, equal}

///|
pub extend LunaFluxPromotionVerifierAuthority with ToJson::{to_json}

///|
pub extend LunaFluxPromotionVerifierAuthority with FromJson::{from_json}

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
pub extend LunaFluxPromotionVerifierPolicy with Debug::{to_repr}

///|
pub extend LunaFluxPromotionVerifierPolicy with Eq::{not_equal, equal}

///|
pub extend LunaFluxPromotionVerifierPolicy with ToJson::{to_json}

///|
pub extend LunaFluxPromotionVerifierPolicy with FromJson::{from_json}

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
pub extend LunaFluxSignedEvidenceApproval with Debug::{to_repr}

///|
pub extend LunaFluxSignedEvidenceApproval with Eq::{not_equal, equal}

///|
pub extend LunaFluxSignedEvidenceApproval with ToJson::{to_json}

///|
pub extend LunaFluxSignedEvidenceApproval with FromJson::{from_json}

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
pub extend LunaFluxPromotionVerifierError with Debug::{to_repr}

///|
pub extend LunaFluxPromotionVerifierError with Eq::{not_equal, equal}

///|
/// Opaque rollout-scoped verifier. It is deliberately nonserializable and
/// retains a private mutable copy of deployment-injected key bytes so `close`
/// can wipe them deterministically.
pub struct LunaFluxPromotionVerifier {
  priv policy : LunaFluxPromotionVerifierPolicy
  priv key_bytes : FixedArray[Byte]
  priv mut closed : Bool
}
