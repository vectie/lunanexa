///|
fn readiness_capabilities() -> Array[@offline.OfflineCommerceCapabilityEvidence] {
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
    evidence_ref: Some("retained/offline-readiness-\{index}"),
  })
}

///|
fn readiness_document_json(document : OfflineReadinessEvidenceDocument) -> Json {
  {
    "schema_version": document.schema_version,
    "issued_unix_ms": document.issued_unix_ms.to_json(),
    "expires_unix_ms": document.expires_unix_ms.to_json(),
    "capabilities": document.capabilities.to_json(),
    "signature": document.signature,
  }
}

///|
async test "signed offline readiness document is bounded and fail closed" {
  let now = @async.now()
  assert_eq(load_offline_readiness_evidence(None, None, now), ([], 0L))
  // macOS exposes the temporary directory through a `/var` alias. Resolve it
  // before constructing the evidence path so this positive case exercises the
  // same canonical, non-symlink requirement enforced in production.
  let root = @fs.realpath(@fs.tmpdir(prefix="lunanexa-readiness-"))
  let path = "\{root}/readiness.json"
  let secret = "offline-readiness-test-secret-at-least-32-bytes"
  let unsigned : OfflineReadinessEvidenceDocument = {
    schema_version: "lunanexa.offline-commerce-readiness.v1",
    issued_unix_ms: now - 1L,
    expires_unix_ms: now + 600000L,
    capabilities: readiness_capabilities(),
    signature: "",
  }
  let signed = {
    ..unsigned,
    signature: offline_readiness_signature(unsigned, secret),
  }
  @fs.write_file(
    path,
    readiness_document_json(signed).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_eq(
    load_offline_readiness_evidence(Some(path), Some(secret), now),
    (signed.capabilities, signed.expires_unix_ms),
  )
  let projected_directory = "\{root}/..data"
  @fs.mkdir(projected_directory, permission=0o700)
  let projected_target = "\{projected_directory}/readiness.json"
  @fs.write_file(
    projected_target,
    readiness_document_json(signed).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let projected_path = "\{root}/projected-readiness.json"
  @fs.symlink(target=projected_target, projected_path)
  assert_eq(
    load_offline_readiness_evidence(Some(projected_path), Some(secret), now),
    (signed.capabilities, signed.expires_unix_ms),
  )
  let outside = @fs.realpath(@fs.tmpdir(prefix="lunanexa-readiness-outside-"))
  let outside_target = "\{outside}/readiness.json"
  @fs.write_file(
    outside_target,
    readiness_document_json(signed).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let escaping_path = "\{root}/escaping-readiness.json"
  @fs.symlink(target=outside_target, escaping_path)
  ignore(
    load_offline_readiness_evidence(Some(escaping_path), Some(secret), now),
  ) catch {
    Failure::Failure(_) => ()
    _ => fail("readiness symlink escaping its configured mount was accepted")
  }
  let ambiguous = {
    ..unsigned,
    capabilities: [unsigned.capabilities[0], unsigned.capabilities[0]],
  }
  let ambiguous = {
    ..ambiguous,
    signature: offline_readiness_signature(ambiguous, secret),
  }
  @fs.write_file(
    path,
    readiness_document_json(ambiguous).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  ignore(load_offline_readiness_evidence(Some(path), Some(secret), now)) catch {
    Failure::Failure(_) => ()
    _ => fail("ambiguous readiness evidence was accepted")
  }
  @fs.rmdir(root, recursive=true)
  @fs.rmdir(outside, recursive=true)
}

///|
async test "signed machine helper evidence is scoped expiring and fail closed" {
  let now = @async.now()
  assert_eq(
    load_machine_helper_adapter_evidence(None, None, "dgx-spark-fleet", now),
    None,
  )
  let root = @fs.realpath(@fs.tmpdir(prefix="lunanexa-helper-readiness-"))
  let path = "\{root}/helper-readiness.json"
  let secret = "machine-helper-readiness-test-secret-more-than-32-bytes"
  let unsigned : @nodelease.MachineHelperAdapterReadinessEvidence = {
    version: @nodelease.helper_adapter_readiness_contract_version,
    adapter_id: "systemd-root-helper",
    node_scope: "dgx-spark-fleet",
    covered_node_ids: ["dgx-spark-01", "dgx-spark-02"],
    evidence_ref: "retained-helper-drill",
    checked_unix_ms: now,
    expires_unix_ms: now + 600000L,
    provision_verified: true,
    revoke_verified: true,
    sanitize_verified: true,
    quarantine_verified: true,
    signature: "",
  }
  let evidence = {
    ..unsigned,
    signature: @nodelease.machine_helper_adapter_signature(unsigned, secret),
  }
  @fs.write_file(
    path,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_eq(
    load_machine_helper_adapter_evidence(
      Some(path),
      Some(secret),
      "dgx-spark-fleet",
      now,
    ),
    Some(evidence),
  )
  let projected_directory = "\{root}/..data"
  @fs.mkdir(projected_directory, permission=0o700)
  let projected_target = "\{projected_directory}/helper-readiness.json"
  @fs.write_file(
    projected_target,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let projected_path = "\{root}/projected-helper-readiness.json"
  @fs.symlink(target=projected_target, projected_path)
  assert_eq(
    load_machine_helper_adapter_evidence(
      Some(projected_path),
      Some(secret),
      "dgx-spark-fleet",
      now,
    ),
    Some(evidence),
  )
  let outside = @fs.realpath(@fs.tmpdir(prefix="lunanexa-helper-outside-"))
  let outside_target = "\{outside}/helper-readiness.json"
  @fs.write_file(
    outside_target,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let escaping_path = "\{root}/escaping-helper-readiness.json"
  @fs.symlink(target=outside_target, escaping_path)
  ignore(
    load_machine_helper_adapter_evidence(
      Some(escaping_path),
      Some(secret),
      "dgx-spark-fleet",
      now,
    ),
  ) catch {
    Failure::Failure(_) => ()
    _ => fail("helper evidence symlink escaping its mount was accepted")
  }
  @fs.write_file(
    path,
    { ..evidence, node_scope: "mutated-fleet" }.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  ignore(
    load_machine_helper_adapter_evidence(
      Some(path),
      Some(secret),
      "dgx-spark-fleet",
      now,
    ),
  ) catch {
    Failure::Failure(_) => ()
    _ => fail("mutated helper readiness evidence was accepted")
  }
  @fs.write_file(
    path,
    evidence.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  ignore(
    load_machine_helper_adapter_evidence(
      Some(path),
      Some(secret),
      "different-fleet",
      now,
    ),
  ) catch {
    Failure::Failure(_) => ()
    _ => fail("helper readiness evidence from another fleet was accepted")
  }
  @fs.rmdir(root, recursive=true)
  @fs.rmdir(outside, recursive=true)
}

///|
test "operational secrets reject weakness and cross-authority reuse" {
  validate_distinct_operational_secrets([
    ("operator", "operator-authority-secret-more-than-thirty-two-bytes"),
    ("helper", "helper-receipt-secret-more-than-thirty-two-bytes"),
    ("exporter", "external-export-proof-secret-more-than-thirty-two-bytes"),
    ("guide-identity", "guide-identity-secret-more-than-thirty-two-bytes"),
    ("guide-observation", "guide-observation-secret-more-than-thirty-two-bytes"),
    ("guide-diagnostics", "guide-diagnostics-secret-more-than-thirty-two-bytes"),
    (
      "notification-delivery", "notification-delivery-secret-more-than-thirty-two-bytes",
    ),
  ])
  assert_true(
    try {
      validate_distinct_operational_secrets([
        ("monitoring", "same-authority-secret-more-than-thirty-two-bytes"),
        ("exporter", "same-authority-secret-more-than-thirty-two-bytes"),
      ])
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      validate_distinct_operational_secrets([
        ("operator", "shared-notification-secret-more-than-thirty-two-bytes"),
        (
          "notification-delivery", "shared-notification-secret-more-than-thirty-two-bytes",
        ),
      ])
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      validate_distinct_operational_secrets([("credential", "too-short")])
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      validate_distinct_operational_secrets([
        (
          "provider-callback", "shared-guide-provider-secret-more-than-thirty-two-bytes",
        ),
        (
          "guide-diagnostics", "shared-guide-provider-secret-more-than-thirty-two-bytes",
        ),
      ])
      false
    } catch {
      _ => true
    },
  )
}
