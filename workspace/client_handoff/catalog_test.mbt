///|
test "WebIDE catalog validates all bridges and rejects duplicate identities" {
  let desktop : @client_handoff.ClientLaunchConfig = {
    client_id: "desktop",
    display_name: "Desktop WebIDE",
    launch_uri: "http://127.0.0.1:4188/connect",
    public_api_base_url: "https://gateway.example/v1",
    handoff_lifetime_ms: 120000L,
    maximum_requests: 1000L,
    allowed_organization_ids: None,
  }
  let comfy = {
    ..desktop,
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://creative.example/connect",
  }
  let robo = {
    ..desktop,
    client_id: "moonrobo",
    display_name: "MoonRobo",
    launch_uri: "https://robot.example/connect",
  }
  let town = {
    ..desktop,
    client_id: "moontown",
    display_name: "MoonTown",
    launch_uri: "https://platform.example/moontown/connect",
  }
  assert_true(
    @client_handoff.valid_client_launch_catalog([desktop, comfy, robo, town]),
  )
  assert_false(@client_handoff.valid_client_launch_catalog([]))
  assert_false(@client_handoff.valid_client_launch_catalog([desktop, desktop]))
  assert_false(
    @client_handoff.valid_client_launch_catalog([
      desktop,
      { ..comfy, launch_uri: "http://public.example:8188", },
    ]),
  )
  assert_false(
    @client_handoff.valid_client_launch_catalog([
      desktop,
      { ..comfy, public_api_base_url: "https://gateway.example/?secret=bad", },
    ]),
  )
  assert_false(
    @client_handoff.valid_client_launch_catalog(Array::make(33, comfy)),
  )
  let scoped = { ..desktop, allowed_organization_ids: Some(["org-youth"]), }
  assert_true(@client_handoff.valid_client_launch_config(scoped))
  assert_true(scoped.allows_organization("org-youth"))
  assert_false(scoped.allows_organization("org-other"))
  assert_true(desktop.allows_organization("org-other"))
  assert_false(
    { ..desktop, allowed_organization_ids: Some([]), }.allows_organization(
      "org-youth",
    ),
  )
  assert_false(
    @client_handoff.valid_client_launch_config({
      ..desktop,
      allowed_organization_ids: Some(["org-youth", "org-youth"]),
    }),
  )
  let legacy : @client_handoff.ClientLaunchConfig = @json.from_json(
    @json.parse(
      "{\"client_id\":\"legacy\",\"display_name\":\"Legacy\",\"launch_uri\":\"https://app.example/connect\",\"public_api_base_url\":\"https://api.example/v1\",\"handoff_lifetime_ms\":\"120000\",\"maximum_requests\":\"1000\"}",
    ),
  )
  assert_true(legacy.allows_organization("org-other"))
}
