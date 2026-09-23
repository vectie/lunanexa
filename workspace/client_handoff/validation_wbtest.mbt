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
test "public HTTP API origin needs its own exact deployment allowlist" {
  let config = launch_fixture(
    "https://workspace.example/connect", "http://198.51.100.5:5000/v1",
  )
  assert_false(valid_client_launch_config(config))
  assert_true(
    valid_client_launch_config(config, allowed_http_api_origins=[
      "http://198.51.100.5:5000",
    ]),
  )
  assert_false(
    valid_client_launch_config(
      { ..config, public_api_base_url: "http://198.51.100.5:5001/v1", },
      allowed_http_api_origins=["http://198.51.100.5:5000"],
    ),
  )
  assert_false(
    valid_client_launch_config(
      { ..config, launch_uri: "http://198.51.100.5:5000/connect", },
      allowed_http_api_origins=["http://198.51.100.5:5000"],
    ),
  )
}

///|
test "explicit HTTP launch origin does not relax model API or adjacent origins" {
  let allowed = ["http://198.51.100.5:5000"]
  let config = launch_fixture(
    "http://198.51.100.5:5000/connect", "https://gateway.example/v1",
  )
  assert_false(valid_client_launch_config(config))
  assert_true(
    valid_client_launch_config(config, allowed_http_launch_origins=allowed),
  )
  assert_true(
    valid_client_launch_catalog([config], allowed_http_launch_origins=allowed),
  )
  for
    uri in [
      "http://198.51.100.5:5001/connect", "http://198.51.100.6:5000/connect", "http://198.51.100.5:5000.evil/connect",
      "http://user@198.51.100.5:5000/connect", "http://198.51.100.5:5000/connect#secret",
      "http://198.51.100.5:5000\\evil/connect",
    ] {
    assert_false(
      valid_client_launch_config(
        { ..config, launch_uri: uri, },
        allowed_http_launch_origins=allowed,
      ),
    )
  }
  assert_false(
    valid_client_launch_config(
      { ..config, public_api_base_url: "http://198.51.100.5:5000/v1", },
      allowed_http_launch_origins=allowed,
    ),
  )
  let decoded : ClientLaunchConfig = @json.from_json(
    @json.parse(config.to_json().stringify()),
  )
  assert_true(
    valid_client_launch_config(decoded, allowed_http_launch_origins=allowed),
  )
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
