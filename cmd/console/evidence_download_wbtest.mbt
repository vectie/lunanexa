///|
test "operator downloads require short lived digest bound download grants" {
  let grant : @offline.OfflineTransferGrant = {
    session_id: "download",
    transfer_path: "/transfers/download",
    session_token: "token",
    direction: DownloadTransfer,
    media_types: ["application/pdf"],
    maximum_byte_count: 1024L,
    expected_sha256: Some("sha256:abc"),
    expires_unix_ms: 121000L,
  }
  validate_operator_download(grant, "sha256:abc", 1000L)
  for
    invalid in [
      { ..grant, direction: UploadTransfer, },
      { ..grant, expected_sha256: None, },
      { ..grant, expires_unix_ms: 121001L, },
      { ..grant, expires_unix_ms: 1000L, },
    ] {
    let denied = try {
      validate_operator_download(invalid, "sha256:abc", 1000L)
      false
    } catch {
      _ => true
    }
    assert_true(denied)
  }
}
