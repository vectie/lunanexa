///|
test "runtime diagnostics never disclose exception strings or upstream bodies" {
  assert_eq(
    runtime_failure_outcome(
      @runtimes.RemoteRuntimeError::UpstreamRejected(
        status=400,
        body="private prompt and Bearer secret",
      ),
    ),
    "upstream_http_400",
  )
  assert_eq(
    runtime_failure_outcome(
      @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(
        "private prompt and lnx_secret",
      ),
    ),
    "invalid_upstream_response",
  )
  assert_eq(
    runtime_failure_outcome(
      @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(
        "tool calls must belong to an assistant message",
      ),
    ),
    "invalid_tool_call_role",
  )
  assert_eq(
    runtime_failure_outcome(
      @runtimes.RemoteRuntimeError::UpstreamFailed(
        code="private prompt",
        retryable=false,
      ),
    ),
    "upstream_failed_event",
  )
}
