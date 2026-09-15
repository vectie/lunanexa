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
