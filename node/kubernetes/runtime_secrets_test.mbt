///|
fn runtime_binding() -> @kubernetes.RuntimeSecretBinding {
  {
    image_ref: identity().image_ref,
    environment_name: "TEST_VIDEO_BEARER",
    secret_name: "lunanexa-runtime-test-video-v1",
    secret_key: "bearer",
  }
}

///|
test "runtime secret references are image-bound required references, never inline credentials" {
  let assignment = runtime_assignment()
  let settings = {
    ..runtime_settings(),
    runtime_secrets: Some([runtime_binding()]),
  }
  let plan = @kubernetes.render_runtime(
    settings,
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_true(
    plan.pod
    is {
      "spec": {
        "containers": [
          {
            "env": [
              _,
              _,
              {
                "name": "TEST_VIDEO_BEARER",
                "valueFrom": {
                  "secretKeyRef": {
                    "name": "lunanexa-runtime-test-video-v1",
                    "key": "bearer",
                    "optional": false,
                    ..
                  },
                  ..
                },
                ..
              },
            ],
            ..
          },
        ],
        ..
      },
      ..
    },
  )
  let foreign = {
    ..runtime_binding(),
    image_ref: "other/runtime@" + assignment.runtime.image_digest,
  }
  let other_plan = @kubernetes.render_runtime(
    { ..settings, runtime_secrets: Some([foreign]), },
    assignment,
    "/var/lib/lunanexa/models/model",
    assignment.artifact.digest,
    5L,
    1000L,
  )
  assert_false(other_plan.pod.stringify().contains("TEST_VIDEO_BEARER"))
  assert_false(
    other_plan.pod.stringify().contains("lunanexa-runtime-test-video"),
  )
}

///|
test "runtime secret configuration cannot override node authority, device selection or model location" {
  let assignment = runtime_assignment()
  for
    name in [
      "LUNANEXA_MODEL_PATH", "AWS_SECRET_ACCESS_KEY", "NVIDIA_VISIBLE_DEVICES", "LD_PRELOAD",
      "PATH", "HTTPS_PROXY", "9TOKEN",
    ] {
    let settings = {
      ..runtime_settings(),
      runtime_secrets: Some([{ ..runtime_binding(), environment_name: name, }]),
    }
    try
      @kubernetes.render_runtime(
        settings,
        assignment,
        "/var/lib/lunanexa/models/model",
        assignment.artifact.digest,
        5L,
        1000L,
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong reserved environment rejection")
    } noraise {
      _ => fail("reserved environment override accepted")
    }
  }
}

///|
test "runtime secret references reject unpinned images cross-purpose names and duplicates" {
  let assignment = runtime_assignment()
  for
    bindings in [
      [{ ..runtime_binding(), image_ref: "registry/runtime:latest", }],
      [{ ..runtime_binding(), secret_name: "node-token", }],
      [{ ..runtime_binding(), secret_key: "", }],
      [runtime_binding(), runtime_binding()],
    ] {
    try
      @kubernetes.render_runtime(
        { ..runtime_settings(), runtime_secrets: Some(bindings), },
        assignment,
        "/var/lib/lunanexa/models/model",
        assignment.artifact.digest,
        5L,
        1000L,
      )
    catch {
      @kubernetes.InvalidResource => ()
      _ => fail("wrong reference rejection")
    } noraise {
      _ => fail("unsafe secret reference accepted")
    }
  }
}

///|
test "existing runtime configuration without a secret field remains compatible" {
  let value = runtime_settings().to_json()
  guard value is Object(fields) else { fail("not a settings object") }
  fields.remove("runtime_secrets")
  let restored : @kubernetes.RuntimeSettings = @json.from_json(value)
  assert_eq(restored.runtime_secrets, None)
}

///|
async test "changed secret references preserve journal cleanup and require a new deployment generation" {
  let checkpoint : Ref[String?] = Ref(None)
  let api = fake_api(checkpoint)
  let original = restore_supervisor(api, checkpoint)
  let assignment = future_assignment()
  ignore(
    original.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    ),
  )
  let configured = {
    ..runtime_settings(),
    runtime_secrets: Some([runtime_binding()]),
  }
  let restored = @kubernetes.RuntimeSupervisor::restore(
    configured,
    api.transport(),
    value => checkpoint.val = Some(value),
    checkpoint.val,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  try
    restored.ensure_started(
      assignment,
      "/var/lib/lunanexa/models/model",
      assignment.artifact.digest,
      5L,
      @async.now(),
    )
  catch {
    @kubernetes.OwnershipConflict => ()
    _ => fail("wrong unchanged-generation rejection")
  } noraise {
    _ => fail("secret change silently rewrote a live generation")
  }
  let replacement = { ..assignment, generation: assignment.generation + 1L, }
  let mut ready = false
  for _ in 0..<6 {
    let result = restored.ensure_started(
      replacement,
      "/var/lib/lunanexa/models/model",
      replacement.artifact.digest,
      5L,
      @async.now(),
    )
    if result.state == @contracts.Ready {
      ready = true
    }
  }
  assert_true(ready)
  assert_eq(api.objects.length(), 3)
  assert_true(restored.snapshot().contains("lunanexa-runtime-test-video-v1"))
}
