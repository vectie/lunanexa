///|
async test "operator artifact downloads are attributed scoped short lived and never purchaser impersonation" {
  let dir = @fs.tmpdir(prefix="operator-download-")
  defer @fs.rmdir(dir, recursive=true)
  let snapshot = undertaking_test_snapshot("\{dir}/empty.json")
  let quarantined = {
    ..snapshot.artifacts[0],
    artifact_id: "quarantined-a",
    scan_state: ScanRejected,
    review_state: ReviewRejected,
  }
  let snapshot = {
    ..snapshot,
    artifacts: snapshot.artifacts + [quarantined],
    orders: [
      {
        ..snapshot.orders[0],
        artifact_ids: snapshot.orders[0].artifact_ids +
        [quarantined.artifact_id],
      },
    ],
  }
  @fs.write_file(
    "\{dir}/offline.json",
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  let offline = @offline_store.OfflineCommerceStore::open("\{dir}/offline.json")
  let durable = @store.FileStore::open("\{dir}/state.json")
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(allow_failure=true) <| ((_, body, connection) => {
        let data = @json.parse(body.read_all().text())
        guard data
          is { "session_id": String(id), "expires_unix_ms": expires, .. } else {
          fail("invalid transfer intent")
        }
        connection.send_response(201, "Created", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(
          (
            {
              "session_id": id.to_json(),
              "expires_unix_ms": expires,
              "transfer_url": "http://\{server.addr}/v1/offline-transfers/\{id}".to_json(),
              "provider_receipt": "test-only-storage",
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
      "sha256:" + "a".repeat(64),
      allow_http_loopback=true,
    )
    let service = ApiService::new(
        durable, runtime, "operator-token", "inference-token", "node-token", "test",
      )
      .with_offline_commerce_store(offline)
      .with_operator_tokens([
        ("reviewer-a", "operator-token"),
        ("reviewer-b", "operator-b-token"),
      ])
      .with_offline_transfer_adapter(
        "http://\{server.addr}/v1/offline-transfers",
        "adapter-token-longer-than-thirty-two-characters",
        "session-secret-longer-than-thirty-two-characters",
      )
    let intent : Json = {
      "tenant_ref": "tenant-a",
      "organization_id": "org-a",
      "order_id": "undertaking-order",
      "session_id": "review-download-a",
      "idempotency_key": "download-key",
    }
    let path = "/v1/offline-commerce/operator/artifacts/signed-a:download"
    let actor = { "Authorization": "Bearer operator-token" }
    let now = @async.now()
    ignore(
      offline.issue_transfer_session({
        session_id: "purchaser-session",
        idempotency_key: "purchaser-key",
        session_token_sha256: "sha256:" + "c".repeat(64),
        organization_id: "org-a",
        subject_ref: "subject-a",
        order_id: "undertaking-order",
        artifact_id: "signed-a",
        direction: DownloadTransfer,
        media_types: ["application/pdf"],
        maximum_byte_count: 100L,
        expected_sha256: Some("sha256:" + "b".repeat(64)),
        state: TransferIssued,
        issued_unix_ms: now,
        expires_unix_ms: now + 300000L,
        consumed_unix_ms: None,
      }),
    )
    let collision = intent
      .stringify()
      .replace_all(old="review-download-a", new="purchaser-session")
    assert_eq(service.handle(Post, path, actor, collision).status, 403)
    assert_eq(
      offline.transfer_session("org-a", "subject-a", "purchaser-session").idempotency_key,
      "purchaser-key",
    )
    assert_eq(
      service.handle(
        Post,
        path,
        {
          "Authorization": "Bearer inference-token",
          "X-LunaNexa-Operator": "reviewer-a",
        },
        intent.stringify(),
      ).status,
      401,
    )
    let wrong = "{\"tenant_ref\":\"other\",\"organization_id\":\"org-a\",\"order_id\":\"undertaking-order\",\"session_id\":\"wrong-scope\",\"idempotency_key\":\"download-key\"}"
    assert_eq(service.handle(Post, path, actor, wrong).status, 403)
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/artifacts/quarantined-a:download",
        actor,
        intent.stringify(),
      ).status,
      409,
    )
    let issued = service.handle(Post, path, actor, intent.stringify())
    assert_eq(issued.status, 201, msg=issued.body)
    assert_false(issued.body.contains("object://"))
    assert_false(issued.body.contains("adapter-token"))
    let grant : @offline.OfflineTransferGrant = @json.from_json(
      @json.parse(issued.body),
    )
    let session = offline.transfer_session(
      "org-a",
      "operator:reviewer-a",
      grant.session_id,
    )
    assert_eq(session.subject_ref, "operator:reviewer-a")
    assert_eq(session.expires_unix_ms - session.issued_unix_ms, 120000L)
    assert_eq(
      service.handle(Post, path, actor, intent.stringify()).body,
      issued.body,
    )
    assert_eq(
      service.handle(
        Post,
        path,
        { "Authorization": "Bearer operator-b-token" },
        intent.stringify(),
      ).status,
      403,
    )
    let revoked = service.with_operator_tokens([
      ("reviewer-b", "operator-b-token"),
    ])
    assert_eq(revoked.handle(Post, path, actor, intent.stringify()).status, 401)
    let events = durable.audit_events()
    assert_true(
      events.any(event => {
        event.actor == "reviewer-a" &&
        event.action == "offline.artifact.review.download"
      }),
    )
    assert_false(
      @fs.read_file("\{dir}/offline.json").text().contains(grant.session_token),
    )
    try
      offline.consume_transfer_session(
        grant.session_id,
        session.session_token_sha256,
        "application/pdf",
        100L,
        "sha256:" + "b".repeat(64),
        "test-only-expired",
        session.expires_unix_ms + 1L,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("expired capability consumed")
    }
    ignore(
      offline.consume_transfer_session(
        grant.session_id,
        session.session_token_sha256,
        "application/pdf",
        100L,
        "sha256:" + "b".repeat(64),
        "test-only-consume",
        session.issued_unix_ms + 1L,
      ),
    )
    try
      offline.consume_transfer_session(
        grant.session_id,
        session.session_token_sha256,
        "application/pdf",
        100L,
        "sha256:" + "b".repeat(64),
        "test-only-replay",
        session.issued_unix_ms + 2L,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("one-time capability replay accepted")
    }
  }
}
