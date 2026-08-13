///|
fn capability_blocker(capability : OfflineCommerceCapability) -> String {
  match capability {
    ApprovedLegalTemplates => "ApprovedLegalTemplatesPending"
    ObjectStorage => "ObjectStoragePending"
    MalwareScanner => "MalwareScannerPending"
    OoxmlWorker => "OoxmlWorkerPending"
    PdfRenderer => "MoonLeafPdfRendererPending"
    SpreadsheetFormulaEngine => "SpreadsheetFormulaEnginePending"
    CjkFonts => "CjkFontsPending"
    MachineCallbackIdentity => "MachineCallbackIdentityPending"
    EntitlementAuthority => "EntitlementAuthorityPending"
    FinanceLegalPolicy => "FinanceLegalPolicyPending"
  }
}

///| Computes the fail-closed production readiness projection. A capability is

///| ready only when deployment configuration and retained verification evidence

///|
/// are both present; repository defaults therefore remain pending.
pub fn offline_commerce_readiness(
  capabilities : Array[OfflineCommerceCapabilityEvidence],
  evaluated_unix_ms : Int64,
) -> OfflineCommerceReadiness {
  let expected = [
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
  let blockers = []
  if evaluated_unix_ms <= 0L {
    blockers.push("ReadinessEvaluationTimeInvalid")
  }
  if capabilities.length() != expected.length() {
    blockers.push("ReadinessCapabilitySetInvalid")
  }
  let seen : Array[OfflineCommerceCapability] = []
  let evidence_refs : Map[String, Unit] = Map([])
  for value in capabilities {
    if seen.contains(value.capability) {
      blockers.push("ReadinessCapabilityDuplicate")
    } else {
      seen.push(value.capability)
    }
    match value.evidence_ref {
      Some(reference) if evidence_refs.contains(reference) =>
        blockers.push("ReadinessEvidenceReferenceDuplicate")
      Some(reference) => evidence_refs[reference] = ()
      None => ()
    }
  }
  for capability in expected {
    let matching = capabilities.filter(value => value.capability == capability)
    let evidence = matching.get(0)
    if evidence is None ||
      matching.length() != 1 ||
      evidence.map_or(true, value => {
        !value.configured ||
        !value.verified ||
        value.evidence_ref.map_or(true, reference => {
          !valid_readiness_ref(reference)
        })
      }) {
      blockers.push(capability_blocker(capability))
    }
  }
  {
    status: if blockers.length() == 0 {
      OfflineCommerceReady
    } else {
      OfflineCommerceAdaptersPending
    },
    capabilities,
    blocker_codes: blockers,
    evaluated_unix_ms,
  }
}

///|
fn valid_readiness_ref(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 256 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':' ||
    character == '/'
  })
}

///| Safe repository default: external legal, finance, storage, scanning,

///|
/// rendering, font, callback and entitlement gates are not inferred.
pub fn pending_offline_commerce_readiness(
  evaluated_unix_ms : Int64,
) -> OfflineCommerceReadiness {
  offline_commerce_readiness([], evaluated_unix_ms)
}
