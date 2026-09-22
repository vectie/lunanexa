///|
struct FontFile {
  family : String
  filename : String
  sha256 : String
  license_reference : String
} derive(FromJson, ToJson)

///|
struct FontConfiguration {
  default_family : String
  fonts : Array[FontFile]
} derive(FromJson, ToJson)

///|
/// Unknown replacement-plan properties belong to the preparation worker.
struct RenderJob {
  schema_version : Int
  request : @offline.ArtifactGenerationRequest
  prepared_filename : String
  output_filename : String
  render_manifest_filename : String
} derive(FromJson)

///|
struct VisualEvidence {
  page_or_sheet_index : Int
  filename : String
  sha256 : String
} derive(ToJson)

///|
struct Manifest {
  schema_version : Int
  request_id : String
  artifact_sha256 : String
  source_sha256 : String
  kind : @offline.DocumentArtifactKind
  page_or_sheet_count : Int
  passed : Bool
  renderer_receipt : String
  rendered_unix_ms : Int64
  moonleaf : @render.Evidence
  visual_evidence : Array[VisualEvidence]
  signature : String
} derive(ToJson)

///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(s) && s.trim() != "" else {
    raise Failure("missing setting: " + name)
  }
  s
}

///|
fn filename(s : String) -> String raise {
  guard s.length() > 0 &&
    s.length() <= 180 &&
    s != "." &&
    s != ".." &&
    s.all(c => {
      c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '.' ||
      c == '_' ||
      c == '-'
    }) else {
    raise Failure("unsafe staging filename")
  }
  s
}

///|
fn digest(bytes : Bytes) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes.to_fixedarray()))
}

///|
async fn read(root : String, name : String, maximum : Int) -> Bytes {
  let path = root + "/" + filename(name)
  guard @fs.realpath(path) == path else {
    raise Failure("symlinked staged input refused")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard file.kind() == Regular && size > 0L && size <= maximum.to_int64() else {
    raise Failure("input is not bounded regular file")
  }
  file.read_exactly_at(size.to_int(), position=0L)
}

///|
async fn write(root : String, name : String, bytes : Bytes) -> Unit {
  let target = root + "/" + filename(name)
  let temporary = target + ".renderer-" + @async.now().to_string()
  // Per-job directories must not be writable by untrusted callers.
  @fs.write_file(
    temporary,
    bytes,
    create_mode=CreateNew,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, target, replace=true)
}

///|
fn sign(m : Manifest, secret : String, kind : String) -> String {
  let evidence = m.visual_evidence
    .map(e => "\{e.page_or_sheet_index}:\{e.filename}:\{e.sha256}")
    .join(",")
  let material = "lunanexa.render-evidence.v3|\{m.request_id}|\{m.artifact_sha256}|\{m.source_sha256}|\{kind}|\{m.page_or_sheet_count}|\{m.passed}|\{m.renderer_receipt}|\{m.rendered_unix_ms}|\{m.moonleaf.to_json().stringify()}|\{evidence}"
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).exact_view(),
      @utf8.encode(material).exact_view(),
    ),
  )
}

///|
async fn main {
  let root = @fs.realpath(required("LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT"))
  let job : RenderJob = @json.from_json(
    @json.parse(
      @utf8.decode(
        read(root, required("LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME"), 1048576),
      ),
    ),
  )
  guard job.schema_version == 1 else { raise Failure("unsupported job schema") }
  let kind = match job.request.kind {
    PrintReadyContractPdf => "print-ready-contract-pdf"
    EditableContractDocx => "editable-contract-docx"
    QuoteScheduleXlsx => "quote-schedule-xlsx"
    _ =>
      raise Failure(
        "MoonLeaf DOCX PDF renderer does not accept this artifact kind",
      )
  }
  let config_path = required("LUNANEXA_OFFLINE_FONT_CONFIG_FILENAME")
  let config_bytes = @fs.read_file(config_path).binary()
  guard config_bytes.length() <= 1048576 else {
    raise Failure("font configuration too large")
  }
  let config : FontConfiguration = @json.from_json(
    @json.parse(@utf8.decode(config_bytes)),
  )
  let font_root = @fs.realpath(required("LUNANEXA_OFFLINE_FONT_ROOT"))
  let fonts : Array[@render.PdfFontInput] = []
  let identities : Array[String] = []
  for font in config.fonts {
    guard font.license_reference.trim() != "" else {
      raise Failure("font license provenance missing")
    }
    let bytes = read(font_root, font.filename, 67108864)
    guard digest(bytes) == font.sha256 else {
      raise Failure("font digest mismatch")
    }
    fonts.push({ family: font.family, bytes, })
    identities.push(
      font.family + ":" + font.sha256 + ":" + font.license_reference,
    )
  }
  let source = read(root, job.prepared_filename, 100000000)
  let source_package = @opc.open(source.to_fixedarray())
  let result = if job.request.kind == QuoteScheduleXlsx {
    @render.render_xlsx_proof_pdf(
      source_package,
      fonts,
      default_family=config.default_family,
    )
  } else {
    @render.render_docx_pdf(
      source_package,
      fonts,
      default_family=config.default_family,
    )
  }
  let artifact = if job.request.kind == PrintReadyContractPdf {
    result.bytes
  } else {
    source
  }
  guard job.output_filename != job.prepared_filename &&
    job.render_manifest_filename != job.output_filename else {
    raise Failure("output aliases source or manifest")
  }
  let pdf_name = if job.request.kind == PrintReadyContractPdf {
    job.output_filename
  } else {
    "moonleaf-preview.pdf"
  }
  write(root, pdf_name, result.bytes)
  let rasterizer = @env.get_env_var("LUNANEXA_OFFLINE_PDFTOPPM_BIN").unwrap_or(
    "pdftoppm",
  )
  let evidence : Array[VisualEvidence] = []
  for page in 1..<=result.page_count {
    let stem = "moonleaf-page-\{page}"
    let code = @process.run(rasterizer, [
      "-f",
      page.to_string(),
      "-l",
      page.to_string(),
      "-singlefile",
      "-r",
      "96",
      "-png",
      root + "/" + filename(pdf_name),
      root + "/" + stem,
    ])
    guard code == 0 else { raise Failure("PDF raster verification failed") }
    let bytes = read(root, stem + ".png", 20971520)
    guard bytes.has_prefix(b"\x89PNG\r\n\x1a\n") else {
      raise Failure("rasterizer did not produce PNG")
    }
    evidence.push({
      page_or_sheet_index: page,
      filename: stem + ".png",
      sha256: digest(bytes),
    })
  }
  write(root, job.output_filename, artifact)
  let secret = required("LUNANEXA_RENDER_EVIDENCE_SECRET")
  guard secret.length() >= 32 && secret.length() <= 4096 else {
    raise Failure("invalid render authority")
  }
  let now = @async.now()
  let m : Manifest = {
    schema_version: 3,
    request_id: job.request.request_id,
    artifact_sha256: digest(artifact),
    source_sha256: digest(source),
    kind: job.request.kind,
    page_or_sheet_count: result.page_count,
    passed: true,
    renderer_receipt: "moonleaf-pdf-v1-" + now.to_string(),
    rendered_unix_ms: now,
    moonleaf: {
      contract_version: @render.contract_version(),
      engine: @render.engine_id(),
      engine_version: "0.2.0-legal-v1",
      source_sha256: digest(source),
      artifact_sha256: digest(artifact),
      font_bundle_sha256: digest(@utf8.encode(identities.join("\n"))),
      layout_profile_sha256: digest(
        @utf8.encode("moonleaf-legal-v1:" + config.default_family),
      ),
      page_count: result.page_count,
      rendered_unix_ms: now,
    },
    visual_evidence: evidence,
    signature: "",
  }
  write(
    root,
    job.render_manifest_filename,
    @utf8.encode(
      ToJson::to_json({ ..m, signature: sign(m, secret, kind), }).stringify(),
    ),
  )
  println("MoonLeaf rendered and raster-verified \{result.page_count} page(s)")
}
