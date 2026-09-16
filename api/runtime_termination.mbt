///|
async fn ApiService::accept_runtime_terminations(
  self : ApiService,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if body.length() > 262144 {
    return api_error(
      413, "InvalidRequest", "termination report is too large", false,
    )
  }
  let report : @contracts.RuntimeTerminationReport = @json.from_json(
    @json.parse(body),
  ) catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "invalid termination report", false,
      )
  }
  if !@contracts.valid_identifier(report.node_id) ||
    !self.node_authorized(headers, report.node_id) ||
    report.signature !=
    @node.termination_report_signature(
      report,
      node_credential(headers).unwrap_or(""),
    ) {
    return api_error(
      401, "Unauthenticated", "valid node authority is required", false,
    )
  }
  let now = @async.now()
  if report.records.is_empty() ||
    report.records.length() > 128 ||
    report.timestamp_unix_ms < now - 60000L ||
    report.timestamp_unix_ms > now + 15000L {
    return api_error(
      409, "InvalidTermination", "invalid report bounds or send time", false,
    )
  }
  guard self.media is Some(media) else {
    return api_error(
      503, "MediaNotConfigured", "media is not configured", false,
    )
  }
  if self.reconciliation_only || !self.store.current_epoch_is_durable() {
    return api_error(
      503, "TerminationUnavailable", "active durable controller is required", true,
    )
  }
  let accepted = media.jobs.snapshot().terminations.unwrap_or([])
  let assignments = self.store.assignments()
  // A retry of previously persisted exact evidence remains valid after the
  // assignment was removed. New evidence requires the original assignment.
  for evidence in report.records {
    let original_valid = evidence.original_assignment.map_or(false, assignment => {
      self.assignment_signing_secret != node_credential(headers).unwrap_or("") &&
      assignment.signature != "" &&
      assignment.signature ==
      @node.assignment_signature(assignment, self.assignment_signing_secret) &&
      assignment.node_id == report.node_id &&
      assignment.assignment_id == evidence.assignment_id &&
      assignment.deployment_id == evidence.deployment_id &&
      assignment.generation == evidence.generation &&
      assignment.controller_epoch == evidence.controller_epoch &&
      assignment.artifact.digest == evidence.artifact_digest &&
      assignment.runtime.image_digest == evidence.image_digest
    })
    if evidence.observed_unix_ms < 0L ||
      evidence.observed_unix_ms > report.timestamp_unix_ms ||
      !@contracts.valid_sha256_digest("sha256:" + evidence.instance_id) ||
      !(accepted.contains({ node_id: report.node_id, evidence, }) ||
      original_valid ||
      assignments.any(assignment => {
        assignment.node_id == report.node_id &&
        assignment.assignment_id == evidence.assignment_id &&
        assignment.deployment_id == evidence.deployment_id &&
        assignment.generation == evidence.generation &&
        assignment.controller_epoch == evidence.controller_epoch &&
        assignment.artifact.digest == evidence.artifact_digest &&
        assignment.runtime.image_digest == evidence.image_digest
      })) {
      return api_error(
        409, "InvalidTermination", "termination does not match an original assignment",
        false,
      )
    }
  }
  try {
    for evidence in report.records {
      media.jobs.accept_termination({ node_id: report.node_id, evidence, })
    }
  } catch {
    @media_jobs.Conflict =>
      return api_error(
        409, "InvalidTermination", "conflicting termination evidence", false,
      )
    _ =>
      return api_error(
        503, "TerminationUnavailable", "termination persistence unavailable", true,
      )
  }
  json_reply(202, { "accepted": report.records.to_json() })
}
