///|
fn fixture_deployment() -> Json {
  {
    "metadata": { "name": "model-1", "uid": "uid-1", "resourceVersion": "9" },
    "spec": {
      "template": {
        "spec": {
          "nodeSelector": { "kubernetes.io/hostname": "node-1" },
          "containers": [
            {
              "name": "vllm",
              "command": ["vllm"],
              "args": ["serve", "/models/old"],
              "volumeMounts": [
                {
                  "name": "model",
                  "mountPath": "/models/old",
                  "readOnly": true,
                },
              ],
            },
          ],
          "volumes": [{ "name": "model", "hostPath": { "path": "/old/model" } }],
        },
      },
    },
  }
}

///|
fn fixture_selection() -> Selection {
  {
    model_id: "qwen-a3b",
    version: "v1",
    model_alias: "qwen-a3b",
    served_model: "qwen-a3b",
    artifact: {
      digest: "sha256:" + "a".repeat(64),
      uri: "modelstore://models/a",
      size_bytes: 100L,
      signature_ref: "manifest",
    },
  }
}

///|
test "replica patch changes only model arguments and its read-only mount" {
  let patch = switch_patch(
    fixture_deployment(),
    {
      deployment: "model-1",
      node_id: "node-1",
      kube_node: "node-1",
      cache_root: "/cache",
    },
    fixture_selection(),
  )
  guard patch is Array(operations) else { fail("not a JSON patch") }
  assert_eq(operations.length(), 6)
  assert_eq(operations[0], {
    "op": "test",
    "path": "/metadata/uid",
    "value": "uid-1",
  })
  assert_eq(operations[4], {
    "op": "replace",
    "path": "/spec/template/spec/volumes/0/hostPath/path",
    "value": "/cache/sha256/" + "a".repeat(64) + ".revision",
  })
  assert_false(patch.stringify().contains("max-num-seqs"))
  assert_false(patch.stringify().contains("trust-remote-code"))
}

///|
async test "transport refuses resources outside the four configured deployments" {
  let targets = [
    for i in 0..<4 => {
      {
        deployment: "model-\{i}",
        node_id: "node-\{i}",
        kube_node: "node-\{i}",
        cache_root: "/cache",
      }
    }
  ]
  let transport = authenticated_transport(
    "https://kubernetes.default.svc", "/token", "/ca", "models", targets,
  )
  try
    transport(
      "PATCH",
      "/apis/apps/v1/namespaces/models/deployments/other",
      Some([]),
    )
  catch {
    PoolError::OutsideScope => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("out-of-scope resource accepted")
  }
}

///|
async test "adoption persists original specs and survives controller restart" {
  let root = @fs.tmpdir(prefix="model-pool-test-")
  defer @fs.rmdir(root, recursive=true)
  let targets = [
    for i in 0..<4 => {
      {
        deployment: "model-\{i}",
        node_id: "node-\{i}",
        kube_node: "node-\{i}",
        cache_root: "/cache",
      }
    }
  ]
  let calls = Ref(0)
  let transport : Transport = (verb, path, _) => {
    assert_eq(verb, "GET")
    calls.val += 1
    let name = path.split("/").to_array().last().unwrap()
    let index = name["model-".length():].to_owned()
    (
      200,
      {
        "metadata": {
          "name": name,
          "uid": "uid-" + index,
          "resourceVersion": "1",
        },
        "spec": {
          "template": {
            "spec": {
              "nodeSelector": { "kubernetes.io/hostname": "node-" + index },
            },
          },
        },
      },
    )
  }
  let pool = Pool::open(transport, "models", targets, root + "/state.json", profiles=[
    fixture_runtime_profile(),
  ])
  pool.adopt()
  assert_eq(calls.val, 4)
  let recovered = Pool::open(
    transport,
    "models",
    targets,
    root + "/state.json",
    profiles=[fixture_runtime_profile()],
  )
  assert_true(recovered.adopted())
  recovered.adopt()
  assert_eq(calls.val, 4)
  recovered.select(fixture_selection())
  let resumed = Pool::open(transport, "models", targets, root + "/state.json", profiles=[
    fixture_runtime_profile(),
  ])
  assert_true(resumed.selection() == Some(fixture_selection()))
  assert_eq(resumed.generation(), 1L)
  assert_false(resumed.active())
  resumed.set_speculative_tokens(2)
  let speculative = Pool::open(
    transport,
    "models",
    targets,
    root + "/state.json",
    profiles=[fixture_runtime_profile()],
  )
  assert_eq(speculative.speculative_tokens(), 2)
  assert_eq(speculative.generation(), 2L)
  speculative.set_speculative_tokens(2)
  assert_eq(speculative.generation(), 2L)
  speculative.set_speculative_tokens(0)
  assert_eq(speculative.speculative_tokens(), 0)
  assert_eq(speculative.generation(), 3L)
  assert_true(speculative.selection() == Some(fixture_selection()))
}
