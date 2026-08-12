///|
const TestRenderSecret : String = "renderer-test-secret-with-at-least-32-bytes"

///|
fn docx_template() -> FixedArray[Byte] raise {
  @opc.save(
    (
      {
        parts: [
          {
            name: "[Content_Types].xml",
            content: (
              #|<?xml version="1.0" encoding="UTF-8"?>
              #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              #|  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              #|  <Default Extension="xml" ContentType="application/xml"/>
              #|  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              #|</Types>
            )
            |> @utf8.encode
            |> Bytes::to_fixedarray,
          },
          {
            name: "_rels/.rels",
            content: (
              #|<?xml version="1.0" encoding="UTF-8"?>
              #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
              #|</Relationships>
            )
            |> @utf8.encode
            |> Bytes::to_fixedarray,
          },
          {
            name: "word/document.xml",
            content: (
              #|<?xml version="1.0" encoding="UTF-8"?>
              #|<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>{{ORDER_ID}}</w:t></w:r></w:p><w:sectPr/></w:body></w:document>
            )
            |> @utf8.encode
            |> Bytes::to_fixedarray,
          },
        ],
      } : @opc.Package),
  )
}

///|
fn generation_request(now : Int64) -> @offline.ArtifactGenerationRequest {
  {
    request_id: "request-worker-1",
    order_id: "order-worker-1",
    organization_id: "org-worker-1",
    artifact_id: "artifact-worker-1",
    kind: EditableContractDocx,
    template_id: "template-contract",
    template_version: "v1",
    locale: "zh-CN",
    expected_object_ref: "object://offline/order-worker-1/contract.docx",
    input_snapshot_sha256: "sha256:" + "1".repeat(64),
    requested_by: "operator-worker-1",
    requested_unix_ms: now - 60000L,
  }
}

///|
fn png_evidence() -> FixedArray[Byte] {
  [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x76, 0x69, 0x73, 0x75, 0x61,
    0x6c,
  ]
}

///|
fn signed_manifest(
  request : @offline.ArtifactGenerationRequest,
  artifact_sha256 : String,
  visual_sha256 : String,
  rendered_unix_ms : Int64,
  kind? : @offline.DocumentArtifactKind = EditableContractDocx,
  page_or_sheet_count? : Int = 1,
  visual_evidence_filename? : String = "render.png",
) -> RenderEvidenceManifest {
  let unsigned : RenderEvidenceManifest = {
    schema_version: 1,
    request_id: request.request_id,
    artifact_sha256,
    kind,
    page_or_sheet_count,
    passed: true,
    renderer_receipt: "renderer-receipt-1",
    rendered_unix_ms,
    visual_evidence_filename,
    visual_evidence_sha256: visual_sha256,
    signature: "",
  }
  {
    ..unsigned,
    signature: render_evidence_signature(unsigned, TestRenderSecret),
  }
}

///|
fn base_job(
  request : @offline.ArtifactGenerationRequest,
  manifest_sha256 : String,
) -> OfflineArtifactJob {
  {
    schema_version: 1,
    request,
    template_filename: "contract.docx",
    prepared_filename: "contract.prepared.docx",
    output_filename: "contract.generated.docx",
    result_filename: "result.json",
    render_manifest_filename: "render-manifest.json",
    render_manifest_sha256: manifest_sha256,
    docx_replacements: [
      { placeholder: "{{ORDER_ID}}", value: "order-worker-1" },
    ],
    xlsx_replacements: [],
  }
}

///|
async fn write_manifest_and_job(
  root : String,
  request : @offline.ArtifactGenerationRequest,
  manifest : RenderEvidenceManifest,
) -> Unit {
  let manifest_text = manifest.to_json().stringify()
  @fs.write_file(
    "\{root}/render-manifest.json",
    manifest_text,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  @fs.write_file(
    "\{root}/job.json",
    base_job(request, sha256(@utf8.encode(manifest_text).to_fixedarray()))
    .to_json()
    .stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
}

///|
async fn expect_job_failure(root : String, now : Int64) -> Unit {
  ignore(run_job(root, "job.json", TestRenderSecret, now)) catch {
    Failure(_) => ()
    _ => fail("invalid renderer evidence was accepted")
  }
}

///|
async test "worker binds signed render evidence to the customized DOCX" {
  let now = @async.now()
  let root = "/tmp/lunanexa-offline-worker-\{now}"
  @fs.mkdir(root, permission=0o700)
  let template = docx_template()
  let evidence = png_evidence()
  let request = generation_request(now)
  let customized = @worker.customize_docx_template(template, [
    { placeholder: "{{ORDER_ID}}", value: "order-worker-1" },
  ])
  @fs.write_file(
    "\{root}/contract.docx",
    Bytes::from_array(template),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  @fs.write_file(
    "\{root}/render.png",
    Bytes::from_array(evidence),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let manifest = signed_manifest(
    request,
    sha256(customized.bytes),
    sha256(evidence),
    now,
  )
  write_manifest_and_job(root, request, manifest)
  assert_eq(prepare_job(root, "job.json"), sha256(customized.bytes))
  assert_true(@fs.exists("\{root}/contract.prepared.docx"))
  let result = run_job(root, "job.json", TestRenderSecret, now)
  assert_true(result.verified)
  assert_true(result.moonleaf_verified)
  assert_true(result.render_verified)
  assert_true(@fs.exists("\{root}/contract.generated.docx"))
  assert_true(@fs.exists("\{root}/result.json"))
  let reopened = @opc.open(
    @fs.read_file("\{root}/contract.generated.docx").binary().to_fixedarray(),
  )
  assert_true(reopened.text("word/document.xml").contains("order-worker-1"))
  let persisted : @offline.ArtifactGenerationResult = @json.from_json(
    @json.parse(@fs.read_file("\{root}/result.json").text()),
  )
  assert_eq(persisted, result)
  @fs.rmdir(root, recursive=true)
}

///|
async test "worker rejects unbound, tampered, stale, or malformed render evidence" {
  let now = @async.now()
  let root = "/tmp/lunanexa-offline-worker-reject-\{now}"
  @fs.mkdir(root, permission=0o700)
  let template = docx_template()
  let request = generation_request(now)
  let customized = @worker.customize_docx_template(template, [
    { placeholder: "{{ORDER_ID}}", value: "order-worker-1" },
  ])
  let artifact_sha256 = sha256(customized.bytes)
  let evidence = png_evidence()
  @fs.write_file(
    "\{root}/contract.docx",
    Bytes::from_array(template),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )

  // Arbitrary non-render bytes fail even when their digest is signed.
  let arbitrary : FixedArray[Byte] = [
    0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
  ]
  @fs.write_file(
    "\{root}/render.png",
    Bytes::from_array(arbitrary),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  write_manifest_and_job(
    root,
    request,
    signed_manifest(request, artifact_sha256, sha256(arbitrary), now),
  )
  expect_job_failure(root, now)

  @fs.write_file(
    "\{root}/render.png",
    Bytes::from_array(evidence),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  // A valid signature for a different artifact cannot be replayed.
  write_manifest_and_job(
    root,
    request,
    signed_manifest(request, "sha256:" + "2".repeat(64), sha256(evidence), now),
  )
  expect_job_failure(root, now)

  // A signed manifest becomes invalid if any field is tampered afterward.
  let signed = signed_manifest(request, artifact_sha256, sha256(evidence), now)
  write_manifest_and_job(root, request, { ..signed, passed: false })
  expect_job_failure(root, now)

  write_manifest_and_job(
    root,
    request,
    signed_manifest(request, artifact_sha256, sha256(evidence), now - 1000000L),
  )
  expect_job_failure(root, now)

  write_manifest_and_job(
    root,
    request,
    signed_manifest(
      request,
      artifact_sha256,
      sha256(evidence),
      now,
      kind=QuoteScheduleXlsx,
    ),
  )
  expect_job_failure(root, now)

  write_manifest_and_job(
    root,
    request,
    signed_manifest(
      request,
      artifact_sha256,
      sha256(evidence),
      now,
      page_or_sheet_count=0,
    ),
  )
  expect_job_failure(root, now)

  ignore(run_job(root, "../job.json", TestRenderSecret, now)) catch {
    Failure(_) => ()
    _ => fail("traversal filename was accepted")
  }
  ignore(run_job(root, "job.json", "short-secret", now)) catch {
    Failure(_) => ()
    _ => fail("short render-evidence secret was accepted")
  }
  @fs.rmdir(root, recursive=true)
}
