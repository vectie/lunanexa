///|
async test "workspace drain waits for old pods and rejects incomplete listings" {
  let calls = Ref(0)
  let mode = Ref(0)
  let host : WorkspaceHost = {
    config: host_config(),
    locks: {},
    kubernetes_override: Some((_, path, _) => {
      assert_true(
        path.contains(
          "/pods?labelSelector=lunanexa.io%2Fworkspace%3Dwebide-test",
        ),
      )
      calls.val += 1
      if mode.val == 2 {
        (200, { "items": [], "metadata": { "continue": "more" } })
      } else if calls.val == 1 {
        if mode.val == 0 {
          (
            200,
            {
              "items": [
                { "metadata": { "deletionTimestamp": "2026-09-15T00:00:00Z" } },
              ],
            },
          )
        } else {
          (200, { "items": [{ "metadata": { "name": "live" } }] })
        }
      } else {
        (200, { "items": [] })
      }
    }),
  }
  host.wait_for_workspace_pods("webide-test", terminating_only=true)
  assert_eq(calls.val, 2)
  calls.val = 0
  mode.val = 1
  host.wait_for_workspace_pods("webide-test", terminating_only=true)
  assert_eq(calls.val, 1)
  calls.val = 0
  host.wait_for_workspace_pods("webide-test", terminating_only=false)
  assert_eq(calls.val, 2)
  mode.val = 2
  try host.wait_for_workspace_pods("webide-test", terminating_only=true) catch {
    HostError::WorkspaceUnavailable => ()
    _ => fail("unexpected pod list failure")
  } noraise {
    _ => fail("partial pod list accepted")
  }
}

///|
async test "gateway restart reads desired replica state instead of assuming old pods are active" {
  let value : Ref[Json] = Ref({ "items": [] })
  let host : WorkspaceHost = {
    config: host_config(),
    locks: {},
    kubernetes_override: Some((_, path, _) => {
      assert_true(path.contains("/deployments?labelSelector="))
      (200, value.val)
    }),
  }
  assert_false(host.workspace_scaled_down("webide-test"))
  value.val = { "items": [{ "metadata": { "name": "webide-test" }, "spec": { "replicas": 0 } }] }
  assert_true(host.workspace_scaled_down("webide-test"))
  value.val = { "items": [{ "metadata": { "name": "webide-test" }, "spec": { "replicas": 1 } }] }
  assert_false(host.workspace_scaled_down("webide-test"))
  value.val = { "items": [{ "metadata": { "name": "other" }, "spec": { "replicas": 0 } }] }
  try host.workspace_scaled_down("webide-test") catch {
    HostError::WorkspaceUnavailable => ()
    _ => fail("unexpected deployment state error")
  } noraise {
    _ => fail("unrelated deployment accepted")
  }
}
