///|
/// Sanitized evidence from a real streaming model request; never stores text
/// or credentials. Token counts come from usage, not SSE chunk counts.
pub(all) struct Sample {
  user : Int32
  concurrency : Int32
  round : Int32
  status : Int32
  output_tokens : Int32
  ttft_ms : Int64
  elapsed_ms : Int64
  decode_tokens_per_second : Double
  end_to_end_tokens_per_second : Double
  valid : Bool
  response_id : String
  receipt : String
  error : String
  timings : Map[String, Int64]
  cached_input_tokens : Int32?
  input_tokens : Int32?
} derive(ToJson, FromJson)

///|
pub extend Sample with ToJson::{to_json}

///|
pub extend Sample with FromJson::{from_json}

///|
fn token_count(value : Json) -> Int32 raise {
  match value {
    Number(n, ..) => n.to_int()
    String(s) => @string.parse_int(s)
    _ => fail("invalid usage")
  }
}

///|
pub fn decode_rate(tokens : Int32, first : Int64, last : Int64) -> Double {
  if tokens > 1 && first > 0L && last > first {
    (tokens - 1).to_double() * 1000.0 / (last - first).to_double()
  } else {
    0.0
  }
}

///|
// Keep diagnostics bounded to known field names; never persist answer text.
fn quality_error(answer : String, expected : Json) -> String {
  let actual = @json.parse(answer.trim().to_owned()) catch {
    _ => return "quality: invalid JSON"
  }
  if actual == expected {
    return ""
  }
  guard actual is Object(fields) && expected is Object(wanted) else {
    return "quality: expected JSON object"
  }
  let mismatches : Array[String] = []
  for name in ["room", "total", "label"] {
    if fields.get(name) != wanted.get(name) {
      mismatches.push(name)
    }
  }
  if fields.length() != wanted.length() {
    mismatches.push("field count")
  }
  "quality: mismatch " + mismatches.join(", ")
}

///|
pub async fn sample(
  origin : String,
  key : String,
  model : String,
  user~ : Int32,
  concurrency~ : Int32,
  round~ : Int32,
  nonce~ : String,
  max_tokens~ : Int32 = 512,
  profile~ : String = "short",
  quality~ : Bool = false,
) -> Sample {
  let started = @async.now()
  let mut first = 0L
  let mut last = 0L
  let mut tokens = 0
  let mut status = 0
  let mut done = false
  let mut chunks = 0
  let mut response_id = ""
  let mut receipt = ""
  let mut input_tokens : Int32? = None
  let mut cached_input_tokens : Int32? = None
  let answer : Array[String] = []
  let (payload, expected) = request_fixture(
    model, user, round, nonce, max_tokens, profile, quality,
  )
  let timings : Map[String, Int64] = Map([])
  let mut done_at = 0L
  let mut error = try {
    @async.with_timeout(180000) <| () => {
      let client = @http.Client(origin)
      defer client.close()
      timings["connect_ms"] = @async.now() - started
      let response = client.post(
        "/trial/v1/chat/completions",
        payload.stringify(),
        extra_headers={
          "Authorization": "Bearer " + key,
          "Content-Type": "application/json",
          "X-LunaNexa-Prefix-Cache": "tenant",
        },
      )
      status = response.code
      timings["headers_ms"] = @async.now() - started
      guard status == 200 else { fail("HTTP \{status}") }
      while client.read_until("\n") is Some(line) {
        let line = line.trim()
        if !line.has_prefix("data:") {
          continue
        }
        let data = line[5:].trim().to_owned()
        if data == "[DONE]" {
          done = true
          done_at = @async.now()
          break
        }
        let parsed = @json.parse(data)
        if parsed is { "id": String(id), .. } {
          response_id = id
        }
        if parsed is { "choices": Array(choices), .. } {
          for choice in choices {
            if choice is { "delta": { "content": String(text), .. }, .. } &&
              text != "" {
              let now = @async.now()
              if first == 0L {
                first = now
              }
              last = now
              chunks += 1
              if quality {
                answer.push(text)
              }
            }
          }
        }
        if parsed is { "usage": { "completion_tokens": value, .. }, .. } {
          tokens = token_count(value)
        }
        if parsed is { "usage": { "prompt_tokens": value, .. }, .. } {
          input_tokens = Some(token_count(value))
        }
        if parsed
          is {
            "usage": {
              "prompt_tokens_details": { "cached_tokens": value, .. },
              ..
            },
            ..
          } {
          cached_input_tokens = Some(token_count(value))
        }
        if parsed is { "lunanexa_receipt": String(value), .. } {
          receipt = value
        }
        if parsed is { "error": _, .. } {
          fail("stream error")
        }
      }
    }
    ""
  } catch {
    _ =>
      if status != 0 && status != 200 {
        "HTTP \{status}"
      } else {
        "stream incomplete or transport timeout"
      }
  }
  let elapsed = (@async.now() - started).max(1L)
  if first > 0L && done_at > 0L {
    timings["decode_ms"] = last - first
    timings["stream_tail_ms"] = done_at - last
    timings["close_ms"] = (@async.now() - done_at).max(0L)
  }
  let rate = decode_rate(tokens, first, last)
  if error == "" &&
    (
      !done ||
      tokens < (if quality { 1 } else { max_tokens.min(256) }) ||
      chunks < (if quality { 1 } else { 2 }) ||
      (!quality && rate <= 0.0) ||
      receipt == ""
    ) {
    error = "incomplete stream, usage or receipt"
  }
  if error == "" && expected is Some(expected) {
    error = quality_error(answer.join(""), expected)
  }
  {
    user,
    concurrency,
    round,
    status,
    output_tokens: tokens,
    ttft_ms: if first > 0L {
      first - started
    } else {
      -1L
    },
    elapsed_ms: elapsed,
    decode_tokens_per_second: rate,
    end_to_end_tokens_per_second: tokens.to_double() *
    1000.0 /
    elapsed.to_double(),
    valid: error == "" &&
    done &&
    tokens >= (if quality { 1 } else { max_tokens.min(256) }) &&
    chunks >= (if quality { 1 } else { 2 }) &&
    (quality || rate > 0.0) &&
    receipt != "",
    response_id,
    receipt,
    error,
    timings,
    cached_input_tokens,
    input_tokens,
  }
}
