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
    [{ ..capabilities[0], evidence_ref: None, }, ..capabilities[1:]],
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
      { ..capabilities[1], evidence_ref: capabilities[0].evidence_ref, },
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

///|
test "the undertaking's tiers are one ordered list both sides can render" {
  // The operator's tariff picker and the enterprise portal's term picker both
  // read this list. If they ever read two lists, a customer can ask for a tier
  // the operator cannot quote.
  assert_eq(@offline.undertaking_term_tiers.length(), 5)
  let units = @offline.undertaking_term_tiers.map(tier => tier.unit)
  assert_eq(units, ["day", "week", "month", "quarter", "year"])
  // Shortest first, and the days must increase with the price.
  for index = 1; index < @offline.undertaking_term_tiers.length(); index = index + 1 {
    let previous = @offline.undertaking_term_tiers[index - 1]
    let current = @offline.undertaking_term_tiers[index]
    assert_true(previous.days < current.days)
    assert_true(previous.minor_units < current.minor_units)
  }
  // The tariff and the day count are derived from the list, never restated.
  for tier in @offline.undertaking_term_tiers {
    assert_eq(@offline.undertaking_tariff(tier.unit), Some(tier.minor_units))
    assert_eq(@offline.undertaking_term_days(tier.unit), Some(tier.days))
  }
  assert_eq(@offline.undertaking_tariff("hour"), None)
  assert_eq(@offline.undertaking_term_tier("hour"), None)
}
