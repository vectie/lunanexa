///|
test "compatible chat retains output truncation and reasoning deltas" {
  assert_eq(
    compatible_finish_reason(Some({ "finish_reason": "length" }), false),
    "length",
  )
  assert_eq(
    compatible_finish_reason(Some({ "finish_reason": "length" }), true),
    "length",
  )
  assert_eq(compatible_finish_reason(None, true), "tool_calls")
  assert_eq(compatible_finish_reason(None, false), "stop")
  assert_eq(
    compatible_stream_delta({ "reasoning_delta": "Checking the source." }),
    { "reasoning_content": "Checking the source." },
  )
  assert_eq(compatible_stream_delta({ "text_delta": "Answer" }), {
    "content": "Answer",
  })
}
