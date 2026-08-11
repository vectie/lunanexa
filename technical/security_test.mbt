///|
fn transfer_grant() -> @technical.TransferGrant {
  {
    grant_id: "grant-1",
    nonce: "nonce-unique-0001",
    node_id: "dgx-2",
    deployment_id: "deployment-1",
    model_digest: model_digest(),
    scope: ModelRead,
    issued_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
}

///|
fn transfer_use() -> @technical.TransferGrantUse {
  {
    node_id: "dgx-2",
    deployment_id: "deployment-1",
    model_digest: model_digest(),
    scope: ModelRead,
  }
}

///|
test "transfer grant is short lived one use and fully bound" {
  let grant = transfer_grant()
  let requested = transfer_use()
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      requested,
      Verified,
      [],
      1500L,
      1000L,
    ),
    Accepted(consumed_nonce="nonce-unique-0001"),
  )
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      requested,
      Verified,
      ["nonce-unique-0001"],
      1500L,
      1000L,
    ),
    Rejected(NonceReplayed),
  )
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      { ..requested, node_id: "dgx-3" },
      Verified,
      [],
      1500L,
      1000L,
    ),
    Rejected(NodeMismatch),
  )
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      requested,
      Verified,
      [],
      2000L,
      1000L,
    ),
    Rejected(GrantExpired),
  )
  assert_eq(
    @technical.validate_transfer_grant(
      grant,
      requested,
      Unverified,
      [],
      1500L,
      1000L,
    ),
    Rejected(AuthenticityRequired),
  )
}

///|
test "only reviewed named sidecars with opaque config references are accepted" {
  let decision = @technical.select_sidecar_profiles(
    [
      { profile: InferenceGateway, configuration_ref: "config://gateway/v1" },
      { profile: TelemetryExporter, configuration_ref: "config://metrics/v1" },
    ],
    [InferenceGateway, TelemetryExporter],
  )
  match decision {
    Accepted(profiles) => {
      assert_eq(profiles.length(), 2)
      assert_true(profiles.all(profile => profile.read_only_root))
      assert_true(profiles.all(profile => profile.drops_all_capabilities))
      assert_true(profiles.all(profile => !profile.host_network))
    }
    Rejected(reason) => fail("unexpected sidecar rejection: \{Repr(reason)}")
  }
  assert_eq(
    @technical.select_sidecar_profiles(
      [
        { profile: InferenceGateway, configuration_ref: "config://one" },
        { profile: InferenceGateway, configuration_ref: "config://two" },
      ],
      [InferenceGateway],
    ),
    Rejected(DuplicateProfile),
  )
  assert_eq(
    @technical.select_sidecar_profiles(
      [{ profile: CertificateReloader, configuration_ref: "raw:yaml" }],
      [CertificateReloader],
    ),
    Rejected(InvalidConfigurationReference),
  )
  assert_eq(
    @technical.select_sidecar_profiles(
      [
        {
          profile: CertificateReloader,
          configuration_ref: "config://../host-secret",
        },
      ],
      [CertificateReloader],
    ),
    Rejected(InvalidConfigurationReference),
  )
}

///|
fn cache_entry() -> @technical.CacheEntryTelemetry {
  {
    node_ref: "node-ref-2",
    model_digest: model_digest(),
    lifecycle: Ready,
    logical_bytes: 1024L,
    transferred_bytes: 1024L,
    assignment_references: 1,
    signature_verified: true,
    last_access_unix_ms: 1000L,
    observed_unix_ms: 1100L,
  }
}

///|
test "cache telemetry exposes safe lifecycle fields and never evicts references" {
  assert_eq(
    @technical.cache_reconcile_action(cache_entry(), 2000L, 1000L),
    RetainReferenced,
  )
  assert_eq(
    @technical.cache_reconcile_action(
      { ..cache_entry(), assignment_references: 0 },
      2000L,
      1000L,
    ),
    EligibleForEviction,
  )
  let invalid = {
    ..cache_entry(),
    transferred_bytes: 100L,
    signature_verified: false,
  }
  let findings = @technical.validate_cache_telemetry(invalid)
  assert_true(findings.contains(ReadyWithoutCompleteTransfer))
  assert_true(findings.contains(ReadyWithoutSignature))
  assert_eq(
    @technical.cache_reconcile_action(cache_entry(), 1L, 0L),
    QuarantineInvalidTelemetry([InvalidPressureBounds]),
  )
  let encoded = cache_entry().to_json().stringify()
  assert_false(encoded.contains("path"))
  assert_false(encoded.contains("uri"))
  assert_false(encoded.contains("credential"))
}

///|
test "decision snapshots round trip through JSON" {
  let decision = @technical.decide_autoscale(
    autoscale_policy(),
    autoscale_snapshot(),
  )
  let encoded = decision.to_json().stringify()
  let decoded : @technical.AutoscaleDecision = @json.from_json(
    @json.parse(encoded),
  )
  assert_eq(decoded, decision)
}
