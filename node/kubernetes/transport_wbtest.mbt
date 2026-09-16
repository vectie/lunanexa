///|
test "transport path allowlist excludes secrets exec subresources and traversal" {
  for
    path in [
      "/api/v1/namespaces/runtime/pods", "/api/v1/namespaces/runtime/pods/one", "/apis/networking.k8s.io/v1/namespaces/runtime/networkpolicies/one",
      "/apis/resource.k8s.io/v1/namespaces/runtime/resourceclaimtemplates/one",
    ] {
    assert_true(allowed_resource_path(path))
  }
  for
    path in [
      "/api/v1/namespaces/runtime/secrets", "/api/v1/nodes", "/api/v1/namespaces/runtime/pods/one/exec",
      "/api/v1/namespaces/runtime/pods/one?x=y", "/api/v1/namespaces/../pods/one",
      "/api/v1/namespaces/runtime/pods/%2e%2e", "/apis/resource.k8s.io/v1/namespaces/runtime/resourceclaims",
    ] {
    assert_false(allowed_resource_path(path))
  }
}

///|
test "PATCH authority is limited to an exact Pod stop deadline" {
  let path = "/api/v1/namespaces/runtime/pods/one"
  let body : Json = [
    { "op": "test", "path": "/metadata/uid", "value": "original" },
    { "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 1 },
  ]
  assert_true(valid_stop_patch(path, Some(body)))
  assert_false(valid_stop_patch("/api/v1/namespaces/runtime/pods", Some(body)))
  assert_false(
    valid_stop_patch(
      "/apis/networking.k8s.io/v1/namespaces/runtime/networkpolicies/one",
      Some(body),
    ),
  )
  assert_false(valid_stop_patch(path, None))
  let invalid : Array[Json] = [
    [{ "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 1 }],
    [
      { "op": "test", "path": "/metadata/uid", "value": "" },
      { "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 1 },
    ],
    [
      { "op": "test", "path": "/metadata/uid", "value": "original" },
      { "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 60 },
    ],
    [
      { "op": "test", "path": "/metadata/uid", "value": "original" },
      { "op": "add", "path": "/spec/containers", "value": [] },
    ],
  ]
  for patch in invalid {
    assert_false(valid_stop_patch(path, Some(patch)))
  }
}
