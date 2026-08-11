///|
let document_hash : String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
fn base_store() -> @commercial.CommercialStore raise {
  let store = @commercial.CommercialStore::new()
  store.add_organization({
    organization_id: "org-a",
    display_name: "Alpha Research",
    state: Active,
    verification_ref: Some("verify:alpha"),
    created_unix_ms: 1000L,
  })
  store.add_cost_center({
    cost_center_id: "cc-a",
    organization_id: "org-a",
    parent_cost_center_id: None,
    display_name: "Inference",
    created_unix_ms: 1000L,
  })
  store.add_project({
    project_id: "project-a",
    organization_id: "org-a",
    cost_center_id: "cc-a",
    display_name: "=Serving",
    created_unix_ms: 1000L,
  })
  store.grant_role({
    grant_id: "grant-owner",
    organization_id: "org-a",
    user_id: "owner-a",
    role: OrganizationOwner,
    granted_by: "owner-a",
    granted_unix_ms: 1000L,
    expires_unix_ms: None,
  })
  store.grant_role({
    grant_id: "grant-billing",
    organization_id: "org-a",
    user_id: "finance-a",
    role: BillingAdministrator,
    granted_by: "owner-a",
    granted_unix_ms: 1001L,
    expires_unix_ms: None,
  })
  store.grant_role({
    grant_id: "grant-legal",
    organization_id: "org-a",
    user_id: "signer-a",
    role: LegalSigner,
    granted_by: "owner-a",
    granted_unix_ms: 1002L,
    expires_unix_ms: None,
  })
  store.grant_role({
    grant_id: "grant-procurement",
    organization_id: "org-a",
    user_id: "approver-a",
    role: ProcurementApprover,
    granted_by: "owner-a",
    granted_unix_ms: 1003L,
    expires_unix_ms: None,
  })
  store
}

///|
fn usage(
  event_id : String,
  quantity : Int64,
  started_unix_ms? : Int64 = 2000L,
  ended_unix_ms? : Int64 = 3000L,
) -> @commercial.UsageObservation {
  {
    event_id,
    organization_id: "org-a",
    project_id: "project-a",
    actor_ref: "actor-a",
    workload_id: "lease-a",
    node_id: "dgx-1",
    lease_epoch: 1L,
    meter: "node-second",
    quantity,
    unit: "second",
    started_unix_ms,
    ended_unix_ms,
    observed_unix_ms: ended_unix_ms + 1L,
  }
}

///|
fn rate(price : Int64) -> @commercial.RateCard raise {
  {
    rate_card_id: "lease-rate",
    version: "v1",
    meter: "node-second",
    unit: "second",
    unit_price: @commercial.money(price, "CNY", 2),
    effective_from_unix_ms: 1000L,
    effective_until_unix_ms: 10000L,
  }
}

///|
fn add_rated_usage(
  store : @commercial.CommercialStore,
  event_id : String,
  entry_id : String,
  quantity : Int64,
) -> @commercial.LedgerEntry raise {
  ignore(store.ingest_usage(usage(event_id, quantity)))
  let (entry, _) = store.rate_usage(event_id, entry_id, rate(2L), 3100L)
  entry
}

///|
test "hierarchy rejects cross-tenant parentage" {
  let store = base_store()
  store.add_organization({
    organization_id: "org-b",
    display_name: "Beta Research",
    state: Active,
    verification_ref: None,
    created_unix_ms: 1000L,
  })
  let mut rejected = false
  store.add_project({
    project_id: "project-bad",
    organization_id: "org-b",
    cost_center_id: "cc-a",
    display_name: "Cross tenant",
    created_unix_ms: 1100L,
  }) catch {
    TenantMismatch => rejected = true
    _ => ()
  }
  assert_true(rejected)
  let mut usage_rejected = false
  ignore(
    store.ingest_usage({
      ..usage("cross-tenant-event", 1L),
      organization_id: "org-b",
    }),
  ) catch {
    TenantMismatch => usage_rejected = true
    _ => ()
  }
  assert_true(usage_rejected)
  assert_eq(store.snapshot("org-a").projects.length(), 1)
  assert_eq(store.snapshot("org-b").projects.length(), 0)
}

///|
test "period closure refuses unrated observations" {
  let store = base_store()
  ignore(store.ingest_usage(usage("unrated", 10L)))
  let mut rejected = false
  ignore(
    store.finalize_period(
      "period-unrated", "org-a", 1500L, 4000L, "UTC", "CNY", 2, "finance-a", 5000L,
    ),
  ) catch {
    InvalidInput("period contains unrated usage") => rejected = true
    _ => ()
  }
  assert_true(rejected)
  assert_eq(store.snapshot("org-a").finalized_periods.length(), 0)
}

///|
test "fixed money rejects invalid units, mismatch, and overflow" {
  let mut invalid = false
  ignore(@commercial.money(1L, "usd", 2)) catch {
    InvalidInput(_) => invalid = true
    _ => ()
  }
  assert_true(invalid)
  let mut mismatch = false
  ignore(@commercial.money(1L, "CNY", 2).add(@commercial.money(1L, "USD", 2))) catch {
    CurrencyMismatch => mismatch = true
    _ => ()
  }
  assert_true(mismatch)
  let mut overflow = false
  ignore(
    @commercial.money(9223372036854775807L, "CNY", 2).add(
      @commercial.money(1L, "CNY", 2),
    ),
  ) catch {
    ArithmeticOverflow => overflow = true
    _ => ()
  }
  assert_true(overflow)
}

///|
test "usage normalization and rating are exactly-once" {
  let store = base_store()
  assert_eq(store.ingest_usage(usage("event-1", 10L)), Created)
  assert_eq(store.ingest_usage(usage("event-1", 10L)), Replayed)
  let mut changed = false
  ignore(store.ingest_usage(usage("event-1", 11L))) catch {
    IdempotencyConflict(_) => changed = true
    _ => ()
  }
  assert_true(changed)
  let (entry, first) = store.rate_usage("event-1", "entry-1", rate(2L), 3100L)
  assert_eq(first, Created)
  assert_eq(entry.amount.minor_units, 20L)
  let (_, replay) = store.rate_usage("event-1", "entry-1", rate(2L), 3100L)
  assert_eq(replay, Replayed)
  let mut rerated = false
  ignore(store.rate_usage("event-1", "entry-2", rate(3L), 3100L)) catch {
    @commercial.CommercialError::IdempotencyConflict(_) => rerated = true
    _ => ()
  }
  assert_true(rerated)
  assert_eq(store.snapshot("org-a").ledger_entries.length(), 1)
}

///|
test "negative usage and rating overflow fail closed" {
  let store = base_store()
  let mut negative = false
  ignore(store.ingest_usage(usage("negative", -1L))) catch {
    InvalidInput(_) => negative = true
    _ => ()
  }
  assert_true(negative)
  ignore(store.ingest_usage(usage("huge", 9223372036854775807L)))
  let mut overflow = false
  ignore(store.rate_usage("huge", "entry-huge", rate(2L), 3100L)) catch {
    @commercial.CommercialError::ArithmeticOverflow => overflow = true
    _ => ()
  }
  assert_true(overflow)
  assert_eq(store.snapshot("org-a").ledger_entries.length(), 0)
}

///|
test "finalized periods are immutable and corrections stay linked" {
  let store = base_store()
  ignore(add_rated_usage(store, "event-1", "entry-1", 10L))
  let period = store.finalize_period(
    "2026-08", "org-a", 1500L, 4000L, "Asia/Shanghai", "CNY", 2, "finance-a", 5000L,
  )
  assert_eq(period.total.minor_units, 20L)
  let credit = store.append_adjustment(
    "credit-1",
    "org-a",
    "entry-1",
    Credit,
    @commercial.money(5L, "CNY", 2),
    "SLA credit",
    5100L,
  )
  assert_eq(credit.amount.minor_units, -5L)
  assert_eq(credit.linked_entry_id, Some("entry-1"))
  let adjustment_period = store.finalize_period(
    "2026-09", "org-a", 5000L, 6000L, "Asia/Shanghai", "CNY", 2, "finance-a", 7000L,
  )
  assert_eq(adjustment_period.total.minor_units, -5L)
  let mut late = false
  ignore(
    store.ingest_usage(
      usage("late-event", 1L, started_unix_ms=2500L, ended_unix_ms=2600L),
    ),
  ) catch {
    PeriodFinalized("2026-08") => late = true
    _ => ()
  }
  assert_true(late)
  let mut refinalize = false
  ignore(
    store.finalize_period(
      "2026-08", "org-a", 1500L, 4000L, "Asia/Shanghai", "CNY", 2, "finance-a", 5200L,
    ),
  ) catch {
    PeriodFinalized(_) => refinalize = true
    _ => ()
  }
  assert_true(refinalize)
  assert_eq(store.snapshot("org-a").finalized_periods[0], period)
}

///|
test "role elevation and commitment approval require separate actors" {
  let store = base_store()
  let mut self_elevation = false
  store.grant_role({
    grant_id: "grant-self",
    organization_id: "org-a",
    user_id: "owner-a",
    role: BillingAdministrator,
    granted_by: "owner-a",
    granted_unix_ms: 1100L,
    expires_unix_ms: None,
  }) catch {
    SeparationOfDuties(_) => self_elevation = true
    _ => ()
  }
  assert_true(self_elevation)
  store.add_commitment({
    commitment_id: "commitment-a",
    organization_id: "org-a",
    cluster_id: "cluster-a",
    gpu_class: "dgx-spark",
    service_mode: "exclusive-lease",
    capacity_units: 4L,
    effective_from_unix_ms: 2000L,
    effective_until_unix_ms: 9000L,
    created_by: "buyer-a",
    approved_by: None,
    state: Proposed,
  })
  let mut self_approval = false
  ignore(store.approve_commitment("org-a", "commitment-a", "buyer-a", 2100L)) catch {
    SeparationOfDuties(_) => self_approval = true
    _ => ()
  }
  assert_true(self_approval)
  let approved = store.approve_commitment(
    "org-a", "commitment-a", "approver-a", 2100L,
  )
  assert_eq(approved.state, ActiveCommitment)
}

///|
test "entitlements are deterministic, bounded, and replay-safe" {
  let store = base_store()
  for item in [("later", 9000L), ("earlier", 8000L)] {
    let (id, expiry) = item
    store.add_commitment({
      commitment_id: id,
      organization_id: "org-a",
      cluster_id: "cluster-a",
      gpu_class: "dgx-spark",
      service_mode: "managed",
      capacity_units: 2L,
      effective_from_unix_ms: 2000L,
      effective_until_unix_ms: expiry,
      created_by: "buyer-a",
      approved_by: None,
      state: Proposed,
    })
    ignore(store.approve_commitment("org-a", id, "approver-a", 2100L))
  }
  let decision = store.admit({
    organization_id: "org-a",
    project_id: "project-a",
    meter: "node-second",
    expected_quantity: 1L,
    expected_cost: @commercial.money(0L, "CNY", 2),
    required_capacity_units: 1L,
    required_agreement_types: [],
    now_unix_ms: 2200L,
  })
  assert_eq(decision.matching_commitment_id, Some("earlier"))
  let consumption : @commercial.EntitlementConsumption = {
    consumption_id: "consume-1",
    commitment_id: "earlier",
    organization_id: "org-a",
    workload_id: "deployment-a",
    quantity: 2L,
    consumed_unix_ms: 2300L,
  }
  assert_eq(store.consume_entitlement(consumption), Created)
  assert_eq(store.consume_entitlement(consumption), Replayed)
  let mut exhausted = false
  ignore(
    store.consume_entitlement({
      ..consumption,
      consumption_id: "consume-2",
      quantity: 1L,
    }),
  ) catch {
    AdmissionDenied(_) => exhausted = true
    _ => ()
  }
  assert_true(exhausted)
  assert_eq(store.remaining_capacity("earlier"), 0L)
}

///|
test "budgets, quotas, and agreement gates compose at admission" {
  let store = base_store()
  ignore(add_rated_usage(store, "existing", "entry-existing", 30L))
  store.add_budget({
    budget_id: "budget-a",
    organization_id: "org-a",
    project_id: Some("project-a"),
    limit: @commercial.money(100L, "CNY", 2),
    warning_percent: 80,
    warning_action: RequireApproval,
    hard_stop: true,
    grace_minor_units: 0L,
    effective_from_unix_ms: 1000L,
    effective_until_unix_ms: 9000L,
  })
  let warning = store.admit({
    organization_id: "org-a",
    project_id: "project-a",
    meter: "node-second",
    expected_quantity: 0L,
    expected_cost: @commercial.money(25L, "CNY", 2),
    required_capacity_units: 0L,
    required_agreement_types: [],
    now_unix_ms: 4000L,
  })
  assert_eq(warning.kind, ApprovalRequired)
  store.add_quota({
    quota_id: "quota-a",
    organization_id: "org-a",
    project_id: Some("project-a"),
    meter: "node-second",
    maximum_quantity: 40L,
    period_started_unix_ms: 1000L,
    period_ended_unix_ms: 9000L,
  })
  let decision = store.admit({
    organization_id: "org-a",
    project_id: "project-a",
    meter: "node-second",
    expected_quantity: 20L,
    expected_cost: @commercial.money(30L, "CNY", 2),
    required_capacity_units: 0L,
    required_agreement_types: ["acceptable-use"],
    now_unix_ms: 4000L,
  })
  assert_eq(decision.kind, Blocked)
  assert_true(decision.reasons.contains("quota exceeded:quota-a"))
  assert_true(decision.reasons.contains("missing agreement:acceptable-use"))
}

///|
test "clickwrap and signature evidence are version and tenant bound" {
  let store = base_store()
  store.register_agreement_template({
    template_id: "terms-a",
    agreement_type: "acceptable-use",
    version: "1.0.0",
    locale: "en-US",
    effective_unix_ms: 1000L,
    rendered_document_hash: document_hash,
    state: DraftTemplate,
    created_unix_ms: 1000L,
  })
  ignore(store.set_template_state("terms-a", "1.0.0", ReadyTemplate))
  let acceptance : @commercial.ClickwrapAcceptance = {
    acceptance_id: "acceptance-a",
    idempotency_key: "accept-key-a",
    organization_id: "org-a",
    user_id: "owner-a",
    template_id: "terms-a",
    template_version: "1.0.0",
    rendered_document_hash: document_hash,
    intent: "accept acceptable use",
    presentation_context_hash: "sha256:presentation",
    network_context_hash: "sha256:network",
    accepted_unix_ms: 2000L,
  }
  assert_eq(store.accept_clickwrap(acceptance), Created)
  assert_eq(store.accept_clickwrap(acceptance), Replayed)
  let allowed = store.admit({
    organization_id: "org-a",
    project_id: "project-a",
    meter: "node-second",
    expected_quantity: 0L,
    expected_cost: @commercial.money(0L, "CNY", 2),
    required_capacity_units: 0L,
    required_agreement_types: ["acceptable-use"],
    now_unix_ms: 2100L,
  })
  assert_eq(allowed.kind, Allowed)
  store.create_agreement({
    agreement_id: "agreement-a",
    organization_id: "org-a",
    template_id: "terms-a",
    template_version: "1.0.0",
    rendered_document_hash: document_hash,
    signer_user_id: "signer-a",
    signer_authority_ref: "authority:board",
    external_envelope_ref: Some("envelope-a"),
    executed_artifact_ref: None,
    executed_artifact_hash: None,
    state: DraftAgreement,
    created_unix_ms: 2200L,
    updated_unix_ms: 2200L,
  })
  ignore(
    store.transition_agreement(
      "org-a",
      "agreement-a",
      "signer-a",
      InternalReview,
      2300L,
    ),
  )
  ignore(
    store.transition_agreement(
      "org-a",
      "agreement-a",
      "signer-a",
      ReadyForSignature,
      2400L,
    ),
  )
  ignore(
    store.transition_agreement(
      "org-a",
      "agreement-a",
      "signer-a",
      AwaitingSigner,
      2500L,
    ),
  )
  let callback : @commercial.SignatureCallback = {
    callback_id: "signature-callback-a",
    organization_id: "org-a",
    agreement_id: "agreement-a",
    external_envelope_ref: "envelope-a",
    rendered_document_hash: document_hash,
    signer_user_id: "signer-a",
    expected_previous_state: AwaitingSigner,
    next_state: Executed,
    executed_artifact_ref: Some("artifact:agreement-a"),
    executed_artifact_hash: Some(document_hash),
    verified: true,
    received_unix_ms: 2600L,
  }
  let (executed, first) = store.reconcile_signature_callback(callback)
  assert_eq(first, Created)
  assert_eq(executed.state, Executed)
  let (_, replay) = store.reconcile_signature_callback(callback)
  assert_eq(replay, Replayed)
  let mut cross_tenant = false
  ignore(
    store.reconcile_signature_callback({
      ..callback,
      callback_id: "signature-callback-b",
      organization_id: "org-b",
    }),
  ) catch {
    TenantMismatch => cross_tenant = true
    _ => ()
  }
  assert_true(cross_tenant)
}

///|
test "tenant-scoped snapshot and privacy-safe CSV resist formula injection" {
  let store = base_store()
  store.add_organization({
    organization_id: "org-b",
    display_name: "Beta",
    state: Active,
    verification_ref: None,
    created_unix_ms: 1000L,
  })
  ignore(add_rated_usage(store, "event-export", "entry-export", 10L))
  let artifact = store.export_ledger_csv("org-a", "finance-a", None, 4000L)
  assert_eq(artifact.row_count, 1)
  assert_true(artifact.content_sha256.has_prefix("sha256:"))
  assert_false(artifact.csv_content.contains("actor-a"))
  assert_false(artifact.csv_content.contains("dgx-1"))
  assert_true(artifact.csv_content.contains("\"'=Serving\""))
  let mut denied = false
  ignore(store.export_ledger_csv("org-b", "finance-a", None, 4000L)) catch {
    PermissionDenied(_) => denied = true
    _ => ()
  }
  assert_true(denied)
  assert_eq(store.snapshot("org-b").ledger_entries.length(), 0)
  let summary = store.summary("org-a", "CNY", 2, 4000L)
  assert_eq(summary.provisional_total.minor_units, 20L)
}

///|
test "durable commercial snapshot restores tenant hierarchy and idempotency indexes" {
  let store = @commercial.CommercialStore::new()
  store.add_organization({
    organization_id: "org-durable",
    display_name: "Durable Organization",
    state: Active,
    verification_ref: Some("identity-evidence"),
    created_unix_ms: 1000L,
  })
  store.add_cost_center({
    cost_center_id: "cc-durable",
    organization_id: "org-durable",
    parent_cost_center_id: None,
    display_name: "Durable Cost Center",
    created_unix_ms: 1001L,
  })
  store.add_project({
    project_id: "project-durable",
    organization_id: "org-durable",
    cost_center_id: "cc-durable",
    display_name: "Durable Project",
    created_unix_ms: 1002L,
  })
  let snapshot = store.durable_snapshot()
  let encoded = snapshot.to_json().stringify()
  let decoded : @commercial.CommercialDurableSnapshot = @json.from_json(
    @json.parse(encoded),
  )
  let restored = @commercial.CommercialStore::from_durable_snapshot(decoded)
  assert_eq(restored.durable_snapshot(), snapshot)
}
