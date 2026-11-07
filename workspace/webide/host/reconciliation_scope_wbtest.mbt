///|
async test "shared and exclusive gateways do not reconcile each other's ComfyUI" {
  for
    (require_exclusive, delivery_id) in [
      (true, None),
      (false, Some("delivery-other-gateway")),
    ] {
    let credentials = {
      ..proxy_config("http://controller", "http://gateway"),
      delivery_id,
      expires_unix_ms: @async.now() - 1L,
    }
    let name = resource_name(@webide.workspace_id(credentials.grant()))
    let secret : Json = {
      "data": {
        "model-proxy.json": @base64.encode(
          @utf8.encode(ToJson::to_json(credentials).stringify()),
        ),
      },
    }
    let host : WorkspaceHost = {
      config: host_config(),
      require_exclusive,
      observation_token: "",
      locks: {},
      kubernetes_override: Some((verb, path, _) => {
        if verb == Get && path.contains("/secrets/") {
          (200, secret)
        } else {
          fail("a different workspace profile must not stop this workspace")
        }
      }),
    }
    host.reconcile_page(
      { "items": [{ "metadata": { "name": name } }] },
      "comfyui",
      "",
    )
  }
}
