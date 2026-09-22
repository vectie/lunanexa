///|
fn host_config() -> HostConfig {
  {
    namespace_name: "webide",
    controller_namespace: "lunanexa",
    model_gateway_namespace: "webide",
    comfyui_image: "registry.test/comfyui@sha256:" + "a".repeat(64),
    model_proxy_image: "registry.test/proxy@sha256:" + "b".repeat(64),
    storage_class: "local-path",
    storage_gib: 10,
    cpu_millis: 1000,
    memory_mib: 2048,
    controller_origin: "http://controller.webide.svc:5000",
    model_gateway_origin: "http://model-gateway.webide.svc:5001",
    trusted_ca_config_map: None,
    controller_port: 5000,
    model_gateway_port: 5001,
    kubernetes_origin: "https://kubernetes.default.svc",
    kubernetes_ca_file: "/run/secrets/ca.crt",
    kubernetes_token_file: "/run/secrets/token",
  }
}

///|
fn proxy_config(controller : String, gateway : String) -> ModelProxyConfig {
  {
    delivery_id: None,
    client_id: "comfyui",
    tenant_ref: "tenant-a",
    subject_ref: "alice",
    organization_id: "org-a",
    project_id: "project-a",
    api_secret: "lnx_private_fake_test_credential_only",
    allowed_models: ["video.h3"],
    expires_unix_ms: @async.now() + 60000L,
    controller_origin: controller,
    model_gateway_origin: gateway,
  }
}

///|
test "platform CA is deployment-owned and mounted only by the model proxy" {
  let config = { ..host_config(), trusted_ca_config_map: Some("platform-ca"), }
  let host = WorkspaceHost::new(config)
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let resources = host.resources(@webide.workspace_id(grant), grant)
  let workload = resources
    .iter()
    .find_first(entry => entry.0.contains("/deployments/"))
    .unwrap().1
  guard workload
    is {
      "spec": {
        "template": {
          "metadata": {
            "labels": { "app.kubernetes.io/managed-by": String(manager), .. },
            ..
          },
          ..
        },
        ..
      },
      ..
    } else {
    fail("workspace pods must match gateway network-policy selectors")
  }
  assert_eq(manager, "lunanexa-webide")
  let deployment = resources
    .iter()
    .find_first(entry => entry.0.contains("/deployments/"))
    .unwrap().1
  guard deployment
    is {
      "spec": {
        "template": { "spec": { "containers": Array(containers), .. }, .. },
        ..
      },
      ..
    } else {
    fail("missing workspace containers")
  }
  for container in containers {
    guard container is { "name": String(name), .. } else {
      fail("missing container name")
    }
    if name == "model-proxy" {
      assert_true(container.stringify().contains("SSL_CERT_FILE"))
      assert_true(container.stringify().contains("/run/platform-trust"))
    } else {
      assert_false(container.stringify().contains("platform-trust"))
      assert_false(container.stringify().contains("SSL_CERT_FILE"))
    }
  }
  assert_true(deployment.stringify().contains("ca-bundle.crt"))
  try
    WorkspaceHost::new({ ..config, trusted_ca_config_map: Some("../secret"), })
  catch {
    InvalidConfiguration => ()
    _ => fail("unexpected host error")
  } noraise {
    _ => fail("invalid ConfigMap reference accepted")
  }
}

///|
test "workspace desired state is deterministic, private and CPU-only" {
  let config = host_config()
  let host = WorkspaceHost::new(config)
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let id = @webide.workspace_id(grant)
  let resources = host.resources(id, grant)
  assert_eq(resources, host.resources(id, grant))
  assert_eq(resources.length(), 5)
  assert_true(resources[0].0.contains("networkpolicies"))
  assert_true(
    resources[0].1
    .stringify()
    .contains("\"kubernetes.io/metadata.name\":\"lunanexa\""),
  )
  assert_true(
    resources[0].1
    .stringify()
    .contains("\"kubernetes.io/metadata.name\":\"webide\""),
  )
  let mut secrets = 0
  for entry in resources {
    let (path, value) = entry
    let text = value.stringify()
    if path.contains("/secrets/") {
      assert_true(text.contains(grant.api_secret))
      secrets += 1
    } else {
      assert_false(text.contains(grant.api_secret))
    }
    assert_false(text.contains("hostPath"))
    assert_false(text.contains("NodePort"))
    assert_false(text.contains("nvidia.com/gpu"))
    assert_false(text.contains("privileged"))
  }
  assert_eq(secrets, 1)
  let deployment = resources[4].1
  let desired = deployment.stringify()
  assert_false(desired.contains("--base-directory"))
  assert_true(desired.contains("--disable-api-nodes"))
  assert_true(desired.contains("--disable-all-custom-nodes"))
  assert_true(desired.contains("--enable-assets"))
  assert_true(desired.contains("sqlite:////workspace/user/comfyui.db"))
  assert_true(desired.contains("initialize-workspace"))
  assert_true(
    deployment
    is {
      "spec": {
        "template": {
          "spec": {
            "automountServiceAccountToken": False,
            "nodeSelector": { "lunanexa.io/workspace-host": String("true"), .. },
            ..
          },
          ..
        },
        ..
      },
      ..
    },
  )
  assert_true(deployment.stringify().contains("127.0.0.1") == false)
  assert_eq(resource_name(id).length(), 63)
  assert_true(dns_label(resource_name(id)))
  assert_true(
    resource_name(id) !=
    resource_name(@webide.workspace_id({ ..grant, subject_ref: "bob", })),
  )
}

///|
async test "workspace initialization preserves user edits and refuses symlink directories" {
  let root = @fs.tmpdir(prefix="lunanexa-webide-initialize-")
  defer @fs.rmdir(root, recursive=true)
  initialize_workspace(root, "video.h3")
  let path = root + "/user/default/workflows/LunaNexa Video.json"
  let initial = @fs.read_file(path).text()
  assert_true(initial.contains("VLLMOmniGenerateVideo"))
  assert_true(initial.contains("http://127.0.0.1:8189/v1"))
  assert_false(initial.contains("api_secret"))
  @fs.write_file(path, "user-owned-workflow")
  initialize_workspace(root, "video.another-approved-model")
  assert_eq(@fs.read_file(path).text(), "user-owned-workflow")
  let unsafe_root = @fs.tmpdir(prefix="lunanexa-webide-symlink-")
  defer @fs.rmdir(unsafe_root, recursive=true)
  @fs.symlink(target=root + "/user", unsafe_root + "/user")
  try {
    initialize_workspace(unsafe_root, "video.h3")
    fail("symlink directory accepted")
  } catch {
    HostError::InvalidConfiguration => ()
    error => fail("Unexpected error: \{error}")
  }
}

///|
test "host accepts only bounded resources and immutable images" {
  assert_true(pinned_image(host_config().comfyui_image))
  for
    image in [
      "comfyui:latest",
      "image@sha256:short",
      "image@sha256:" + "g".repeat(64),
    ] {
    assert_false(pinned_image(image))
  }
  for
    config in [
      { ..host_config(), storage_gib: 0, },
      { ..host_config(), cpu_millis: 0, },
      { ..host_config(), kubernetes_origin: "http://kubernetes.default.svc", },
      { ..host_config(), namespace_name: "../../kube-system", },
      { ..host_config(), controller_namespace: "../../kube-system", },
      { ..host_config(), model_gateway_namespace: "*", },
    ] {
    try {
      ignore(WorkspaceHost::new(config))
      fail("unsafe host configuration accepted")
    } catch {
      HostError::InvalidConfiguration => ()
      error => fail("Unexpected validation error: \{error}")
    }
  }
}

///|
test "ComfyUI forms cannot override or duplicate the approved model" {
  assert_eq(encode_query("a/b+c="), "a%2Fb%2Bc%3D")
  assert_eq(
    form_model(
      "application/x-www-form-urlencoded", b"model=video.h3&prompt=hello+world",
    ),
    Some("video.h3"),
  )
  assert_eq(
    form_model("application/x-www-form-urlencoded", b"%6dodel=video.h3"),
    Some("video.h3"),
  )
  assert_eq(
    form_model(
      "application/x-www-form-urlencoded", b"model=video.h3&%6dodel=evil",
    ),
    None,
  )
  assert_eq(form_model("application/x-www-form-urlencoded", b"model=%GG"), None)
  let multipart = "--boundary\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvideo.h3\r\n--boundary--\r\n"
  assert_eq(
    form_model(
      "multipart/form-data; boundary=boundary",
      @utf8.encode(multipart),
    ),
    Some("video.h3"),
  )
  assert_eq(
    form_model("multipart/form-data; boundary=other", @utf8.encode(multipart)),
    None,
  )
  assert_false(model_route(Get, "/v1/videos/../../models"))
  assert_false(model_route(Post, "/v1/videos/123/content"))
  assert_true(model_route(Get, "/v1/videos/video-123/content"))
  assert_true(model_route(Delete, "/v1/videos/video-123"))
}

///|
async test "partial provisioning resumes deterministically and stale reconciliation rechecks the current secret" {
  let controller = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer controller.close()
  let config = {
    ..host_config(),
    controller_origin: "http://\{controller.addr}",
  }
  let credentials = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  )
  let grant = credentials.grant()
  let name = resource_name(@webide.workspace_id(grant))
  let resources : Map[String, Json] = Map([])
  let requests : Array[String] = []
  let state = { "fail_secret": true, "active": true, "outage": false }
  let secret : Json = {
    "metadata": { "name": name },
    "data": {
      "model-proxy.json": @base64.encode(
        @utf8.encode(ToJson::to_json(credentials).stringify()),
      ),
    },
  }
  let ready : Json = {
    "metadata": { "generation": 1 },
    "spec": { "replicas": 1 },
    "status": {
      "availableReplicas": 1,
      "updatedReplicas": 1,
      "observedGeneration": 1,
    },
  }
  let host : WorkspaceHost = {
    config,
    require_exclusive: false,
    observation_token: "",
    locks: {},
    kubernetes_override: Some((verb, path, body) => {
      requests.push(path)
      if path.contains("/pods?") || path.contains("/deployments?") {
        (200, { "items": [] })
      } else if verb == Patch {
        if path.contains("/secrets/") && state["fail_secret"] {
          raise HostError::WorkspaceUnavailable
        }
        resources[path] = body.unwrap()
        (200, body.unwrap())
      } else if verb == Put {
        resources[path] = body.unwrap()
        (200, body.unwrap())
      } else if path.contains("/secrets?") {
        // The list deliberately contains a malformed/stale secret. The live
        // per-workspace GET is the authority used for the stop decision.
        (
          200,
          {
            "items": [
              {
                "metadata": { "name": name },
                "data": { "model-proxy.json": "stale" },
              },
            ],
            "metadata": { "continue": "" },
          },
        )
      } else if path.contains("/secrets/") {
        (200, secret)
      } else {
        (200, ready)
      }
    }),
  }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      controller.run_forever((_request, _body, connection) => {
        connection.send_response(
          if state["outage"] {
            503
          } else if state["active"] {
            200
          } else {
            401
          },
          "Authority",
        )
        connection.write_string("{}")
        connection.end_response()
      })
    })
    try {
      ignore(host.provision(@webide.workspace_id(grant), grant))
      fail("partial provisioning claimed success")
    } catch {
      HostError::WorkspaceUnavailable => ()
      error => fail("Unexpected provisioning error: \{error}")
    }
    assert_eq(resources.length(), 2)
    assert_false(resources.keys().any(path => path.contains("/deployments/")))
    state["fail_secret"] = false
    let backend = host.provision(@webide.workspace_id(grant), grant)
    assert_eq(resources.length(), 5)
    assert_eq(backend.http_url, "http://\{name}.webide.svc.cluster.local:8188")
    host.reconcile()
    assert_false(resources.keys().any(path => path.has_suffix("/scale")))
    state["outage"] = true
    try host.authorize(grant) catch {
      @webide.BridgeError::AuthorityUnavailable => ()
      error => fail("Unexpected authority error: \{error}")
    } noraise {
      _ =>
        fail("Unavailable authority must not grant access or claim revocation")
    }
    host.reconcile()
    assert_false(resources.keys().any(path => path.has_suffix("/scale")))
    assert_false(
      host.authorize({ ..grant, expires_unix_ms: @async.now() - 1L, }),
    )
    state["outage"] = false
    assert_true(host.authorize(grant))
    state["active"] = false
    host.reconcile()
    let scales = resources
      .iter()
      .filter(pair => pair.0.has_suffix("/scale"))
      .to_array()
    assert_eq(scales.length(), 1)
    assert_true(
      scales[0].1 is { "spec": { "replicas": Number(0.0, ..), .. }, .. },
    )
    assert_true(
      requests
      .filter(path => path.contains("/persistentvolumeclaims/"))
      .length() ==
      2,
    )
  }
}

///|
async test "pod-local model proxy injects scoped credentials and never bypasses the provider gateway" {
  let controller = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let gateway = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let proxy = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer controller.close()
  defer gateway.close()
  defer proxy.close()
  let directory = @fs.tmpdir(prefix="lunanexa-webide-model-proxy-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/config.json"
  let config = proxy_config(
    "http://\{controller.addr}",
    "http://\{gateway.addr}",
  )
  @fs.write_file(
    path,
    ToJson::to_json(config).stringify(),
    create_mode=CreateNew,
    permission=0o600,
  )
  let state = { "active": true }
  let forwarded : Array[String] = []
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      controller.run_forever((request, _body, connection) => {
        assert_eq(request.path, "/v1/models")
        assert_eq(
          request_header(request.headers, "authorization"),
          Some("Bearer " + config.api_secret),
        )
        connection.send_response(
          if state["active"] {
            200
          } else {
            401
          },
          "Authority",
        )
        connection.write_string("{}")
        connection.end_response()
      })
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      gateway.run_forever((request, body, connection) => {
        assert_eq(
          request_header(request.headers, "authorization"),
          Some("Bearer " + config.api_secret),
        )
        forwarded.push(@utf8.decode(limited(body, 4096)))
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string("{\"id\":\"video-123\",\"status\":\"queued\"}")
        connection.end_response()
      })
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      proxy.run_forever((request, body, connection) => {
        handle_model_proxy(path, request, body, connection)
      })
    })
    let origin = "http://\{proxy.addr}"
    let (models, listed) = @http.get(origin + "/v1/models")
    assert_eq(models.code, 200)
    assert_true(listed.text().contains("video.h3"))
    assert_false(listed.text().contains(config.api_secret))
    let headers = {
      "content-type": "application/x-www-form-urlencoded",
      "authorization": "Bearer browser-poison",
      "idempotency-key": "fixture-video-request",
    }
    let (submitted, result) = @http.post(
      origin + "/v1/videos",
      "model=video.h3&prompt=hello",
      headers~,
    )
    assert_eq(submitted.code, 200)
    assert_false(result.text().contains(config.api_secret))
    assert_eq(forwarded, ["model=video.h3&prompt=hello"])
    let (wrong_model, _) = @http.post(
      origin + "/v1/videos",
      "model=unapproved&prompt=hello",
      headers~,
    )
    assert_eq(wrong_model.code, 403)
    let (duplicate, _) = @http.post(
      origin + "/v1/videos",
      "model=video.h3&model=evil",
      headers~,
    )
    assert_eq(duplicate.code, 403)
    let multipart = "--editor\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvideo.h3\r\n--editor\r\nContent-Disposition: form-data; name=\"prompt\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nTEST ONLY 中文\r\n--editor--\r\n"
    let (converted, _) = @http.post(origin + "/v1/videos", multipart, headers={
      "content-type": "multipart/form-data; boundary=editor",
      "idempotency-key": "fixture-multipart-request",
    })
    assert_eq(converted.code, 200)
    json_inspect(@json.parse(forwarded[1]), content={
      "model": "video.h3",
      "prompt": "TEST ONLY 中文",
    })
    state["active"] = false
    let (revoked, _) = @http.post(
      origin + "/v1/videos",
      "model=video.h3&prompt=hello",
      headers~,
    )
    assert_eq(revoked.code, 401)
    assert_eq(forwarded.length(), 2)
  }
}
