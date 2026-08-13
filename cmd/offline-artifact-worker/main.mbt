///|
const MaximumJobBytes : Int = 1048576

///|
const MaximumVisualEvidenceBytes : Int = 20971520

///|
pub(all) struct OfflineArtifactJob {
  schema_version : Int
  request : @offline.ArtifactGenerationRequest
  template_filename : String
  prepared_filename : String
  output_filename : String
  result_filename : String
  render_manifest_filename : String
  docx_replacements : Array[@worker.TextReplacement]
  xlsx_replacements : Array[@worker.CellReplacement]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct RenderVisualEvidence {
  page_or_sheet_index : Int
  filename : String
  sha256 : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct RenderEvidenceManifest {
  schema_version : Int
  request_id : String
  artifact_sha256 : String
  source_sha256 : String
  kind : @offline.DocumentArtifactKind
  page_or_sheet_count : Int
  passed : Bool
  renderer_receipt : String
  rendered_unix_ms : Int64
  visual_evidence : Array[RenderVisualEvidence]
  signature : String
} derive(Debug, Eq, FromJson, ToJson)

///|
fn required_env(name : String) -> String raise Failure {
  guard @env.get_env_var(name) is Some(value) && value.trim() != "" else {
    raise Failure("required environment setting is unavailable")
  }
  value
}

///|
fn safe_filename(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 180 &&
  value != "." &&
  value != ".." &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
fn valid_identifier(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 256 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':'
  })
}

///|
fn require_suffix(filename : String, suffix : String) -> Unit raise Failure {
  if !filename.to_lower().has_suffix(suffix) {
    raise Failure("artifact filename extension does not match its kind")
  }
}

///|
fn staging_path(root : String, filename : String) -> String raise Failure {
  if !safe_filename(filename) {
    raise Failure("staging filename is outside the bounded namespace")
  }
  "\{root}/\{filename}"
}

///|
async fn read_bounded_bytes(path : String, maximum : Int) -> FixedArray[Byte] {
  let bytes = @fs.read_file(path).binary()
  if bytes.length() == 0 || bytes.length() > maximum {
    raise Failure("staged input is empty or exceeds its size bound")
  }
  bytes.to_fixedarray()
}

///|
fn sha256(bytes : FixedArray[Byte]) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes))}"
}

///| Exposes the same bounded OPC parse gate used by the executable integration

///|
/// tests, without reimplementing OOXML parsing outside MoonLeaf.
pub fn ooxml_package_part_count(bytes : FixedArray[Byte]) -> Int raise {
  @opc.open(bytes).parts.length()
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn artifact_kind_label(kind : @offline.DocumentArtifactKind) -> String {
  match kind {
    EditableContractDocx => "editable-contract-docx"
    QuoteScheduleXlsx => "quote-schedule-xlsx"
    PrintReadyContractPdf => "print-ready-contract-pdf"
    ExecutedContractScan => "executed-contract-scan"
    PaymentReceipt => "payment-receipt"
    IssuedInvoice => "issued-invoice"
    InternalApprovalEvidence => "internal-approval-evidence"
    IdentityVerificationEvidence => "identity-verification-evidence"
  }
}

///|
fn render_evidence_material(manifest : RenderEvidenceManifest) -> String {
  let evidence = manifest.visual_evidence
    .map(item => "\{item.page_or_sheet_index}:\{item.filename}:\{item.sha256}")
    .join(",")
  "lunanexa.render-evidence.v2|\{manifest.request_id}|\{manifest.artifact_sha256}|\{manifest.source_sha256}|\{artifact_kind_label(manifest.kind)}|\{manifest.page_or_sheet_count}|\{manifest.passed}|\{manifest.renderer_receipt}|\{manifest.rendered_unix_ms}|\{evidence}"
}

///|
fn render_evidence_signature(
  manifest : RenderEvidenceManifest,
  secret : String,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(render_evidence_material(manifest)).view(),
    ),
  )
}

///|
fn valid_visual_evidence(filename : String, bytes : FixedArray[Byte]) -> Bool {
  if filename.to_lower().has_suffix(".png") {
    bytes.length() >= 45 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0d &&
    bytes[5] == 0x0a &&
    bytes[6] == 0x1a &&
    bytes[7] == 0x0a &&
    bytes[8] == 0x00 &&
    bytes[9] == 0x00 &&
    bytes[10] == 0x00 &&
    bytes[11] == 0x0d &&
    bytes[12] == 0x49 &&
    bytes[13] == 0x48 &&
    bytes[14] == 0x44 &&
    bytes[15] == 0x52 &&
    (
      bytes[16] != 0x00 ||
      bytes[17] != 0x00 ||
      bytes[18] != 0x00 ||
      bytes[19] != 0x00
    ) &&
    (
      bytes[20] != 0x00 ||
      bytes[21] != 0x00 ||
      bytes[22] != 0x00 ||
      bytes[23] != 0x00
    ) &&
    bytes[bytes.length() - 12] == 0x00 &&
    bytes[bytes.length() - 11] == 0x00 &&
    bytes[bytes.length() - 10] == 0x00 &&
    bytes[bytes.length() - 9] == 0x00 &&
    bytes[bytes.length() - 8] == 0x49 &&
    bytes[bytes.length() - 7] == 0x45 &&
    bytes[bytes.length() - 6] == 0x4e &&
    bytes[bytes.length() - 5] == 0x44
  } else if filename.to_lower().has_suffix(".pdf") {
    bytes.length() >= 8 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2d
  } else {
    false
  }
}

///| Structural lower bound for a renderer-produced PDF. The renderer's signed

///|
/// evidence remains the semantic/page-image authority.
fn bytes_contain_ascii(
  bytes : FixedArray[Byte],
  value : String,
  start : Int,
) -> Bool {
  if value.length() == 0 || bytes.length() - start < value.length() {
    return false
  }
  let limit = bytes.length() - value.length() + 1
  for index in start..<limit {
    let mut matches = true
    for offset in 0..<value.length() {
      if bytes[index + offset].to_int() != value[offset].to_int() {
        matches = false
        break
      }
    }
    if matches {
      return true
    }
  }
  false
}

///|
/// This intentionally does not UTF-8 decode binary PDF streams.
fn valid_pdf(bytes : FixedArray[Byte]) -> Bool {
  if bytes.length() < 12 ||
    bytes[0] != 0x25 ||
    bytes[1] != 0x50 ||
    bytes[2] != 0x44 ||
    bytes[3] != 0x46 ||
    bytes[4] != 0x2d {
    return false
  }
  let tail_start = (bytes.length() - 2048).max(0)
  let mut end = bytes.length()
  while end > 0 &&
        (
          bytes[end - 1] == 0x20 ||
          bytes[end - 1] == 0x09 ||
          bytes[end - 1] == 0x0a ||
          bytes[end - 1] == 0x0d
        ) {
    end -= 1
  }
  end >= 5 &&
  bytes[end - 5] == 0x25 &&
  bytes[end - 4] == 0x25 &&
  bytes[end - 3] == 0x45 &&
  bytes[end - 2] == 0x4f &&
  bytes[end - 1] == 0x46 &&
  bytes_contain_ascii(bytes, "startxref", tail_start) &&
  (
    bytes_contain_ascii(bytes, "xref", 5) ||
    bytes_contain_ascii(bytes, "/XRef", 5)
  )
}

///|
async fn write_bytes_atomic(path : String, bytes : FixedArray[Byte]) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    Bytes::from_array(bytes),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn write_text_atomic(path : String, text : String) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    text,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn validate_job(job : OfflineArtifactJob) -> Unit raise Failure {
  if job.schema_version != 1 ||
    !valid_identifier(job.request.request_id) ||
    !valid_identifier(job.request.artifact_id) ||
    !@offline.valid_object_ref(job.request.expected_object_ref) ||
    !@offline.valid_sha256(job.request.input_snapshot_sha256) {
    raise Failure("artifact job contract is invalid")
  }
  if job.output_filename == job.template_filename ||
    job.prepared_filename == job.template_filename ||
    job.prepared_filename == job.output_filename ||
    job.result_filename == job.output_filename ||
    job.result_filename == job.template_filename ||
    job.render_manifest_filename == job.output_filename ||
    job.render_manifest_filename == job.result_filename {
    raise Failure("artifact job staging filenames must be distinct")
  }
  match job.request.kind {
    EditableContractDocx => {
      require_suffix(job.template_filename, ".docx")
      require_suffix(job.prepared_filename, ".docx")
      require_suffix(job.output_filename, ".docx")
      if job.docx_replacements.length() == 0 ||
        job.xlsx_replacements.length() != 0 {
        raise Failure("DOCX job has an invalid replacement set")
      }
    }
    QuoteScheduleXlsx => {
      require_suffix(job.template_filename, ".xlsx")
      require_suffix(job.prepared_filename, ".xlsx")
      require_suffix(job.output_filename, ".xlsx")
      if job.xlsx_replacements.length() == 0 ||
        job.docx_replacements.length() != 0 {
        raise Failure("XLSX job has an invalid replacement set")
      }
    }
    PrintReadyContractPdf => {
      require_suffix(job.template_filename, ".docx")
      require_suffix(job.prepared_filename, ".docx")
      require_suffix(job.output_filename, ".pdf")
      if job.docx_replacements.length() == 0 ||
        job.xlsx_replacements.length() != 0 {
        raise Failure("PDF source job has an invalid replacement set")
      }
    }
    _ => raise Failure("artifact worker accepts only editable OOXML jobs")
  }
  require_suffix(job.result_filename, ".json")
  require_suffix(job.render_manifest_filename, ".json")
}

///| First pass: stage the exact deterministic OOXML bytes that the independent

///|
/// renderer must inspect and bind into its signed evidence manifest.
async fn prepare_job(configured_root : String, job_filename : String) -> String {
  let root = @fs.realpath(configured_root) catch {
    _ => raise Failure("artifact staging root is unavailable")
  }
  let job_bytes = read_bounded_bytes(
    staging_path(root, job_filename),
    MaximumJobBytes,
  )
  let job : OfflineArtifactJob = @json.from_json(
    @json.parse(@utf8.decode(Bytes::from_array(job_bytes))),
  ) catch {
    _ => raise Failure("artifact job JSON is malformed")
  }
  validate_job(job)
  let template_path = staging_path(root, job.template_filename)
  let real_template = @fs.realpath(template_path) catch {
    _ => raise Failure("staged template is unavailable")
  }
  if real_template != template_path {
    raise Failure("staged template contains a path alias")
  }
  let template = read_bounded_bytes(template_path, 100000000)
  let customized = match job.request.kind {
    EditableContractDocx | PrintReadyContractPdf =>
      @worker.customize_exact_docx_template(template, job.docx_replacements) catch {
        _ => raise Failure("MoonLeaf rejected the DOCX customization")
      }
    QuoteScheduleXlsx =>
      @worker.customize_xlsx_template(template, job.xlsx_replacements) catch {
        _ => raise Failure("MoonLeaf rejected the XLSX customization")
      }
    _ => raise Failure("unsupported artifact kind")
  }
  if customized.verification.active_content_detected ||
    !customized.verification.moonleaf_verified ||
    customized.verification.formula_error_count != 0 {
    raise Failure("prepared artifact did not pass MoonLeaf verification")
  }
  write_bytes_atomic(
    staging_path(root, job.prepared_filename),
    customized.bytes,
  )
  sha256(customized.bytes)
}

///|
async fn verify_render_evidence(
  root : String,
  job : OfflineArtifactJob,
  artifact_sha256 : String,
  secret : String,
  now_unix_ms : Int64,
) -> RenderEvidenceManifest {
  if secret.length() < 32 ||
    secret.length() > 4096 ||
    !secret.all(character => character >= '!' && character <= '~') {
    raise Failure("render-evidence authority is unavailable")
  }
  let manifest_path = staging_path(root, job.render_manifest_filename)
  let real_manifest = @fs.realpath(manifest_path) catch {
    _ => raise Failure("render-evidence manifest is unavailable")
  }
  if real_manifest != manifest_path {
    raise Failure("render-evidence manifest contains a path alias")
  }
  let manifest_bytes = read_bounded_bytes(manifest_path, MaximumJobBytes)
  let manifest : RenderEvidenceManifest = @json.from_json(
    @json.parse(@utf8.decode(Bytes::from_array(manifest_bytes))),
  ) catch {
    _ => raise Failure("render-evidence manifest JSON is malformed")
  }
  let expected_signature = render_evidence_signature(manifest, secret)
  if manifest.signature.length() != 64 ||
    !manifest.signature.all(character => character.is_ascii_hexdigit()) ||
    !constant_time_equal(manifest.signature, expected_signature) {
    raise Failure("render-evidence signature verification failed")
  }
  if manifest.schema_version != 2 ||
    manifest.request_id != job.request.request_id ||
    manifest.artifact_sha256 != artifact_sha256 ||
    !@offline.valid_sha256(manifest.source_sha256) ||
    manifest.kind != job.request.kind ||
    manifest.page_or_sheet_count <= 0 ||
    manifest.page_or_sheet_count > 1000 ||
    !manifest.passed ||
    !valid_identifier(manifest.renderer_receipt) ||
    manifest.visual_evidence.length() != manifest.page_or_sheet_count ||
    manifest.rendered_unix_ms < job.request.requested_unix_ms ||
    manifest.rendered_unix_ms > now_unix_ms + 300000L ||
    now_unix_ms - manifest.rendered_unix_ms > 900000L {
    raise Failure("render-evidence semantic verification failed")
  }
  let seen_visual_filenames : Map[String, Bool] = Map([])
  let mut total_visual_bytes = 0
  for index, evidence in manifest.visual_evidence {
    if evidence.page_or_sheet_index != index + 1 ||
      !@offline.valid_sha256(evidence.sha256) ||
      seen_visual_filenames.contains(evidence.filename) {
      raise Failure("visual render evidence index is invalid")
    }
    seen_visual_filenames[evidence.filename] = true
    let visual_path = staging_path(root, evidence.filename)
    let real_visual = @fs.realpath(visual_path) catch {
      _ => raise Failure("visual render evidence is unavailable")
    }
    if real_visual != visual_path {
      raise Failure("visual render evidence contains a path alias")
    }
    let visual_bytes = read_bounded_bytes(
      visual_path,
      MaximumVisualEvidenceBytes,
    )
    total_visual_bytes += visual_bytes.length()
    if total_visual_bytes > 104857600 {
      raise Failure("visual render evidence aggregate is too large")
    }
    if sha256(visual_bytes) != evidence.sha256 ||
      !valid_visual_evidence(evidence.filename, visual_bytes) {
      raise Failure("visual render evidence verification failed")
    }
  }
  manifest
}

///|
async fn run_job(
  configured_root : String,
  job_filename : String,
  render_evidence_secret : String,
  now_unix_ms : Int64,
) -> @offline.ArtifactGenerationResult {
  let root = @fs.realpath(configured_root) catch {
    _ => raise Failure("artifact staging root is unavailable")
  }
  let job_path = staging_path(root, job_filename)
  let job_bytes = read_bounded_bytes(job_path, MaximumJobBytes)
  let job : OfflineArtifactJob = @json.from_json(
    @json.parse(@utf8.decode(Bytes::from_array(job_bytes))),
  ) catch {
    _ => raise Failure("artifact job JSON is malformed")
  }
  validate_job(job)
  let template_path = staging_path(root, job.template_filename)
  let output_path = staging_path(root, job.output_filename)
  let result_path = staging_path(root, job.result_filename)
  let real_template = @fs.realpath(template_path) catch {
    _ => raise Failure("staged template is unavailable")
  }
  if real_template != template_path {
    raise Failure("staged template contains a path alias")
  }
  let template = read_bounded_bytes(template_path, 100000000)
  let customized = match job.request.kind {
    EditableContractDocx | PrintReadyContractPdf =>
      @worker.customize_exact_docx_template(template, job.docx_replacements) catch {
        _ => raise Failure("MoonLeaf rejected the DOCX customization")
      }
    QuoteScheduleXlsx =>
      @worker.customize_xlsx_template(template, job.xlsx_replacements) catch {
        _ => raise Failure("MoonLeaf rejected the XLSX customization")
      }
    _ => raise Failure("unsupported artifact kind")
  }
  if customized.verification.active_content_detected ||
    !customized.verification.moonleaf_verified ||
    customized.verification.formula_error_count != 0 {
    raise Failure("customized artifact did not pass MoonLeaf verification")
  }
  let artifact_sha256 = sha256(customized.bytes)
  let source_sha256 = artifact_sha256
  let (artifact_bytes, artifact_sha256) = if job.request.kind ==
    PrintReadyContractPdf {
    let rendered = read_bounded_bytes(output_path, 100000000)
    if !valid_pdf(rendered) {
      raise Failure("renderer output is not a structurally valid PDF")
    }
    (rendered, sha256(rendered))
  } else {
    (customized.bytes, artifact_sha256)
  }
  let render_evidence = verify_render_evidence(
    root, job, artifact_sha256, render_evidence_secret, now_unix_ms,
  )
  if render_evidence.source_sha256 != source_sha256 {
    raise Failure("render evidence is not bound to the prepared source")
  }
  let visual_evidence_sha256 = sha256(
    @utf8.encode(
      render_evidence.visual_evidence.map(item => item.sha256).join("|"),
    ).to_fixedarray(),
  )
  if job.request.kind != PrintReadyContractPdf {
    write_bytes_atomic(output_path, artifact_bytes)
  }
  let result : @offline.ArtifactGenerationResult = {
    request_id: job.request.request_id,
    artifact_id: job.request.artifact_id,
    expected_object_ref: job.request.expected_object_ref,
    media_type: match job.request.kind {
      EditableContractDocx =>
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      QuoteScheduleXlsx =>
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      PrintReadyContractPdf => "application/pdf"
      _ => raise Failure("unsupported artifact kind")
    },
    byte_count: Int64::from_int(artifact_bytes.length()),
    sha256: artifact_sha256,
    worker_receipt: "moonleaf:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode("\{job.request.request_id}|\{artifact_sha256}|\{visual_evidence_sha256}|\{render_evidence.renderer_receipt}")))}",
    verified: true,
    active_content_detected: false,
    moonleaf_verified: true,
    render_verified: true,
    formula_error_count: 0,
    visual_evidence_sha256,
    completed_unix_ms: now_unix_ms,
  }
  write_text_atomic(result_path, result.to_json().stringify(indent=2))
  result
}

///|
async fn main {
  let root = required_env("LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT")
  let job_filename = required_env("LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME")
  match required_env("LUNANEXA_OFFLINE_ARTIFACT_MODE") {
    "prepare" => {
      let digest = prepare_job(root, job_filename)
      println(
        ({ "ok": true, "mode": "prepare", "sha256": digest } : Json).stringify(),
      )
    }
    "finalize" => {
      let secret = required_env("LUNANEXA_RENDER_EVIDENCE_SECRET")
      let result = run_job(root, job_filename, secret, @async.now())
      println(
        (
          {
            "ok": true,
            "mode": "finalize",
            "request_id": result.request_id,
            "artifact_id": result.artifact_id,
            "sha256": result.sha256,
          } : Json).stringify(),
      )
    }
    _ => raise Failure("artifact mode must be explicitly prepare or finalize")
  }
}
