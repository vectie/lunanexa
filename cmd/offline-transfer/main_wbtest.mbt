///|
test "object storage reference cannot escape bucket or namespace" {
  assert_true(trusted_service_endpoint("https://storage.internal:8333"))
  assert_true(trusted_service_endpoint("http://127.0.0.1:8333"))
  assert_false(trusted_service_endpoint("http://storage.internal:8333"))
  assert_false(trusted_service_endpoint("http://127.0.0.1:80@evil/"))
  assert_false(trusted_service_endpoint("http://127.0.0.1.evil:8333"))
  assert_true(valid_public_endpoint("/v1/offline-transfers"))
  assert_true(
    valid_public_endpoint("http://127.0.0.1:8096/v1/offline-transfers"),
  )
  assert_false(valid_public_endpoint("//other-host/v1/offline-transfers"))
  assert_false(
    valid_public_endpoint("https://user:password@host/v1/offline-transfers"),
  )
  assert_false(
    valid_public_endpoint("https://host/v1/offline-transfers?secret=x"),
  )
  assert_eq(
    object_key("object://offline-uploads/org/order/file", "commerce"),
    "offline-uploads/org/order/file",
  )
  assert_eq(
    object_key("s3://commerce/offline-generated/a.pdf", "commerce"),
    "offline-generated/a.pdf",
  )
  for
    reference in [
      "s3://other/key", "object://../key", "object://a//b", "object://a/%2e%2e/b",
      "object://a/key?x=1", "https://attacker/x", "object://a/./b", "object://a/../../b",
    ] {
    try object_key(reference, "commerce") catch {
      _ => ()
    } noraise {
      _ => fail("unsafe reference accepted")
    }
  }
}

///|
fn example_intent() -> Intent {
  {
    session_id: "session-1",
    idempotency_key: "idem-1",
    direction: UploadTransfer,
    object_ref: "object://offline-uploads/org/order/file",
    session_token_sha256: digest(b"secret"),
    media_types: ["application/pdf"],
    maximum_byte_count: 100L,
    expected_sha256: None,
    expires_unix_ms: 10000L,
    upload_grant_id: Some("grant-1"),
  }
}

///|
test "public transfer intent wire decoding accepts absent optional bindings" {
  let input : Json = {
    "session_id": "acceptance-a",
    "idempotency_key": "acceptance-a",
    "direction": "DownloadTransfer",
    "object_ref": "s3://commerce/templates/quote.xlsx",
    "session_token_sha256": digest(b"test-token"),
    "media_types": [
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ],
    "maximum_byte_count": "67108864",
    "expires_unix_ms": "1790073258222",
  }
  let decoded : Intent = @json.from_json(input)
  assert_eq(decoded.direction, DownloadTransfer)
}

///|
test "transfer grant expiry size callback binding and media validation" {
  let intent = example_intent()
  validate(intent, "commerce", 1000L)
  for
    invalid in [
      { ..intent, expires_unix_ms: 999L, },
      { ..intent, maximum_byte_count: 0L, },
      { ..intent, maximum_byte_count: 67108865L, },
      { ..intent, upload_grant_id: None, },
      { ..intent, session_id: "../escape", },
      { ..intent, session_token_sha256: "secret", },
      { ..intent, media_types: ["text/html"], },
    ] {
    try validate(invalid, "commerce", 1000L) catch {
      _ => ()
    } noraise {
      _ => fail("unsafe grant accepted")
    }
  }
}

///|
test "content type must agree with actual bytes" {
  assert_true(matches_magic(b"%PDF-1.7", "application/pdf"))
  assert_false(matches_magic(b"<html>not a PDF</html>", "application/pdf"))
  assert_false(matches_magic(b"%PDF-1.7", "image/png"))
  assert_false(matches_magic(b"PK\x03\x04", "text/html"))
}

///|
async test "transfer issuance and pending callbacks survive restart" {
  let root = @fs.tmpdir(prefix="lunanexa-transfer-test-")
  defer @fs.rmdir(root, recursive=true)
  let config : Config = {
    root,
    endpoint: "http://adapter/v1/offline-transfers",
    token: "test",
    scanner_token: "test",
    controller: "http://controller",
    bucket: "commerce",
    s3_endpoint: "http://store",
  }
  let intent = example_intent()
  persist(config, { intent, state: "issued", completion: None, upload: None, })
  assert_true(load(config, intent.session_id).intent == intent)
  let completion : Completion = {
    session_id: intent.session_id,
    session_token: "secret",
    media_type: "application/pdf",
    byte_count: 8L,
    sha256: digest(b"%PDF-1.7"),
    provider_receipt: "s3-transfer:session-1",
  }
  persist(config, {
    intent,
    state: "pending",
    completion: Some(completion),
    upload: None,
  })
  let recovered = load(config, intent.session_id)
  assert_eq(recovered.state, "pending")
  assert_eq(recovered.completion.unwrap().sha256, completion.sha256)
}

///|
async test "HTTP grants authenticate issuer and reject foreign capability replay" {
  let root = @fs.tmpdir(prefix="lunanexa-transfer-http-test-")
  defer @fs.rmdir(root, recursive=true)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let server_endpoint = "http://\{server.addr}/v1/offline-transfers"
  let config : Config = {
    root,
    endpoint: "/v1/offline-transfers",
    token: "test-issuer-token",
    scanner_token: "test-scanner-token",
    controller: "http://127.0.0.1:1",
    bucket: "commerce",
    s3_endpoint: "http://127.0.0.1:1",
  }
  let intent = { ..example_intent(), expires_unix_ms: @async.now() + 60000L, }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever(allow_failure=true, (request, reader, connection) => {
        handle(config, request, reader, connection)
      })
    })
    let denied = @http.post_stream(server_endpoint, headers={
      "Authorization": "Bearer wrong-token",
      "Content-Type": "application/json",
    })
    defer denied.close()
    denied.write(ToJson::to_json(intent))
    assert_eq(denied.end_request().code, 401)
    ignore(bounded(denied, 4096))
    let issued = @http.post_stream(server_endpoint, headers={
      "Authorization": "Bearer \{config.token}",
      "Content-Type": "application/json",
    })
    defer issued.close()
    issued.write(ToJson::to_json(intent))
    assert_eq(issued.end_request().code, 201)
    let receipt = @utf8.decode(bounded(issued, 4096))
    assert_false(receipt.contains("object://"))
    assert_false(receipt.contains("secret"))
    assert_true(
      receipt.contains("\"transfer_url\":\"/v1/offline-transfers/session-1\""),
    )
    assert_false(receipt.contains("127.0.0.1"))
    let (stolen_head, stolen) = @http.get_stream(
      "\{server_endpoint}/\{intent.session_id}",
      headers={ "Authorization": "Bearer other-tenant-token" },
    )
    defer stolen.close()
    assert_eq(stolen_head.code, 401)
    ignore(bounded(stolen, 4096))
    persist(config, {
      intent,
      state: "consumed",
      completion: None,
      upload: None,
    })
    let (replay_head, replay) = @http.get_stream(
      "\{server_endpoint}/\{intent.session_id}",
      headers={ "Authorization": "Bearer secret" },
    )
    defer replay.close()
    assert_eq(replay_head.code, 409)
    ignore(bounded(replay, 4096))
  })
}

///|
async test "subprocess output is bounded before collection completes" {
  let (status, bytes) = bounded_command_output("printf", ["abcdef"], 6)
  assert_eq(status, 0)
  assert_eq(bytes, b"abcdef")
  try bounded_command_output("printf", ["abcdef"], 5) catch {
    Failure::Failure("body-too-large") => ()
    error => raise error
  } noraise {
    _ => fail("oversized child output accepted")
  }
}

///|
async test "regular file bounded reads work without polling a regular descriptor" {
  let root = @fs.tmpdir(prefix="offline-regular-file-")
  defer @fs.rmdir(root, recursive=true)
  let path = "\{root}/data"
  @fs.write_file(path, b"abcdef", create_mode=CreateNew)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  assert_eq(bounded_file(file, 6), b"abcdef")
  let limited = @fs.open(path, mode=ReadOnly)
  defer limited.close()
  try bounded_file(limited, 5) catch {
    Failure::Failure("body-too-large") => ()
    error => raise error
  } noraise {
    _ => fail("oversized file accepted")
  }
}

///|
test "Office XML rejects active markup without interpreting ZIP entry names as globs" {
  assert_false(
    office_active_content(
      "<Types><Override PartName='/word/document.xml'/></Types>",
    ),
  )
  assert_true(office_active_content("<Relationship TargetMode = 'External'/>"))
  assert_true(office_active_content("<w:instrText>DDEAUTO run</w:instrText>"))
  assert_true(office_active_content("<o:OLEObject/>"))
}

///|
test "PDF active content inspects decoded names, not embedded font or text bytes" {
  assert_true(pdf_active_content({ "/OpenAction": "1 0 R" }))
  assert_true(pdf_active_content({ "value": { "/S": "/JavaScript" } }))
  assert_true(pdf_active_content({ "/AA": { "/JS": "u:alert(1)" } }))
  assert_false(
    pdf_active_content({
      "/Contents": "u:Example /JS and /AA text",
      "/FontFile2": "2 0 R",
    }),
  )
  assert_false(pdf_active_content({ "/Type": "/Font", "/BaseFont": "/AASans" }))
}
