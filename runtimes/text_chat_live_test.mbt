///|
/// Explicit live boundary gate. The default unit suite never contacts a model.
/// This verifies the runtime adapter, not customer authorization or public ingress.
async test "opt-in live text Chat adapter JSON SSE cancellation and reuse" {
  guard @env.get_env_var("LUNANEXA_LIVE_TEXT_ENDPOINT") is Some(endpoint) else {
    return
  }
  guard @env.get_env_var("LUNANEXA_LIVE_TEXT_CREDENTIAL_FILE") is Some(path) else {
    fail("live credential file is required")
  }
  let credential = @fs.read_file(path).text().trim().to_owned()
  let revision = @env.get_env_var("LUNANEXA_LIVE_TEXT_REVISION").unwrap()
  let artifact = @env.get_env_var("LUNANEXA_LIVE_TEXT_ARTIFACT").unwrap()
  let runtime = @runtimes.OpenAiTextRuntime::native(
      endpoint,
      credential,
      "live-native-adapter",
      revision,
      artifact,
      allow_http_loopback=true,
    )
    .with_text_chat_completions()
    .with_served_model_name("glm-5.3")
  let base = remote_request()
  let request = {
    ..base,
    resource_ceiling: { ..base.resource_ceiling, max_output_units: 64, },
    payload: {
      "messages": [
        { "role": "system", "content": "Answer only the requested result." },
        { "role": "user", "content": "What is 17 times 19?" },
      ],
      "temperature": 0,
    },
  }
  let answer = runtime.invoke(request) catch {
    @runtimes.RemoteRuntimeError::UpstreamRejected(status~, body~) =>
      fail("live upstream status=\{status} body=\{body}")
    error => raise error
  }
  assert_true(answer.output.stringify().contains("323"))
  assert_true(answer.input_units > 0 && answer.output_units > 0)
  assert_true(answer.output_units <= 64)
  println("LIVE JSON answer=323 usage present and output budget respected")
  let chunks = []
  let streamed = runtime.invoke_stream(
    { ..request, idempotency_key: "live-stream", },
    chunk => chunks.push(chunk),
  )
  assert_true(streamed.output.stringify().contains("323"))
  assert_true(chunks.length() > 0)
  assert_true(streamed.input_units > 0 && streamed.output_units > 0)
  println("LIVE SSE answer=323 chunks and final usage present")
  // Raise from the consumer after a real token: defer must close the upstream.
  let mut observed = false
  try
    runtime.invoke_stream(
      {
        ..request,
        idempotency_key: "live-disconnect",
        resource_ceiling: { ..request.resource_ceiling, max_output_units: 512, },
        payload: {
          "messages": [
            {
              "role": "user",
              "content": "Count from 1 to 100, one number per line.",
            },
          ],
          "temperature": 0,
        },
      },
      _ => {
        observed = true
        fail("intentional live consumer disconnect")
      },
    )
  catch {
    _ => assert_true(observed)
  } noraise {
    _ => fail("consumer disconnect was not propagated")
  }
  let reused = runtime.invoke({ ..request, idempotency_key: "live-reuse", })
  assert_true(reused.output.stringify().contains("323"))
  println("LIVE consumer disconnect propagated; next JSON request completed")
}
