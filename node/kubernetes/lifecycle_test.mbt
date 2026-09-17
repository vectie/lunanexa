///|
async test "delete uses a UID precondition and awaits observed absence" {
  let calls : Array[String] = []
  let manager = @kubernetes.PodManager::new("runtime", (verb, path, body) => {
    calls.push(verb)
    assert_eq(path, "/api/v1/namespaces/runtime/pods/assignment-1")
    if verb == "DELETE" {
      assert_true(body is Some({ "preconditions": { "uid": "uid-1", .. }, .. }))
      (202, {})
    } else {
      (404, {})
    }
  })
  assert_eq(manager.stop(identity()), Draining)
  assert_eq(manager.observe(identity()), Stopped)
  assert_eq(calls, ["DELETE", "GET"])
}

///|
async test "delete cannot remove a replacement and API failures are not absence" {
  for status in [409, 403, 500] {
    let manager = @kubernetes.PodManager::new("runtime", (_, _, _) => {
      (status, {})
    })
    try manager.stop(identity()) catch {
      @kubernetes.OwnershipConflict => assert_eq(status, 409)
      @kubernetes.ApiRejected(actual) => assert_eq(actual, status)
      _ => fail("unexpected error")
    } noraise {
      _ => fail("failed deletion reported success")
    }
    try manager.observe(identity()) catch {
      @kubernetes.ApiRejected(actual) => assert_eq(actual, status)
      _ => fail("unexpected error")
    } noraise {
      _ => fail("failed observation reported absence")
    }
  }
}

///|
async test "create binds returned UID and never adopts conflicts" {
  let resource : Json = {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "namespace": "runtime",
      "name": "assignment-1",
      "labels": { "app.kubernetes.io/managed-by": "lunanexa-node" },
    },
  }
  let manager = @kubernetes.PodManager::new("runtime", (verb, path, body) => {
    assert_eq(verb, "POST")
    assert_eq(path, "/api/v1/namespaces/runtime/pods")
    assert_eq(body, Some(resource))
    (
      201,
      {
        "metadata": {
          "namespace": "runtime",
          "name": "assignment-1",
          "uid": "created",
        },
      },
    )
  })
  assert_eq(manager.create(resource), "created")
  let conflict = @kubernetes.PodManager::new("runtime", (_, _, _) => (409, {}))
  try conflict.create(resource) catch {
    @kubernetes.OwnershipConflict => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("adopted conflicting Pod")
  }
}
