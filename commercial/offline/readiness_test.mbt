///|
test "offline commerce readiness is complete only with evidence for every gate" {
  let pending = @offline.pending_offline_commerce_readiness(1000L)
  assert_eq(pending.status, OfflineCommerceAdaptersPending)
  assert_eq(pending.blocker_codes.length(), 11)
  let capability_names : Array[@offline.OfflineCommerceCapability] = [
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
  let capabilities : Array[@offline.OfflineCommerceCapabilityEvidence] = capability_names.mapi((
      index,
      capability,
    ) => {
      capability,
      configured: true,
      verified: true,
      evidence_ref: Some("evidence:acceptance-\{index}"),
    },
  )
  let ready = @offline.offline_commerce_readiness(capabilities, 2000L)
  assert_eq(ready.status, OfflineCommerceReady)
  assert_eq(ready.blocker_codes, [])
  let missing_evidence = @offline.offline_commerce_readiness(
    [{ ..capabilities[0], evidence_ref: None }, ..capabilities[1:]],
    3000L,
  )
  assert_eq(missing_evidence.status, OfflineCommerceAdaptersPending)
  assert_true(
    missing_evidence.blocker_codes.contains("ApprovedLegalTemplatesPending"),
  )
  let duplicate = @offline.offline_commerce_readiness(
    [capabilities[0], ..capabilities],
    4000L,
  )
  assert_eq(duplicate.status, OfflineCommerceAdaptersPending)
  assert_true(duplicate.blocker_codes.contains("ReadinessCapabilityDuplicate"))
  let duplicate_receipt = @offline.offline_commerce_readiness(
    [
      capabilities[0],
      { ..capabilities[1], evidence_ref: capabilities[0].evidence_ref },
      ..capabilities[2:],
    ],
    5000L,
  )
  assert_true(
    duplicate_receipt.blocker_codes.contains(
      "ReadinessEvidenceReferenceDuplicate",
    ),
  )
  let bad_time = @offline.offline_commerce_readiness(capabilities, 0L)
  assert_eq(bad_time.status, OfflineCommerceAdaptersPending)
  assert_true(bad_time.blocker_codes.contains("ReadinessEvaluationTimeInvalid"))
}
