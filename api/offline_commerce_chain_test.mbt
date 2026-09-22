///|
fn chain_operator() -> Map[String, String] {
  { "Authorization": "Bearer operator-token" }
}

///|
fn chain_purchaser() -> Map[String, String] {
  {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
}

///|
fn chain_other_purchaser() -> Map[String, String] {
  {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
}

///|
fn chain_worker() -> Map[String, String] {
  { "Authorization": "Bearer artifact-worker-token-32-bytes-minimum-a" }
}

///|
fn chain_scanner() -> Map[String, String] {
  { "Authorization": "Bearer artifact-scanner-token-32-bytes-minimum-b" }
}

///|
fn chain_authority() -> Map[String, String] {
  { "Authorization": "Bearer entitlement-authority-token-32-bytes-minimum-c" }
}

///|
fn chain_transfer_adapter() -> Map[String, String] {
  {
    "Authorization": "Bearer offline-transfer-adapter-token-32-bytes-minimum-d",
  }
}

///|
priv struct ChainTransferIntent {
  session_id : String
  idempotency_key : String
  expires_unix_ms : Int64
} derive(FromJson)

///|
/// Seeds the durable proofs the store documents for acceptance tests: recent
/// dispatcher heartbeats/successes and a recent reconciler pass, one minute in
/// the past so a later real claim is observable as a strictly newer heartbeat.
async fn offline_chain_fixture(
  directory : String,
  transfer_endpoint : String,
) -> (@api.ApiService, @offline_store.OfflineCommerceStore) {
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let now = @async.now()
  ignore(
    portal.put_membership({
      membership_id: "member-chain-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  ignore(
    portal.put_membership({
      membership_id: "member-chain-b",
      tenant_ref: "tenant-b",
      organization_id: "org-b",
      subject_ref: "subject-b",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline-commerce.json",
  )
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let seeded = now - 60000L
  offline.record_worker_acceptance(ArtifactDispatcher, seeded)
  offline.record_worker_acceptance(EntitlementDispatcher, seeded)
  offline.record_reconciler_attempt(seeded)
  offline.record_reconciler_success(seeded)
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_offline_commerce_store(offline)
    .with_notification_store(notifications)
    .with_offline_artifact_callback_tokens(
      "artifact-worker-token-32-bytes-minimum-a", "artifact-scanner-token-32-bytes-minimum-b",
    )
    .with_entitlement_authority_callback_token(
      "entitlement-authority-token-32-bytes-minimum-c",
    )
    .with_offline_transfer_adapter(
      transfer_endpoint, "offline-transfer-adapter-token-32-bytes-minimum-d", "offline-transfer-session-secret-32-bytes-minimum-e",
    )
    .with_offline_commerce_capabilities(
      offline_ready_capabilities(),
      @async.now() + 3600000L,
    )
  (service, offline)
}

///|
async fn chain_snapshot(
  service : @api.ApiService,
) -> @offline.OfflineCommerceSnapshot {
  let response = service.handle(
    Get,
    "/v1/offline-commerce/operator/snapshot",
    chain_operator(),
    "",
  )
  if response.status != 200 {
    fail("operator snapshot failed: \{response.status} \{response.body}")
  }
  @json.from_json(@json.parse(response.body))
}

///|
fn chain_order(
  snapshot : @offline.OfflineCommerceSnapshot,
  order_id : String,
) -> @offline.CommercialOrder raise {
  match snapshot.orders.filter(order => order.order_id == order_id).get(0) {
    Some(order) => order
    None => fail("order \{order_id} is missing from the operator snapshot")
  }
}

///|
fn chain_grant(
  snapshot : @offline.OfflineCommerceSnapshot,
  grant_id : String,
) -> @offline.EvidenceUploadGrant raise {
  match
    snapshot.upload_grants.filter(grant => grant.grant_id == grant_id).get(0) {
    Some(grant) => grant
    None =>
      fail("upload grant \{grant_id} is missing from the operator snapshot")
  }
}

///|
async fn chain_self_order(
  service : @api.ApiService,
  order_id : String,
) -> @offline.CommercialOrder {
  let response = service.handle(
    Get,
    "/v1/offline-commerce/self/orders",
    chain_purchaser(),
    "",
  )
  if response.status != 200 {
    fail("purchaser order projection failed: \{response.status}")
  }
  let orders : Array[@offline.CommercialOrder] = @json.from_json(
    @json.parse(response.body),
  )
  match orders.filter(order => order.order_id == order_id).get(0) {
    Some(order) => order
    None => fail("order \{order_id} is missing from the purchaser projection")
  }
}

///|
fn chain_assert_operator_projection(body : String) -> Unit raise {
  assert_false(body.contains("document_bytes"))
  assert_false(body.contains("private_key"))
  assert_false(body.contains("session_secret"))
}

///|
fn chain_assert_purchaser_projection(body : String) -> Unit raise {
  assert_false(body.contains("object://"))
  assert_false(body.contains("s3://"))
  assert_false(body.contains("object_ref"))
  assert_false(body.contains("worker_receipt"))
  assert_false(body.contains("creator_receipt"))
  assert_false(body.contains("scanner_receipt"))
  assert_false(body.contains("session_token"))
  assert_false(body.contains("authority_receipt"))
  assert_false(body.contains("session_token_sha256"))
}

///|
async test "offline commerce chain fails closed until every deployment proof exists" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-chain-gate-")
  defer @fs.rmdir(directory, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let offline = @offline_store.OfflineCommerceStore::open(
    "\{directory}/offline.json",
  )
  let bare = @api.ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_offline_commerce_store(offline)
  let readiness = bare.handle(
    Get,
    "/v1/offline-commerce/operator/readiness",
    chain_operator(),
    "",
  )
  assert_eq(readiness.status, 200)
  assert_true(readiness.body.contains("OfflineCommerceAdaptersPending"))
  assert_true(readiness.body.contains("MoonLeafPdfRendererPending"))
  assert_true(readiness.body.contains("CjkFontsPending"))
  assert_true(readiness.body.contains("ApprovedLegalTemplatesPending"))
  assert_true(readiness.body.contains("ReadinessEvidenceExpired"))
  assert_true(
    readiness.body.contains("ReadinessArtifactDispatcherHeartbeatStale"),
  )
  assert_true(
    readiness.body.contains("ReadinessEntitlementDispatcherSuccessStale"),
  )
  assert_true(readiness.body.contains("ReadinessOfflineReconcilerDegraded"))
  assert_true(
    readiness.body.contains("ReadinessArtifactWorkerCallbackUnavailable"),
  )
  assert_true(readiness.body.contains("ReadinessTransferAdapterUnavailable"))
  // No initiating route may proceed on an unproven deployment.
  let blocked = bare.handle(
    Post,
    "/v1/offline-commerce/operator/quotes",
    chain_operator(),
    "{}",
  )
  assert_eq(blocked.status, 503)
  assert_true(blocked.body.contains("OfflineCommerceNotReady"))
  // Only the blockers for the capabilities this route requires cross the gate.
  assert_true(blocked.body.contains("ApprovedLegalTemplatesPending"))
  assert_true(blocked.body.contains("FinanceLegalPolicyPending"))
  assert_true(blocked.body.contains("ReadinessEvidenceExpired"))
  assert_false(blocked.body.contains("MoonLeafPdfRendererPending"))
  // A route whose required capability set differs reports its own blockers.
  let unproven_generation : @offline.ArtifactGenerationRequest = {
    request_id: "request-unproven",
    order_id: "order-unproven",
    organization_id: "org-a",
    artifact_id: "artifact-unproven",
    kind: PrintReadyContractPdf,
    template_id: "contract-unproven",
    template_version: "v1",
    locale: "zh-CN",
    expected_object_ref: "s3://orders/order-unproven/contract.pdf",
    input_snapshot_sha256: "sha256:" + "a".repeat(64),
    requested_by: "platform-operator",
    requested_unix_ms: @async.now(),
  }
  let gated_generation = bare.handle(
    Post,
    "/v1/offline-commerce/operator/generation-requests",
    chain_operator(),
    unproven_generation.to_json().stringify(),
  )
  assert_eq(gated_generation.status, 503)
  assert_true(gated_generation.body.contains("OoxmlWorkerPending"))
  assert_true(gated_generation.body.contains("MoonLeafPdfRendererPending"))
  assert_true(gated_generation.body.contains("CjkFontsPending"))
  assert_false(gated_generation.body.contains("FinanceLegalPolicyPending"))
  assert_eq(
    bare.handle(
      Post,
      "/v1/offline-commerce/operator/fulfillments",
      chain_operator(),
      "{}",
    ).status,
    503,
  )

  // The same store with only the machine identities configured: the evidence
  // window and dispatcher proofs are still absent, so the gate stays closed
  // while terminal callbacks remain reachable for already-issued work.
  let directory_identities = @fs.tmpdir(prefix="lunanexa-offline-chain-ident-")
  defer @fs.rmdir(directory_identities, recursive=true)
  let portal = @portal_store.FilePortalStore::open(
    "\{directory_identities}/portal.json",
  )
  let now = @async.now()
  ignore(
    portal.put_membership({
      membership_id: "member-chain-gate",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [LeaseRequester],
      active: true,
      created_unix_ms: now,
    }),
  )
  let identified = @api.ApiService::new(
      @store.FileStore::open("\{directory_identities}/state.json"),
      @runtimes.OpenAiTextRuntime::new(
        "http://127.0.0.1:1/v1/responses",
        "runtime-secret",
        "runtime-v1",
        "sha256:" + "b".repeat(64),
        "sha256:" + "a".repeat(64),
        allow_http_loopback=true,
      ),
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_offline_commerce_store(
      @offline_store.OfflineCommerceStore::open(
        "\{directory_identities}/offline.json",
      ),
    )
    .with_offline_artifact_callback_tokens(
      "artifact-worker-token-32-bytes-minimum-a", "artifact-scanner-token-32-bytes-minimum-b",
    )
  assert_eq(
    identified.handle(
      Post,
      "/v1/offline-commerce/self/upload-grants",
      chain_purchaser(),
      "{}",
    ).status,
    503,
  )
  assert_eq(
    identified.handle(
      Get,
      "/v1/offline-commerce/operator/generation-requests/pending",
      chain_worker(),
      "",
    ).status,
    200,
  )
  let terminal = identified.handle(
    Post,
    "/v1/offline-commerce/operator/generation-results",
    chain_worker(),
    "{}",
  )
  // Readiness gates initiation only; a malformed terminal callback reaches
  // validation instead of the gate.
  assert_eq(terminal.status, 400)
  assert_false(terminal.body.contains("OfflineCommerceNotReady"))
}

///|
async test "offline commerce chain walks order evidence entitlement transfer and download" {
  let directory = @fs.tmpdir(prefix="lunanexa-offline-chain-")
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let endpoint = "http://\{adapter.addr}/v1/offline-transfers"
  let (service, store) = offline_chain_fixture(directory, endpoint)
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((_request, body, connection) => {
        let intent : ChainTransferIntent = @json.from_json(
          @json.parse(body.read_all().text()),
        )
        connection.send_response(201, "Created", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          (
            {
              "session_id": intent.session_id,
              "transfer_url": "\{endpoint}/\{intent.session_id}",
              "expires_unix_ms": intent.expires_unix_ms.to_json(),
              "provider_receipt": "provider-\{intent.idempotency_key}",
            } : Json).stringify(),
        )
        connection.end_response()
      })
    }
    let now = @async.now()
    let operator = chain_operator()
    let purchaser = chain_purchaser()
    let order_id = "order-chain-a"
    let digest_a = "sha256:" + "a".repeat(64)
    let digest_b = "sha256:" + "b".repeat(64)
    let digest_c = "sha256:" + "c".repeat(64)

    // 1. Readiness is evaluated from the seeded deployment proofs.
    let readiness = service.handle(
      Get,
      "/v1/offline-commerce/operator/readiness",
      operator,
      "",
    )
    assert_eq(readiness.status, 200)
    let evaluated : @offline.OfflineCommerceReadiness = @json.from_json(
      @json.parse(readiness.body),
    )
    assert_eq(evaluated.status, OfflineCommerceReady)
    assert_eq(evaluated.blocker_codes.length(), 0)
    let seeded_snapshot = chain_snapshot(service)
    let heartbeat_seeded = seeded_snapshot.worker_health.artifact_dispatcher_heartbeat_unix_ms.unwrap()

    // 2. Register the immutable template metadata.
    let template : @offline.DocumentTemplate = {
      template_id: "contract-chain",
      version: "v1",
      kind: ContractTemplate,
      locale: "zh-CN",
      media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      object_ref: "s3://templates/contract-chain-v1.docx",
      sha256: digest_a,
      byte_count: 20000L,
      active_content_allowed: false,
      created_unix_ms: now,
      superseded_unix_ms: None,
    }
    let registered = service.handle(
      Post,
      "/v1/offline-commerce/operator/templates",
      operator,
      template.to_json().stringify(),
    )
    assert_eq(registered.status, 201)
    let after_template = chain_snapshot(service)
    assert_eq(after_template.templates.length(), 1)
    assert_eq(after_template.templates[0].template_id, "contract-chain")
    chain_assert_operator_projection(registered.body)

    // The purchaser opens the draft intent the operator will quote.
    let create_body : Json = {
      "order_id": order_id,
      "idempotency_key": "idem-order-chain-a",
      "project_id": "project-chain",
      "selected_service_code": "exclusive-dgx",
      "selected_sla_code": "standard",
      "expires_unix_ms": (now + 7200000L).to_json(),
    }
    let created = service.handle(
      Post,
      "/v1/offline-commerce/self/orders",
      purchaser,
      create_body.stringify(),
    )
    assert_eq(created.status, 201)
    assert_true(created.body.contains("org-a"))
    assert_eq(chain_self_order(service, order_id).state, Draft)

    // 3. A drifted quote is refused; the arithmetic-checked quote is pinned.
    let drifted : @offline.ImmutableQuote = {
      ..offline_test_quote("chain-drift", now),
      lines: [
        {
          line_id: "line-1",
          description: "Exclusive machine lease",
          quantity: 2L,
          unit: "lease",
          unit_price: { currency: "CNY", minor_units: 50000L, scale: 2, },
          line_total: { currency: "CNY", minor_units: 100001L, scale: 2, },
        },
      ],
      subtotal: { currency: "CNY", minor_units: 100001L, scale: 2, },
      tax: { currency: "CNY", minor_units: 0L, scale: 2, },
      total: { currency: "CNY", minor_units: 100001L, scale: 2, },
    }
    let drift_body : Json = { "order_id": order_id, "quote": drifted.to_json() }
    let drift = service.handle(
      Post,
      "/v1/offline-commerce/operator/quotes",
      operator,
      drift_body.stringify(),
    )
    assert_eq(drift.status, 400)
    assert_true(drift.body.contains("OfflineCommerceRejected"))
    assert_eq(chain_order(chain_snapshot(service), order_id).state, Draft)
    let quote = offline_test_quote("chain", now)
    let quote_body : Json = { "order_id": order_id, "quote": quote.to_json() }
    let quoted = service.handle(
      Post,
      "/v1/offline-commerce/operator/quotes",
      operator,
      quote_body.stringify(),
    )
    assert_eq(quoted.status, 200)
    let after_quote = chain_snapshot(service)
    let quoted_order = chain_order(after_quote, order_id)
    assert_eq(quoted_order.state, Quoted)
    assert_eq(quoted_order.quote.unwrap().terms_digest, quote.terms_digest)
    assert_eq(chain_self_order(service, order_id).state, Quoted)

    // 4. Start the approval/offline state machine.
    let begin_body : Json = {
      "order_id": order_id,
      "expected_generation": quoted_order.generation.to_json(),
    }
    let begun = service.handle(
      Post,
      "/v1/offline-commerce/operator/begin",
      operator,
      begin_body.stringify(),
    )
    assert_eq(begun.status, 200)
    assert_eq(
      chain_order(chain_snapshot(service), order_id).state,
      PendingInternalApproval,
    )
    assert_eq(
      chain_self_order(service, order_id).state,
      PendingInternalApproval,
    )

    // 5. Enqueue the bound artifact work.
    let generation : @offline.ArtifactGenerationRequest = {
      request_id: "request-chain-pdf",
      order_id,
      organization_id: "org-a",
      artifact_id: "contract-pdf-chain",
      kind: PrintReadyContractPdf,
      template_id: "contract-chain",
      template_version: "v1",
      locale: "zh-CN",
      expected_object_ref: "s3://orders/order-chain-a/contract.pdf",
      input_snapshot_sha256: quote.terms_digest,
      requested_by: "body-supplied-identity",
      requested_unix_ms: now,
    }
    // Neither the body nor an mTLS ingress identity selects the recorded actor:
    // the route derives it and the durable request keeps the derived value.
    let operator_with_ingress = {
      "Authorization": "Bearer operator-token",
      "ssl-client-verify": "SUCCESS",
      "ssl-client-subject-dn": "CN=legal-reviewer,O=LunaNexa",
    }
    let enqueued = service.handle(
      Post,
      "/v1/offline-commerce/operator/generation-requests",
      operator_with_ingress,
      generation.to_json().stringify(),
    )
    assert_eq(enqueued.status, 202)
    assert_eq(chain_snapshot(service).generation_requests.length(), 1)

    // 6. The artifact dispatcher claims the work and records its heartbeat.
    let claimed = service.handle(
      Get,
      "/v1/offline-commerce/operator/generation-requests/pending",
      chain_worker(),
      "",
    )
    assert_eq(claimed.status, 200)
    let pending : Array[@offline.ArtifactGenerationRequest] = @json.from_json(
      @json.parse(claimed.body),
    )
    assert_eq(pending.length(), 1)
    assert_eq(pending[0].request_id, generation.request_id)
    assert_eq(pending[0].requested_by, "platform-operator")
    let after_claim = chain_snapshot(service)
    assert_true(
      after_claim.worker_health.artifact_dispatcher_heartbeat_unix_ms.unwrap() >
      heartbeat_seeded,
    )
    assert_eq(after_claim.work_claims.length(), 1)
    let success_before = after_claim.worker_health.artifact_dispatcher_success_unix_ms.unwrap()

    // 7. Forged and active-content results are refused; the verified terminal
    // result records the separate success proof.
    let verified : @offline.ArtifactGenerationResult = {
      request_id: pending[0].request_id,
      artifact_id: pending[0].artifact_id,
      expected_object_ref: pending[0].expected_object_ref,
      media_type: "application/pdf",
      byte_count: 30000L,
      sha256: digest_b,
      worker_receipt: "worker-receipt-chain",
      verified: true,
      active_content_detected: false,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: digest_a,
      completed_unix_ms: pending[0].requested_unix_ms + 1L,
    }
    let forged_results : Array[@offline.ArtifactGenerationResult] = [
      { ..verified, expected_object_ref: "s3://attacker/forged.pdf", },
      { ..verified, sha256: "sha256:not-a-digest", },
      { ..verified, active_content_detected: true, },
    ]
    for forged in forged_results {
      let body : Json = { "result": forged.to_json() }
      let refused = service.handle(
        Post,
        "/v1/offline-commerce/operator/generation-results",
        chain_worker(),
        body.stringify(),
      )
      assert_eq(refused.status, 409)
      assert_true(refused.body.contains("ArtifactUnavailable"))
    }
    assert_eq(chain_snapshot(service).artifacts.length(), 0)
    let result_body : Json = { "result": verified.to_json() }
    let accepted_result = service.handle(
      Post,
      "/v1/offline-commerce/operator/generation-results",
      chain_worker(),
      result_body.stringify(),
    )
    assert_eq(accepted_result.status, 201)
    let after_result = chain_snapshot(service)
    assert_eq(after_result.artifacts.length(), 1)
    assert_eq(after_result.artifacts[0].generation_state, ArtifactGenerated)
    assert_true(
      after_result.worker_health.artifact_dispatcher_success_unix_ms.unwrap() >
      success_before,
    )
    assert_true(
      chain_order(after_result, order_id).artifact_ids.contains(
        "contract-pdf-chain",
      ),
    )

    // 8a. The offline packet cannot be released before review.
    let early_release_body : Json = {
      "order_id": order_id,
      "expected_generation": chain_order(chain_snapshot(service), order_id).generation.to_json(),
    }
    let early_release = service.handle(
      Post,
      "/v1/offline-commerce/operator/release-packets",
      operator,
      early_release_body.stringify(),
    )
    assert_eq(early_release.status, 409)
    assert_true(early_release.body.contains("InvalidTransition"))

    // 9. The purchaser asks for one grant per required evidence artifact.
    let evidence : Array[(String, @offline.DocumentArtifactKind)] = [
      ("evidence-chain-approval", InternalApprovalEvidence),
      ("evidence-chain-contract", ExecutedContractScan),
      ("evidence-chain-payment", PaymentReceipt),
      ("evidence-chain-invoice", IssuedInvoice),
      ("evidence-chain-identity", IdentityVerificationEvidence),
    ]
    let transfers : Array[@api.OfflineUploadTransferView] = []
    for entry in evidence {
      let body : Json = {
        "grant_id": "grant-\{entry.0}",
        "idempotency_key": "upload-\{entry.0}",
        "order_id": order_id,
        "artifact_id": entry.0,
        "kind": entry.1.to_json(),
        "revision": (1 : Int).to_json(),
        "allowed_media_types": (["application/pdf"] : Array[String]).to_json(),
        "maximum_byte_count": 1000000L.to_json(),
        "expires_unix_ms": (now + 900000L).to_json(),
      }
      let response = service.handle(
        Post,
        "/v1/offline-commerce/self/upload-grants",
        purchaser,
        body.stringify(),
      )
      if response.status != 201 {
        fail(
          "upload grant \{entry.0} failed: \{response.status} \{response.body}",
        )
      }
      // The browser capability never carries the object route, the caller
      // identity, or the idempotency authority.
      assert_false(response.body.contains("object://"))
      assert_false(response.body.contains("s3://"))
      assert_false(response.body.contains("idempotency_key"))
      assert_false(response.body.contains("subject_ref"))
      assert_true(response.body.contains("session_token"))
      transfers.push(@json.from_json(@json.parse(response.body)))
    }
    assert_eq(chain_snapshot(service).upload_grants.length(), 5)

    // 10a. A callback that disagrees with the grant is refused.
    let grants_snapshot = chain_snapshot(service)
    let approval_grant = chain_grant(
      grants_snapshot, "grant-evidence-chain-approval",
    )
    let approval_callback : @offline.EvidenceUploadCallback = {
      callback_id: "callback-chain-approval",
      grant_id: approval_grant.grant_id,
      expected_object_ref: approval_grant.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 50000L,
      sha256: digest_c,
      scan_passed: true,
      active_content_detected: false,
      scanner_receipt: "scanner-chain-approval",
      verified: true,
      completed_unix_ms: approval_grant.created_unix_ms + 1L,
    }
    let mismatched_callbacks : Array[@offline.EvidenceUploadCallback] = [
      {
        ..approval_callback,
        callback_id: "callback-chain-bytes",
        byte_count: approval_grant.maximum_byte_count + 1L,
      },
      {
        ..approval_callback,
        callback_id: "callback-chain-media",
        media_type: "text/plain",
      },
      {
        ..approval_callback,
        callback_id: "callback-chain-digest",
        sha256: "sha256:deadbeef",
      },
      {
        ..approval_callback,
        callback_id: "callback-chain-ref",
        expected_object_ref: "object://offline-uploads/org-a/order-chain-a/other",
      },
    ]
    for mismatched in mismatched_callbacks {
      let refused = service.handle(
        Post,
        "/v1/offline-commerce/operator/upload-callbacks",
        chain_scanner(),
        mismatched.to_json().stringify(),
      )
      assert_eq(refused.status, 409)
      assert_true(refused.body.contains("ArtifactUnavailable"))
    }
    assert_eq(chain_snapshot(service).artifacts.length(), 1)
    let reconciled = service.handle(
      Post,
      "/v1/offline-commerce/operator/upload-callbacks",
      chain_scanner(),
      approval_callback.to_json().stringify(),
    )
    assert_eq(reconciled.status, 201)
    let after_approval_upload = chain_snapshot(service)
    assert_eq(after_approval_upload.artifacts.length(), 2)
    assert_eq(after_approval_upload.upload_callbacks.length(), 1)
    assert_eq(
      chain_order(after_approval_upload, order_id).state,
      PendingInternalApproval,
    )

    // 10b. Approval evidence is reviewed by the ingress-derived operator, not
    // by the identity the request body claims.
    let approval_review_body : Json = {
      "review_id": "review-chain-approval",
      "order_id": order_id,
      "artifact_id": "evidence-chain-approval",
      "expected_artifact_sha256": digest_c,
      "reviewer_ref": "subject-a",
      "accepted": true,
      "reason_code": "EvidenceVerified",
      "audit_receipt": "audit-chain-approval",
      "reviewed_unix_ms": now.to_json(),
    }
    let approval_review = service.handle(
      Post,
      "/v1/offline-commerce/operator/reviews",
      operator,
      approval_review_body.stringify(),
    )
    assert_eq(approval_review.status, 200)
    let after_approval_review = chain_snapshot(service)
    assert_eq(after_approval_review.reviews.length(), 1)
    assert_eq(
      after_approval_review.reviews[0].reviewer_ref,
      "platform-operator",
    )
    assert_eq(
      chain_order(after_approval_review, order_id).state,
      PendingOfflineExecution,
    )

    // 8b. With the reviewed PDF gate satisfied the packet is released.
    let release_body : Json = {
      "order_id": order_id,
      "expected_generation": chain_order(chain_snapshot(service), order_id).generation.to_json(),
    }
    let released = service.handle(
      Post,
      "/v1/offline-commerce/operator/release-packets",
      operator,
      release_body.stringify(),
    )
    assert_eq(released.status, 200)
    assert_true(released.body.contains("PendingEvidenceUpload"))
    assert_eq(chain_self_order(service, order_id).state, PendingEvidenceUpload)

    // 9b. The remaining verified callbacks reconcile against their grants.
    for index, entry in evidence {
      if index == 0 {
        continue
      }
      let grant = chain_grant(chain_snapshot(service), "grant-\{entry.0}")
      let body : Json = {
        "callback_id": "callback-\{entry.0}",
        "grant_id": grant.grant_id,
        "expected_object_ref": grant.expected_object_ref,
        "media_type": "application/pdf",
        "byte_count": 50000L.to_json(),
        "sha256": digest_c,
        "scan_passed": true,
        "active_content_detected": false,
        "scanner_receipt": "scanner-\{entry.0}",
        "verified": true,
        "completed_unix_ms": (grant.created_unix_ms + 1L).to_json(),
      }
      let response = service.handle(
        Post,
        "/v1/offline-commerce/operator/upload-callbacks",
        chain_scanner(),
        body.stringify(),
      )
      if response.status != 201 {
        fail(
          "upload callback \{entry.0} failed: \{response.status} \{response.body}",
        )
      }
    }
    let after_uploads = chain_snapshot(service)
    assert_eq(after_uploads.artifacts.length(), 6)
    assert_eq(chain_order(after_uploads, order_id).state, UnderReconciliation)
    assert_eq(chain_self_order(service, order_id).state, UnderReconciliation)

    // 10c. Review binds the exact artifact id and SHA-256.
    let forged_review_body : Json = {
      "review_id": "review-chain-contract-forged",
      "order_id": order_id,
      "artifact_id": "evidence-chain-contract",
      "expected_artifact_sha256": digest_a,
      "reviewer_ref": "legal-a",
      "accepted": true,
      "reason_code": "EvidenceVerified",
      "audit_receipt": "audit-chain-contract-forged",
      "reviewed_unix_ms": now.to_json(),
    }
    let forged_review = service.handle(
      Post,
      "/v1/offline-commerce/operator/reviews",
      operator,
      forged_review_body.stringify(),
    )
    assert_eq(forged_review.status, 400)
    for index, entry in evidence {
      if index == 0 {
        continue
      }
      let body : Json = {
        "review_id": "review-\{entry.0}",
        "order_id": order_id,
        "artifact_id": entry.0,
        "expected_artifact_sha256": digest_c,
        "reviewer_ref": "legal-a",
        "accepted": true,
        "reason_code": "EvidenceVerified",
        "audit_receipt": "audit-\{entry.0}",
        "reviewed_unix_ms": now.to_json(),
      }
      let response = service.handle(
        Post,
        "/v1/offline-commerce/operator/reviews",
        operator,
        body.stringify(),
      )
      if response.status != 200 {
        fail("review \{entry.0} failed: \{response.status} \{response.body}")
      }
    }

    // A submitter cannot review the digest it submitted, even when it holds the
    // operator token: the reviewer identity is derived, not asserted.
    let sod_quote = store.quote_order(
      store.create_order({
        order_id: "order-chain-sod",
        idempotency_key: "idem-order-chain-sod",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        project_id: "project-chain",
        purchaser_subject_ref: "platform-operator",
        selected_service_code: "exclusive-dgx",
        selected_sla_code: "standard",
        policy: {
          require_executed_agreement: true,
          require_payment: false,
          invoice_timing: InvoiceNotRequired,
          require_identity_verification: false,
          require_internal_approval: true,
        },
        quote: None,
        agreement_ref: None,
        artifact_ids: [],
        entitlement_ref: None,
        requested_undertaking_term: None,
        state: Draft,
        generation: 1L,
        created_unix_ms: now,
        updated_unix_ms: now,
        expires_unix_ms: now + 7200000L,
      }).order_id,
      offline_test_quote("chain-sod", now),
      "platform-operator",
      now,
    )
    ignore(
      store.begin_offline_execution(
        "order-chain-sod",
        sod_quote.generation,
        now,
      ),
    )
    let sod_grant : @offline.EvidenceUploadGrant = {
      grant_id: "grant-chain-sod",
      idempotency_key: "upload-chain-sod",
      order_id: "order-chain-sod",
      organization_id: "org-a",
      subject_ref: "platform-operator",
      artifact_id: "evidence-chain-sod",
      kind: ExecutedContractScan,
      revision: 1,
      expected_object_ref: "object://offline-uploads/org-a/order-chain-sod/evidence-chain-sod",
      allowed_media_types: ["application/pdf"],
      maximum_byte_count: 1000000L,
      expires_unix_ms: now + 900000L,
      state: UploadGranted,
      created_unix_ms: now,
    }
    ignore(store.grant_upload(sod_grant))
    let sod_artifact = store.complete_upload({
      callback_id: "callback-chain-sod",
      grant_id: sod_grant.grant_id,
      expected_object_ref: sod_grant.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 1000L,
      sha256: digest_b,
      scan_passed: true,
      active_content_detected: false,
      scanner_receipt: "scanner-chain-sod",
      verified: true,
      completed_unix_ms: now + 1L,
    })
    assert_eq(sod_artifact.submitted_by, "platform-operator")
    let self_review_body : Json = {
      "review_id": "review-chain-sod",
      "order_id": "order-chain-sod",
      "artifact_id": sod_artifact.artifact_id,
      "expected_artifact_sha256": sod_artifact.sha256,
      "reviewer_ref": "legal-a",
      "accepted": true,
      "reason_code": "EvidenceVerified",
      "audit_receipt": "audit-chain-sod",
      "reviewed_unix_ms": now.to_json(),
    }
    let self_review = service.handle(
      Post,
      "/v1/offline-commerce/operator/reviews",
      operator,
      self_review_body.stringify(),
    )
    assert_eq(self_review.status, 409)
    assert_true(self_review.body.contains("SeparationOfDuties"))

    // 11. Fulfillment binds the opaque entitlement only after every required
    // evidence kind is accepted.
    let reconciled_order = chain_order(chain_snapshot(service), order_id)
    assert_eq(reconciled_order.state, UnderReconciliation)
    let fulfillment_body : Json = {
      "order_id": order_id,
      "expected_generation": reconciled_order.generation.to_json(),
      "activation_id": "activation-chain-a",
      "idempotency_key": "activate-chain-a",
      "entitlement_kind": "ExclusiveMachineLease",
      "authority_target_ref": "lease-target-chain-a",
    }
    let fulfilled = service.handle(
      Post,
      "/v1/offline-commerce/operator/fulfillments",
      operator,
      fulfillment_body.stringify(),
    )
    assert_eq(fulfilled.status, 202)
    assert_true(fulfilled.body.contains("FulfillmentPending"))
    assert_eq(chain_self_order(service, order_id).state, FulfillmentPending)

    // 12. The typed authority completes exactly the claimed activation saga.
    let work = service.handle(
      Get,
      "/v1/offline-commerce/operator/entitlement-work/pending",
      chain_authority(),
      "",
    )
    assert_eq(work.status, 200)
    let batch : @offline.OfflineAuthorityWorkBatch = @json.from_json(
      @json.parse(work.body),
    )
    assert_eq(batch.activations.length(), 1)
    assert_eq(batch.activations[0].activation_id, "activation-chain-a")
    let activation = batch.activations[0]
    let mismatched : @offline.EntitlementActivation = {
      ..activation,
      state: EntitlementActivationConfirmed,
      entitlement_ref: Some("lease-chain-a"),
      authority_receipt: Some("authority-receipt-chain-a"),
      authority_target_ref: "lease-target-attacker",
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/entitlement-activation-results",
        chain_authority(),
        mismatched.to_json().stringify(),
      ).status,
      400,
    )
    let confirmed : @offline.EntitlementActivation = {
      ..activation,
      state: EntitlementActivationConfirmed,
      entitlement_ref: Some("lease-chain-a"),
      authority_receipt: Some("authority-receipt-chain-a"),
    }
    let completed = service.handle(
      Post,
      "/v1/offline-commerce/operator/entitlement-activation-results",
      chain_authority(),
      confirmed.to_json().stringify(),
    )
    assert_eq(completed.status, 200)
    assert_true(completed.body.contains("Fulfilled"))
    let replay = service.handle(
      Post,
      "/v1/offline-commerce/operator/entitlement-activation-results",
      chain_authority(),
      confirmed.to_json().stringify(),
    )
    assert_eq(replay.status, 200)
    let after_activation = chain_snapshot(service)
    let activated = chain_order(after_activation, order_id)
    assert_eq(activated.state, Fulfilled)
    assert_eq(activated.entitlement_ref, Some("lease-chain-a"))
    assert_eq(chain_self_order(service, order_id).state, Fulfilled)
    assert_true(
      after_activation.worker_health.entitlement_dispatcher_heartbeat_unix_ms.unwrap() >
      seeded_snapshot.worker_health.entitlement_dispatcher_heartbeat_unix_ms.unwrap(),
    )

    // 13. The transfer adapter consumes one issued capability exactly once.
    let upload_transfer = transfers[0].transfer
    assert_eq(upload_transfer.expected_sha256, None)
    let wrong_media_body : Json = {
      "session_id": upload_transfer.session_id,
      "session_token": upload_transfer.session_token,
      "media_type": "image/png",
      "byte_count": 50000L.to_json(),
      "sha256": digest_c,
      "provider_receipt": "provider-receipt-chain-wrong-media",
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        chain_transfer_adapter(),
        wrong_media_body.stringify(),
      ).status,
      403,
    )
    let upload_completion_body : Json = {
      "session_id": upload_transfer.session_id,
      "session_token": upload_transfer.session_token,
      "media_type": "application/pdf",
      "byte_count": 50000L.to_json(),
      "sha256": digest_c,
      "provider_receipt": "provider-receipt-chain-upload",
    }
    let transfer_consumed = service.handle(
      Post,
      "/v1/offline-commerce/operator/transfer-results",
      chain_transfer_adapter(),
      upload_completion_body.stringify(),
    )
    assert_eq(transfer_consumed.status, 200)
    assert_true(transfer_consumed.body.contains("TransferConsumed"))
    let after_transfer = chain_snapshot(service)
    assert_eq(after_transfer.transfer_sessions.length(), 5)
    assert_eq(
      after_transfer.transfer_sessions
      .filter(session => session.session_id == upload_transfer.session_id)
      .get(0)
      .unwrap().state,
      TransferConsumed,
    )
    assert_eq(after_transfer.transfer_evidence.length(), 1)
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        chain_transfer_adapter(),
        upload_completion_body.stringify(),
      ).status,
      403,
    )

    // 14. The purchaser receives a one-time, digest-bound download capability
    // and the public artifact view exposes no object route.
    let download_intent : Json = {
      "session_id": "transfer-chain-download",
      "idempotency_key": "transfer-chain-download-idem",
    }
    let download = service.handle(
      Post,
      "/v1/offline-commerce/self/artifacts/contract-pdf-chain:download",
      purchaser,
      download_intent.stringify(),
    )
    assert_eq(download.status, 201)
    let capability : @offline.OfflineTransferGrant = @json.from_json(
      @json.parse(download.body),
    )
    assert_eq(capability.direction, DownloadTransfer)
    assert_eq(capability.expected_sha256, Some(digest_b))
    assert_eq(capability.media_types.length(), 1)
    assert_true(capability.media_types.contains("application/pdf"))
    assert_true(capability.transfer_path.has_prefix(endpoint))
    assert_true(capability.session_token.has_prefix("lnxot_"))
    assert_false(download.body.contains("object://"))
    assert_false(download.body.contains("s3://"))
    let artifact_view = service.handle(
      Get,
      "/v1/offline-commerce/self/artifacts/contract-pdf-chain",
      purchaser,
      "",
    )
    assert_eq(artifact_view.status, 200)
    assert_true(artifact_view.body.contains("contract-pdf-chain"))
    assert_true(artifact_view.body.contains(digest_b))
    assert_false(artifact_view.body.contains("object_ref"))
    assert_false(artifact_view.body.contains("object://"))
    assert_false(artifact_view.body.contains("s3://"))
    assert_false(artifact_view.body.contains("creator_receipt"))
    assert_false(artifact_view.body.contains("submitted_by"))
    assert_false(artifact_view.body.contains("worker_receipt"))
    let wrong_digest_body : Json = {
      "session_id": capability.session_id,
      "session_token": capability.session_token,
      "media_type": "application/pdf",
      "byte_count": 30000L.to_json(),
      "sha256": digest_c,
      "provider_receipt": "provider-receipt-chain-download-wrong",
    }
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        chain_transfer_adapter(),
        wrong_digest_body.stringify(),
      ).status,
      403,
    )
    let download_completion_body : Json = {
      "session_id": capability.session_id,
      "session_token": capability.session_token,
      "media_type": "application/pdf",
      "byte_count": 30000L.to_json(),
      "sha256": digest_b,
      "provider_receipt": "provider-receipt-chain-download",
    }
    let download_consumed = service.handle(
      Post,
      "/v1/offline-commerce/operator/transfer-results",
      chain_transfer_adapter(),
      download_completion_body.stringify(),
    )
    assert_eq(download_consumed.status, 200)
    // The consumed capability cannot be reissued: the adapter boundary fails
    // closed rather than minting a second browser credential.
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/self/artifacts/contract-pdf-chain:download",
        purchaser,
        download_intent.stringify(),
      ).status,
      503,
    )
    assert_eq(chain_snapshot(service).transfer_sessions.length(), 6)

    // Both projections agree on the terminal state and leak nothing extra.
    let final_snapshot = chain_snapshot(service)
    let final_order = chain_order(final_snapshot, order_id)
    assert_eq(final_order.state, Fulfilled)
    assert_eq(final_order.entitlement_ref, Some("lease-chain-a"))
    assert_eq(final_snapshot.reviews.length(), 5)
    assert_eq(final_snapshot.transfer_evidence.length(), 2)
    chain_assert_operator_projection(final_snapshot.to_json().stringify())
    let self_orders = service.handle(
      Get,
      "/v1/offline-commerce/self/orders",
      purchaser,
      "",
    )
    assert_eq(self_orders.status, 200)
    assert_true(self_orders.body.contains(order_id))
    assert_true(self_orders.body.contains("Fulfilled"))
    assert_false(self_orders.body.contains("order-chain-sod"))
    chain_assert_purchaser_projection(self_orders.body)
    let isolated = service.handle(
      Get,
      "/v1/offline-commerce/self/orders",
      chain_other_purchaser(),
      "",
    )
    assert_eq(isolated.status, 200)
    assert_false(isolated.body.contains(order_id))
    assert_eq(
      service.handle(
        Get,
        "/v1/offline-commerce/self/artifacts/contract-pdf-chain",
        chain_other_purchaser(),
        "",
      ).status,
      403,
    )
    adapter.close()
  }
  @fs.rmdir(directory, recursive=true)
}
