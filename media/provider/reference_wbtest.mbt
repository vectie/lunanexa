///|
fn reference_request() -> Json {
  let image = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
  let audio = b"RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x80\x3e\x00\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x00\x00"
  {
    "model": "video.h3",
    "prompt": "test reference",
    "width": 512,
    "height": 512,
    "num_frames": 25,
    "fps": 24,
    "input_reference": "data:image/png;base64," + @base64.encode(image),
    "audio_reference": (
      { "audio_url": "data:audio/wav;base64," + @base64.encode(audio) } : Json).stringify(),
  }
}

///|
test "reference profiles accept only bounded embedded PNG and PCM data" {
  let enabled = {
    ..profile(),
    image_reference_supported: Some(true),
    image_reference_required: Some(true),
  }
  let configured : Profile = @json.from_json(
    (
      {
        "model": "video.h3",
        "provider_model": "MiniMax-H3",
        "widths": [512],
        "heights": [512],
        "maximum_frames": 121,
        "maximum_fps": 24,
        "maximum_steps": 50,
        "sound_supported": true,
        "image_reference_supported": true,
        "image_reference_required": true,
      } : Json),
  )
  assert_true(configured == enabled)
  let legacy : Profile = @json.from_json(
    (
      {
        "model": "video.h3",
        "provider_model": "MiniMax-H3",
        "widths": [512],
        "heights": [512],
        "maximum_frames": 121,
        "maximum_fps": 24,
        "maximum_steps": 50,
        "sound_supported": true,
      } : Json),
  )
  assert_true(legacy == profile())
  let body = reference_request()
  ignore(VideoRequest::decode(enabled, "application/json", body.stringify()))
  let request = VideoRequest::decode(
    enabled,
    "application/json",
    body.stringify(),
  )
  assert_false(request.within_workspace_budget(64, 121))
  assert_true(request.within_workspace_budget(1048576, 121))
  for disabled in [profile(), { ..enabled, image_reference_supported: None, }] {
    try
      ignore(
        VideoRequest::decode(disabled, "application/json", body.stringify()),
      )
    catch {
      InvalidRequest | InvalidConfiguration => ()
      error => raise error
    } noraise {
      _ => fail("reference bypassed qualification")
    }
  }
  for
    (key, value) in [
      ("input_reference", "file:///etc/passwd"),
      ("input_reference", "https://example.invalid/image.png"),
      ("input_reference", "data:image/png;base64,AAAA"),
      ("audio_reference", "{\"audio_url\":\"http://169.254.169.254/\"}"),
    ] {
    guard @json.parse(body.stringify()) is Object(fields) else {
      fail("bad test body")
    }
    fields[key] = Json::string(value)
    try
      ignore(
        VideoRequest::decode(
          enabled,
          "application/json",
          Json::object(fields).stringify(),
        ),
      )
    catch {
      InvalidRequest => ()
      error => raise error
    } noraise {
      _ => fail("unsafe reference accepted")
    }
  }
  try
    ignore(
      VideoRequest::decode(enabled, "application/x-www-form-urlencoded", form()),
    )
  catch {
    InvalidRequest => ()
    error => raise error
  } noraise {
    _ => fail("required reference missing")
  }
}

///|
async test "qualified reference is sent as binary multipart with the provider model" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let observed = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever(allow_failure=true, (request, body, connection) => {
        let payload = @io.Reader::read_all(body).binary()
        assert_true(
          request.headers
          .get("content-type")
          .unwrap()
          .has_prefix("multipart/form-data; boundary="),
        )
        assert_true(payload.find(b"filename=\"reference.png\"") is Some(_))
        assert_true(payload.find(b"\x89PNG\r\n\x1a\n") is Some(_))
        assert_true(payload.find(b"MiniMax-H3") is Some(_))
        assert_false(payload.find(b"data:image/png;base64") is Some(_))
        observed[0] = true
        connection.send_response(200, "OK", extra_headers={
          "content-type": "application/json",
        })
        connection.write_string(
          "{\"id\":\"job-1\",\"status\":\"queued\",\"model\":\"MiniMax-H3\"}",
        )
        connection.end_response()
      })
    })
    let approved = { ..profile(), image_reference_supported: Some(true), }
    let provider = Provider::new("http://\{server.addr}", approved)
    let result = provider.submit(
      VideoRequest::decode(
        approved,
        "application/json",
        reference_request().stringify(),
      ),
    )
    assert_eq(result.state, Queued)
    assert_true(observed[0])
  }
}
