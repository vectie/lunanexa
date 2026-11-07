///|
async test "two-node scope survives restart and never mutates excluded services during switch or rollback" {
  let directory = @fs.tmpdir(prefix="model-pool-scope-")
  defer @fs.rmdir(directory, recursive=true)
  let targets : Array[Target] = [
    for i in 0..<4 => {
      {
        deployment: "model-\{i}",
        node_id: "node-\{i}",
        kube_node: "node-\{i}",
        cache_root: "/cache",
      }
    }
  ]
  let writes : Array[String] = []
  let paused : Map[String, Bool] = Map([])
  let fail_pause = Ref(false)
  let transport : Transport = (verb, path, body) => {
    let target = targets
      .iter()
      .find_first(t => path.has_suffix("/" + t.deployment))
      .unwrap()
    if verb == "PATCH" {
      writes.push(target.node_id)
      if fail_pause.val {
        return (503, {})
      }
      if body is Some(Array(ops)) &&
        ops.last() ==
        Some({ "op": "add", "path": "/spec/replicas", "value": 0 }) {
        assert_eq(ops.length(), 3)
        assert_eq(ops[0], {
          "op": "test",
          "path": "/metadata/uid",
          "value": target.node_id,
        })
        paused[target.node_id] = true
      }
      return (200, {})
    }
    (
      200,
      {
        "metadata": {
          "name": target.deployment,
          "uid": target.node_id,
          "resourceVersion": "1",
        },
        "spec": {
          "replicas": if paused.get(target.node_id) == Some(true) {
            0
          } else {
            1
          },
          "template": {
            "spec": {
              "nodeSelector": { "kubernetes.io/hostname": target.kube_node },
            },
          },
        },
        "status": {
          "replicas": if paused.get(target.node_id) == Some(true) {
            0
          } else {
            1
          },
        },
      },
    )
  }
  let path = directory + "/pool.json"
  let pool = Pool::open(transport, "models", targets, path)
  pool.adopt()
  pool.select_nodes(["node-0", "node-1"], { "node-0": "176", "node-1": "177" })
  let restored = Pool::open(transport, "models", targets, path)
  assert_eq(restored.selected_targets().map(t => t.node_id), [
    "node-0", "node-1",
  ])
  assert_eq(restored.node_name("node-1"), "177")
  for invalid in [[], ["node-0", "node-0"], ["node-4"]] {
    try restored.select_nodes(invalid, {}) catch {
      PoolError::InvalidConfiguration => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("bad scope accepted")
    }
  }
  try restored.pause_excluded("node-0") catch {
    PoolError::OutsideScope => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("selected node paused")
  }
  try restored.switch_replica("node-2") catch {
    PoolError::OutsideScope => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("excluded node switched")
  }
  assert_true(writes.is_empty())
  fail_pause.val = true
  try restored.pause_excluded("node-2") catch {
    PoolError::Unavailable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("failed pause hidden")
  }
  assert_eq(restored.selected_targets().length(), 2)
  fail_pause.val = false
  restored.pause_excluded("node-2")
  restored.pause_excluded("node-3")
  assert_true(restored.paused("node-2"))
  assert_true(restored.paused("node-3"))
  writes.clear()
  restored.rollback()
  assert_eq(writes, ["node-0", "node-1"])
  assert_eq(restored.selected_targets().length(), 2)
  assert_true(restored.paused("node-2"))
}

///|
test "re-enabling a selected paused service restores its one replica without a sequence limit" {
  guard fixture_deployment() is Object(value) else { fail("fixture") }
  guard value["spec"] is Object(spec) else { fail("fixture spec") }
  spec["replicas"] = 0
  let patch = switch_patch(
    Json(value),
    {
      deployment: "model-1",
      node_id: "node-1",
      kube_node: "node-1",
      cache_root: "/cache",
    },
    fixture_selection(),
  )
  guard patch is Array(ops) else { fail("patch") }
  assert_eq(
    ops.last(),
    Some({ "op": "replace", "path": "/spec/replicas", "value": 1 }),
  )
  assert_false(patch.stringify().contains("max-num-seqs"))
}
