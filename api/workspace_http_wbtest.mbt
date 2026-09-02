///|
test "asserted workspace subject is refused without transport proof" {
  let headers = { "X-LunaNexa-Subject": "subject-workspace" }
  assert_eq(trusted_workspace_subject(headers, false), None)
  assert_eq(trusted_workspace_subject(headers, true), Some("subject-workspace"))
}

///|
test "verified ingress identity remains available to non-loopback dispatch" {
  let raw_dn = "CN=developer,O=LunaNexa"
  let expected = "mtls:sha256:\{digest_hex(raw_dn)}"
  assert_eq(
    trusted_workspace_subject(
      {
        "ssl-client-verify": "SUCCESS",
        "ssl-client-subject-dn": raw_dn,
        "X-LunaNexa-Subject": "forged-fallback",
      },
      false,
    ),
    Some(expected),
  )
  assert_false(loopback_client(@socket.Addr::parse("192.0.2.10:443")))
  assert_true(loopback_client(@socket.Addr::parse("127.0.0.1:443")))
}

///|
test "OpenAI bridge declares the actual canonical input size" {
  let budgets = @settings.default_global_admin_settings().request_budgets
  let value : OpenAiChatRequest = {
    model: "smoke-model",
    messages: [{ "role": "user", "content": "Reply with OK" }],
    stream: Some(false),
    max_tokens: Some(16),
    tools: None,
    tool_choice: None,
    parallel_tool_calls: None,
    temperature: None,
    top_p: None,
  }
  let (workload, _) = openai_workload(
    value,
    {
      key_id: "smoke-key",
      tenant_ref: "default-tenant",
      subject_ref: "static-inference-subject",
    },
    {},
    false,
    1788015700000L,
    budgets,
  )
  let actual_input_units = @utf8.encode(workload.payload.stringify()).length()
  assert_eq(workload.resource_ceiling.max_input_units, actual_input_units)
  assert_true(
    workload.resource_ceiling.max_input_units < budgets.openai_max_input_units,
  )
  assert_eq(workload.resource_ceiling.max_output_units, 16)
}

///|
test "OpenAI bridge converts Responses function calls without leaking the envelope" {
  let output : Json = {
    "id": "resp-1",
    "output": [
      {
        "type": "message",
        "content": [{ "type": "output_text", "text": "Checking. " }],
      },
      {
        "type": "function_call",
        "id": "item-1",
        "call_id": "call-1",
        "name": "read_file",
        "arguments": "{\"path\":\"README.md\"}",
      },
    ],
  }
  let (content, tool_calls) = openai_chat_message_from_runtime(Some(output))
  assert_eq(content, "Checking. ")
  assert_eq(tool_calls.length(), 1)
  guard tool_calls[0] is Object(call) else { fail("expected tool call") }
  assert_eq(call["id"], Json::string("call-1"))
  guard call["function"] is Object(function) else { fail("expected function") }
  assert_eq(function["name"], Json::string("read_file"))
  assert_eq(function["arguments"], Json::string("{\"path\":\"README.md\"}"))
  assert_false(content.contains("resp-1"))
}
