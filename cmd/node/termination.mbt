///|
priv struct TerminationAcknowledgement {
  accepted : Array[@contracts.RuntimeTermination]
} derive(FromJson)

///|
fn acknowledgement_matches(
  sent : Array[@contracts.RuntimeTermination],
  accepted : Array[@contracts.RuntimeTermination],
) -> Bool {
  if accepted.length() > sent.length() {
    return false
  }
  for i, entry in accepted {
    if !sent.contains(entry) {
      return false
    }
    for j in 0..<i {
      if accepted[j] == entry {
        return false
      }
    }
  }
  true
}

///|
fn termination_batch(
  pending : Array[@contracts.RuntimeTermination],
  offset : Int,
) -> (Array[@contracts.RuntimeTermination], Int) {
  if pending.is_empty() {
    return ([], 0)
  }
  let mut next = if offset < 0 { 0 } else { offset % pending.length() }
  for _ in 0..<pending.length() {
    let entry = pending[next]
    next = (next + 1) % pending.length()
    if @utf8.encode(ToJson::to_json(entry).stringify()).length() <= 200000 {
      return ([entry], next)
    }
  }
  ([], next)
}

///|
async fn send_pending_terminations(
  supervisor : @kubernetes.RuntimeSupervisor,
  base : String,
  node_id : String,
  token : String,
  cursor : Ref[Int],
) -> Unit {
  let (records, next) = termination_batch(
    supervisor.pending_terminations(),
    cursor.val,
  )
  // Independent reports keep rejected historical evidence from starving later
  // records. Oversized entries remain durable for operator investigation.
  cursor.val = next
  if records.is_empty() {
    return
  }
  let report : @contracts.RuntimeTerminationReport = {
    node_id,
    timestamp_unix_ms: @async.now(),
    records,
    signature: "",
  }
  let signed = {
    ..report,
    signature: @node_agent.termination_report_signature(report, token),
  }
  @async.with_timeout(10000, () => {
    let (response, body) = @http.post(
      endpoint(base, "/v1/nodes/runtime-terminations"),
      ToJson::to_json(signed),
      headers=node_headers(node_id, token),
    )
    if response.code != 202 {
      raise Failure("termination report was not accepted")
    }
    let acknowledgement : TerminationAcknowledgement = @json.from_json(
      @json.parse(body.text()),
    )
    if !acknowledgement_matches(records, acknowledgement.accepted) {
      raise Failure("termination acknowledgement does not match the sent batch")
    }
    supervisor.acknowledge_terminations(acknowledgement.accepted)
  })
}
