///|
fn launch_fixture(
  launch_uri : String,
  public_api_base_url : String,
) -> ClientLaunchConfig {
  {
    client_id: "desktop-workspace",
    display_name: "Desktop WebIDE",
    launch_uri,
    public_api_base_url,
    handoff_lifetime_ms: 120_000L,
    maximum_requests: 100_000L,
  }
}

///|
test "client launch URLs accept HTTPS and exact loopback HTTP only" {
  assert_true(
    valid_client_launch_config(
      launch_fixture(
        "http://127.0.0.1:4188/?mode=mooncode", "https://management.example/v1",
      ),
    ),
  )
  assert_true(
    valid_client_launch_config(
      launch_fixture(
        "lunanexa-client://workspace/open", "http://localhost:18443/v1",
      ),
    ),
  )
  for
    malicious in [
      "http://localhost:4188@attacker.invalid/", "http://127.0.0.1.attacker.invalid/",
      "http://localhost:not-a-port/", "https://trusted.example@attacker.invalid/",
      "https://management.example/#stale-fragment",
    ] {
    assert_false(
      valid_client_launch_config(
        launch_fixture(malicious, "https://management.example/v1"),
      ),
    )
  }
}

///|
test "public API base rejects query, fragment, userinfo, and remote HTTP" {
  for
    malicious in [
      "http://management.example/v1", "https://management.example/v1?token=secret",
      "https://management.example/v1#fragment", "https://trusted@management.example/v1",
    ] {
    assert_false(
      valid_client_launch_config(
        launch_fixture("https://workspace.example/open", malicious),
      ),
    )
  }
}
