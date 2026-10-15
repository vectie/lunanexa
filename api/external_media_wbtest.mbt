///|
async test "external media remains scoped to its approved model tenant node and generation" {
  let root = @fs.tmpdir(prefix="lunanexa-external-media-")
  defer @fs.rmdir(root, recursive=true)
  let listener = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer listener.close()
  let present = [true]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      listener.run_forever(allow_failure=true, (request, _, connection) => {
        assert_eq(
          request.headers.get("authorization"),
          Some("Bearer fixture-provider-token"),
        )
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string(
          if request.path == "/health" {
            "{}"
          } else if present[0] {
            "{\"data\":[{\"id\":\"served-video\"}]}"
          } else {
            "{\"data\":[]}"
          },
        )
        connection.end_response()
      })
    })
    let store = @store.FileStore::open(root + "/control.json")
    let registry = @registry.FileRegistry::open(root + "/registry.json")
    seed_access_package_model(registry)
    let runtime = @runtimes.OpenAiTextRuntime::new(
      "https://runtime.invalid/v1/responses",
      "",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    let token_path = root + "/provider-token"
    @fs.write_file(token_path, "fixture-provider-token", create_mode=CreateNew)
    let provider : ExternalMediaProvider = {
      provider_id: "external-media-trial-video",
      generation: 1L,
      active: true,
      tenant_ref: "tenant-a",
      node_id: "trial-node-a",
      artifact_digest: "sha256:" + "a".repeat(64),
      origin: "http://\{listener.addr}",
      bearer_file: Some(token_path),
      profile: {
        model: "qwen.default",
        provider_model: "served-video",
        widths: [512],
        heights: [512],
        maximum_frames: 25,
        maximum_fps: 24,
        maximum_steps: 8,
        sound_supported: false,
        image_reference_supported: None,
        image_reference_required: None,
      },
    }
    let base = ApiService::with_registry(
      store, registry, runtime, "operator", "inference", "node", "test",
    )
    let service = base
      .with_external_media_providers([provider])
      .with_client_model_policies({
        "comfyui": ["qwen.default"],
        "desktop-workspace": ["text.private"],
      })
    assert_true(service.external_media_ready(provider))
    assert_false(
      service.external_media_ready({
        ..provider,
        artifact_digest: "sha256:" + "c".repeat(64),
      }),
    )
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-a",
      ),
      ["qwen.default"],
    )
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-b",
      ),
      [],
    )
    assert_eq(
      service.client_models("comfyui", ["text.private", "qwen.default"]),
      ["qwen.default"],
    )
    assert_eq(
      service.client_models("desktop-workspace", [
        "text.private", "qwen.default",
      ]),
      ["text.private"],
    )
    let binding = provider.binding()
    let owner : @media_jobs.Owner = {
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      organization_id: "org-a",
      project_id: "project-a",
      authority: PrivateWorkspace("lease-a"),
    }
    assert_true(service.media_order_matches(owner, binding.execution_context()))
    assert_false(
      service.media_order_matches(
        { ..owner, tenant_ref: "tenant-b", },
        binding.execution_context(),
      ),
    )
    assert_false(
      service.media_order_matches(
        { ..owner, authority: DedicatedOrder("paid-order"), },
        binding.execution_context(),
      ),
    )
    assert_true(
      service.media_execution_authorized(
        "qwen.default",
        binding.execution_context(),
      ),
    )
    assert_false(
      service.media_execution_authorized("qwen.default", {
        ..binding.execution_context(),
        node_id: "reserved-node",
      }),
    )
    assert_false(
      service.media_execution_authorized("qwen.default", {
        ..binding.execution_context(),
        generation: 2L,
      }),
    )
    present[0] = false
    assert_false(service.external_media_ready(provider))
    assert_eq(
      service.serving_client_model_aliases(
        ["qwen.default"],
        tenant_ref="tenant-a",
      ),
      [],
    )
    // Readiness loss preserves the original cleanup authority and identity.
    assert_true(
      service.media_execution_authorized(
        "qwen.default",
        binding.execution_context(),
      ),
    )
    for
      bad in [
        { ..provider, origin: "http://example.com", },
        { ..provider, provider_id: "managed-deployment", },
      ] {
      try ignore(base.with_external_media_providers([bad])) catch {
        Failure(_) => ()
        error => raise error
      } noraise {
        _ => fail("unsafe provider accepted")
      }
    }
  }
}
