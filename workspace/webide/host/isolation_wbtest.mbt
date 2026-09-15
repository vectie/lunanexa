///|
test "every authority dimension gets a distinct PVC and only its own credential volume" {
  let config = host_config()
  let host = WorkspaceHost::new(config)
  let original = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let names : Map[String, Bool] = Map([])
  for
    grant in [
      original,
      { ..original, tenant_ref: "tenant-b", },
      { ..original, organization_id: "org-b", },
      { ..original, project_id: "project-b", },
      { ..original, subject_ref: "bob", },
    ] {
    let name = resource_name(@webide.workspace_id(grant))
    assert_false(names.contains(name))
    names[name] = true
    let resources = host.resources(@webide.workspace_id(grant), grant)
    let claim = resources
      .iter()
      .find_first(entry => entry.0.contains("/persistentvolumeclaims/"))
      .unwrap().1
    assert_true(
      claim is { "metadata": { "name": String(actual), .. }, .. } &&
      actual == name,
    )
    let deployment = resources
      .iter()
      .find_first(entry => entry.0.contains("/deployments/"))
      .unwrap().1
    guard deployment
      is {
        "spec": {
          "template": {
            "spec": {
              "volumes": Array(volumes),
              "containers": Array(containers),
              ..
            },
            ..
          },
          ..
        },
        ..
      } else {
      fail("No workspace volumes")
    }
    let claims = volumes.filter(volume => {
      volume is { "persistentVolumeClaim": _, .. }
    })
    assert_eq(claims.length(), 1)
    assert_true(
      claims[0]
      is { "persistentVolumeClaim": { "claimName": String(actual), .. }, .. } &&
      actual == name,
    )
    assert_false(volumes.any(volume => volume is { "hostPath": _, .. }))
    assert_eq(
      containers
      .filter(container => container is { "name": "comfyui", .. })
      .length(),
      1,
    )
    for container in containers {
      if container is { "name": "comfyui", .. } {
        assert_true(container is { "volumeMounts": Array(_), .. })
      }
      if container is { "name": "comfyui", "volumeMounts": Array(mounts), .. } {
        assert_false(
          mounts.any(mount => mount is { "name": "model-credential", .. }),
        )
        assert_false(container.stringify().contains(original.api_secret))
      }
    }
  }
  assert_eq(names.length(), 5)
}
