///|
/// Opt-in export for a real Kubernetes runtime qualification. This is explicitly
/// NOT a stored commercial order, authorization receipt, or legal acceptance.
async test "export bounded production runtime qualification quote" {
  guard @env.get_env_var("LUNANEXA_PRODUCTION_QUOTE_PROBE_ROOT") is Some(root) &&
    @env.get_env_var("LUNANEXA_PRODUCTION_ADMISSION_PROBE_IMAGE") is Some(image) &&
    @env.get_env_var("LUNANEXA_PRODUCTION_QUOTE_SOURCE") is Some(source) else {
    return
  }
  assert_true(pinned_image(image))
  ensure_directory(root)
  let source_bytes = @fs.read_file(source).binary()
  let run_id = "technical-runtime-qualification-20260922"
  let request : @offline.ArtifactGenerationRequest = {
    request_id: run_id,
    artifact_id: run_id + "-quote",
    order_id: "TECHNICAL-QUALIFICATION-NOT-A-COMMERCIAL-ORDER",
    organization_id: "TECHNICAL-QUALIFICATION",
    kind: QuoteScheduleXlsx,
    template_id: "offline-quote-v1",
    template_version: "1",
    locale: "zh-CN",
    expected_object_ref: "object://technical-qualification/20260922/quote.xlsx",
    input_snapshot_sha256: digest(source_bytes),
    requested_by: "technical-runtime-qualification",
    requested_unix_ms: @async.now(),
  }
  let replacements : Array[@worker.CellReplacement] = [
    (2, request.order_id),
    (3, request.organization_id),
    (4, "TECHNICAL-NON-COMMERCIAL-QUOTE"),
    (5, "CNY"),
    (6, "72000"),
    (7, "4320"),
    (9, "2"),
  ].map(pair => { sheet_name: "Quote", row: pair.0, column: 2, value: pair.1, })
  let job : Json = {
    "schema_version": 1,
    "request": request.to_json(),
    "template_filename": "template.xlsx",
    "prepared_filename": "prepared.xlsx",
    "output_filename": "output.xlsx",
    "result_filename": "result.json",
    "render_manifest_filename": "render.json",
    "docx_replacements": [],
    "xlsx_replacements": replacements.to_json(),
  }
  let directory = digest(@utf8.encode(run_id)).split(":").to_array()[1].to_owned()
  ensure_directory(root + "/" + directory)
  write_atomic(root + "/" + directory + "/template.xlsx", source_bytes)
  write_atomic(
    root + "/" + directory + "/job.json",
    @utf8.encode(job.stringify(indent=2)),
  )
  let manifest = artifact_job_manifest(
    "offline-artifact-" + directory[0:40].to_owned(),
    "lunanexa",
    image,
    "artifact/" + directory,
    "lunanexa-offline-dispatcher-state",
    "lunanexa-offline-approved-fonts",
    "lunanexa-offline-render-evidence",
    digest(@utf8.encode(image + "|" + job.stringify(indent=2))),
  )
  write_atomic(
    root + "/job-manifest.json",
    @utf8.encode(manifest.stringify(indent=2)),
  )
  println("Technical runtime qualification directory: " + directory)
}

///|
async test "export bounded production runtime qualification undertaking" {
  guard @env.get_env_var("LUNANEXA_PRODUCTION_DOCX_PROBE_ROOT") is Some(root) &&
    @env.get_env_var("LUNANEXA_PRODUCTION_ADMISSION_PROBE_IMAGE") is Some(image) &&
    @env.get_env_var("LUNANEXA_PRODUCTION_DOCX_SOURCE") is Some(source) else {
    return
  }
  assert_true(pinned_image(image))
  ensure_directory(root)
  let source_bytes = @fs.read_file(source).binary()
  let run_id = "technical-docx-runtime-qualification-20260922"
  let request : @offline.ArtifactGenerationRequest = {
    request_id: run_id,
    artifact_id: run_id + "-pdf",
    order_id: "TECHNICAL-QUALIFICATION-NOT-A-COMMERCIAL-ORDER",
    organization_id: "TECHNICAL-QUALIFICATION",
    kind: PrintReadyContractPdf,
    template_id: "youthpolicy-device-undertaking-ofl-v2",
    template_version: "v2",
    locale: "zh-CN",
    expected_object_ref: "object://technical-qualification/20260922/undertaking.pdf",
    input_snapshot_sha256: digest(source_bytes),
    requested_by: "technical-runtime-qualification",
    requested_unix_ms: @async.now(),
  }
  let replacements = @worker.exact_docx_markers(source_bytes.to_fixedarray()).map(marker => {
      "placeholder": marker,
      "value": if marker == "{{lessee.name}}" {
        "技术验收样例（非商业订单，未签署）"
      } else if marker == "{{undertaking.signed_date.year}}" {
        "2026"
      } else if marker == "{{undertaking.signed_date.month}}" {
        "09"
      } else if marker == "{{undertaking.signed_date.day}}" {
        "22"
      } else {
        "技术验收未签署样例"
      },
    },
  )
  let job : Json = {
    "schema_version": 1,
    "request": request.to_json(),
    "template_filename": "template.docx",
    "prepared_filename": "prepared.docx",
    "output_filename": "output.pdf",
    "result_filename": "result.json",
    "render_manifest_filename": "render.json",
    "docx_replacements": replacements.to_json(),
    "xlsx_replacements": [],
  }
  let directory = digest(@utf8.encode(run_id)).split(":").to_array()[1].to_owned()
  ensure_directory(root + "/" + directory)
  write_atomic(root + "/" + directory + "/template.docx", source_bytes)
  write_atomic(
    root + "/" + directory + "/job.json",
    @utf8.encode(job.stringify(indent=2)),
  )
  let manifest = artifact_job_manifest(
    "offline-artifact-" + directory[0:40].to_owned(),
    "lunanexa",
    image,
    "artifact/" + directory,
    "lunanexa-offline-dispatcher-state",
    "lunanexa-offline-approved-fonts",
    "lunanexa-offline-render-evidence",
    digest(@utf8.encode(image + "|" + job.stringify(indent=2))),
  )
  write_atomic(
    root + "/job-manifest.json",
    @utf8.encode(manifest.stringify(indent=2)),
  )
  println("Technical DOCX qualification directory: " + directory)
}
