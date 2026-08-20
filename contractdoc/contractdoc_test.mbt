///|
test "source manifest covers seven long-horizon forms and keeps secrets offline" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  @contractdoc.validate_manifest(manifest)
  inspect(manifest.forms.length(), content="7")
  assert_true(manifest.fields.length() > 80)
  let password = manifest.field("access.initial_password").unwrap()
  assert_eq(password.collection_policy, CompleteOffline)
  assert_false(password.required)
}

///|
test "generation remains blocked until supplied information is confirmed" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-1",
    "packet-key-1",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  )
  assert_true(
    @contractdoc.missing_required_fields(manifest, packet).length() > 0,
  )
  try
    packet.request_generation(
      1L, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      2000L,
    )
  catch {
    ConfirmationMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unconfirmed packet must not generate")
  }
}

///|
test "secret-bearing offline fields cannot enter persisted packet data" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-access",
    "packet-key-access",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [AccessConfirmation],
    1000L,
  )
  try
    packet.update_information(
      manifest,
      1L,
      [{ field_id: "access.initial_password", value: "do-not-store" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      2000L,
    )
  catch {
    ForbiddenSecret("access.initial_password") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("password must stay outside durable contract state")
  }
}

///|
test "physical choice markers use source glyphs and missing optional slots stay blank" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-choice",
    "packet-key-choice",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  ).update_information(
    manifest,
    1L,
    [{ field_id: "lease.tier", value: "月租" }],
    ManagerOperator,
    "operator-1",
    "operator-console",
    2000L,
  )
  assert_eq(packet.marker_value("{{lease.month.mark}}"), "☒")
  assert_eq(packet.marker_value("{{lease.day.mark}}"), "□")
  assert_eq(packet.marker_value("{{lease.month.start}}"), "")
  assert_eq(packet.marker_value("{{reservation.operator_comment}}"), "")
}

///|
test "generation rejects a MoonLeaf receipt with the wrong physical page count" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let requested = @contractdoc.new_packet(
    manifest,
    "packet-page-count",
    "packet-page-count-key",
    "tenant-page-count",
    "organization-page-count",
    "subject-page-count",
    "order-page-count",
    None,
    [MasterLease],
    1000L,
  )
  let requested = { ..requested, state: GenerationRequested }
  let evidence = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let docx : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-docx-wrong-pages",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    sha256: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    byte_count: 1000L,
    page_count: 17,
    render_evidence_sha256: evidence,
    generated_unix_ms: 2000L,
  }
  let pdf : @contractdoc.ContractGeneratedArtifact = {
    artifact_id: "contract-pdf-wrong-pages",
    media_type: "application/pdf",
    sha256: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    byte_count: 1000L,
    page_count: 17,
    render_evidence_sha256: evidence,
    generated_unix_ms: 2000L,
  }
  try
    requested.complete_generation(requested.revision, docx, pdf, 2000L)
  catch {
    InvalidInput("contract generation evidence is invalid") => ()
    error => fail("unexpected page-count rejection: \{Repr(error)}")
  } noraise {
    _ =>
      fail("17-page MoonLeaf evidence must not complete the 18-page contract")
  }
}

///|
test "field ownership prevents cross-party edits and records provenance" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-ownership",
    "packet-key-ownership",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease, ReservationApplication, AccessConfirmation],
    1000L,
  )
  assert_eq(manifest.field("lessee.name").unwrap().owner, CustomerMessenger)
  assert_eq(manifest.field("lessor.name").unwrap().owner, ManagerOperator)
  assert_eq(
    manifest.field("access.order_number").unwrap().owner,
    PlatformDerived,
  )
  assert_eq(
    manifest.field("lessor.signatory").unwrap().owner,
    OfflineParticipant,
  )
  let customer = packet.update_information(
    manifest,
    1L,
    [{ field_id: "lessee.name", value: "星海科技" }],
    CustomerMessenger,
    "subject-1",
    "enterprise-portal",
    2000L,
  )
  let provenance = customer.assignment("lessee.name").unwrap()
  assert_eq(provenance.owner, CustomerMessenger)
  assert_eq(provenance.source_ref, "enterprise-portal")
  try
    customer.update_information(
      manifest,
      2L,
      [{ field_id: "lessor.name", value: "不应允许" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      3000L,
    )
  catch {
    InvalidInput("contract field is owned by another participant") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("customer must not edit manager-owned information")
  }
}

///|
fn lifecycle_test_packet(
  packet_id : String,
  state : @contractdoc.ContractPacketState,
  revision : Int64,
  values_sha256 : String?,
) -> @contractdoc.ContractPacket {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = try! @contractdoc.new_packet(
    manifest,
    packet_id,
    "\{packet_id}-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  )
  { ..packet, state, revision, values_sha256 }
}

///|
test "failed generation records the reason and retries with the confirmed digest" {
  let digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let requested = lifecycle_test_packet(
    "packet-retry",
    GenerationRequested,
    3L,
    Some(digest),
  )
  let draft = { ..requested, state: InformationDraft }
  try draft.fail_generation(3L, "renderer crashed", 4000L) catch {
    InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("only a requested generation may fail")
  }
  try requested.fail_generation(3L, "  ", 4000L) catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("empty failure reasons must be rejected")
  }
  let failed = requested.fail_generation(3L, "renderer crashed", 4000L)
  assert_eq(failed.state, GenerationFailed)
  assert_eq(failed.generation_failure, Some("renderer crashed"))
  let retried = failed.request_generation(failed.revision, digest, 5000L)
  assert_eq(retried.state, GenerationRequested)
  assert_eq(retried.generation_failure, None)
  let failed_again = retried.fail_generation(
    retried.revision,
    "renderer crashed again",
    6000L,
  )
  try
    failed_again.request_generation(
      failed_again.revision,
      "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      7000L,
    )
  catch {
    ConfirmationMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a stale digest must not retry generation")
  }
}

///|
test "execution registration requires generated state and valid evidence" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let generated = lifecycle_test_packet(
    "packet-execution",
    Generated,
    5L,
    Some(digest),
  )
  let evidence : @contractdoc.ContractExecution = {
    evidence_sha256: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    signed_on: "2026-08-14",
    registered_by: "operator-1",
    registered_unix_ms: 6000L,
  }
  let drafting = { ..generated, state: InformationDraft }
  try drafting.register_execution(5L, evidence, 6000L) catch {
    InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("only a generated packet may register execution")
  }
  try
    generated.register_execution(
      5L,
      { ..evidence, evidence_sha256: "not-a-digest" },
      6000L,
    )
  catch {
    InvalidEvidence(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a malformed evidence digest must be rejected")
  }
  try
    generated.register_execution(5L, { ..evidence, signed_on: " " }, 6000L)
  catch {
    InvalidEvidence(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an empty signing date must be rejected")
  }
  for
    bad_date in [
      "14/08/2026", "2026-8-4", "2026-13-14", "2026-08-00", "2026-08-32",
    ] {
    try
      generated.register_execution(
        5L,
        { ..evidence, signed_on: bad_date },
        6000L,
      )
    catch {
      InvalidExecutionDate(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("a malformed signing date must be rejected: \{bad_date}")
    }
  }
  try
    generated.register_execution(5L, { ..evidence, registered_by: "" }, 6000L)
  catch {
    InvalidEvidence(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an invalid registrar must be rejected")
  }
  let effective = generated.register_execution(5L, evidence, 6000L)
  assert_eq(effective.state, Effective)
  assert_eq(effective.execution, Some(evidence))
  try
    effective.update_information(
      manifest,
      effective.revision,
      [{ field_id: "lessee.name", value: "事后修改" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      7000L,
    )
  catch {
    InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an effective packet must not accept edits")
  }
}

///|
test "closure requires an effective packet and settlements for early termination" {
  let effective = lifecycle_test_packet("packet-closure", Effective, 6L, None)
  let expiry : @contractdoc.ContractClosure = {
    kind: Expired,
    reason: "lease term ended",
    closed_by: "operator-1",
    closed_unix_ms: 8000L,
  }
  let generated = { ..effective, state: Generated }
  try generated.close_packet(6L, expiry, false, 8000L) catch {
    InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("only an effective packet may close")
  }
  let early : @contractdoc.ContractClosure = {
    kind: EarlyTermination,
    reason: "tenant vacated ahead of term",
    closed_by: "operator-1",
    closed_unix_ms: 8000L,
  }
  try effective.close_packet(6L, early, false, 8000L) catch {
    InvalidInput("early termination requires a confirmed settlement") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("early termination without settlement must be rejected")
  }
  let terminated = effective.close_packet(6L, early, true, 8000L)
  assert_eq(terminated.state, Closed)
  assert_eq(terminated.closure, Some(early))
  let settled = effective.close_packet(
    6L,
    {
      kind: Settled,
      reason: "balance cleared",
      closed_by: "operator-1",
      closed_unix_ms: 8000L,
    },
    false,
    8000L,
  )
  assert_eq(settled.state, Closed)
  let closed = effective.close_packet(6L, expiry, false, 8000L)
  assert_eq(closed.state, Closed)
  assert_eq(closed.closure, Some(expiry))
  try effective.close_packet(6L, { ..expiry, reason: "" }, false, 8000L) catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an empty closure reason must be rejected")
  }
}

///|
test "supersession is rejected for effective or terminal packets" {
  let packet = lifecycle_test_packet(
    "packet-supersede",
    InformationDraft,
    1L,
    None,
  )
  let supersession : @contractdoc.ContractSupersession = {
    successor_ref: "packet-successor",
    reason: "reissued with corrected dates",
    superseded_by: "operator-1",
    superseded_unix_ms: 3000L,
  }
  let superseded = packet.supersede_packet(1L, supersession, 3000L)
  assert_eq(superseded.state, Superseded)
  assert_eq(superseded.supersession, Some(supersession))
  let terminal_states : Array[@contractdoc.ContractPacketState] = [
    Effective,
    Closed,
    Superseded,
  ]
  for state in terminal_states {
    let terminal = { ..packet, state, }
    try terminal.supersede_packet(1L, supersession, 3000L) catch {
      InvalidTransition(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("effective or terminal packets must not be superseded")
    }
  }
  try
    packet.supersede_packet(1L, { ..supersession, successor_ref: "" }, 3000L)
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an invalid successor reference must be rejected")
  }
  try
    packet.supersede_packet(1L, { ..supersession, reason: " " }, 3000L)
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an empty supersession reason must be rejected")
  }
}

///|
test "follow-up forms map to the effective creation stage" {
  assert_eq(@contractdoc.form_creation_stage(MasterLease), InitialStage)
  assert_eq(
    @contractdoc.form_creation_stage(ReservationApplication),
    InitialStage,
  )
  assert_eq(
    @contractdoc.form_creation_stage(AccessConfirmation),
    EffectiveStage,
  )
  assert_eq(@contractdoc.form_creation_stage(ViolationNotice), EffectiveStage)
  assert_eq(@contractdoc.form_creation_stage(DamageAssessment), EffectiveStage)
  assert_eq(
    @contractdoc.form_creation_stage(SettlementConfirmation),
    EffectiveStage,
  )
  assert_eq(
    @contractdoc.form_creation_stage(EarlyTerminationApplication),
    EffectiveStage,
  )
}

///|
test "renewal draft carries initial forms and drops offline and derived values" {
  let base = @contractdoc.youthpolicy_remote_lease_manifest()
  let derived : @contractdoc.ContractFieldDefinition = {
    field_id: "lease.derived_marker",
    form: MasterLease,
    label_zh_cn: "派生标记",
    label_en: "Derived marker",
    kind: PlainText,
    required: false,
    maximum_characters: 64,
    allowed_values: [],
    collection_policy: PersistedContractData,
    owner: PlatformDerived,
    locator: "synthetic",
  }
  let manifest = { ..base, fields: base.fields + [derived] }
  let source = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-source",
      "packet-source-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      None,
      [MasterLease, AccessConfirmation],
      1000L,
    ),
    state: Effective,
    values: [
      { field_id: "lessee.name", value: "星海科技" },
      { field_id: "lease.start_date", value: "2026-09-01" },
      { field_id: "lease.derived_marker", value: "derived-value" },
      { field_id: "lessee.signatory", value: "offline-signature" },
      { field_id: "access.order_number", value: "order-1" },
    ],
  }
  let renewal = source.renewal_draft(
    manifest, "packet-renewal-1", "packet-renewal-key-1", 5000L,
  )
  assert_eq(renewal.packet_id, "packet-renewal-1")
  assert_eq(renewal.idempotency_key, "packet-renewal-key-1")
  assert_eq(renewal.state, InformationDraft)
  assert_eq(renewal.revision, 1L)
  // Effective-stage forms are relationship children and do not renew.
  assert_eq(renewal.active_forms, [MasterLease])
  assert_eq(renewal.preceding_packet_ref, Some("packet-source"))
  assert_eq(renewal.tenant_ref, "tenant-1")
  assert_eq(renewal.organization_id, "org-1")
  assert_eq(renewal.subject_ref, "subject-1")
  assert_eq(renewal.order_ref, "order-1")
  assert_eq(renewal.value("lessee.name"), Some("星海科技"))
  assert_eq(renewal.value("lease.start_date"), Some("2026-09-01"))
  // Platform-derived values are re-derived by the server; offline-completed
  // signatures are redone offline; neither is copied.
  assert_eq(renewal.value("lease.derived_marker"), None)
  assert_eq(renewal.value("lessee.signatory"), None)
  assert_eq(renewal.value("access.order_number"), None)
  assert_eq(renewal.values_sha256, None)
  assert_eq(renewal.created_unix_ms, 5000L)
}

///|
test "renewal draft requires an effective source with initial-stage forms" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let drafting = @contractdoc.new_packet(
    manifest,
    "packet-draft",
    "packet-draft-key",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    None,
    [MasterLease],
    1000L,
  )
  try
    drafting.renewal_draft(
      manifest, "packet-renewal-2", "packet-renewal-key-2", 5000L,
    )
  catch {
    ContractNotRenewable(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a non-effective packet must not renew")
  }
  let follow_up_only = {
    ..@contractdoc.new_packet(
      manifest,
      "packet-followup",
      "packet-followup-key",
      "tenant-1",
      "org-1",
      "subject-1",
      "order-1",
      Some("packet-master"),
      [AccessConfirmation],
      1000L,
    ),
    state: Effective,
  }
  try
    follow_up_only.renewal_draft(
      manifest, "packet-renewal-3", "packet-renewal-key-3", 5000L,
    )
  catch {
    ContractNotRenewable(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a packet without initial-stage forms must not renew")
  }
}

///|
test "contract dates and money render stable human-readable values" {
  assert_eq(@contractdoc.format_unix_ms_utc(0L), "1970-01-01 00:00:00 UTC")
  assert_eq(
    @contractdoc.format_unix_ms_utc(1787184000000L),
    "2026-08-20 00:00:00 UTC",
  )
  assert_eq(@contractdoc.format_cny_minor_units(0L), "0.00")
  assert_eq(@contractdoc.format_cny_minor_units(12345L), "123.45")
  assert_eq(@contractdoc.format_cny_minor_units(-5L), "-0.05")
}
