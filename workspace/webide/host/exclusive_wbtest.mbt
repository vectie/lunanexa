///|
fn exclusive_fixture() -> ExclusivePlacement {
  {
    reservation_id: "reservation-123",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    node_name: "spark-25e2",
  }
}

///|
test "delivery runtime identities isolate clients while same-client data survives renewal" {
  let config = host_config()
  let host = WorkspaceHost::new(config)
  let base = proxy_config(config.controller_origin, config.model_gateway_origin).grant()
  let comfy = {
    ..base,
    delivery_id: Some("delivery-comfy"),
    client_id: "comfyui",
  }
  let terminal = {
    ..base,
    delivery_id: Some("delivery-terminal"),
    client_id: "terminal",
  }
  let renewed = { ..comfy, delivery_id: Some("delivery-next"), }
  assert_true(@webide.workspace_id(comfy) != @webide.workspace_id(terminal))
  assert_true(@webide.workspace_id(comfy) != @webide.workspace_id(renewed))
  assert_eq(@webide.workspace_id(comfy), @webide.workspace_id(comfy))
  assert_true(
    @webide.workspace_storage_id(comfy) !=
    @webide.workspace_storage_id(terminal),
  )
  assert_eq(
    @webide.workspace_storage_id(comfy),
    @webide.workspace_storage_id(renewed),
  )
  assert_eq(@webide.workspace_storage_id(base), @webide.workspace_id(base))
  let original_resources = host.resources(
    @webide.workspace_id(comfy),
    comfy,
    placement=exclusive_fixture(),
  )
  let renewed_resources = host.resources(
    @webide.workspace_id(renewed),
    renewed,
    placement=exclusive_fixture(),
  )
  assert_eq(original_resources[1], renewed_resources[1])
  assert_true(original_resources[4].0 != renewed_resources[4].0)
  let secret = original_resources[2].1
  guard secret
    is { "stringData": { "model-proxy.json": String(serialized), .. }, .. } else {
    fail("missing recovery secret")
  }
  let restored : ModelProxyConfig = @json.from_json(@json.parse(serialized))
  assert_eq(restored.delivery_id, Some("delivery-comfy"))
  assert_eq(@webide.workspace_id(restored.grant()), @webide.workspace_id(comfy))
}

///|
async test "stop drains only the selected workspace and does not delete persistence" {
  let config = host_config()
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let id = @webide.workspace_id(grant)
  let name = resource_name(id)
  let requests : Array[String] = []
  let host : WorkspaceHost = {
    config,
    require_exclusive: false,
    observation_token: "",
    locks: {},
    kubernetes_override: Some((verb, path, body) => {
      requests.push(path)
      if verb == Put {
        assert_true(path.has_suffix("/deployments/\{name}/scale"))
        assert_true(
          body is Some({ "spec": { "replicas": Number(0.0, ..), .. }, .. }),
        )
        (200, {})
      } else {
        assert_eq(verb, Get)
        assert_true(path.contains("workspace%3D\{name}"))
        (200, { "items": [] })
      }
    }),
  }
  host.stop(id)
  assert_eq(requests.length(), 2)
  assert_false(requests.any(path => path.contains("persistentvolumeclaims")))
}

///|
test "exclusive ComfyUI uses reserved node and retains stable customer volume" {
  let config = host_config()
  let host = WorkspaceHost::new(config)
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let id = @webide.workspace_id(grant)
  let legacy = host.resources(id, grant)
  let assigned = host.resources(id, grant, placement=exclusive_fixture())
  assert_eq(legacy[1], assigned[1])
  let workload = assigned[4].1.stringify()
  assert_true(workload.contains("spark-25e2"))
  assert_true(workload.contains("reservation-123"))
  assert_false(workload.contains("workspace-host"))
  assert_false(workload.contains("nvidia.com/gpu"))
  assert_true(workload.contains("/workspace/output"))
  assert_eq(assigned, host.resources(id, grant, placement=exclusive_fixture()))
  let renewed = host.resources(id, grant, placement={
    ..exclusive_fixture(),
    reservation_id: "reservation-456",
  })
  assert_eq(assigned[1], renewed[1])
  try
    host.resources(id, grant, placement={
      ..exclusive_fixture(),
      tenant_ref: "other",
    })
  catch {
    HostError::ControllerRejected => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("cross tenant placement accepted")
  }
}

///|
test "exclusive GPU terminal has persistent HOME and no host authority" {
  let config = host_config()
  let host = WorkspaceHost::new(config)
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let grant = { ..grant, allowed_models: [], }
  let runtime : ExclusiveContainer = {
    image: "registry.test/terminal@sha256:" + "c".repeat(64),
    command: ["/usr/bin/ttyd"],
    args: ["-p", "7681", "bash"],
    port: 7681,
    cpu_millis: 4000,
    memory_mib: 8192,
    gpu: true,
  }
  let resources = host.resources(
    @webide.workspace_id(grant),
    grant,
    placement=exclusive_fixture(),
    container=runtime,
  )
  let workload = resources[4].1.stringify()
  assert_true(workload.contains("nvidia.com/gpu"))
  assert_true(workload.contains("\"runtimeClassName\":\"nvidia\""))
  assert_true(workload.contains("\"workingDir\":\"/workspace\""))
  assert_true(workload.contains("\"runAsNonRoot\":true"))
  assert_true(workload.contains("\"automountServiceAccountToken\":false"))
  assert_false(workload.contains("/opt/ComfyUI/main.py"))
  for
    forbidden in [
      "hostPath", "hostNetwork", "privileged", "containerd.sock", "docker.sock",
    ] {
    assert_false(workload.contains(forbidden))
  }
  assert_true(resources[3].1.stringify().contains("\"targetPort\":7681"))
  assert_true(resources[0].1.stringify().contains("\"port\":7681"))
  try
    host.resources(@webide.workspace_id(grant), grant, container=runtime)
  catch {
    HostError::InvalidConfiguration => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("GPU container without placement accepted")
  }
}
