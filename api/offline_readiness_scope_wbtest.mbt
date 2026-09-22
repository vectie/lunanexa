///|
test "quotation does not require rendering storage or historical orders" {
  let required : Array[@offline.OfflineCommerceCapability] = [
    ApprovedLegalTemplates,
    FinanceLegalPolicy,
  ]
  for
    code in [
      "MoonLeafPdfRendererPending", "ReadinessArtifactDispatcherHeartbeatStale",
      "ReadinessEntitlementDispatcherHeartbeatStale", "ReadinessArtifactDispatcherSuccessStale",
      "ReadinessEntitlementDispatcherSuccessStale", "ReadinessTransferAdapterUnavailable",
      "ReadinessOfflineReconcilerDegraded",
    ] {
    assert_false(offline_blocker_applies(code, required))
  }
  assert_true(
    offline_blocker_applies("ApprovedLegalTemplatesPending", required),
  )
  assert_true(offline_blocker_applies("ReadinessEvidenceExpired", required))
  assert_true(
    offline_blocker_applies("ReadinessCapabilitySetInvalid", required),
  )
  assert_true(
    offline_blocker_applies("ReadinessOfflineStoreUnavailable", required),
  )
  assert_true(
    offline_blocker_applies("ReadinessUnknownFutureBlocker", required),
  )
}

///|
test "first worker job needs live dependencies not a previous business success" {
  let required : Array[@offline.OfflineCommerceCapability] = [
    OoxmlWorker,
    PdfRenderer,
    CjkFonts,
  ]
  assert_false(
    offline_blocker_applies("ReadinessArtifactDispatcherSuccessStale", required),
  )
  assert_true(
    offline_blocker_applies(
      "ReadinessArtifactDispatcherHeartbeatStale", required,
    ),
  )
  assert_true(
    offline_blocker_applies(
      "ReadinessArtifactWorkerCallbackUnavailable", required,
    ),
  )
  assert_true(offline_blocker_applies("MoonLeafPdfRendererPending", required))
  assert_true(offline_blocker_applies("CjkFontsPending", required))
  assert_false(
    offline_blocker_applies(
      "ReadinessEntitlementDispatcherHeartbeatStale", required,
    ),
  )
}

///|
test "upload and entitlement dependencies remain separate and enforced" {
  let upload : Array[@offline.OfflineCommerceCapability] = [
    ObjectStorage,
    MalwareScanner,
    MachineCallbackIdentity,
  ]
  let authority : Array[@offline.OfflineCommerceCapability] = [
    EntitlementAuthority,
    MachineCallbackIdentity,
    FinanceLegalPolicy,
  ]
  assert_true(
    offline_blocker_applies("ReadinessTransferAdapterUnavailable", upload),
  )
  assert_true(
    offline_blocker_applies(
      "ReadinessArtifactScannerCallbackUnavailable", upload,
    ),
  )
  assert_false(
    offline_blocker_applies("ReadinessArtifactDispatcherHeartbeatStale", upload),
  )
  assert_true(
    offline_blocker_applies(
      "ReadinessEntitlementAuthorityCallbackUnavailable", authority,
    ),
  )
  assert_true(
    offline_blocker_applies(
      "ReadinessEntitlementDispatcherHeartbeatStale", authority,
    ),
  )
  assert_true(
    offline_blocker_applies("ReadinessOfflineReconcilerDegraded", authority),
  )
  assert_false(
    offline_blocker_applies(
      "ReadinessEntitlementDispatcherSuccessStale", authority,
    ),
  )
  assert_false(
    offline_blocker_applies("ReadinessTransferAdapterUnavailable", authority),
  )
}
