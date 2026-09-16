///|
test "WebIDE catalog validates all bridges and rejects duplicate identities" {
  let desktop : @client_handoff.ClientLaunchConfig = {
    client_id: "desktop",
    display_name: "Desktop WebIDE",
    launch_uri: "http://127.0.0.1:4188/connect",
    public_api_base_url: "https://gateway.example/v1",
    handoff_lifetime_ms: 120000L,
    maximum_requests: 1000L,
  }
  let comfy = {
    ..desktop,
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://creative.example/connect",
  }
  assert_true(@client_handoff.valid_client_launch_catalog([desktop, comfy]))
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
}
