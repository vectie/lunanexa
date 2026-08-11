///|
struct AcceptSignatureVerifier {
  mut calls : Int
}

///|
pub impl @node.ArtifactSignatureVerifier for AcceptSignatureVerifier with fn verify(
  self,
  artifact_path,
  signature_path,
  digest,
) {
  self.calls += 1
  assert_true(@fs.exists(artifact_path))
  assert_true(@fs.exists(signature_path))
  assert_eq(
    digest, "sha256:6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c",
  )
}

///|
enum RejectSignatureVerifier {
  Reject
}

///|
pub impl @node.ArtifactSignatureVerifier for RejectSignatureVerifier with fn verify(
  _self,
  _artifact_path,
  _signature_path,
  _digest,
) {
  raise Failure::Failure("test signature rejection")
}

///|
fn materialization_assignment() -> @contracts.DesiredAssignment {
  {
    assignment_id: "assignment-materialize-1",
    deployment_id: "deployment-materialize-1",
    node_id: "node-a",
    artifact: {
      digest: "sha256:6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c",
      uri: "s3://models/model.bin",
      size_bytes: 14L,
      signature_ref: "s3://models/model.bin.sig",
    },
    runtime: {
      name: "registry.invalid/text-runtime",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [TextGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
    resources: {
      accelerator_count: 1,
      accelerator_memory_mib: 8000,
      cpu_millis: 2000,
      memory_mib: 16000,
    },
    devices: ["gpu-0"],
    network: {
      allow_controller: true,
      allow_artifact_store: true,
      allowed_egress: [],
    },
    health: {
      readiness_path: "/health",
      interval_ms: 1000,
      failure_threshold: 3,
      termination_grace_ms: 5000,
    },
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    generation: 1L,
    lease_expires_unix_ms: 1900000000000L,
    controller_epoch: 1L,
    signature: "signed",
  }
}

///|
async test "assigned node materializes verifies reuses and prunes its model" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let request_count = Ref(0)
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        request_count.val += 1
        match request.path {
          "/models/model.bin" => {
            connection.send_response(200, "OK")
            connection.write_string("artifact-bytes")
          }
          "/models/model.bin.sig" => {
            connection.send_response(200, "OK")
            connection.write_string("detached-signature")
          }
          _ => connection.send_response(404, "Not Found")
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-materializer-")
    let verifier = { calls: 0 }
    let materializer = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1024L,
      allow_http_loopback=true,
    )
    let artifact = materializer.materialize(
      materialization_assignment(),
      verifier,
    )
    assert_eq(artifact.size_bytes(), 14L)
    assert_true(@fs.exists(artifact.host_path()))
    assert_eq(@fs.read_file(artifact.host_path()).text(), "artifact-bytes")
    assert_eq(request_count.val, 2)
    assert_eq(verifier.calls, 1)
    ignore(materializer.materialize(materialization_assignment(), verifier))
    assert_eq(request_count.val, 2)
    assert_eq(verifier.calls, 1)
    let restarted = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1024L,
      allow_http_loopback=true,
    )
    ignore(restarted.materialize(materialization_assignment(), verifier))
    assert_eq(request_count.val, 2)
    assert_eq(verifier.calls, 2)
    restarted.prune_unassigned([])
    assert_false(@fs.exists(artifact.host_path()))
    @fs.rmdir(directory, recursive=true)
    server.close()
  }
}

///|
async test "digest mismatch quarantines the selected node download" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        connection.send_response(200, "OK")
        if request.path.has_suffix(".sig") {
          connection.write_string("detached-signature")
        } else {
          connection.write_string("corrupt-bytes!")
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-corrupt-model-")
    let materializer = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1024L,
      allow_http_loopback=true,
    )
    try
      materializer.materialize(materialization_assignment(), { calls: 0 })
    catch {
      @node.ArtifactMaterializationError::ArtifactDigestMismatch => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("a corrupt model was materialized")
    }
    let entries = @fs.readdir("\{directory}/sha256")
    assert_true(entries.any(entry => entry.has_suffix(".quarantine")))
    assert_false(entries.any(entry => entry.has_suffix(".ready")))
    @fs.rmdir(directory, recursive=true)
    server.close()
  }
}

///|
async test "selected node resumes an incomplete model transfer" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let saw_range = Ref(false)
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        match request.path {
          "/models/model.bin" => {
            saw_range.val = request.headers.get("Range") == Some("bytes=9-") ||
              request.headers.get("range") == Some("bytes=9-")
            connection.send_response(206, "Partial Content")
            connection.write_string("bytes")
          }
          "/models/model.bin.sig" => {
            connection.send_response(200, "OK")
            connection.write_string("detached-signature")
          }
          _ => connection.send_response(404, "Not Found")
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-resume-model-")
    let materializer = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1024L,
      allow_http_loopback=true,
    )
    let partial = "\{directory}/sha256/6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c.model.partial"
    @fs.write_file(
      partial,
      "artifact-",
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    let assignment = materialization_assignment()
    let artifact = materializer.materialize(
      {
        ..assignment,
        artifact: { ..assignment.artifact, signature_ref: "cosign:model" },
      },
      { calls: 0 },
    )
    assert_true(saw_range.val)
    assert_eq(@fs.read_file(artifact.host_path()).text(), "artifact-bytes")
    @fs.rmdir(directory, recursive=true)
    server.close()
  }
}

///|
async test "invalid detached signature never publishes a ready model" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        connection.send_response(200, "OK")
        if request.path.has_suffix(".sig") {
          connection.write_string("invalid-signature")
        } else {
          connection.write_string("artifact-bytes")
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-invalid-signature-")
    let materializer = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1024L,
      allow_http_loopback=true,
    )
    try materializer.materialize(materialization_assignment(), Reject) catch {
      @node.ArtifactMaterializationError::ArtifactSignatureInvalid => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("an invalid signature was accepted")
    }
    let entries = @fs.readdir("\{directory}/sha256")
    assert_false(entries.any(entry => entry.has_suffix(".ready")))
    assert_false(entries.any(entry => entry.has_suffix(".model")))
    @fs.rmdir(directory, recursive=true)
    server.close()
  }
}

///|
async test "declared artifact size is enforced before transfer" {
  let directory = @fs.tmpdir(prefix="lunanexa-model-size-")
  let materializer = @node.ArtifactMaterializer::open(
    directory,
    "http://127.0.0.1:1",
    "artifact-token",
    maximum_artifact_size_bytes=1024L,
    allow_http_loopback=true,
  )
  let assignment = materialization_assignment()
  try
    materializer.materialize(
      { ..assignment, artifact: { ..assignment.artifact, size_bytes: 2048L } },
      { calls: 0 },
    )
  catch {
    @node.ArtifactMaterializationError::ArtifactTooLarge => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("an oversized model was fetched")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "assignment materializes on only the selected node cache" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let request_count = Ref(0)
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        request_count.val += 1
        connection.send_response(200, "OK")
        if request.path.has_suffix(".sig") {
          connection.write_string("detached-signature")
        } else {
          connection.write_string("artifact-bytes")
        }
        connection.end_response()
      })
    }
    let roots = [
      @fs.tmpdir(prefix="lunanexa-dgx-1-cache-"),
      @fs.tmpdir(prefix="lunanexa-dgx-2-cache-"),
      @fs.tmpdir(prefix="lunanexa-dgx-3-cache-"),
      @fs.tmpdir(prefix="lunanexa-dgx-4-cache-"),
    ]
    let materializers = [
      for root in roots => {
        @node.ArtifactMaterializer::open(
          root,
          "http://\{server.addr}",
          "assignment-scoped-token",
          maximum_artifact_size_bytes=1024L,
          allow_http_loopback=true,
        )
      }
    ]
    let selected = 2
    let artifact = materializers[selected].materialize(
      { ..materialization_assignment(), node_id: "node-c" },
      { calls: 0 },
    )
    assert_true(@fs.exists(artifact.host_path()))
    assert_eq(request_count.val, 2)
    for index, root in roots {
      let entries = @fs.readdir("\{root}/sha256")
      if index == selected {
        assert_true(entries.any(value => value.has_suffix(".model")))
        assert_true(entries.any(value => value.has_suffix(".ready")))
      } else {
        assert_eq(entries, [])
      }
      @fs.rmdir(root, recursive=true)
    }
    server.close()
  }
}

///|
async test "cache pressure pruning preserves every file for an assigned digest" {
  let directory = @fs.tmpdir(prefix="lunanexa-cache-pressure-")
  let materializer = @node.ArtifactMaterializer::open(
    directory,
    "http://127.0.0.1:1",
    "artifact-token",
    maximum_artifact_size_bytes=1024L,
    allow_http_loopback=true,
  )
  let assigned = "6521df166eb07efaf36eba5b6bedefd9d6a252e9c80bab1c99653700ec71473c"
  let stale = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  for suffix in ["model", "sig", "ready", "model.partial"] {
    @fs.write_file(
      "\{directory}/sha256/\{assigned}.\{suffix}",
      "assigned",
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    @fs.write_file(
      "\{directory}/sha256/\{stale}.\{suffix}",
      "stale-pressure-data",
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
  }
  materializer.prune_unassigned(["sha256:\{assigned}"])
  let remaining = @fs.readdir("\{directory}/sha256")
  assert_true(remaining.length() == 4)
  assert_true(remaining.all(value => value.has_prefix("\{assigned}.")))
  assert_false(remaining.any(value => value.has_prefix("\{stale}.")))
  @fs.rmdir(directory, recursive=true)
}
