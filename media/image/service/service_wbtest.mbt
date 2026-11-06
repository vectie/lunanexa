///|
async test "lost Comfy acceptance reconciles without a second POST and survives restart" {
  let runtime = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer runtime.close()
  let app = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer app.close()
  let root = @fs.tmpdir(prefix="image-adapter-")
  defer @fs.rmdir(root, recursive=true)
  let id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let key = "fixture-key-for-private-image-adapter-only"
  let origin = "http://\{runtime.addr}"
  let artifact = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let evidence = (
    {
      "approved": true,
      "node_id": "fixture-node",
      "runtime_origin": origin,
      "artifact_digest": artifact,
      "workflow": "z-image-turbo-v1",
    } : Json).stringify()
  @fs.write_file(root + "/evidence.json", evidence, create_mode=CreateNew)
  @fs.write_file(root + "/key", key, create_mode=CreateNew, permission=0o600)
  let config : Config = {
    origin,
    model: "fixture-image-model",
    node_id: "fixture-node",
    artifact_digest: artifact,
    profile: {
      diffusion: "z_image_turbo_bf16.safetensors",
      text_encoder: "qwen_3_4b.safetensors",
      vae: "ae.safetensors",
    },
    state_dir: root + "/jobs",
    bearer_file: root + "/key",
    qualification_file: root + "/evidence.json",
    qualification_sha256: digest(@utf8.encode(evidence)),
    maximum_requests: 1,
  }
  let service = Service::new(config)
  let posts = Ref(0)
  let png = @base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aH2QAAAAASUVORK5CYII=",
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      runtime.run_forever((request, body, conn) => {
        if request.path == "/prompt" {
          posts.val += 1
          assert_true(
            @json.parse(@utf8.decode(bounded(body, 16384)))
            is { "client_id": String(actual), .. } &&
            actual == id,
          )
          // The runtime accepted the graph, but its POST response was lost.
          return reply(conn, 503, { "error": "lost_response" })
        }
        if request.path == "/queue" {
          return reply(conn, 200, { "queue_running": [], "queue_pending": [] })
        }
        if request.path.has_prefix("/history") {
          let history : Map[String, Json] = Map([])
          history.set("fixture-upstream", {
            "prompt": [
              0,
              "fixture-upstream",
              {},
              { "lunanexa_request_id": id },
              ["10"],
            ],
            "status": { "completed": true, "status_str": "success" },
            "outputs": {
              "10": {
                "images": [
                  {
                    "filename": id + "_00001_.png",
                    "subfolder": "",
                    "type": "output",
                  },
                ],
              },
            },
          })
          return reply(conn, 200, Json::object(history))
        }
        if request.path.has_prefix("/view?") {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "image/png",
          })
          conn.write(png)
          conn.end_response()
          return
        }
        reply(conn, 404, {})
      })
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      app.run_forever((request, body, conn) => {
        service.handle(request, body, conn)
      })
    })
    let url = "http://\{app.addr}/v1/images/generations"
    let input : Json = {
      "model": "fixture-image-model",
      "prompt": "a small forest in a coffee cup",
      "n": 1,
      "size": "1024x1024",
      "response_format": "b64_json",
    }
    let headers : @http.Headers = {
      "authorization": "Bearer " + key,
      "content-type": "application/json",
      "idempotency-key": id,
    }
    assert_eq(@http.post(url, input.stringify()).0.code, 401)
    assert_eq(@http.post(url, input.stringify(), headers~).0.code, 503)
    assert_eq(posts.val, 1)
    let (recovered, body) = @http.post(url, input.stringify(), headers~)
    assert_eq(recovered.code, 200)
    assert_true(
      @json.parse(body.text())
      is { "id": String(actual), "data": [{ "b64_json": String(_), .. }], .. } &&
      actual == id,
    )
    assert_eq(posts.val, 1)
    let restarted = Service::new(config)
    restarted.reconcile(id)
    assert_true(restarted.read()[0].state is Completed)
    let conflict : Json = {
      "model": "fixture-image-model",
      "prompt": "changed",
      "n": 1,
      "size": "1024x1024",
      "response_format": "b64_json",
    }
    assert_eq(@http.post(url, conflict.stringify(), headers~).0.code, 409)
    headers["idempotency-key"] = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    assert_eq(@http.post(url, input.stringify(), headers~).0.code, 429)
    assert_eq(posts.val, 1)
    assert_true(
      try {
        ignore(Service::new({ ..config, node_id: "unqualified-other-node", }))
        false
      } catch {
        _ => true
      },
    )
  })
}
