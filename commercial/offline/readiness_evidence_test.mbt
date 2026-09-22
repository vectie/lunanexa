///|
fn readiness_evidence_capabilities() -> Array[
  @offline.OfflineCommerceCapabilityEvidence,
] {
  let kinds : Array[@offline.OfflineCommerceCapability] = [
    ApprovedLegalTemplates,
    ObjectStorage,
    MalwareScanner,
    OoxmlWorker,
    PdfRenderer,
    SpreadsheetFormulaEngine,
    CjkFonts,
    MachineCallbackIdentity,
    EntitlementAuthority,
    FinanceLegalPolicy,
  ]
  kinds.mapi((index, capability) => {
    capability,
    configured: true,
    verified: true,
    evidence_ref: Some("retained/readiness-\{index}"),
  })
}

///|
/// The signed material is the contract between the tool that writes a document
/// and the control plane that verifies it. A retained document stops verifying
/// the moment this string changes, so it is pinned literally.
test "the signed readiness material is pinned byte for byte" {
  assert_eq(
    @offline.offline_readiness_schema_version, "lunanexa.offline-commerce-readiness.v1",
  )
  assert_eq(@offline.offline_readiness_maximum_validity_ms, 2678400000L)
  let capabilities : Array[@offline.OfflineCommerceCapabilityEvidence] = [
    {
      capability: ApprovedLegalTemplates,
      configured: true,
      verified: true,
      evidence_ref: Some("retained/readiness-0"),
    },
    {
      capability: ObjectStorage,
      configured: false,
      verified: false,
      evidence_ref: None,
    },
  ]
  let document : @offline.OfflineReadinessEvidenceDocument = {
    schema_version: @offline.offline_readiness_schema_version,
    issued_unix_ms: 1700000000000L,
    expires_unix_ms: 1700000600000L,
    capabilities,
    signature: "",
  }
  assert_eq(
    @offline.offline_readiness_material(document),
    "lunanexa.offline-commerce-readiness.v1|1700000000000|1700000600000|[{\"capability\":\"ApprovedLegalTemplates\",\"configured\":true,\"verified\":true,\"evidence_ref\":\"retained/readiness-0\"},{\"capability\":\"ObjectStorage\",\"configured\":false,\"verified\":false}]",
  )
}

///|
test "the readiness signature is a deterministic lowercase sha256 hex" {
  let document : @offline.OfflineReadinessEvidenceDocument = {
    schema_version: @offline.offline_readiness_schema_version,
    issued_unix_ms: 1700000000000L,
    expires_unix_ms: 1700000600000L,
    capabilities: readiness_evidence_capabilities(),
    signature: "",
  }
  let secret = "offline-readiness-unit-test-secret-32-bytes"
  let signature = @offline.offline_readiness_signature(document, secret)
  assert_eq(signature.length(), 64)
  assert_true(
    signature.all(character => {
      let code = character.to_int()
      (code >= 48 && code <= 57) || (code >= 97 && code <= 102)
    }),
  )
  assert_eq(signature, @offline.offline_readiness_signature(document, secret))
  assert_true(
    signature !=
    @offline.offline_readiness_signature(document, "\{secret}-other"),
  )
  // A re-signed document carries the same signature as long as the material is
  // unchanged, which is what lets the control plane re-derive it.
  let signed = { ..document, signature, }
  assert_eq(
    signed.signature,
    @offline.offline_readiness_signature(signed, secret),
  )
}
