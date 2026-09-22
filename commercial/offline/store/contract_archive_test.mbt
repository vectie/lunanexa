///|
fn archived_object(
  kind : @offline.DocumentArtifactKind,
) -> @store.ContractArchiveObject raise {
  {
    artifact_id: @store.contract_archive_artifact_id("packet-a", 3L, kind),
    object_ref: @store.contract_archive_object_ref(
      "org-a", "order-a", "packet-a", 3L, kind,
    ),
    media_type: if kind == EditableContractDocx {
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    } else {
      "application/pdf"
    },
    sha256: digest_a,
    byte_count: 2000L,
    storage_receipt: "stored-a",
    stored_unix_ms: 1500L,
    verified: true,
    active_content_detected: false,
  }
}

///|
async fn archive_pair(
  store : @store.OfflineCommerceStore,
  docx : @store.ContractArchiveObject,
  pdf : @store.ContractArchiveObject,
  tenant? : String = "tenant-a",
  organization? : String = "org-a",
  subject? : String = "buyer-a",
  template_id? : String = "youthpolicy-device-undertaking-v1",
  template_version? : String = "v1",
) -> Array[@offline.DocumentArtifact] {
  store.archive_contract_generation(
    tenant_ref=tenant,
    organization_id=organization,
    subject_ref=subject,
    order_id="order-a",
    packet_id="packet-a",
    packet_revision=3L,
    template_id~,
    template_version~,
    locale="zh-CN",
    now_unix_ms=2000L,
    docx~,
    pdf~,
  )
}

///|
async test "OFL undertaking archive preserves new identity and rejects version substitution" {
  let directory = @fs.tmpdir(prefix="contract-archive-ofl-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/state.json"
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.create_order(order("order-a")))
  let docx = archived_object(EditableContractDocx)
  let pdf = archived_object(PrintReadyContractPdf)
  let archived = archive_pair(
    store,
    docx,
    pdf,
    template_id="youthpolicy-device-undertaking-ofl-v2",
    template_version="v2",
  )
  assert_eq(
    archived[0].template_id,
    Some("youthpolicy-device-undertaking-ofl-v2"),
  )
  assert_eq(archived[1].template_version, Some("v2"))
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(
    archive_pair(
      reopened,
      docx,
      pdf,
      template_id="youthpolicy-device-undertaking-ofl-v2",
      template_version="v2",
    ),
    archived,
  )
  for
    pair in [
      ("youthpolicy-device-undertaking-ofl-v2", "v1"),
      ("youthpolicy-device-undertaking-v1", "v2"),
      ("unknown-template", "v2"),
    ] {
    try
      archive_pair(
        reopened,
        docx,
        pdf,
        template_id=pair.0,
        template_version=pair.1,
      )
    catch {
      @offline.OfflineCommerceError::InvalidInput(_) => ()
      error => fail("unexpected mismatch rejection: \{Repr(error)}")
    } noraise {
      _ => fail("template version substitution was accepted")
    }
  }
  let retained = reopened.snapshot().artifacts
  assert_eq(retained.length(), archived.length())
  for artifact in archived {
    assert_true(retained.contains(artifact))
  }
}

///|
async test "contract archive persists pair and exact replay survives restart" {
  let directory = @fs.tmpdir(prefix="contract-archive-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/state.json"
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.create_order(order("order-a")))
  let docx = archived_object(EditableContractDocx)
  let pdf = archived_object(PrintReadyContractPdf)
  let archived = archive_pair(store, docx, pdf)
  assert_eq(archived.length(), 2)
  let before = store.snapshot()
  assert_eq(archive_pair(store, docx, pdf), archived)
  assert_eq(store.snapshot(), before)
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(archive_pair(reopened, docx, pdf), archived)
  assert_eq(reopened.snapshot(), before)
  assert_eq(
    reopened.artifact("org-a", docx.artifact_id).object_ref,
    docx.object_ref,
  )
  // Existing transfer authority can now issue a digest-bound download.
  ignore(
    reopened.issue_transfer_session({
      session_id: "download-a",
      idempotency_key: "download-a",
      session_token_sha256: digest_b,
      organization_id: "org-a",
      subject_ref: "buyer-a",
      order_id: "order-a",
      artifact_id: docx.artifact_id,
      direction: DownloadTransfer,
      media_types: [docx.media_type],
      maximum_byte_count: docx.byte_count,
      expected_sha256: Some(docx.sha256),
      state: TransferIssued,
      issued_unix_ms: 2000L,
      expires_unix_ms: 3000L,
      consumed_unix_ms: None,
    }),
  )
}

///|
async test "contract archive rejects scope object substitution invalid evidence and partial pairs" {
  let directory = @fs.tmpdir(prefix="contract-archive-deny-")
  defer @fs.rmdir(directory, recursive=true)
  let store = @store.OfflineCommerceStore::open("\{directory}/state.json")
  ignore(store.create_order(order("order-a")))
  let docx = archived_object(EditableContractDocx)
  let pdf = archived_object(PrintReadyContractPdf)
  let before = store.snapshot()
  for
    bad in [
      { ..pdf, verified: false, },
      { ..pdf, active_content_detected: true, },
      { ..pdf, object_ref: "object://different/path", },
      { ..pdf, artifact_id: "client-selected", },
      { ..pdf, byte_count: 0L, },
      { ..pdf, byte_count: 100000001L, },
      { ..pdf, sha256: "sha256:bad", },
      { ..pdf, storage_receipt: "https://secret?token=secret", },
      { ..pdf, media_type: docx.media_type, },
      { ..pdf, stored_unix_ms: 500L, },
      { ..pdf, stored_unix_ms: 2500L, },
    ] {
    try archive_pair(store, docx, bad) catch {
      _ => ()
    } noraise {
      _ => fail("invalid archive accepted")
    }
    assert_eq(store.snapshot(), before)
  }
  for axis in ["tenant", "organization", "subject"] {
    try
      archive_pair(
        store,
        docx,
        pdf,
        tenant=if axis == "tenant" { "other" } else { "tenant-a" },
        organization=if axis == "organization" { "other" } else { "org-a" },
        subject=if axis == "subject" { "other" } else { "buyer-a" },
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("foreign archive accepted")
    }
    assert_eq(store.snapshot(), before)
  }
  ignore(archive_pair(store, docx, pdf))
  let committed = store.snapshot()
  try archive_pair(store, docx, { ..pdf, sha256: digest_b, }) catch {
    _ => ()
  } noraise {
    _ => fail("conflicting replay accepted")
  }
  assert_eq(store.snapshot(), committed)
}

///|
async test "contract archive failed persistence rolls back both artifacts and releases mutex" {
  let directory = @fs.tmpdir(prefix="contract-archive-fault-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/state.json"
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.create_order(order("order-a")))
  let docx = archived_object(EditableContractDocx)
  let pdf = archived_object(PrintReadyContractPdf)
  let before = store.snapshot()
  let disk = @fs.read_file(path).text()
  @fs.mkdir(path + ".next")
  for _ in 0..<2 {
    try archive_pair(store, docx, pdf) catch {
      _ => ()
    } noraise {
      _ => fail("expected disk write fault")
    }
    assert_eq(store.snapshot(), before)
    assert_eq(@fs.read_file(path).text(), disk)
  }
  @fs.rmdir(path + ".next")
  ignore(archive_pair(store, docx, pdf))
  assert_eq(
    @store.OfflineCommerceStore::open(path).snapshot(),
    store.snapshot(),
  )
}
