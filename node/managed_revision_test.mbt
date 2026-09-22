///|
/// A revision assignment: `modelstore://<directory>` with the manifest digest
/// as the artifact digest, exactly what the control plane adopts.
fn revision_assignment(
  directory : String,
  manifest : String,
  size_bytes : Int64,
) -> @contracts.DesiredAssignment {
  let base = materialization_assignment()
  {
    ..base,
    artifact: {
      digest: "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(manifest)))}",
      uri: "\{@contracts.model_store_scheme}\{directory}",
      size_bytes,
      signature_ref: "\{@contracts.model_store_scheme}\{directory}/\{@contracts.model_store_manifest_name}",
    },
  }
}

///|
fn revision_file(path : String, content : String) -> (String, String, Int64) {
  (path, content, @utf8.encode(content).length().to_int64())
}

///|
fn revision_manifest(files : Array[(String, String, Int64)]) -> String {
  let entries : Array[Json] = []
  for file in files {
    entries.push(
      Json::object({
        "path": Json::string(file.0),
        "revision": Json::string("abc123"),
        "sha256": Json::string(
          @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(file.1))),
        ),
        "size": Json::string(file.2.to_string()),
        "lfs": Json::boolean(false),
      }),
    )
  }
  Json::object({
    "schema_version": Json::string(@contracts.source_manifest_schema_version),
    "source": Json::string("modelscope"),
    "model_id": Json::string("stepfun-ai/Step-3.5-Flash"),
    "requested_revision": Json::string("master"),
    "observed_revision": Json::string("abc123"),
    "generated_unix_ms": Json::string("1000"),
    "files": Json::array(entries),
  }).stringify(indent=2)
}

///|
enum RevisionVerifier {
  Unused
}

///|
pub impl @node.ArtifactSignatureVerifier for RevisionVerifier with fn verify(
  _self,
  _artifact_path,
  _signature_path,
  _digest,
) {
  raise Failure::Failure("a managed revision carries no detached signature")
}

///|
async test "a managed revision is fetched file by file and refuses a drifted tree" {
  let files = [
    revision_file("config.json", "{\"model\":\"stepfun\"}"),
    revision_file("weights/model.safetensors", "weights-bytes"),
  ]
  let manifest = revision_manifest(files)
  let mut total = 0L
  for file in files {
    total += file.2
  }
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let fetched : Array[String] = []
  let corrupt = Ref(false)
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever() <| ((request, _, connection) => {
        fetched.push(request.path)
        let key = request.path
        let manifest_key = "/stepfun/\{@contracts.model_store_manifest_name}"
        if key == manifest_key {
          connection.send_response(200, "OK")
          connection.write_string(
            if corrupt.val {
              "\{manifest} "
            } else {
              manifest
            },
          )
        } else {
          match files.iter().find_first(file => key == "/stepfun/\{file.0}") {
            Some(file) => {
              connection.send_response(200, "OK")
              connection.write_string(
                if corrupt.val && file.0 == "weights/model.safetensors" {
                  "corrupted-weights"
                } else {
                  file.1
                },
              )
            }
            None => connection.send_response(404, "Not Found")
          }
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-revision-")
    let materializer = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1048576L,
      allow_http_loopback=true,
    )
    let assignment = revision_assignment("stepfun", manifest, total)
    let artifact = materializer.materialize(assignment, Unused)
    assert_eq(materializer.verified_cache_digests(), [
      assignment.artifact.digest,
    ])
    assert_eq(artifact.size_bytes(), total)
    assert_true(artifact.host_path().has_suffix(".revision"))
    assert_eq(
      @fs.read_file("\{artifact.host_path()}/config.json").text(),
      "{\"model\":\"stepfun\"}",
    )
    assert_eq(
      @fs.read_file("\{artifact.host_path()}/weights/model.safetensors").text(),
      "weights-bytes",
    )
    let downloads = fetched.length()
    // Reuse must not re-fetch a verified revision.
    let reused = materializer.materialize(assignment, Unused)
    assert_eq(reused.host_path(), artifact.host_path())
    assert_eq(fetched.length(), downloads)
    let restarted = @node.ArtifactMaterializer::open(
      directory,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1048576L,
      allow_http_loopback=true,
    )
    assert_eq(restarted.verified_cache_digests(), [assignment.artifact.digest])
    @fs.write_file(
      "\{artifact.host_path()}/config.json",
      "bad",
      create_mode=CreateOrTruncate,
    )
    assert_eq(restarted.verified_cache_digests(), [])

    // A tree whose bytes no longer reproduce the signed manifest is refused,
    // and the digest is taken from the manifest the controller pinned, so a
    // re-written manifest cannot be smuggled in either.
    let second = @fs.tmpdir(prefix="lunanexa-revision-drift-")
    let strict = @node.ArtifactMaterializer::open(
      second,
      "http://\{server.addr}",
      "artifact-token",
      maximum_artifact_size_bytes=1048576L,
      allow_http_loopback=true,
    )
    corrupt.val = true
    let drifted = try {
      ignore(strict.materialize(assignment, Unused))
      false
    } catch {
      @node.ArtifactMaterializationError::ArtifactDigestMismatch => true
      _ => false
    } noraise {
      value => value
    }
    assert_true(drifted)
    corrupt.val = false
    // A revision that claims a total the assignment did not pin is refused.
    let mismatched = revision_assignment("stepfun", manifest, total + 1L)
    let rejected = try {
      ignore(strict.materialize(mismatched, Unused))
      false
    } catch {
      @node.ArtifactMaterializationError::ArtifactSizeMismatch => true
      _ => false
    } noraise {
      value => value
    }
    assert_true(rejected)
    @fs.rmdir(directory, recursive=true)
    @fs.rmdir(second, recursive=true)
    server.close()
  }
}
