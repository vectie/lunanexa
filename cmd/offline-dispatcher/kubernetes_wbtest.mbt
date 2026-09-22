///|
async test "artifact Jobs contain only per-request work fonts and render authority" {
  let image = "registry.example/worker@sha256:" + "a".repeat(64)
  let manifest = artifact_job_manifest(
    "job-test",
    "test-namespace",
    image,
    "artifact/request-hash",
    "work-pvc",
    "font-pvc",
    "render-secret",
    "sha256:" + "b".repeat(64),
  )
  let json = manifest.stringify()
  assert_true(
    manifest
    is {
      "spec": {
        "template": {
          "spec": {
            "automountServiceAccountToken": False,
            "enableServiceLinks": False,
            ..
          },
          ..
        },
        ..
      },
      ..
    },
  )
  assert_true(json.contains("artifact/request-hash"))
  assert_false(json.contains("LUNANEXA_CONTROLLER_ENDPOINT"))
  assert_false(json.contains("LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN"))
  assert_false(json.contains("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN"))
  assert_false(json.contains("hostPath"))
  assert_false(json.contains("privileged"))
  assert_true(json.contains("render-secret"))
  assert_true(json.contains("readOnlyRootFilesystem"))
  if @env.get_env_var("LUNANEXA_KUBERNETES_MANIFEST_PROBE") is Some(path) {
    let isolated = artifact_job_manifest(
      "artifact-admission-probe",
      "offline-transfer-verify-20260922",
      image,
      "artifact/request-hash",
      "test-work-pvc",
      "test-font-pvc",
      "test-render-secret",
      "sha256:" + "b".repeat(64),
    )
    write_atomic(path, @utf8.encode(isolated.stringify(indent=2)))
  }
  if @env.get_env_var("LUNANEXA_PRODUCTION_ADMISSION_PROBE_PATH") is Some(path) &&
    @env.get_env_var("LUNANEXA_PRODUCTION_ADMISSION_PROBE_IMAGE") is Some(image) {
    assert_true(pinned_image(image))
    let actual = artifact_job_manifest(
      "offline-artifact-" + "a".repeat(40),
      "lunanexa",
      image,
      "artifact/" + "a".repeat(64),
      "lunanexa-offline-dispatcher-state",
      "lunanexa-offline-approved-fonts",
      "lunanexa-offline-render-evidence",
      "sha256:" + "b".repeat(64),
    )
    write_atomic(path, @utf8.encode(actual.stringify(indent=2)))
  }
}

///|
test "artifact image rejects mutable tags and malformed digests" {
  assert_true(pinned_image("registry.example/worker@sha256:" + "a".repeat(64)))
  for
    image in [
      "worker:latest",
      "worker@sha256:abc",
      "@sha256:" + "a".repeat(64),
      "worker@sha256:" + "z".repeat(64),
    ] {
    assert_false(pinned_image(image))
  }
}
