///|
test "unbounded company model key stays visible to the workbench" {
  let key : @access.ApiCredentialView = {
    key_id: "key-a",
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: Some("organization-a"),
    project_id: Some("project-a"),
    display_name: "shared model",
    scopes: [Inference],
    allowed_models: ["text.glm"],
    issued_unix_ms: 1L,
    expires_unix_ms: 100L,
    maximum_requests: 0L,
    consumed_requests: 42L,
    revoked_unix_ms: None,
  }
  assert_true(workspace_model_key_visible(key, 50L))
  assert_false(
    workspace_model_key_visible({ ..key, maximum_requests: 42L, }, 50L),
  )
  assert_false(
    workspace_model_key_visible({ ..key, revoked_unix_ms: Some(40L), }, 50L),
  )
  assert_false(workspace_model_key_visible(key, 100L))
}
