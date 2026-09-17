///|
priv struct OperatorArtifactDownloadIntent {
  tenant_ref : String
  organization_id : String
  order_id : String
  session_id : String
  idempotency_key : String
} derive(FromJson)

///|
async fn ApiService::operator_artifact_download(
  self : ApiService,
  store : @offline_store.OfflineCommerceStore,
  artifact_id : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(actor) else {
    return api_error(
      401, "Unauthenticated", "attributed operator authority is required", false,
    )
  }
  let decoded : OperatorArtifactDownloadIntent? = decode_offline(body)
  guard decoded is Some(intent) &&
    @contracts.valid_identifier(intent.tenant_ref) &&
    @contracts.valid_identifier(intent.organization_id) &&
    @contracts.valid_identifier(intent.order_id) &&
    @contracts.valid_identifier(intent.session_id) &&
    @contracts.valid_identifier(intent.idempotency_key) &&
    @contracts.valid_identifier(artifact_id) &&
    @contracts.valid_identifier(actor, maximum_length=240) else {
    return api_error(
      400, "InvalidRequest", "explicit review scope and idempotency are required",
      false,
    )
  }
  let grant = try {
    let order = store.order(intent.organization_id, intent.order_id)
    let artifact = store.artifact(intent.organization_id, artifact_id)
    if order.tenant_ref != intent.tenant_ref ||
      artifact.order_id != order.order_id {
      raise @offline.OfflineCommerceError::TenantMismatch
    }
    if artifact.scan_state != ScanPassed {
      raise @offline.OfflineCommerceError::ArtifactUnavailable(
        "unscanned evidence remains quarantined",
      )
    }
    let scope = "operator-download.v1|\{actor}|\{intent.tenant_ref}|\{intent.organization_id}|\{intent.order_id}|\{artifact_id}|\{artifact.sha256}|\{intent.idempotency_key}"
    let scoped_key = "review-" +
      @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(scope)))
    let now = @async.now()
    let issued = self.issue_offline_transfer(
      store,
      intent.session_id,
      scoped_key,
      intent.organization_id,
      "operator:\{actor}",
      intent.order_id,
      artifact_id,
      DownloadTransfer,
      artifact.object_ref,
      [artifact.media_type],
      artifact.byte_count,
      Some(artifact.sha256),
      now,
      now + 120000L,
      operator_scope=(intent.tenant_ref, actor),
    )
    // Persist attribution before returning the capability to the browser.
    self.operator_audit_as(
      actor,
      "offline.artifact.review.download",
      artifact_id,
      "review:\{intent.tenant_ref}:\{intent.organization_id}:\{intent.order_id}:\{intent.session_id}",
    )
    issued
  } catch {
    error => return offline_error_reply(error)
  } noraise {
    value => value
  }
  json_reply(201, grant.to_json())
}
