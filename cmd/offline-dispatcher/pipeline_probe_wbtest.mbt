///|
/// Opt-in integration probe: real worker, renderer, PDF rasterizer and object
/// storage adapter; only the controller plan/callback boundary is a test server.
/// Never creates production readiness evidence or uses a production order.
async test "isolated actual artifact pipeline retries failed callback" {
  guard @env.get_env_var("LUNANEXA_OFFLINE_PIPELINE_PROBE_ROOT")
    is Some(configured_root) else {
    return
  }
  ensure_directory(configured_root)
  let root = @fs.realpath(configured_root)
  let transfer = required("LUNANEXA_OFFLINE_TRANSFER_OBJECT_ENDPOINT")
  let token = required("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN")
  let run_id = "test-only-" + @async.now().to_string()
  let reference = "object://verification/\{run_id}/template.docx"
  let parts : Array[@opc.Part] = [
    {
      name: "[Content_Types].xml",
      content: @utf8.encode(
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
      ).to_fixedarray(),
    },
    {
      name: "_rels/.rels",
      content: @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
      ).to_fixedarray(),
    },
    {
      name: "word/document.xml",
      content: @utf8.encode(
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>Engineering verification only. Not a legal agreement.</w:t></w:r></w:p><w:p><w:r><w:t>{{ORDER_ID}}</w:t></w:r></w:p><w:sectPr/></w:body></w:document>",
      ).to_fixedarray(),
    },
  ]
  let template = match
    @env.get_env_var("LUNANEXA_OFFLINE_PIPELINE_PROBE_DOCX") {
    Some(path) => @fs.read_file(path).binary()
    None => Bytes::from_array(@opc.save(({ parts, } : @opc.Package)))
  }
  let (uploaded, upload_response) = exchange(
    transfer,
    token,
    "/internal/v1/objects/write",
    Post,
    template,
    extra={
      "Content-Type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "X-LunaNexa-Object-Ref": reference,
      "X-LunaNexa-Sha256": digest(template),
    },
  )
  if uploaded != 201 {
    println(
      "Template upload rejected: \{uploaded} \{@utf8.decode_lossy(upload_response)}",
    )
  }
  assert_eq(uploaded, 201)
  let request : @offline.ArtifactGenerationRequest = {
    request_id: run_id,
    artifact_id: run_id + "-artifact",
    order_id: run_id + "-order",
    organization_id: "test-only-organization",
    kind: PrintReadyContractPdf,
    template_id: "test-only-template",
    template_version: "1",
    locale: "en-US",
    expected_object_ref: "object://verification/\{run_id}/output.pdf",
    input_snapshot_sha256: "sha256:" + "a".repeat(64),
    requested_by: "test-only-probe",
    requested_unix_ms: @async.now(),
  }
  let markers = @worker.exact_docx_markers(template.to_fixedarray())
  let replacements : Array[Json] = markers.map(marker => {
    "placeholder": marker,
    "value": if marker == "{{lessee.name}}" {
      "示例使用单位"
    } else if marker == "{{undertaking.signed_date.year}}" {
      "2026"
    } else if marker == "{{undertaking.signed_date.month}}" {
      "09"
    } else if marker == "{{undertaking.signed_date.day}}" {
      "22"
    } else {
      "TEST-ONLY-ORDER"
    },
  })
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
  let plan : Json = {
    "job": job,
    "template_object_ref": reference,
    "template_sha256": digest(template),
  }
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let plans = Ref(0)
  let callbacks = Ref(0)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      server.run_forever(allow_failure=true, (incoming, _, connection) => {
        if incoming.path == "/v1/offline-commerce/operator/generation-plan" {
          plans.val += 1
          connection.send_response(200, "OK")
          connection.write_string(plan.stringify())
        } else {
          callbacks.val += 1
          connection.send_response(
            if callbacks.val == 1 {
              503
            } else {
              200
            },
            "Callback",
          )
          connection.write_string("{}")
        }
        connection.end_response()
      })
    })
    let config = Config::{
      origin: "http://\{server.addr}",
      token: "test-only-controller",
      root,
    }
    try artifact(config, request) catch {
      error => println("First pipeline attempt: \{Repr(error)}")
    } noraise {
      _ => fail("first callback was expected to fail")
    }
    // A render/upload failure must not masquerade as the expected callback error.
    assert_eq(callbacks.val, 1)
    assert_eq(plans.val, 2)
    resume_artifacts(config)
    assert_eq(callbacks.val, 2)
    assert_eq(plans.val, 2)
    let (read_status, pdf) = exchange(
      transfer,
      token,
      "/internal/v1/objects/read",
      Post,
      @utf8.encode(
        (
          {
            "object_ref": request.expected_object_ref,
            "maximum_byte_count": "67108864",
          } : Json).stringify(),
      ),
      extra={ "Content-Type": "application/json" },
      maximum=67108864,
    )
    assert_eq(read_status, 200)
    assert_true(pdf.has_prefix(b"%PDF-"))
    let summary : Json = {
      "schema": "lunanexa.offline-pipeline.probe.v1",
      "production_ready": false,
      "run_id": run_id,
      "real_worker": true,
      "real_renderer": true,
      "real_object_roundtrip": true,
      "failed_callback_recovered": true,
      "plan_calls": plans.val,
      "callback_calls": callbacks.val,
      "output_sha256": digest(pdf),
      "template_sha256": digest(template),
      "output_byte_count": pdf.length(),
    }
    write_atomic(
      "\{root}/probe-summary.json",
      @utf8.encode(summary.stringify(indent=2)),
    )
    println(summary.stringify())
  })
}
