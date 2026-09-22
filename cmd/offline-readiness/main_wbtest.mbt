///|
fn valid_readiness_capabilities() -> Array[
  @offline.OfflineCommerceCapabilityEvidence,
] {
  let kinds : Array[@offline.OfflineCommerceCapability] = [
    @offline.ApprovedLegalTemplates,
    @offline.ObjectStorage,
    @offline.MalwareScanner,
    @offline.OoxmlWorker,
    @offline.PdfRenderer,
    @offline.SpreadsheetFormulaEngine,
    @offline.CjkFonts,
    @offline.MachineCallbackIdentity,
    @offline.EntitlementAuthority,
    @offline.FinanceLegalPolicy,
  ]
  kinds.mapi((index, capability) => {
    capability,
    configured: true,
    verified: true,
    evidence_ref: Some("retained/readiness-\{index}"),
  })
}

///|
/// Returns the refusal message, or None when the document would be signed.
fn readiness_refusal(
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence],
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> String? {
  ignore(
    validate_readiness_evidence(capabilities, issued_unix_ms, expires_unix_ms),
  ) catch {
    Failure::Failure(message) => return Some(message)
    _ => return Some("unexpected validation error")
  }
  None
}

///|
test "readiness validation refuses every shape the control plane refuses" {
  let issued = 1700000000000L
  let expires = issued + 600000L
  let valid = valid_readiness_capabilities()
  assert_true(readiness_refusal(valid, issued, expires) is None)
  // Nine or eleven entries: the ten gates must be covered exactly once.
  assert_true(readiness_refusal([..valid[0:9]], issued, expires) is Some(_))
  assert_true(
    readiness_refusal([..valid, valid[0]], issued, expires) is Some(_),
  )
  // A capability declared twice leaves another gate missing.
  assert_true(
    readiness_refusal([valid[0], valid[0], ..valid[2:]], issued, expires)
    is Some(_),
  )
  // A retained reference may not be shared by two capabilities.
  assert_true(
    readiness_refusal(
      [
        valid[0],
        { ..valid[1], evidence_ref: valid[0].evidence_ref, },
        ..valid[2:],
      ],
      issued,
      expires,
    )
    is Some(_),
  )
  // A reference is 1 to 256 characters of ASCII alphanumerics or - _ . : /.
  for
    malformed in ["", " ", "retained ref#1", "retained-ref\n", "a".repeat(257)] {
    assert_true(
      readiness_refusal(
        [valid[0], { ..valid[1], evidence_ref: Some(malformed), }, ..valid[2:]],
        issued,
        expires,
      )
      is Some(_),
    )
  }
  // The issue time is positive and the window is at most 31 days.
  assert_true(readiness_refusal(valid, 0L, expires) is Some(_))
  assert_true(readiness_refusal(valid, issued, issued) is Some(_))
  assert_true(readiness_refusal(valid, issued, issued - 1L) is Some(_))
  assert_true(readiness_refusal(valid, issued, issued + 2678400001L) is Some(_))
  assert_true(readiness_refusal(valid, issued, issued + 2678400000L) is None)
}

///|
test "a structurally complete document is accepted even while gates are pending" {
  let issued = 1700000000000L
  let expires = issued + 600000L
  let pending = valid_readiness_capabilities().mapi((index, entry) => {
    if index % 2 == 0 {
      { ..entry, configured: false, verified: false, }
    } else {
      entry
    }
  })
  assert_true(readiness_refusal(pending, issued, expires) is None)
  // The reader only turns the unverified gates into `…Pending` blockers; the
  // structural `Readiness` blockers are exactly what validation must prevent.
  let readiness = @offline.offline_commerce_readiness(pending, issued)
  assert_false(
    readiness.blocker_codes.any(code => code.has_prefix("Readiness")),
  )
  assert_true(
    readiness.blocker_codes.any(code => {
      code.has_prefix("ApprovedLegalTemplates")
    }),
  )
}

///|
test "a short signing secret is refused before anything is signed" {
  let issued = 1700000000000L
  ignore(
    sign_readiness_evidence(
      valid_readiness_capabilities(),
      issued,
      issued + 600000L,
      "too-short",
    ),
  ) catch {
    Failure::Failure(_) => return
    _ => fail("a short signing secret was refused with an unexpected error")
  }
  fail("a short signing secret was accepted")
}

///|
async test "the tool signs a document the control plane can load and verify" {
  let issued = 1700000000000L
  let expires = issued + 600000L
  let secret = "offline-readiness-tool-test-secret-32-bytes"
  let root = @fs.realpath(@fs.tmpdir(prefix="lunanexa-offline-readiness-"))
  let input_path = "\{root}/input.json"
  let output_path = "\{root}/readiness.json"
  let capabilities = valid_readiness_capabilities()
  let input : Json = { "capabilities": capabilities.to_json() }
  @fs.write_file(
    input_path,
    input.stringify(indent=2),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let document = sign_readiness_evidence(
    read_readiness_input(input_path),
    issued,
    expires,
    secret,
  )
  write_readiness_document(output_path, document)
  // The reader's own decoder, over the exact bytes the tool wrote.
  let loaded : @offline.OfflineReadinessEvidenceDocument = @json.from_json(
    @json.parse(@fs.read_file(output_path).text()),
  )
  assert_eq(loaded.capabilities, capabilities)
  assert_eq(loaded.schema_version, @offline.offline_readiness_schema_version)
  assert_eq(loaded.issued_unix_ms, issued)
  assert_eq(loaded.expires_unix_ms, expires)
  assert_eq(loaded.signature, document.signature)
  assert_eq(
    loaded.signature,
    @offline.offline_readiness_signature(loaded, secret),
  )
  assert_true(
    loaded.signature !=
    @offline.offline_readiness_signature(loaded, "\{secret}-other"),
  )
  assert_eq(
    @offline.offline_commerce_readiness(loaded.capabilities, issued),
    @offline.offline_commerce_readiness(capabilities, issued),
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "an explicit null evidence_ref still signs a loadable document" {
  let issued = 1700000000000L
  let secret = "offline-readiness-null-ref-test-secret-32"
  let root = @fs.realpath(@fs.tmpdir(prefix="lunanexa-offline-readiness-null-"))
  let input_path = "\{root}/input.json"
  let output_path = "\{root}/readiness.json"
  let capabilities = valid_readiness_capabilities()
  let entries = capabilities.mapi((index, entry) => {
    let reference = if index == 0 {
      "null"
    } else {
      entry.evidence_ref.unwrap().to_json().stringify()
    }
    "{\"capability\":\{entry.capability.to_json().stringify()},\"configured\":true,\"verified\":true,\"evidence_ref\":\{reference}}"
  })
  @fs.write_file(
    input_path,
    "{\"capabilities\":[\{entries.join(",")}]}",
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let loaded_input = read_readiness_input(input_path)
  assert_true(loaded_input[0].evidence_ref is None)
  let document = sign_readiness_evidence(
    loaded_input,
    issued,
    issued + 600000L,
    secret,
  )
  write_readiness_document(output_path, document)
  let written = @fs.read_file(output_path).text()
  assert_false(written.contains("\"evidence_ref\": null"))
  let loaded : @offline.OfflineReadinessEvidenceDocument = @json.from_json(
    @json.parse(written),
  )
  assert_true(loaded.capabilities[0].evidence_ref is None)
  assert_eq(
    loaded.signature,
    @offline.offline_readiness_signature(loaded, secret),
  )
  @fs.rmdir(root, recursive=true)
}
