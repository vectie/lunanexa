///|
const LUNAFLUX_PROMOTION_VERIFIER_POLICY_SCHEMA : String = "lunanexa.lunaflux.promotion-verifier-policy.v1"

///|
const LUNAFLUX_SIGNED_PROMOTION_RECEIPT_SCHEMA : String = "lunanexa.lunaflux.signed-promotion-receipt.v1"

///|
const LUNAFLUX_SIGNED_PROMOTION_RECEIPT_DOMAIN : String = "lunanexa.lunaflux.signed-promotion-receipt-hmac-sha256.v1"

///|
fn verifier_authority_for(
  policy : LunaFluxPromotionVerifierPolicy,
  subject : LunaFluxPromotionAuthoritySubject,
) -> String? {
  for authority in policy.authorities {
    if authority.subject == subject {
      return Some(authority.authority_id)
    }
  }
  None
}

///|
fn validate_promotion_verifier_policy(
  policy : LunaFluxPromotionVerifierPolicy,
) -> Unit raise LunaFluxPromotionVerifierError {
  if policy.schema_version != LUNAFLUX_PROMOTION_VERIFIER_POLICY_SCHEMA {
    raise UnsupportedPromotionVerifierPolicySchema
  }
  if !@contracts.valid_sha256_digest(policy.rollout_digest) {
    raise InvalidPromotionVerifierRolloutDigest
  }
  if !@contracts.valid_identifier(policy.verifier_key_id, maximum_length=128) {
    raise InvalidPromotionVerifierKeyId
  }
  if policy.authorities.length() != 10 {
    raise InvalidPromotionVerifierAuthorityCount(policy.authorities.length())
  }
  for subject in promotion_authority_subjects() {
    let matches = policy.authorities.filter(authority => {
      authority.subject == subject
    })
    if matches.length() == 0 {
      raise MissingPromotionVerifierAuthority(subject)
    }
    if matches.length() != 1 {
      raise DuplicatePromotionVerifierAuthority(subject)
    }
    if !@contracts.valid_identifier(matches[0].authority_id, maximum_length=128) {
      raise InvalidPromotionVerifierAuthority(subject)
    }
  }
}

///|
fn verifier_key_has_nonzero_byte(key_bytes : BytesView) -> Bool {
  for byte in key_bytes {
    if byte != 0 {
      return true
    }
  }
  false
}

///|
/// Copies one bounded HMAC-SHA256 key and one exact ten-subject rollout policy.
/// The caller remains responsible for deployment secret acquisition and key
/// rotation; neither the key nor a constructor for adapter authority is
/// exposed by this package.
pub fn LunaFluxPromotionVerifier::new(
  policy : LunaFluxPromotionVerifierPolicy,
  key_bytes : BytesView,
) -> LunaFluxPromotionVerifier raise LunaFluxPromotionVerifierError {
  validate_promotion_verifier_policy(policy)
  if key_bytes.length() < 32 ||
    key_bytes.length() > 64 ||
    !verifier_key_has_nonzero_byte(key_bytes) {
    raise InvalidPromotionVerifierSecret
  }
  {
    policy: { ..policy, authorities: policy.authorities.copy() },
    key_bytes: key_bytes.to_fixedarray(),
    closed: false,
  }
}

///|
/// Wipes the verifier-owned key copy exactly once. Closing an already closed
/// verifier is idempotent.
pub fn LunaFluxPromotionVerifier::close(
  self : LunaFluxPromotionVerifier,
) -> Unit {
  if !self.closed {
    self.key_bytes.fill(0)
    self.closed = true
  }
}

///|
/// Canonical public signing material for an inert receipt. Every field is
/// length-bounded or a fixed digest before verification, so the delimiter
/// encoding is unambiguous. The candidate digest binds every subject to the
/// same exact candidate, including subjects whose evidence digest is shared
/// across releases.
pub fn LunaFluxSignedEvidenceApproval::canonical_signing_bytes(
  self : LunaFluxSignedEvidenceApproval,
  candidate_manifest_digest : String,
) -> Bytes {
  @utf8.encode(
    "\{LUNAFLUX_SIGNED_PROMOTION_RECEIPT_DOMAIN}|\{self.schema_version}|\{promotion_authority_subject_label(self.subject)}|\{self.rollout_digest}|\{candidate_manifest_digest}|\{self.evidence_digest}|\{self.approval_receipt_digest}|\{self.authority_id}|\{self.verifier_key_id}",
  )
}

///|
fn lower_hex_nibble(code : UInt16) -> Byte? {
  if code >= '0' && code <= '9' {
    return Some((code - '0').to_byte())
  }
  if code >= 'a' && code <= 'f' {
    return Some((code - 'a' + 10).to_byte())
  }
  None
}

///|
fn decode_lower_hex_sha256(value : String) -> FixedArray[Byte]? {
  if value.length() != 64 {
    return None
  }
  let decoded : FixedArray[Byte] = FixedArray::make(32, 0)
  for index in 0..<32 {
    guard lower_hex_nibble(value[index * 2]) is Some(high) &&
      lower_hex_nibble(value[index * 2 + 1]) is Some(low) else {
      decoded.fill(0)
      return None
    }
    decoded[index] = high.shl(4).lor(low)
  }
  Some(decoded)
}

///|
fn valid_lower_hex_sha256(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
fn fixed_sha256_equal(
  left : FixedArray[Byte],
  right : FixedArray[Byte],
) -> Bool {
  if left.length() != 32 || right.length() != 32 {
    return false
  }
  let mut difference : Byte = 0
  for index in 0..<32 {
    difference = difference.lor(left[index].lxor(right[index]))
  }
  difference == 0
}

///|
fn verifier_hmac_sha256(
  key_bytes : FixedArray[Byte],
  material : Bytes,
) -> FixedArray[Byte] {
  let inner_pad : FixedArray[Byte] = FixedArray::make(64, 0x36)
  let outer_pad : FixedArray[Byte] = FixedArray::make(64, 0x5c)
  for index in 0..<key_bytes.length() {
    inner_pad[index] = inner_pad[index].lxor(key_bytes[index])
    outer_pad[index] = outer_pad[index].lxor(key_bytes[index])
  }
  let inner = @crypto.SHA256::new()
  inner.update(inner_pad)
  inner.update(material)
  let inner_digest = inner.finalize()
  let outer = @crypto.SHA256::new()
  outer.update(outer_pad)
  outer.update(inner_digest)
  let digest = outer.finalize()
  // SHA256::finalize leaves its mutable context intact. Reset both temporary
  // contexts so key-derived chaining state and buffered bytes are overwritten
  // deterministically instead of waiting for garbage collection.
  inner.reset()
  outer.reset()
  inner_pad.fill(0)
  outer_pad.fill(0)
  inner_digest.fill(0)
  digest
}

///|
fn signed_receipt_authenticates(
  verifier : LunaFluxPromotionVerifier,
  receipt : LunaFluxSignedEvidenceApproval,
  candidate_manifest_digest : String,
) -> Bool {
  guard decode_lower_hex_sha256(receipt.signature) is Some(signature) else {
    return false
  }
  let material = receipt.canonical_signing_bytes(candidate_manifest_digest)
  let expected = verifier_hmac_sha256(verifier.key_bytes, material)
  let authenticated = fixed_sha256_equal(signature, expected)
  signature.fill(0)
  expected.fill(0)
  authenticated
}

///|
fn unique_signed_receipt_for(
  receipts : ArrayView[LunaFluxSignedEvidenceApproval],
  subject : LunaFluxPromotionAuthoritySubject,
) -> (LunaFluxSignedEvidenceApproval?, Int) {
  let mut found : LunaFluxSignedEvidenceApproval? = None
  let mut count = 0
  for receipt in receipts {
    if receipt.subject == subject {
      count += 1
      found = Some(receipt)
    }
  }
  (found, count)
}

///|
fn invalid_verifier_report(
  blockers : Array[LunaFluxPromotionBlocker],
) -> LunaFluxPromotionReport {
  { evidence_well_formed: false, routable: false, authority: None, blockers }
}

///|
fn validate_signed_promotion_receipt(
  verifier : LunaFluxPromotionVerifier,
  request : LunaFluxPromotionVerificationRequest,
  receipt : LunaFluxSignedEvidenceApproval,
  subject : LunaFluxPromotionAuthoritySubject,
  candidate_manifest_digest : String,
  blockers : Array[LunaFluxPromotionBlocker],
) -> Unit {
  if receipt.schema_version != LUNAFLUX_SIGNED_PROMOTION_RECEIPT_SCHEMA ||
    !@contracts.valid_sha256_digest(receipt.rollout_digest) ||
    !@contracts.valid_sha256_digest(receipt.evidence_digest) ||
    !@contracts.valid_sha256_digest(receipt.approval_receipt_digest) ||
    !@contracts.valid_identifier(receipt.authority_id, maximum_length=128) ||
    !@contracts.valid_identifier(receipt.verifier_key_id, maximum_length=128) ||
    !valid_lower_hex_sha256(receipt.signature) {
    blockers.push(InvalidSignedPromotionReceipt(subject))
    return
  }
  guard verifier_authority_for(verifier.policy, subject) is Some(authority_id) else {
    blockers.push(SignedPromotionReceiptPolicyMismatch(subject))
    return
  }
  if receipt.rollout_digest != verifier.policy.rollout_digest ||
    receipt.authority_id != authority_id ||
    receipt.verifier_key_id != verifier.policy.verifier_key_id ||
    receipt.evidence_digest !=
    expected_promotion_authority_digest(request, subject) {
    blockers.push(SignedPromotionReceiptPolicyMismatch(subject))
    return
  }
  if !signed_receipt_authenticates(verifier, receipt, candidate_manifest_digest) {
    blockers.push(SignedPromotionReceiptAuthenticationFailed(subject))
  }
}

///|
fn approval_from_signed(
  receipt : LunaFluxSignedEvidenceApproval,
) -> LunaFluxEvidenceApproval {
  {
    evidence_digest: receipt.evidence_digest,
    approval_receipt_digest: receipt.approval_receipt_digest,
    authority_id: receipt.authority_id,
  }
}

///|
fn exact_signed_receipt(
  receipts : ArrayView[LunaFluxSignedEvidenceApproval],
  subject : LunaFluxPromotionAuthoritySubject,
) -> LunaFluxSignedEvidenceApproval {
  let (receipt, _) = unique_signed_receipt_for(receipts, subject)
  guard receipt is Some(value) else {
    abort("validated promotion receipt disappeared")
  }
  value
}

///|
/// Authenticates all ten fixed rollout subjects before constructing the private
/// catalog input. Any malformed, mismatched, replayed, or unauthenticated
/// receipt returns no routing authority. The legacy caller-claim inspection
/// path remains separate and permanently fail-closed.
pub fn LunaFluxPromotionVerifier::verify(
  self : LunaFluxPromotionVerifier,
  request : LunaFluxPromotionVerificationRequest,
  receipts : ArrayView[LunaFluxSignedEvidenceApproval],
) -> LunaFluxPromotionReport {
  if self.closed {
    return invalid_verifier_report([PromotionVerifierClosed])
  }
  if receipts.length() != 10 {
    return invalid_verifier_report([
      InvalidSignedPromotionReceiptCount(receipts.length()),
    ])
  }
  let blockers : Array[LunaFluxPromotionBlocker] = []
  let candidate_manifest_digest = lunaflux_candidate_manifest_digest(
    request.candidate,
  )
  for subject in promotion_authority_subjects() {
    let (receipt, count) = unique_signed_receipt_for(receipts, subject)
    if count == 0 {
      blockers.push(MissingSignedPromotionReceipt(subject))
    } else if count != 1 {
      blockers.push(DuplicateSignedPromotionReceipt(subject))
    } else if receipt is Some(value) {
      validate_signed_promotion_receipt(
        self, request, value, subject, candidate_manifest_digest, blockers,
      )
    }
  }
  for index, receipt in receipts {
    if receipts[:index].any(previous => {
        previous.approval_receipt_digest == receipt.approval_receipt_digest
      }) {
      blockers.push(ReusedSignedPromotionReceipt(receipt.subject))
      break
    }
  }
  if blockers.length() != 0 {
    return invalid_verifier_report(blockers)
  }
  let authority : LunaFluxPromotionAuthorityInput = {
    schema_version: "lunanexa.lunaflux.promotion-authority.v1",
    candidate_manifest: approval_from_signed(
      exact_signed_receipt(receipts, CandidateManifestAuthority),
    ),
    oci_image: approval_from_signed(
      exact_signed_receipt(receipts, OciImageAuthority),
    ),
    sbom: approval_from_signed(exact_signed_receipt(receipts, SbomAuthority)),
    build_provenance: approval_from_signed(
      exact_signed_receipt(receipts, BuildProvenanceAuthority),
    ),
    license: approval_from_signed(
      exact_signed_receipt(receipts, LicenseAuthority),
    ),
    kernel: approval_from_signed(
      exact_signed_receipt(receipts, KernelAuthority),
    ),
    physical_serving: approval_from_signed(
      exact_signed_receipt(receipts, PhysicalServingAuthority),
    ),
    benchmark: approval_from_signed(
      exact_signed_receipt(receipts, BenchmarkAuthority),
    ),
    control_contract: approval_from_signed(
      exact_signed_receipt(receipts, ControlContractAuthority),
    ),
    invocation_contract: approval_from_signed(
      exact_signed_receipt(receipts, InvocationContractAuthority),
    ),
  }
  let catalog : LunaFluxPromotionCatalog? = Some(
    prepare_lunaflux_promotion_catalog(authority),
  ) catch {
    _ => None
  }
  guard catalog is Some(admitted) else {
    return invalid_verifier_report([PromotionVerifierCatalogRejected])
  }
  admitted.verify(request)
}
