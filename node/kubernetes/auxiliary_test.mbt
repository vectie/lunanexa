///|
async test "auxiliary resource creation and deletion are namespace and UID scoped" {
  let assignment = runtime_assignment()
  let plan = @kubernetes.render_runtime(
    runtime_settings(),
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  for resource in [plan.network_policy, plan.claim_template.unwrap()] {
    let manager = @kubernetes.PodManager::new("runtime", (verb, path, body) => {
      assert_true(path.contains("/namespaces/runtime/"))
      assert_false(path.contains("secrets"))
      if verb == "POST" {
        assert_eq(body, Some(resource))
        (
          201,
          {
            "metadata": {
              "name": plan.name.to_json(),
              "namespace": "runtime",
              "uid": "aux-uid",
            },
          },
        )
      } else {
        assert_eq(verb, "DELETE")
        assert_true(
          body is Some({ "preconditions": { "uid": "aux-uid", .. }, .. }),
        )
        (202, {})
      }
    })
    let identity = manager.create_auxiliary(resource)
    assert_eq(identity.uid, "aux-uid")
    assert_eq(manager.remove_auxiliary(identity), @contracts.Draining)
  }
}

///|
async test "auxiliary creation rejects foreign namespaces and unrelated API kinds before transport" {
  let calls = Ref(0)
  let manager = @kubernetes.PodManager::new("runtime", (_, _, _) => {
    calls.val += 1
    (201, {})
  })
  let invalid : Array[Json] = [
    { "apiVersion": "v1", "kind": "Secret" },
    {
      "apiVersion": "networking.k8s.io/v1",
      "kind": "NetworkPolicy",
      "metadata": {
        "namespace": "other",
        "name": "test",
        "labels": { "app.kubernetes.io/managed-by": "lunanexa-node" },
      },
    },
  ]
  for resource in invalid {
    try manager.create_auxiliary(resource) catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong validation error")
    } noraise {
      _ => fail("invalid resource created")
    }
  }
  assert_eq(calls.val, 0)
}
