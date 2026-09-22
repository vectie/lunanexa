///|
async test "deployment template scope binds digest version locale and preserves historical reads" {
  let directory = @fs.tmpdir(prefix="offline-template-scope-")
  defer @fs.rmdir(directory, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let base = ApiService::new(
    @store.FileStore::open(directory + "/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_offline_commerce_store(
    @offline_store.OfflineCommerceStore::open(directory + "/offline.json"),
  )
  let approval : OfflineTemplateApproval = {
    template_id: "youthpolicy-device-undertaking-ofl-v2",
    version: "v2",
    locale: "zh-CN",
    sha256: "sha256:" + "a".repeat(64),
    approval_ref: "platform-owner:technical-acceptance-only",
  }
  let service = base.with_offline_template_approvals([approval])
  let template : @offline.DocumentTemplate = {
    template_id: approval.template_id,
    version: approval.version,
    locale: approval.locale,
    sha256: approval.sha256,
    kind: ContractTemplate,
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    object_ref: "s3://templates/approved.docx",
    byte_count: 100L,
    active_content_allowed: false,
    created_unix_ms: 1L,
    superseded_unix_ms: None,
  }
  assert_true(service.offline_template_scope_gate(Some(template)) is None)
  for
    changed in [
      { ..template, version: "v1", },
      { ..template, locale: "en-US", },
      { ..template, sha256: "sha256:" + "b".repeat(64), },
      { ..template, template_id: "legacy-private-font-template", },
    ] {
    assert_true(service.offline_template_scope_gate(Some(changed)) is Some(_))
  }
  let denied = base.with_offline_template_approvals([])
  assert_true(denied.offline_template_scope_gate(None) is Some(_))
  let response = denied.handle(
    Post,
    "/v1/offline-commerce/operator/begin",
    { "Authorization": "Bearer operator-token" },
    "{}",
  )
  assert_eq(response.status, 503)
  assert_true(response.body.contains("TemplateApprovalScopeMissing"))
  let snapshot = denied.handle(
    Get,
    "/v1/offline-commerce/operator/snapshot",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(snapshot.status, 200)
  try base.with_offline_template_approvals([approval, approval]) catch {
    _ => ()
  } noraise {
    _ => fail("duplicate approval accepted")
  }
}
