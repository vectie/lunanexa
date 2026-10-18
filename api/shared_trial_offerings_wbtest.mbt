///|
test "shared trial slot belongs only to its exact organization and tenant" {
  let offering : SharedTrialOffering = {
    organization_id: "org-energy",
    tenant_ref: "tenant-energy",
    node_id: "trial-node-a",
    node_label: "Shared Spark A",
    model_alias: "video.h3",
    model_name: "MiniMax H3",
    kind: "Video",
    health_url: "http://service.internal/health",
    public_url: "https://example.test/comfyui/",
  }
  assert_true(
    shared_trial_offering_visible(offering, "org-energy", "tenant-energy"),
  )
  assert_false(
    shared_trial_offering_visible(offering, "org-other", "tenant-energy"),
  )
  assert_false(
    shared_trial_offering_visible(offering, "org-energy", "tenant-other"),
  )
  assert_true(shared_trial_node_matches(Some(offering), "trial-node-a"))
  assert_false(shared_trial_node_matches(Some(offering), "other-node"))
}

///|
async test "shared trial configuration rejects duplicate or non-HTTPS public routes" {
  let root = @fs.tmpdir(prefix="shared-trial-config-")
  defer @fs.rmdir(root, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "fixture",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    @store.FileStore::open(root + "/state.json"),
    runtime,
    "operator",
    "inference",
    "node",
    "test",
  )
  let offering : SharedTrialOffering = {
    organization_id: "org-energy",
    tenant_ref: "tenant-energy",
    node_id: "trial-node-a",
    node_label: "Shared Spark A",
    model_alias: "video.h3",
    model_name: "MiniMax H3",
    kind: "Video",
    health_url: "http://service.internal/health",
    public_url: "https://example.test/comfyui/",
  }
  assert_eq(
    service.with_shared_trial_offerings([offering]).shared_trial_offerings.length(),
    1,
  )
  let trial = service.with_shared_trial_offerings([
    { ..offering, kind: "Text", model_alias: "text.qwen", },
  ])
  assert_true(
    trial.shared_trial_text_key_scope(
      "org-energy",
      "tenant-energy",
      ["text.qwen"],
    ),
  )
  assert_false(
    trial.shared_trial_text_key_scope(
      "org-other",
      "tenant-energy",
      ["text.qwen"],
    ),
  )
  assert_false(
    trial.shared_trial_text_key_scope(
      "org-energy",
      "tenant-energy",
      ["text.other"],
    ),
  )
  assert_false(
    service.with_shared_trial_offerings([offering]).shared_trial_text_key_scope(
      "org-energy",
      "tenant-energy",
      ["video.h3"],
    ),
  )
  assert_true(
    try {
      ignore(service.with_shared_trial_offerings([offering, offering]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(service.with_shared_trial_offerings([
        { ..offering, kind: "Text", model_alias: "text.qwen", },
        {
          ..offering,
          node_id: "trial-node-b",
          kind: "Text",
          model_alias: "text.qwen",
        },
      ]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        service.with_shared_trial_offerings([
          { ..offering, public_url: "http://example.test/comfyui/", },
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
async test "shared trial billing authority requires an explicit unlimited company key" {
  let root = @fs.tmpdir(prefix="shared-trial-key-")
  defer @fs.rmdir(root, recursive=true)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "fixture",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let access = @access.AccessStore::open(
    root + "/keys.json",
    "shared-trial-test-issuer-more-than-thirty-two-bytes",
  )
  let service = ApiService::new(
    @store.FileStore::open(root + "/state.json"),
    runtime,
    "operator",
    "inference",
    "node",
    "test",
  )
    .with_access_store(access)
    .with_shared_trial_offerings([{
      organization_id: "org-energy",
      tenant_ref: "tenant-energy",
      node_id: "trial-node-text",
      node_label: "Shared Spark Text",
      model_alias: "text.qwen",
      model_name: "Qwen 27B",
      kind: "Text",
      health_url: "http://service.internal/health",
      public_url: "https://example.test/user/",
    }])
  let key = access.issue(
    {
      key_id: "shared-key",
      tenant_ref: "tenant-energy",
      subject_ref: "subject-a",
      organization_id: "org-energy",
      project_id: "project-a",
      display_name: "Shared trial",
      scopes: [Inference],
      allowed_models: ["text.qwen"],
      expires_unix_ms: 200000L,
      maximum_requests: 0L,
    },
    100000L,
  )
  let authority : @access.ApiAuthorization = {
    key_id: key.credential.key_id,
    tenant_ref: "tenant-energy",
    subject_ref: "subject-a",
    organization_id: "org-energy",
    project_id: "project-a",
  }
  assert_true(service.shared_trial_authorized_key(authority, "text.qwen") is Some(_))
  assert_true(service.shared_trial_authorized_key(authority, "text.other") is None)
  assert_true(
    service.shared_trial_authorized_key(
      { ..authority, organization_id: "org-other", },
      "text.qwen",
    ) is None,
  )
}
