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
/// Retained evidence references are opaque to the control plane but bounded:
/// the writer and the reader must accept exactly the same set.
pub fn valid_readiness_ref(value : String) -> Bool {
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

///|
/// The one canonical schema identifier for the signed readiness document. The
/// control plane that reads the document, the tool that writes it, and the
/// signed material all compare against this value, so it has exactly one
/// definition.
pub let offline_readiness_schema_version : String = "lunanexa.offline-commerce-readiness.v1"

///|
/// The widest accepted issue-to-expiry window, in milliseconds (31 days).
/// Enforced identically when signing and when loading.
pub let offline_readiness_maximum_validity_ms : Int64 = 2678400000L

///|
/// The signed offline-commerce production readiness document. It is the only
/// carrier that can turn the ten capability gates from pending to ready, so a
/// document that fails its signature or bounds must stop startup.
pub(all) struct OfflineReadinessEvidenceDocument {
  schema_version : String
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  capabilities : Array[OfflineCommerceCapabilityEvidence]
  signature : String
} derive(FromJson, ToJson, Debug, Eq)

///|
pub extend OfflineReadinessEvidenceDocument with Debug::{to_repr}

///|
pub extend OfflineReadinessEvidenceDocument with Eq::{not_equal, equal}

///|
pub extend OfflineReadinessEvidenceDocument with ToJson::{to_json}

///|
pub extend OfflineReadinessEvidenceDocument with FromJson::{from_json}

///|
/// The exact byte string covered by the signature. A control plane that
/// already trusts a document verifies this material, so any edit here
/// invalidates retained evidence; a golden test pins it.
pub fn offline_readiness_material(
  document : OfflineReadinessEvidenceDocument,
) -> String {
  "\{offline_readiness_schema_version}|\{document.issued_unix_ms}|\{document.expires_unix_ms}|\{document.capabilities.to_json().stringify()}"
}

///|
pub fn offline_readiness_signature(
  document : OfflineReadinessEvidenceDocument,
  secret : String,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).exact_view(),
      @utf8.encode(offline_readiness_material(document)).exact_view(),
    ),
  )
}
