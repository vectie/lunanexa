///|
fn verifier_test_secret() -> Bytes {
  @utf8.encode("0123456789abcdef0123456789abcdef")
}

///|
fn verifier_test_authority(
  subject : LunaFluxPromotionAuthoritySubject,
) -> String {
  promotion_authority_subject_label(subject) + "-review"
}

///|
fn verifier_test_policy(
  rollout_digest : String,
) -> LunaFluxPromotionVerifierPolicy {
  {
    schema_version: LUNAFLUX_PROMOTION_VERIFIER_POLICY_SCHEMA,
    rollout_digest,
    verifier_key_id: "promotion-key-v1",
    authorities: promotion_authority_subjects().map(subject => {
      subject,
      authority_id: verifier_test_authority(subject),
    }),
  }
}

///|
fn sign_verifier_test_receipt(
  receipt : LunaFluxSignedEvidenceApproval,
  candidate_manifest_digest : String,
  secret : Bytes,
) -> LunaFluxSignedEvidenceApproval {
  let material = receipt.canonical_signing_bytes(candidate_manifest_digest)
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), secret.view(), material.view()),
  )
  { ..receipt, signature, }
}

///|
fn verifier_test_receipts(
  request : LunaFluxPromotionVerificationRequest,
  policy : LunaFluxPromotionVerifierPolicy,
  secret : Bytes,
) -> Array[LunaFluxSignedEvidenceApproval] {
  let receipt_fills : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ]
  let candidate_digest = lunaflux_candidate_manifest_digest(request.candidate)
  let receipts : Array[LunaFluxSignedEvidenceApproval] = []
  for index, subject in promotion_authority_subjects() {
    let receipt : LunaFluxSignedEvidenceApproval = {
      schema_version: LUNAFLUX_SIGNED_PROMOTION_RECEIPT_SCHEMA,
      subject,
      rollout_digest: policy.rollout_digest,
      evidence_digest: expected_promotion_authority_digest(request, subject),
      approval_receipt_digest: catalog_test_digest(receipt_fills[index]),
      authority_id: verifier_test_authority(subject),
      verifier_key_id: policy.verifier_key_id,
      signature: "",
    }
    receipts.push(sign_verifier_test_receipt(receipt, candidate_digest, secret))
  }
  receipts
}

///|
fn verifier_test_fixture() -> (
  LunaFluxPromotionVerificationRequest,
  LunaFluxPromotionVerifierPolicy,
  Bytes,
  Array[LunaFluxSignedEvidenceApproval],
) {
  let request = promotion_verification_request()
  let policy = verifier_test_policy(catalog_test_digest('9'))
  let secret = verifier_test_secret()
  let receipts = verifier_test_receipts(request, policy, secret)
  (request, policy, secret, receipts)
}

///|
test "authenticated LunaFlux verifier admits exactly ten signed subjects" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
  let report = verifier.verify(request, receipts)
  assert_true(report.evidence_well_formed)
  assert_true(report.routable)
  assert_eq(report.blockers, [])
  guard report.authority is Some(authority) else {
    fail("authenticated receipts did not produce adapter authority")
  }
  let adapter = authority.opaque_adapter()
  assert_eq(
    adapter.launch_manifest_digest(),
    request.candidate.launch_manifest_digest,
  )
  assert_true(@contracts.valid_sha256_digest(adapter.contract_digest()))
}

///|
test "verifier HMAC matches the approved crypto primitive" {
  let secret = verifier_test_secret()
  let material = @utf8.encode("lunanexa-verifier-hmac-cross-check")
  let expected = @crypto.hmac(
    @crypto.SHA256::new(),
    secret.view(),
    material.view(),
  )
  let actual = verifier_hmac_sha256(secret.view().to_fixedarray(), material)
  assert_true(fixed_sha256_equal(expected, actual))
  expected.fill(0)
  actual.fill(0)
}

///|
test "every signed promotion subject is independently exact" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let candidate_digest = lunaflux_candidate_manifest_digest(request.candidate)
  for index, subject in promotion_authority_subjects() {
    let changed = receipts.copy()
    let substituted = {
      ..changed[index],
      evidence_digest: catalog_test_digest('0'),
      signature: "",
    }
    changed[index] = sign_verifier_test_receipt(
      substituted, candidate_digest, secret,
    )
    let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
    let report = verifier.verify(request, changed)
    assert_false(report.routable)
    assert_eq(report.authority, None)
    assert_true(
      report.blockers.contains(SignedPromotionReceiptPolicyMismatch(subject)),
    )
  }
}

///|
test "receipt policy binds rollout authority and verifier key" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let candidate_digest = lunaflux_candidate_manifest_digest(request.candidate)
  let substitutions : Array[LunaFluxSignedEvidenceApproval] = [
    { ..receipts[0], rollout_digest: catalog_test_digest('8'), signature: "" },
    { ..receipts[0], authority_id: "replacement-review", signature: "" },
    { ..receipts[0], verifier_key_id: "replacement-key", signature: "" },
  ]
  for substitution in substitutions {
    let changed = receipts.copy()
    changed[0] = sign_verifier_test_receipt(
      substitution, candidate_digest, secret,
    )
    let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
    let report = verifier.verify(request, changed)
    assert_false(report.routable)
    assert_true(
      report.blockers.contains(
        SignedPromotionReceiptPolicyMismatch(CandidateManifestAuthority),
      ),
    )
  }
}

///|
test "missing duplicate and reused signed receipts fail closed" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let missing = receipts.copy()
  missing[1] = missing[0]
  let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
  let missing_report = verifier.verify(request, missing)
  assert_false(missing_report.routable)
  assert_true(
    missing_report.blockers.contains(
      DuplicateSignedPromotionReceipt(CandidateManifestAuthority),
    ),
  )
  assert_true(
    missing_report.blockers.contains(
      MissingSignedPromotionReceipt(OciImageAuthority),
    ),
  )
  let reused = receipts.copy()
  let candidate_digest = lunaflux_candidate_manifest_digest(request.candidate)
  reused[1] = sign_verifier_test_receipt(
    {
      ..reused[1],
      approval_receipt_digest: reused[0].approval_receipt_digest,
      signature: "",
    },
    candidate_digest,
    secret,
  )
  let replay_report = verifier.verify(request, reused)
  assert_false(replay_report.routable)
  assert_true(
    replay_report.blockers.contains(
      ReusedSignedPromotionReceipt(OciImageAuthority),
    ),
  )
}

///|
test "signature candidate and key substitution fail authentication" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let bad_signature = receipts.copy()
  bad_signature[0] = { ..bad_signature[0], signature: "f".repeat(64) }
  let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
  let signature_report = verifier.verify(request, bad_signature)
  assert_false(signature_report.routable)
  assert_true(
    signature_report.blockers.contains(
      SignedPromotionReceiptAuthenticationFailed(CandidateManifestAuthority),
    ),
  )
  let wrong_secret = @utf8.encode("fedcba9876543210fedcba9876543210")
  let wrong_verifier = LunaFluxPromotionVerifier::new(
    policy,
    wrong_secret.view(),
  )
  let key_report = wrong_verifier.verify(request, receipts)
  assert_false(key_report.routable)
  assert_true(
    key_report.blockers.contains(
      SignedPromotionReceiptAuthenticationFailed(CandidateManifestAuthority),
    ),
  )
  let candidate_report = verifier.verify(
    {
      ..request,
      candidate: {
        ..request.candidate,
        runtime: { ..request.candidate.runtime, version: "substituted" },
      },
    },
    receipts,
  )
  assert_false(candidate_report.routable)
  assert_eq(candidate_report.authority, None)
  assert_true(
    candidate_report.blockers.contains(
      SignedPromotionReceiptAuthenticationFailed(OciImageAuthority),
    ),
  )
}

///|
test "malformed and unbounded signed receipt sets fail closed" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
  let malformed = receipts.copy()
  malformed[0] = { ..malformed[0], signature: "ABCDEF".repeat(10) + "ABCD" }
  let malformed_report = verifier.verify(request, malformed)
  assert_false(malformed_report.routable)
  assert_true(
    malformed_report.blockers.contains(
      InvalidSignedPromotionReceipt(CandidateManifestAuthority),
    ),
  )
  let short_report = verifier.verify(request, receipts[:9])
  assert_eq(short_report.blockers, [InvalidSignedPromotionReceiptCount(9)])
  let oversized = receipts.copy()
  oversized.push(receipts[0])
  let oversized_report = verifier.verify(request, oversized)
  assert_eq(oversized_report.blockers, [InvalidSignedPromotionReceiptCount(11)])
}

///|
test "verifier policy and secret admission are exact" {
  let (_, policy, secret, _) = verifier_test_fixture()
  try
    LunaFluxPromotionVerifier::new(
      { ..policy, schema_version: "future" },
      secret.view(),
    )
  catch {
    UnsupportedPromotionVerifierPolicySchema => ()
    _ => fail("wrong policy schema returned the wrong error")
  } noraise {
    _ => fail("wrong policy schema was admitted")
  }
  try LunaFluxPromotionVerifier::new(policy, b"short"[:]) catch {
    InvalidPromotionVerifierSecret => ()
    _ => fail("short verifier key returned the wrong error")
  } noraise {
    _ => fail("short verifier key was admitted")
  }
  try LunaFluxPromotionVerifier::new(policy, Bytes::make(32, 0).view()) catch {
    InvalidPromotionVerifierSecret => ()
    _ => fail("zero verifier key returned the wrong error")
  } noraise {
    _ => fail("zero verifier key was admitted")
  }
  let missing = policy.authorities.copy()
  ignore(missing.pop())
  try
    LunaFluxPromotionVerifier::new(
      { ..policy, authorities: missing },
      secret.view(),
    )
  catch {
    InvalidPromotionVerifierAuthorityCount(9) => ()
    _ => fail("missing verifier authority returned the wrong error")
  } noraise {
    _ => fail("missing verifier authority was admitted")
  }
}

///|
test "closing promotion verifier wipes key authority and is idempotent" {
  let (request, policy, secret, receipts) = verifier_test_fixture()
  let verifier = LunaFluxPromotionVerifier::new(policy, secret.view())
  assert_true(verifier.key_bytes.any(byte => byte != 0))
  verifier.close()
  verifier.close()
  assert_true(verifier.closed)
  assert_true(verifier.key_bytes.all(byte => byte == 0))
  let report = verifier.verify(request, receipts)
  assert_eq(report.blockers, [PromotionVerifierClosed])
  assert_false(report.routable)
  assert_eq(report.authority, None)
}
