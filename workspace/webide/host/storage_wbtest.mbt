///|
test "shared storage is explicit and preserves existing volume profile" {
  let shared = {
    ..host_config(),
    storage_class: "workspace-nfs",
    storage_access_mode: Some("ReadWriteMany"),
  }
  let host = WorkspaceHost::new(shared)
  let grant = {
    ..proxy_config(shared.controller_origin, shared.model_gateway_origin).grant(),
    delivery_id: Some("delivery-a"),
  }
  let resources = host.resources(
    @webide.workspace_id(grant),
    grant,
    placement=exclusive_fixture(),
  )
  assert_true(
    resources[1].1
    is {
      "spec": {
        "accessModes": [String("ReadWriteMany")],
        "storageClassName": String("workspace-nfs"),
        ..
      },
      ..
    },
  )
  assert_false(storage_profile_matches(resources[1].1, host_config()))
  assert_true(storage_profile_matches(resources[1].1, shared))
  try
    WorkspaceHost::new({
      ..host_config(),
      storage_access_mode: Some("ReadWriteMany"),
    })
  catch {
    HostError::InvalidConfiguration => ()
    _ => fail("unexpected profile error")
  } noraise {
    _ => fail("local-path cannot provide shared RWX storage")
  }
}

///|
test "PVC JSON Patch 422 is busy only when resourceVersion really changed" {
  let path = "/api/v1/namespaces/workspaces/persistentvolumeclaims/saved"
  let patch : Json = [
    { "op": "test", "path": "/metadata/resourceVersion", "value": "10" },
    { "op": "add", "path": "/metadata/annotations", "value": {} },
  ]
  assert_true(storage_cas_conflict(409, path, Some(patch), None))
  assert_true(
    storage_cas_conflict(
      422,
      path,
      Some(patch),
      Some({ "metadata": { "resourceVersion": "11" } }),
    ),
  )
  assert_false(
    storage_cas_conflict(
      422,
      path,
      Some(patch),
      Some({ "metadata": { "resourceVersion": "10" } }),
    ),
  )
  assert_false(storage_cas_conflict(422, path, Some(patch), None))
  assert_false(
    storage_cas_conflict(
      422,
      "/api/v1/secrets/saved",
      Some(patch),
      Some({ "metadata": { "resourceVersion": "11" } }),
    ),
  )
  assert_false(
    storage_cas_conflict(
      422,
      path,
      Some({ "kind": "PersistentVolumeClaim" }),
      Some({ "metadata": { "resourceVersion": "11" } }),
    ),
  )
}

///|
async test "PVC CAS ownership prevents simultaneous delivery writers and releases without deleting files" {
  let config = {
    ..host_config(),
    storage_class: "workspace-nfs",
    storage_access_mode: Some("ReadWriteMany"),
  }
  let state : Map[String, Json] = {
    "claim": {
      "metadata": { "name": "saved-workspace", "resourceVersion": "1" },
      "spec": {
        "storageClassName": "workspace-nfs",
        "accessModes": ["ReadWriteMany"],
      },
    },
  }
  let writes : Array[Json] = []
  let host : WorkspaceHost = {
    config,
    require_exclusive: true,
    observation_token: "fixture",
    locks: {},
    kubernetes_override: Some((verb, _path, body) => {
      if verb == Get {
        return (200, { "items": [state["claim"]] })
      }
      assert_eq(verb, Patch)
      guard body is Some(Array([test_version, change])) &&
        test_version
        is {
          "op": String("test"),
          "path": String("/metadata/resourceVersion"),
          "value": String(version),
          ..
        } &&
        change
        is {
          "op": String("add"),
          "path": String("/metadata/annotations"),
          "value": annotations,
          ..
        } &&
        state["claim"] is Object(fields) &&
        fields.get("metadata") is Some(Object(meta)) else {
        fail("writer change must be an atomic metadata CAS")
      }
      assert_eq(meta.get("resourceVersion"), Some(version.to_json()))
      meta["annotations"] = annotations
      meta["resourceVersion"] = (writes.length() + 2).to_string().to_json()
      writes.push(body.unwrap())
      (200, state["claim"])
    }),
  }
  let path = "/api/v1/namespaces/webide/persistentvolumeclaims/saved-workspace"
  let desired : Json = { "metadata": { "name": "saved-workspace" } }
  host.ensure_storage("delivery-a", exclusive_fixture(), path, desired)
  assert_eq(storage_owner(state["claim"]), Some("delivery-a"))
  host.ensure_storage("delivery-a", exclusive_fixture(), path, desired)
  assert_eq(writes.length(), 1)
  try
    host.ensure_storage(
      "delivery-b",
      { ..exclusive_fixture(), node_name: "spark-3782", },
      path,
      desired,
    )
  catch {
    @webide.BridgeError::StorageBusy => ()
    _ => fail("unexpected writer error")
  } noraise {
    _ => fail("concurrent writer acquired shared volume")
  }
  host.release_storage("delivery-b")
  assert_eq(storage_owner(state["claim"]), Some("delivery-a"))
  host.release_storage("delivery-a")
  assert_eq(storage_owner(state["claim"]), None)
  host.ensure_storage(
    "delivery-b",
    { ..exclusive_fixture(), node_name: "spark-3782", },
    path,
    desired,
  )
  assert_eq(storage_owner(state["claim"]), Some("delivery-b"))
  assert_eq(writes.length(), 3)
  assert_true(storage_profile_matches(state["claim"], config))
}

///|
async test "local volume node mismatch and storage class changes request migration without mutation" {
  let config = host_config()
  let claim : Json = {
    "metadata": { "name": "saved-workspace", "resourceVersion": "1" },
    "spec": {
      "storageClassName": "local-path",
      "accessModes": ["ReadWriteOnce"],
      "volumeName": "pv-local",
    },
  }
  let volume : Json = {
    "spec": {
      "nodeAffinity": {
        "required": {
          "nodeSelectorTerms": [
            {
              "matchExpressions": [
                {
                  "key": "kubernetes.io/hostname",
                  "operator": "In",
                  "values": ["spark-25e2"],
                },
              ],
            },
          ],
        },
      },
    },
  }
  let host : WorkspaceHost = {
    config,
    require_exclusive: true,
    observation_token: "fixture",
    locks: {},
    kubernetes_override: Some((verb, path, _body) => {
      assert_eq(verb, Get)
      (
        200,
        if path.contains("/persistentvolumes/") {
          volume
        } else {
          { "items": [claim] }
        },
      )
    }),
  }
  let desired : Json = { "metadata": { "name": "saved-workspace" } }
  let moved = { ..exclusive_fixture(), node_name: "spark-3782", }
  try host.ensure_storage("new", moved, "/unused", desired) catch {
    @webide.BridgeError::StorageMigrationRequired => ()
    _ => fail("unexpected migration error")
  } noraise {
    _ => fail("local data silently moved")
  }
  let shared_host = {
    ..host,
    config: {
      ..config,
      storage_class: "workspace-nfs",
      storage_access_mode: Some("ReadWriteMany"),
    },
  }
  try
    shared_host.ensure_storage("new", exclusive_fixture(), "/unused", desired)
  catch {
    @webide.BridgeError::StorageMigrationRequired => ()
    _ => fail("unexpected profile migration error")
  } noraise {
    _ => fail("existing volume class silently changed")
  }
}
