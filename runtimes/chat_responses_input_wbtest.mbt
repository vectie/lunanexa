///|
test "chat text parts become Responses input text without mutating the transcript" {
  let payload : Json = {
    "messages": [
      { "role": "system", "content": "Keep exact instructions." },
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "Hello\n" },
          { "type": "text", "text": "你好" },
        ],
      },
    ],
  }
  let original = payload.stringify()
  json_inspect(responses_input(payload), content=[
    { "role": "system", "content": "Keep exact instructions." },
    {
      "role": "user",
      "content": [
        { "type": "input_text", "text": "Hello\n" },
        { "type": "input_text", "text": "你好" },
      ],
    },
  ])
  assert_eq(payload.stringify(), original)
  let input : Json = [
    { "type": "function_call_output", "call_id": "call-a", "output": "done" },
  ]
  assert_eq(responses_input({ "input": input }), input)
}

///|
test "chat tool history preserves call identifiers arguments output and order" {
  let payload : Json = {
    "messages": [
      { "role": "user", "content": "Check status." },
      {
        "role": "assistant",
        "content": "Checking.",
        "tool_calls": [
          {
            "id": "call-a",
            "type": "function",
            "function": {
              "name": "lookup_status",
              "arguments": "{\"service\":\"glm\"}",
            },
          },
          {
            "id": "call-b",
            "type": "function",
            "function": {
              "name": "lookup_status",
              "arguments": "{\"service\":\"other\"}",
            },
          },
        ],
      },
      {
        "role": "tool",
        "tool_call_id": "call-a",
        "content": "{\"ready\":true}",
      },
      {
        "role": "tool",
        "tool_call_id": "call-b",
        "content": [{ "type": "text", "text": "ready" }],
      },
      {
        "role": "assistant",
        "content": Json::null(),
        "tool_calls": [
          {
            "id": "call-c",
            "type": "function",
            "function": { "name": "finish", "arguments": "{}" },
          },
        ],
      },
    ],
  }
  json_inspect(responses_input(payload), content=[
    { "role": "user", "content": "Check status." },
    { "role": "assistant", "content": "Checking." },
    {
      "type": "function_call",
      "call_id": "call-a",
      "name": "lookup_status",
      "arguments": "{\"service\":\"glm\"}",
    },
    {
      "type": "function_call",
      "call_id": "call-b",
      "name": "lookup_status",
      "arguments": "{\"service\":\"other\"}",
    },
    {
      "type": "function_call_output",
      "call_id": "call-a",
      "output": "{\"ready\":true}",
    },
    {
      "type": "function_call_output",
      "call_id": "call-b",
      "output": [{ "type": "input_text", "text": "ready" }],
    },
    {
      "type": "function_call",
      "call_id": "call-c",
      "name": "finish",
      "arguments": "{}",
    },
  ])
}

///|
test "chat conversion rejects unsupported content and unbound tool results" {
  for
    messages in [
      Json::object({}),
      Json::array([{ "content": "missing role" }]),
      Json::array([{ "role": "tool", "content": "missing call" }]),
      Json::array([
        {
          "role": "user",
          "content": [
            {
              "type": "image_url",
              "image_url": { "url": "https://example.invalid/image" },
            },
          ],
        },
      ]),
      Json::array([{ "role": "assistant", "content": Json::null() }]),
      Json::array([
        {
          "role": "assistant",
          "tool_calls": [
            {
              "type": "function",
              "function": { "name": "missing_id", "arguments": "{}" },
            },
          ],
        },
      ]),
    ] {
    try responses_messages_from_chat(messages) catch {
      UnsupportedCapability | InvalidUpstreamResponse(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid chat history was accepted")
    }
  }
}
