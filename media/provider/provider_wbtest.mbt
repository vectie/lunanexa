///|
fn profile() -> Profile {
  {
    model: "video.h3",
    provider_model: "MiniMax-H3",
    widths: [512],
    heights: [512],
    maximum_frames: 121,
    maximum_fps: 24,
    maximum_steps: 50,
    sound_supported: true,
  }
}

///|
fn form() -> String {
  "model=video.h3&prompt=%E5%B0%8F%E8%88%B9+%F0%9F%9A%A2&width=512&height=512&num_frames=25&fps=24&generate_sound=true"
}

///|
test "video input is canonical across form and JSON without losing Unicode" {
  let a = VideoRequest::decode(
    profile(),
    "application/x-www-form-urlencoded",
    form(),
  )
  let b = VideoRequest::decode(
    profile(),
    "application/json",
    (
      {
        "model": "video.h3",
        "prompt": "小船 🚢",
        "width": 512,
        "height": 512,
        "num_frames": 25,
        "fps": 24,
        "generate_sound": true,
      } : Json).stringify(),
  )
  assert_eq(a.digest(), b.digest())
  assert_eq(a.fields["prompt"], "小船 🚢")
  assert_eq(a.form(), b.form())
}

///|
test "video profile rejects references paths overrides duplicates and excessive budgets" {
  assert_true(
    try {
      ignore(
        VideoRequest::decode(
          profile(),
          "application/json",
          "{\"model\":\"other\",\"\\u006dodel\":\"video.h3\",\"prompt\":\"x\",\"width\":512,\"height\":512,\"num_frames\":25,\"fps\":24}",
        ),
      )
      false
    } catch {
      InvalidRequest => true
      _ => false
    },
  )
  for
    suffix in [
      "&image_reference=http%3A%2F%2F169.254.169.254", "&frame_interpolation_model_path=%2Fetc%2Fpasswd",
      "&extra_params=%7B%7D", "&model=other", "&%6dodel=video.h3", "&prompt=%GG",
      "&seed=-1", "&num_inference_steps=999",
    ] {
    let rejected = try {
      ignore(
        VideoRequest::decode(
          profile(),
          "application/x-www-form-urlencoded",
          form() + suffix,
        ),
      )
      false
    } catch {
      InvalidRequest => true
      _ => false
    }
    assert_true(rejected)
  }
  for field in ["width=8192", "height=8192", "num_frames=122", "fps=25"] {
    let parts = form()
      .split("&")
      .filter(part => !part.has_prefix(field.split("=").next().unwrap() + "="))
      .to_array()
    let rejected = try {
      ignore(
        VideoRequest::decode(
          profile(),
          "application/x-www-form-urlencoded",
          parts.join("&") + "&" + field,
        ),
      )
      false
    } catch {
      InvalidRequest => true
      _ => false
    }
    assert_true(rejected)
  }
  let no_sound = { ..profile(), sound_supported: false, }
  assert_true(
    try {
      ignore(
        VideoRequest::decode(
          no_sound,
          "application/x-www-form-urlencoded",
          form(),
        ),
      )
      false
    } catch {
      InvalidRequest => true
      _ => false
    },
  )
}

///|
test "provider response normalization drops prompts paths and diagnostic fields" {
  let value : Json = {
    "id": "video_gen_fixture",
    "status": "completed",
    "model": "video.h3",
    "progress": 100,
    "prompt": "private",
    "file_name": "/srv/private.mp4",
    "peak_memory_mb": 100,
    "inference_time_s": 0.001,
  }
  assert_eq(observation(value, Some("video_gen_fixture"), "video.h3"), {
    id: "video_gen_fixture",
    state: Completed,
    progress: Some(100),
  })
  assert_true(
    try {
      ignore(observation(value, Some("someone-else"), "video.h3"))
      false
    } catch {
      InvalidResponse => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(observation(value, None, "other"))
      false
    } catch {
      InvalidResponse => true
      _ => false
    },
  )
  for status in ["unknown", "../completed"] {
    assert_true(
      try {
        ignore(
          observation(
            { "id": "video_gen_fixture", "status": status },
            None,
            "video.h3",
          ),
        )
        false
      } catch {
        InvalidResponse => true
        _ => false
      },
    )
  }
}

///|
test "provider configuration rejects path credentials query and fragments" {
  for
    origin in [
      "file:///etc", "https://user:secret@host", "http://host/a", "http://host?token=x",
      "http://host#fragment",
    ] {
    assert_true(
      try {
        ignore(Provider::new(origin, profile()))
        false
      } catch {
        InvalidConfiguration => true
        _ => false
      },
    )
  }
  ignore(Provider::new("http://127.0.0.1:5878", profile()))
}

///|
async test "native video transport handles failed status cancellation acknowledgement and bounded content" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let provider = Provider::new(
    "http://\{server.addr}",
    profile(),
    bearer="fixture-only-provider-token",
  )
  let calls : Array[String] = []
  let state = { "delete_pending": true }
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, connection) => {
        assert_eq(
          request.headers.get("authorization"),
          Some("Bearer fixture-only-provider-token"),
        )
        calls.push(request.path)
        if request.meth == Post {
          let payload = @utf8.decode(limited(body, 65536))
          assert_true(payload.contains("generate_sound=true"))
          assert_true(payload.contains("model=MiniMax-H3"))
          assert_false(payload.contains("fixture-only-provider-token"))
          connection.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          connection.write_string(
            "{\"id\":\"video_gen_fixture\",\"status\":\"queued\"}",
          )
        } else if request.meth == Delete {
          connection.send_response(
            if state["delete_pending"] {
              409
            } else {
              200
            },
            "Delete",
            extra_headers={ "content-type": "application/json" },
          )
          connection.write_string(
            if state["delete_pending"] {
              "{\"detail\":\"Cancellation in progress\"}"
            } else {
              "{\"id\":\"video_gen_fixture\",\"deleted\":true}"
            },
          )
        } else if request.path.has_suffix("/content") {
          connection.send_response(200, "OK", extra_headers={
            "content-type": "video/mp4",
          })
          connection.write_string("fixture-video-not-a-real-generation")
        } else {
          connection.send_response(500, "Failed", extra_headers={
            "content-type": "application/json",
          })
          connection.write_string(
            "{\"id\":\"video_gen_fixture\",\"status\":\"failed\",\"error\":{\"message\":\"private worker trace\"}}",
          )
        }
        connection.end_response()
      })
    })
    let job = provider.submit(
      VideoRequest::decode(
        profile(),
        "application/x-www-form-urlencoded",
        form(),
      ),
    )
    assert_eq(job.state, Queued)
    assert_eq(provider.poll(job.id).state, Failed)
    assert_false(provider.delete(job.id))
    state["delete_pending"] = false
    assert_true(provider.delete(job.id))
    let output = Buffer()
    assert_eq(
      provider.content(job.id, 100L, bytes => output.write_bytes(bytes)),
      b"fixture-video-not-a-real-generation".length().to_int64(),
    )
    assert_eq(output.to_bytes(), b"fixture-video-not-a-real-generation")
    assert_true(
      try {
        ignore(provider.content(job.id, 1L, _ => ()))
        false
      } catch {
        InvalidResponse => true
        _ => false
      },
    )
    assert_eq(calls.length(), 6)
  }
}
