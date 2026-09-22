///|
test "staging names reject traversal and shell characters" {
  for
    value in [
      "../secret", "/etc/passwd", "..", ".", "a/b", "a\\b", "$(id)", "a\n",
    ] {
    assert_false(filename(value))
  }
  assert_true(filename("contract.zh-CN.docx"))
}

///|
test "work namespaces are stable and do not interpolate remote identifiers" {
  let first = work_directory("/state", "../../activation:abc")
  assert_eq(first.length(), 71)
  assert_true(first.has_prefix("/state/"))
  assert_eq(first, work_directory("/state", "../../activation:abc"))
  assert_true(first != work_directory("/state", "activation:abc"))
}

///|
test "artifact digest uses explicit sha256 namespace" {
  assert_eq(
    digest(b"abc"),
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "execution plan requires typed fields" {
  assert_eq(field({ "file": "output.pdf" }, "file"), "output.pdf")
  try field({ "file": 42 }, "file") catch {
    _ => ()
  } noraise {
    _ => fail("numeric plan field accepted")
  }
}

///|
async test "dispatcher state lock refuses a second owner" {
  let directory = @fs.tmpdir(prefix="lunanexa-dispatcher-lock-")
  defer @fs.rmdir(directory, recursive=true)
  let first = @fs.open(
    directory + "/lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer first.close()
  let second = @fs.open(
    directory + "/lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer second.close()
  assert_true(first.try_lock(Exclusive))
  assert_false(second.try_lock(Exclusive))
}

///|
async test "HTTP transport sends authority and enforces bounded response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let authenticated = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever(allow_failure=true, (request, _, connection) => {
        authenticated.val = request.headers
          .iter()
          .find_first(item => item.0.to_lower() == "authorization")
          .map(item => item.1) ==
          Some("Bearer test-dispatcher")
        connection.send_response(200, "OK")
        connection.write_string("12345678")
        connection.end_response()
      })
    })
    try
      exchange(
        "http://\{server.addr}",
        "test-dispatcher",
        "/bounded",
        Get,
        b"",
        maximum=4,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("oversized response accepted")
    }
    assert_true(authenticated.val)
  })
}

///|
async test "terminal authority journal retries callback without reprovisioning" {
  let directory = @fs.tmpdir(prefix="lunanexa-dispatcher-test-")
  defer @fs.rmdir(directory, recursive=true)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let executions = Ref(0)
  let callbacks = Ref(0)
  let request : @offline.EntitlementActivation = {
    activation_id: "activation-test",
    idempotency_key: "idempotent-test",
    order_id: "order-test",
    organization_id: "org-test",
    purchaser_subject_ref: "subject-test",
    kind: WorkspaceLease,
    authority_target_ref: "lease-test",
    expected_order_generation: 1L,
    state: EntitlementActivationRequested,
    entitlement_ref: None,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-test",
    requested_unix_ms: 1L,
    completed_unix_ms: None,
  }
  let confirmed = {
    ..request,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some("lease-test"),
    authority_receipt: Some("real-authority-test-receipt"),
    completed_unix_ms: Some(2L),
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever(allow_failure=true, (incoming, _, connection) => {
        if incoming.path == "/v1/offline-commerce/operator/entitlement-execute" {
          executions.val += 1
          connection.send_response(200, "OK")
          connection.write_string(confirmed.to_json().stringify())
        } else {
          callbacks.val += 1
          connection.send_response(
            if callbacks.val == 1 {
              503
            } else {
              200
            },
            "Result",
          )
          connection.write_string("{}")
        }
        connection.end_response()
      })
    })
    let config = Config::{
      origin: "http://\{server.addr}",
      token: "test-only",
      root: directory,
    }
    try
      authority(config, request.activation_id, request.to_json(), false)
    catch {
      _ => ()
    } noraise {
      _ => fail("first callback should fail")
    }
    resume_authority(config)
    assert_eq(executions.val, 1)
    assert_eq(callbacks.val, 2)
    resume_authority(config)
    assert_eq(callbacks.val, 2)
  })
}
