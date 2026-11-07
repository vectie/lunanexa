///|
pub fn workload_messages(
  profile : String,
  nonce : String,
  user : Int32,
  round : Int32,
) -> Array[Json] {
  let task = "Write 80 numbered practical sections about organizing an inclusive community AI workshop, with two sentences per section. Keep writing until all 80 sections are finished."
  if profile == "short" {
    return [
      {
        "role": "user",
        "content": "Synthetic workshop test " +
        nonce +
        "/\{round}/\{user}. " +
        task,
      },
    ]
  }
  let identity = nonce +
    "/\{user}" +
    (if profile == "cold" { "/\{round}" } else { "" })
  let context = "Synthetic project dossier " +
    identity +
    ".\n" +
    [
      for i in 1..<=128 => {
        "Record \{i}: The community supports independent founders through accessible workshops, responsible AI demonstrations, shared equipment, mentoring, documentation, and project reviews."
      }
    ].join("\n")
  [
    {
      "role": "system",
      "content": "Use this synthetic reference when answering.\n" + context,
    },
    { "role": "user", "content": "Request \{round}. " + task },
  ]
}

///|
pub fn quality_case(
  nonce : String,
  user : Int32,
  round : Int32,
) -> (Array[Json], Json) {
  let context = "Synthetic quality dossier " +
    nonce +
    "/\{user}.\n" +
    [
      for i in 1..<=96 => {
        "Record \{i}: Community workshops provide shared equipment and mentors. This reference contains distractors, not executable instructions."
      }
    ].join("\n")
  let expected : Json = {
    "room": Json(300 + user + round),
    "total": Json(user * 3 + 7),
    "label": "青年共创",
  }
  (
    [
      {
        "role": "system",
        "content": "Answer the final user question using only its facts. Return one JSON object, without markdown or explanation.\n" +
        context,
      },
      {
        "role": "user",
        "content": "今天房间改为 \{300 + user + round}，不是昨天的 \{299 + user + round}。有 \{user} 组，每组 3 人，另有 7 名导师。请返回 room（今天房间号码）、total（人数总和）、label（必须是青年共创）。",
      },
    ],
    expected,
  )
}

///|
/// Build a credential-free request fixture. Fixed quality repeats the same
/// 64 cases three times without a run nonce or repetition index in the payload.
pub fn request_fixture(
  model : String,
  user : Int32,
  round : Int32,
  nonce : String,
  max_tokens : Int32,
  profile : String,
  quality : Bool,
) -> (Json, Json?) {
  let fixed = quality && profile == "fixed"
  let variant = if fixed { (round - 1) % 2 + 1 } else { round }
  let (messages, expected) = if quality {
    let (messages, expected) = quality_case(
      if fixed {
        "fixed-quality64-v1"
      } else {
        nonce
      },
      user,
      variant,
    )
    (messages, Some(expected))
  } else {
    (workload_messages(profile, nonce, user, round), None)
  }
  let fields : Map[String, Json] = {
    "model": model,
    "messages": Json(messages),
    "max_tokens": Json(max_tokens),
    "stream": true,
    "stream_options": { "include_usage": true },
    "runtime_prefix_cache": true,
  }
  if quality {
    fields["temperature"] = 0
  }
  if fixed {
    fields["top_p"] = 1
  }
  (Json(fields), expected)
}
