///|
async test "public v1 golden fixtures round-trip canonically" {
  let response_text = @fs.read_file("tests/fixtures/response.v1.json")
    .text()
    .trim()
    .to_owned()
  let response : @contracts.WorkloadResponse = @json.from_json(
    @json.parse(response_text),
  )
  assert_eq(response.to_json().stringify(), response_text)
  let assignment_text = @fs.read_file("tests/fixtures/assignment.v1.json")
    .text()
    .trim()
    .to_owned()
  let assignment : @contracts.DesiredAssignment = @json.from_json(
    @json.parse(assignment_text),
  )
  assert_eq(assignment.to_json().stringify(), assignment_text)
  let heartbeat_text = @fs.read_file("tests/fixtures/heartbeat.v1.json")
    .text()
    .trim()
    .to_owned()
  let heartbeat : @contracts.NodeHeartbeat = @json.from_json(
    @json.parse(heartbeat_text),
  )
  assert_eq(heartbeat.to_json().stringify(), heartbeat_text)
  let telemetry_text = @fs.read_file("tests/fixtures/telemetry.v1.json")
    .text()
    .trim()
    .to_owned()
  let telemetry : @contracts.TelemetrySample = @json.from_json(
    @json.parse(telemetry_text),
  )
  assert_eq(telemetry.to_json().stringify(), telemetry_text)
  let audit_text = @fs.read_file("tests/fixtures/audit.v1.json")
    .text()
    .trim()
    .to_owned()
  let audit : @contracts.AuditEvent = @json.from_json(@json.parse(audit_text))
  assert_eq(audit.to_json().stringify(), audit_text)
}
