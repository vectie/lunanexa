///|
// Closed diagnostic labels only: exception strings and upstream bodies may
// contain customer input, credentials, or private endpoint details.
fn runtime_failure_outcome(error : Error) -> String {
  match error {
    @async.TimeoutError => "deadline_exceeded"
    @async.WaitedTaskAlreadyCancelled => "cancelled"
    @runtimes.RemoteRuntimeError::UnsupportedCapability =>
      "unsupported_capability"
    @runtimes.RemoteRuntimeError::UpstreamRejected(status~, body=_) =>
      if status >= 400 && status <= 599 {
        "upstream_http_\{status}"
      } else {
        "upstream_http_rejected"
      }
    @runtimes.RemoteRuntimeError::UpstreamFailed(..) => "upstream_failed_event"
    @runtimes.RemoteRuntimeError::InvalidUpstreamResponse(message) =>
      match message {
        "tool calls must belong to an assistant message" =>
          "invalid_tool_call_role"
        "chat message must contain text or tool calls" => "missing_chat_content"
        "chat content must be text or text parts" => "invalid_chat_content"
        "function call must identify its call, name and arguments" =>
          "invalid_function_call"
        "tool result must identify its call and content" =>
          "invalid_tool_result"
        "upstream stream ended before its completion marker" =>
          "missing_completion_marker"
        "stream exceeded output event ceiling" => "output_event_ceiling"
        "upstream stream event exceeded the configured limit" =>
          "stream_event_bytes"
        "upstream stream exceeded the configured limit" =>
          "stream_response_bytes"
        _ => "invalid_upstream_response"
      }
    @runtimes.RemoteRuntimeError::InsecureEndpoint(_) => "insecure_endpoint"
    @runtimes.RemoteRuntimeError::InvalidNodeRouting(_) =>
      "invalid_node_routing"
    @runtimes.RemoteRuntimeError::RoutingTargetUnavailable(_) =>
      "routing_target_unavailable"
    _ => "runtime_failure"
  }
}

///|
async fn ApiService::record_runtime_failure(
  self : ApiService,
  error : Error,
  workload_id : String,
  accepted : Int64,
  completed : Int64,
) -> Unit {
  let correlation_id = "runtime-\{digest_hex(workload_id)}"
  self.record_component_event(
    "event-\{correlation_id}",
    completed,
    Warning,
    "runtime-adapter",
    "RuntimeInvocationFailed",
    correlation_id,
    "workload",
    runtime_failure_outcome(error),
    502,
    (completed - accepted).clamp(min=0L, max=86400000L),
  ) catch {
    // Observability cannot replace the original inference failure.
    _ => ()
  }
}
