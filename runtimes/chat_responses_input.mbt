///|
// Chat content parts and tool transcripts are not Responses input items.
// Convert only the explicit `messages` payload; canonical `input` stays intact.
fn responses_chat_content(content : Json) -> Json raise RemoteRuntimeError {
  match content {
    String(_) => content
    Array(parts) => {
      let converted : Array[Json] = []
      for part in parts {
        guard part
          is { "type": String("text" | "input_text"), "text": String(text), .. } else {
          raise UnsupportedCapability
        }
        converted.push({ "type": "input_text", "text": text })
      }
      Json::array(converted)
    }
    _ =>
      raise InvalidUpstreamResponse("chat content must be text or text parts")
  }
}

///|
fn responses_messages_from_chat(
  messages : Json,
) -> Json raise RemoteRuntimeError {
  guard messages is Array(messages) else {
    raise InvalidUpstreamResponse("chat messages must be an array")
  }
  let converted : Array[Json] = []
  for message in messages {
    guard message is Object(fields) && fields.get("role") is Some(String(role)) else {
      raise InvalidUpstreamResponse("chat message must have a role")
    }
    if role == "tool" {
      guard fields.get("tool_call_id") is Some(String(call_id)) &&
        call_id != "" &&
        fields.get("content") is Some(content) else {
        raise InvalidUpstreamResponse(
          "tool result must identify its call and content",
        )
      }
      converted.push({
        "type": "function_call_output",
        "call_id": call_id,
        "output": responses_chat_content(content),
      })
      continue
    }
    guard ["system", "developer", "user", "assistant"].contains(role) else {
      raise UnsupportedCapability
    }
    let calls = match fields.get("tool_calls") {
      None | Some(Null) => []
      Some(Array(calls)) if role == "assistant" => calls
      _ =>
        raise InvalidUpstreamResponse(
          "tool calls must belong to an assistant message",
        )
    }
    match fields.get("content") {
      None | Some(Null) if role == "assistant" && !calls.is_empty() => ()
      Some(content) =>
        converted.push({
          "role": role,
          "content": responses_chat_content(content),
        })
      _ =>
        raise InvalidUpstreamResponse(
          "chat message must contain text or tool calls",
        )
    }
    for call in calls {
      guard call
        is {
          "id": String(call_id),
          "type": "function",
          "function": {
            "name": String(name),
            "arguments": String(arguments),
            ..
          },
          ..
        } &&
        call_id != "" &&
        name != "" else {
        raise InvalidUpstreamResponse(
          "function call must identify its call, name and arguments",
        )
      }
      converted.push({
        "type": "function_call",
        "call_id": call_id,
        "name": name,
        "arguments": arguments,
      })
    }
  }
  Json::array(converted)
}
