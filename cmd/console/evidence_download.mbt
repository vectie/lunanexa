///|
priv struct OperatorEvidenceDownloadIntent {
  tenant_ref : String
  organization_id : String
  order_id : String
  session_id : String
  idempotency_key : String
} derive(ToJson)

///|
extern "js" fn operator_download_file(
  path : String,
  token : String,
  limit : Int64,
  digest : String,
  filename : String,
  digest_bytes : (Bytes) -> String,
) -> @js.Promise =
  #| async (path, token, limit, digest, filename, digestBytes) => {
  #|   const target = new URL(path, window.location.href);
  #|   if (target.origin !== window.location.origin || target.username || target.password) throw new Error("Evidence transfer must use the configured same-origin ingress");
  #|   const response = await fetch(target, { headers: { Authorization: `Bearer ${token}` }, credentials: "omit", redirect: "error", cache: "no-store" });
  #|   if (!response.ok) throw new Error(`Download failed with HTTP ${response.status}`);
  #|   const bytes = await response.arrayBuffer();
  #|   if (BigInt(bytes.byteLength) > limit) throw new Error("File exceeds authorized size");
  #|   const actual = digestBytes(new Uint8Array(bytes));
  #|   if (actual !== digest) throw new Error("Evidence digest mismatch");
  #|   const url = URL.createObjectURL(new Blob([bytes]));
  #|   try { const a = document.createElement("a"); a.href = url; a.download = filename; a.click(); }
  #|   finally { URL.revokeObjectURL(url); }
  #|   return filename;
  #| }

///|
fn validate_operator_download(
  grant : @offline.OfflineTransferGrant,
  expected : String,
  now : Int64,
) -> Unit raise {
  guard grant.direction == DownloadTransfer &&
    grant.expected_sha256 == Some(expected) &&
    grant.maximum_byte_count > 0L &&
    grant.expires_unix_ms > now &&
    grant.expires_unix_ms <= now + 120000L &&
    grant.transfer_path != "" &&
    grant.session_token != "" else {
    fail("Invalid operator evidence download grant")
  }
}

///|
async fn download_operator_evidence(
  model : AppModel,
  artifact_id : String,
) -> Unit {
  // Contract documents can be opened before the separate commerce page.
  // Resolve fresh, authenticated artifact metadata rather than a page cache.
  let response = request(
    "GET",
    model.endpoint,
    "/v1/offline-commerce/operator/snapshot",
    model.credential,
  )
  let snapshot : @offline.OfflineCommerceSnapshot = @json.from_json(
    @json.parse(response),
  )
  guard snapshot.artifacts.iter().find_first(a => a.artifact_id == artifact_id)
    is Some(artifact) &&
    artifact.scan_state == ScanPassed else {
    fail("Evidence is unavailable or not scan-passed")
  }
  guard snapshot.orders.iter().find_first(o => o.order_id == artifact.order_id)
    is Some(order) else {
    fail("Evidence order is unavailable")
  }
  let intent : OperatorEvidenceDownloadIntent = {
    tenant_ref: order.tenant_ref,
    organization_id: order.organization_id,
    order_id: order.order_id,
    session_id: random_identifier("operator-download"),
    idempotency_key: random_identifier("operator-download-intent"),
  }
  let response = request(
    "POST",
    model.endpoint,
    "/v1/offline-commerce/operator/artifacts/\{artifact_id}:download",
    model.credential,
    body=ToJson::to_json(intent).stringify(),
  )
  let grant : @offline.OfflineTransferGrant = @json.from_json(
    @json.parse(response),
  )
  validate_operator_download(grant, artifact.sha256, current_unix_ms())
  let suffix = match artifact.media_type {
    "application/pdf" => ".pdf"
    "image/png" => ".png"
    "image/jpeg" => ".jpg"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" =>
      ".docx"
    _ => ""
  }
  let _ = operator_download_file(
    grant.transfer_path,
    grant.session_token,
    grant.maximum_byte_count,
    artifact.sha256,
    artifact_id + suffix,
    operator_download_digest,
  ).wait()
}

///|
fn operator_download_digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes.to_fixedarray()))
}

///|
fn operator_evidence_download_command(
  model : AppModel,
  artifact_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try download_operator_evidence(model, artifact_id) catch {
      error =>
        ActionFailed(
          model.console.locale,
          "Evidence download failed: \{Repr(error)}",
        )
    } noraise {
      _ =>
        ActionComplete(
          model.console.locale,
          console_copy(
            model.console.locale,
            "Verified original downloaded. Review its contents before approving.",
            "已下载核验摘要的原件，请阅读内容后再审核。",
          ),
        )
    }
  })
}
