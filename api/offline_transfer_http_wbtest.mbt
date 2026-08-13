///|
priv enum OfflineTransferAdapterTestMode {
  TransferSuccess
  TransferRedirect
  TransferOversize
  TransferSlow
}

///|
async fn exercise_offline_transfer_adapter(
  mode : OfflineTransferAdapterTestMode,
) -> (Bool, Bool) {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let authenticated = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(allow_failure=true) <| ((request, _, connection) => {
        authenticated[0] = request.headers
          .iter()
          .find_first(item => item.0.to_lower() == "authorization")
          .map(item => item.1) ==
          Some("Bearer offline-transfer-adapter-test-token-more-than-32-bytes") &&
          request.headers
          .iter()
          .find_first(item => item.0.to_lower() == "idempotency-key")
          .map(item => item.1) ==
          Some("transfer-test-idempotency")
        match mode {
          TransferSuccess => {
            connection.send_response(201, "Created", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write_string(
              (
                {
                  "session_id": "transfer-test-session",
                  "transfer_url": "http://\{server.addr}/v1/offline-transfers/transfer-test-session",
                  "expires_unix_ms": 2000L.to_json(),
                  "provider_receipt": "transfer-provider-receipt",
                } : Json).stringify(),
            )
          }
          TransferRedirect => {
            connection.send_response(302, "Found", extra_headers={
              "Location": "http://127.0.0.1:1/private",
              "Content-Type": "application/json",
            })
            connection.write_string("{}")
          }
          TransferOversize => {
            connection.send_response(201, "Created", extra_headers={
              "Content-Type": "application/json",
            })
            for _ in 0..<5000 {
              connection.write_string("x")
            }
          }
          TransferSlow => {
            connection.send_response(201, "Created", extra_headers={
              "Content-Type": "application/json",
            })
            @async.sleep(500)
            connection.write_string("{}")
          }
        }
        connection.end_response()
      })
    }
    let intent : OfflineTransferAdapterIntent = {
      session_id: "transfer-test-session",
      idempotency_key: "transfer-test-idempotency",
      direction: UploadTransfer,
      object_ref: "object://offline/org/order/artifact",
      session_token_sha256: "a".repeat(64),
      media_types: ["application/pdf"],
      maximum_byte_count: 1000L,
      expected_sha256: None,
      expires_unix_ms: 2000L,
    }
    let accepted = try {
      let receipt = @async.with_timeout(250, () => {
        request_offline_transfer_adapter(
          "http://\{server.addr}/v1/offline-transfers",
          "offline-transfer-adapter-test-token-more-than-32-bytes",
          intent,
        )
      })
      receipt.session_id == intent.session_id
    } catch {
      _ => false
    }
    (accepted, authenticated[0])
  }
}

///|
async test "offline transfer adapter is authenticated bounded and fail closed" {
  let (success, success_auth) = exercise_offline_transfer_adapter(
    TransferSuccess,
  )
  assert_true(success)
  assert_true(success_auth)
  let (redirect, redirect_auth) = exercise_offline_transfer_adapter(
    TransferRedirect,
  )
  assert_false(redirect)
  assert_true(redirect_auth)
  let (oversize, oversize_auth) = exercise_offline_transfer_adapter(
    TransferOversize,
  )
  assert_false(oversize)
  assert_true(oversize_auth)
  let (slow, slow_auth) = exercise_offline_transfer_adapter(TransferSlow)
  assert_false(slow)
  assert_true(slow_auth)
}

///|
async fn transfer_store_fixture(
  directory : String,
  now : Int64,
) -> @offline_store.OfflineCommerceStore {
  let quote : @offline.ImmutableQuote = {
    quote_id: "quote-transfer-api",
    version: "v1",
    service_code: "exclusive-dgx",
    sla_code: "standard",
    currency: "CNY",
    lines: [
      {
        line_id: "line-transfer",
        description: "Transfer test",
        quantity: 1L,
        unit: "lease",
        unit_price: { currency: "CNY", minor_units: 1L, scale: 2 },
        line_total: { currency: "CNY", minor_units: 1L, scale: 2 },
      },
    ],
    subtotal: { currency: "CNY", minor_units: 1L, scale: 2 },
    tax: { currency: "CNY", minor_units: 0L, scale: 2 },
    total: { currency: "CNY", minor_units: 1L, scale: 2 },
    valid_until_unix_ms: now + 600000L,
    terms_digest: "sha256:" + "a".repeat(64),
    created_unix_ms: now,
  }
  let order : @offline.CommercialOrder = {
    order_id: "order-transfer-api",
    idempotency_key: "order-transfer-api-idem",
    tenant_ref: "tenant-transfer",
    organization_id: "org-transfer",
    project_id: "project-transfer",
    purchaser_subject_ref: "subject-transfer",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: false,
      invoice_timing: InvoiceNotRequired,
      require_identity_verification: false,
      require_internal_approval: false,
    },
    quote: Some(quote),
    agreement_ref: Some("agreement-transfer"),
    artifact_ids: [],
    entitlement_ref: None,
    state: PendingEvidenceUpload,
    generation: 4L,
    created_unix_ms: now,
    updated_unix_ms: now,
    expires_unix_ms: now + 600000L,
  }
  let grant : @offline.EvidenceUploadGrant = {
    grant_id: "grant-transfer-api",
    idempotency_key: "grant-transfer-api-idem",
    order_id: order.order_id,
    organization_id: order.organization_id,
    subject_ref: order.purchaser_subject_ref,
    artifact_id: "artifact-transfer-api",
    kind: ExecutedContractScan,
    revision: 1,
    expected_object_ref: "object://offline/org-transfer/order-transfer-api/artifact-transfer-api",
    allowed_media_types: ["application/pdf"],
    maximum_byte_count: 1000L,
    expires_unix_ms: now + 300000L,
    state: UploadGranted,
    created_unix_ms: now,
  }
  let snapshot : @offline.OfflineCommerceSnapshot = {
    schema_version: @offline.snapshot_schema_version,
    templates: [],
    orders: [order],
    artifacts: [],
    generation_requests: [],
    upload_grants: [grant],
    upload_callbacks: [],
    reviews: [],
    entitlement_activations: [],
    reversals: [],
    reversal_recoveries: [],
    transfer_sessions: [],
    transfer_evidence: [],
    work_claims: [],
    worker_health: @offline.empty_offline_worker_health(),
  }
  let path = "\{directory}/offline.json"
  @fs.write_file(
    path,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  @offline_store.OfflineCommerceStore::open(path) catch {
    error => fail("transfer fixture rejected: \{Repr(error)}")
  }
}

///|
async test "opaque transfer survives restart and consumes exactly once" {
  let directory = @fs.tmpdir(prefix="lunanexa-transfer-saga-api-")
  let now = @async.now()
  let store = transfer_store_fixture(directory, now)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(allow_failure=true) <| ((_, _, connection) => {
        connection.send_response(201, "Created", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          (
            {
              "session_id": "transfer-grant-transfer-api",
              "transfer_url": "http://\{server.addr}/v1/offline-transfers/transfer-grant-transfer-api",
              "expires_unix_ms": (now + 300000L).to_json(),
              "provider_receipt": "provider-transfer-receipt",
            } : Json).stringify(),
        )
        connection.end_response()
      })
    }
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "http://127.0.0.1:1/v1/responses",
      "runtime-secret",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      allow_http_loopback=true,
    )
    let adapter_token = "offline-transfer-adapter-saga-token-more-than-32-bytes"
    let service = ApiService::new(
        @store.FileStore::open("\{directory}/state.json"),
        runtime,
        "operator-token",
        "inference-token",
        "node-token",
        "test",
      )
      .with_offline_commerce_store(store)
      .with_offline_transfer_adapter(
        "http://\{server.addr}/v1/offline-transfers",
        adapter_token,
        "offline-transfer-saga-session-secret-more-than-32-bytes",
      )
    let transfer = service.issue_offline_transfer(
      store,
      "transfer-grant-transfer-api",
      "transfer-grant-transfer-api-idem",
      "org-transfer",
      "subject-transfer",
      "order-transfer-api",
      "artifact-transfer-api",
      UploadTransfer,
      "object://offline/org-transfer/order-transfer-api/artifact-transfer-api",
      ["application/pdf"],
      1000L,
      None,
      now,
      now + 300000L,
    )
    assert_false(transfer.to_json().stringify().contains("object://"))
    let persisted = @fs.read_file("\{directory}/offline.json").text()
    assert_false(persisted.contains(transfer.session_token))
    assert_true(
      persisted.contains(offline_transfer_token_sha256(transfer.session_token)),
    )
    let reopened = @offline_store.OfflineCommerceStore::open(
      "\{directory}/offline.json",
    )
    let restarted = service.with_offline_commerce_store(reopened)
    let body = (
      {
        "session_id": transfer.session_id,
        "session_token": transfer.session_token,
        "media_type": "application/pdf",
        "byte_count": 321L.to_json(),
        "sha256": "sha256:" + "d".repeat(64),
        "provider_receipt": "provider-byte-transfer-receipt",
      } : Json).stringify()
    assert_eq(
      restarted.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        { "Authorization": "Bearer wrong-adapter" },
        body,
      ).status,
      401,
    )
    let oversized_body = (
      {
        "session_id": transfer.session_id,
        "session_token": transfer.session_token,
        "media_type": "application/pdf",
        "byte_count": (transfer.maximum_byte_count + 1L).to_json(),
        "sha256": "sha256:" + "d".repeat(64),
        "provider_receipt": "provider-byte-transfer-receipt",
      } : Json).stringify()
    assert_eq(
      restarted.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        { "Authorization": "Bearer \{adapter_token}" },
        oversized_body,
      ).status,
      403,
    )
    assert_eq(
      restarted.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        { "Authorization": "Bearer \{adapter_token}" },
        body,
      ).status,
      200,
    )
    assert_eq(
      restarted.handle(
        Post,
        "/v1/offline-commerce/operator/transfer-results",
        { "Authorization": "Bearer \{adapter_token}" },
        body,
      ).status,
      403,
    )
  }
  @fs.rmdir(directory, recursive=true)
}
