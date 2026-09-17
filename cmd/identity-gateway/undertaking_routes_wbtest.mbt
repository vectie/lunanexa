///|
test "undertaking customer routes do not expose management approval authority" {
  let request : @http.Request = {
    meth: Post,
    path: "/v1/contract-documents/self/packet-a:undertaking-submit",
    headers: {},
  }
  for
    path in [
      "/v1/contract-documents/self", "/v1/contract-documents/self/packet-a:undertaking-submit",
      "/v1/contract-documents/self/packet-a:revise", "/v1/contract-documents/self/approvals/approval-a:withdraw",
      "/v1/offline-commerce/self",
    ] {
    assert_true(enterprise_request_allowed(request, path))
  }
  assert_true(
    enterprise_request_allowed(
      { ..request, meth: Get, },
      "/v1/contract-documents/manifest/catalog",
    ),
  )
  for
    path in [
      "/v1/contract-documents/operator/packets/packet-a:execute", "/v1/contract-documents/operator/approvals/approval-a:approve",
      "/v1/contract-governance/operator/admission", "/v1/offline-commerce/operator",
      "/v1/contract-documents/self-operator/packet-a:execute", "/v1/contract-documents/manifest-operator",
    ] {
    assert_false(enterprise_request_allowed(request, path))
  }
  for
    path in [
      "/v1/contract-documents/self/../operator/packets", "/v1/contract-documents/%73elf/packet-a:undertaking-submit",
      "/v1/contract-documents/self/%2e%2e/operator/packets",
    ] {
    assert_eq(canonical_api_path(path), None)
  }
}
